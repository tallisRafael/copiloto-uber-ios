import Foundation

/// Perfil aprendido de um bairro/região com base no histórico real de uso do motorista
struct LearnedRegionProfile: Codable, Identifiable, Equatable {
    var id: String { normalizedName }
    let displayName: String
    let normalizedName: String
    
    /// Quantas vezes tocou corrida para esta região
    var totalOffersCount: Int = 0
    
    /// Quantas vezes o motorista ACEITOU ir para esta região
    var acceptedCount: Int = 0
    
    /// Quantas vezes a corrida era financeiramente BOA (Verde), mas o motorista IGNOROU/RECUSOU
    var rejectedWhenGoodCount: Int = 0
    
    /// Histórico de minutos que o motorista ficou ocioso (sem aceitar nova corrida) após desembarcar nesta região
    var deadheadWaitMinutesSamples: [Double] = []
    
    /// Média de minutos sem corrida após ir para este bairro (Índice de Volta Vazia)
    var averageDeadheadMinutes: Double {
        guard !deadheadWaitMinutesSamples.isEmpty else { return 0.0 }
        let sum = deadheadWaitMinutesSamples.reduce(0.0, +)
        return sum / Double(deadheadWaitMinutesSamples.count)
    }
    
    /// Indica se o sistema aprendeu que o motorista evita este bairro mesmo quando paga bem (mínimo 4 recusas e 0 aceites)
    var isLearnedDangerZone: Bool {
        rejectedWhenGoodCount >= 4 && acceptedCount == 0
    }
    
    /// Indica se o sistema aprendeu que este bairro gera espera longa / volta vazia (> 15 min sem corrida)
    var isLearnedDeadheadZone: Bool {
        deadheadWaitMinutesSamples.count >= 2 && averageDeadheadMinutes >= 15.0
    }
}

/// Recomendação gerada pelo Motor de Aprendizado para uma corrida atual
struct LearnedRideInsight: Equatable {
    let regionName: String
    let isLearnedDanger: Bool
    let isLearnedDeadhead: Bool
    let averageWaitMinutes: Double
}

/// Motor de Aprendizado de Máquina / Heurística Adaptativa On-Device.
final class AdaptiveLearningEngine {
    
    static let shared = AdaptiveLearningEngine()
    
    private static let storageKey = "uber_helper_learned_profiles_v2"
    
    private(set) var regionProfiles: [String: LearnedRegionProfile] = [:]
    
    /// Últimas velocidades médias observadas nas corridas recentes para detectar engarrafamento geral
    private var recentSpeedsKmH: [Double] = []
    
    /// Guarda quando e onde a última corrida aceita terminou para medir o tempo de "volta vazia" até a próxima
    private var lastAcceptedDropoffRegionKey: String?
    private var lastAcceptedEstimatedFinishDate: Date?
    
    private init() {
        loadProfiles()
    }
    
    // MARK: - 1. Consulta de Aprendizado para Avaliar uma Nova Corrida
    
    func insight(for address: String) -> LearnedRideInsight? {
        let regionName = extractRegionName(from: address)
        let key = normalize(regionName)
        guard !key.isEmpty, let profile = regionProfiles[key] else {
            return nil
        }
        
        guard profile.isLearnedDangerZone || profile.isLearnedDeadheadZone else {
            return nil
        }
        
        return LearnedRideInsight(
            regionName: profile.displayName,
            isLearnedDanger: profile.isLearnedDangerZone,
            isLearnedDeadhead: profile.isLearnedDeadheadZone,
            averageWaitMinutes: profile.averageDeadheadMinutes
        )
    }
    
    // MARK: - 2. Registro de Eventos e Aprendizado Contínuo
    
    /// Chamado quando uma oferta de corrida é lida pelo OCR (ignorado se o motorista estiver em Modo Pausa/Café).
    func recordOfferObserved(ride: RideExtractedData, wasFinanciallyApproved: Bool, isPausedForBreak: Bool = false) -> Bool {
        guard !isPausedForBreak else { return false }
        
        let regionName = extractRegionName(from: ride.enderecoDestino)
        let key = normalize(regionName)
        
        if !key.isEmpty {
            var profile = regionProfiles[key] ?? LearnedRegionProfile(
                displayName: regionName,
                normalizedName: key
            )
            profile.totalOffersCount += 1
            if wasFinanciallyApproved {
                profile.rejectedWhenGoodCount += 1
            }
            regionProfiles[key] = profile
            saveProfiles()
        }
        
        recentSpeedsKmH.append(ride.velocidadeMediaKmH)
        if recentSpeedsKmH.count > 3 {
            recentSpeedsKmH.removeFirst()
        }
        
        if recentSpeedsKmH.count == 3 {
            let avgSpeed = recentSpeedsKmH.reduce(0.0, +) / 3.0
            return avgSpeed < 22.0
        }
        return false
    }
    
    /// Chamado quando o motorista ACEITA a corrida (manualmente ou detectado automaticamente na tela da Uber).
    func recordRideAccepted(ride: RideExtractedData, wasFinanciallyApproved: Bool) {
        let now = Date()
        
        if let prevKey = lastAcceptedDropoffRegionKey,
           let finishDate = lastAcceptedEstimatedFinishDate,
           var prevProfile = regionProfiles[prevKey] {
            let idleMinutes = now.timeIntervalSince(finishDate) / 60.0
            if idleMinutes >= 1.0 && idleMinutes <= 90.0 {
                prevProfile.deadheadWaitMinutesSamples.append(idleMinutes)
                if prevProfile.deadheadWaitMinutesSamples.count > 10 {
                    prevProfile.deadheadWaitMinutesSamples.removeFirst()
                }
                regionProfiles[prevKey] = prevProfile
            }
        }
        
        let regionName = extractRegionName(from: ride.enderecoDestino)
        let key = normalize(regionName)
        if !key.isEmpty {
            var profile = regionProfiles[key] ?? LearnedRegionProfile(
                displayName: regionName,
                normalizedName: key
            )
            profile.acceptedCount += 1
            if wasFinanciallyApproved && profile.rejectedWhenGoodCount > 0 {
                profile.rejectedWhenGoodCount -= 1
            }
            regionProfiles[key] = profile
            
            lastAcceptedDropoffRegionKey = key
            lastAcceptedEstimatedFinishDate = now.addingTimeInterval(ride.tempoTotal * 60.0)
        }
        
        saveProfiles()
    }
    
    func simulateLearnedPattern(
        regionName: String,
        rejectedGoodCount: Int,
        deadheadWaitMinutes: [Double]
    ) {
        let key = normalize(regionName)
        guard !key.isEmpty else { return }
        let profile = LearnedRegionProfile(
            displayName: regionName,
            normalizedName: key,
            totalOffersCount: max(rejectedGoodCount, deadheadWaitMinutes.count),
            acceptedCount: deadheadWaitMinutes.count,
            rejectedWhenGoodCount: rejectedGoodCount,
            deadheadWaitMinutesSamples: deadheadWaitMinutes
        )
        regionProfiles[key] = profile
        saveProfiles()
    }
    
    func clearAllLearnedData() {
        regionProfiles.removeAll()
        recentSpeedsKmH.removeAll()
        lastAcceptedDropoffRegionKey = nil
        lastAcceptedEstimatedFinishDate = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
    
    var sortedProfiles: [LearnedRegionProfile] {
        regionProfiles.values.sorted { $0.totalOffersCount > $1.totalOffersCount }
    }
    
    // MARK: - Extração Inteligente de Bairro/Região (Ignorando Números de Porta)
    
    /// Extrai o nome do bairro/cidade de um endereço (ex: "Av. Brasil, 1450 - Zona 01" -> "Zona 01")
    func extractRegionName(from address: String) -> String {
        // Primeiro tenta separar por hífen ou vírgula pegando o último segmento que não seja apenas número
        let segments = address
            .components(separatedBy: CharacterSet(charactersIn: ",-"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { segment in
                guard !segment.isEmpty else { return false }
                // Ignora segmentos que são apenas números de porta (ex: "1450", "S/N")
                let digitsOnly = segment.trimmingCharacters(in: .decimalDigits)
                return !digitsOnly.isEmpty && segment.uppercased() != "S/N"
            }
        
        return segments.last ?? address.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
    
    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(regionProfiles) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
    }
    
    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: LearnedRegionProfile].self, from: data) else {
            return
        }
        regionProfiles = decoded
    }
}
