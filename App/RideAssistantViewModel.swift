import Foundation
import SwiftUI
import Combine

/// ViewModel central que escuta o OCR (via Darwin Notification + App Group),
/// roda o Motor de Regras, consulta o Apple Maps (MapKit), alimenta o Motor de Aprendizado (IA Local),
/// gerencia o Auto-Reset, aciona o alerta sonoro (Bipe/Voz) e atualiza o Picture-in-Picture.
final class RideAssistantViewModel: ObservableObject {
    
    @Published var currentVerdict: RideVerdict = .waiting
    @Published var lastRawOCRText: String = "Nenhum texto capturado ainda."
    
    /// Histórico das corridas lidas durante a sessão (mais recentes no topo)
    @Published var rideHistory: [RideHistoryItem] = []
    
    /// Lista de perfis de bairros aprendidos pela IA Local conforme o motorista usa o app
    @Published var learnedProfiles: [LearnedRegionProfile] = AdaptiveLearningEngine.shared.sortedProfiles
    
    /// Última verificação de trânsito retornada pelo Apple Maps (MapKit)
    @Published var latestMapVerification: MapTrafficVerification?
    
    /// Toggle de Modo Trânsito / Chuva: Ao mudar seu valor, reavalia imediatamente a corrida atual
    @Published var isTrafficModeEnabled: Bool = false {
        didSet {
            reEvaluateLastText()
        }
    }
    
    /// Toggle de Modo "Rumo a Casa" (Destinos Favoritos / Fim de Turno)
    @Published var isGoingHomeModeEnabled: Bool = false {
        didSet {
            reEvaluateLastText()
        }
    }
    
    /// Toggle de Modo "Pausa / Café" (Impede que a IA contabilize recusas enquanto o motorista está abastecendo ou descansando)
    @Published var isPausedForBreak: Bool = false
    
    /// Modo de Alerta Sonoro: Silencioso, Bipe Rápido ou Voz (TTS)
    @Published var audioAlertMode: AudioAlertMode = {
        if let saved = UserDefaults.standard.string(forKey: "uber_helper_audio_mode"),
           let mode = AudioAlertMode(rawValue: saved) {
            return mode
        }
        return .voice
    }() {
        didSet {
            UserDefaults.standard.set(audioAlertMode.rawValue, forKey: "uber_helper_audio_mode")
        }
    }
    
    /// Voz selecionada para os alertas (Felipe Masculina, Feminina Suave ou Automática)
    @Published var driverVoiceType: DriverVoiceType = {
        if let saved = UserDefaults.standard.string(forKey: "uber_helper_voice_type"),
           let type = DriverVoiceType(rawValue: saved) {
            return type
        }
        return .maleFelipe
    }() {
        didSet {
            UserDefaults.standard.set(driverVoiceType.rawValue, forKey: "uber_helper_voice_type")
        }
    }
    
    /// Configurações personalizáveis do motorista (Custos, Metas e Listas Geográficas)
    @Published var settings: RideSettings = RideSettings.load() {
        didSet {
            settings.save()
            reEvaluateLastText()
        }
    }
    
    /// Indica se a captura de tela do ReplayKit está ativa enviando frames
    @Published var isBroadcastActive: Bool = false
    
    let ruleEngine = RideRuleEngine()
    let pipManager = PiPManager()
    
    private var autoResetTimer: Timer?
    private var lastRecordedFingerprint: String = ""
    private static let historyStorageKey = "uber_helper_ride_history_v2"
    
    init() {
        // Carrega o histórico persistente de todas as chamadas salvas do dia
        rideHistory = Self.loadHistoryFromDisk()
        
        // Limpa falsos positivos que tenham sido gerados por cliques anteriores no Simulador
        if !UserDefaults.standard.bool(forKey: "did_clean_sim_pollution_v2") {
            AdaptiveLearningEngine.shared.clearAllLearnedData()
            UserDefaults.standard.set(true, forKey: "did_clean_sim_pollution_v2")
        }
        learnedProfiles = AdaptiveLearningEngine.shared.sortedProfiles
        
        // Pede a permissão dos Banners de Topo (estilo GigU) logo ao abrir o app
        _ = SpeechManager.shared
        
        pipManager.setup(with: self)
        registerDarwinNotificationObserver()
        startLocalUDPReceiver()
    }
    
    private func startLocalUDPReceiver() {
        LocalOCRReceiver.shared.onTextReceived = { [weak self] text in
            guard let self = self else { return }
            self.isBroadcastActive = true
            self.handleNewOCRText(text, isSimulated: false)
        }
        LocalOCRReceiver.shared.startListening()
    }
    
    deinit {
        autoResetTimer?.invalidate()
        TrafficMapService.shared.cancelPendingCheck()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }
    
    // MARK: - Métricas do Termômetro da Meta Diária (Corridas Aceitas)
    
    var acceptedRides: [RideHistoryItem] {
        rideHistory.filter { $0.isAccepted }
    }
    
    var totalBrutoAceito: Double {
        acceptedRides.reduce(0.0) { $0 + $1.data.valorTotal }
    }
    
    var totalKmAceito: Double {
        acceptedRides.reduce(0.0) { $0 + $1.data.kmTotal }
    }
    
    var totalCustoCombustivelAceito: Double {
        acceptedRides.reduce(0.0) { $0 + $1.data.custoOperacional(custoPorKm: settings.custoPorKm) }
    }
    
    var totalLucroLiquidoAceito: Double {
        acceptedRides.reduce(0.0) { $0 + $1.data.lucroLiquido(custoPorKm: settings.custoPorKm) }
    }
    
    var progressoMetaDiaria: Double {
        guard settings.metaDiariaLiquida > 0 else { return 0.0 }
        return min(1.0, totalLucroLiquidoAceito / settings.metaDiariaLiquida)
    }
    
    var percentualRealMetaDiaria: Int {
        guard settings.metaDiariaLiquida > 0 else { return 0 }
        return Int((totalLucroLiquidoAceito / settings.metaDiariaLiquida) * 100.0)
    }
    
    var isMetaDiariaBatida: Bool {
        totalLucroLiquidoAceito >= settings.metaDiariaLiquida && settings.metaDiariaLiquida > 0
    }
    
    var valorExcedenteMetaDiaria: Double {
        max(0.0, totalLucroLiquidoAceito - settings.metaDiariaLiquida)
    }
    
    var faltaParaMetaDiaria: Double {
        max(0.0, settings.metaDiariaLiquida - totalLucroLiquidoAceito)
    }
    
    var isCurrentRideAccepted: Bool {
        guard let first = rideHistory.first,
              first.data.fingerprint == lastRecordedFingerprint else {
            return false
        }
        return first.isAccepted
    }
    
    // MARK: - Métricas de Todas as Chamadas Recebidas (Histórico do Turno)
    
    var totalChamadasRecebidas: Int {
        rideHistory.count
    }
    
    var totalValorOfertadoBruto: Double {
        rideHistory.reduce(0.0) { $0 + $1.data.valorTotal }
    }
    
    var totalChamadasAprovadas: Int {
        rideHistory.filter { $0.verdict.status == .approved || $0.verdict.status == .goingHome }.count
    }
    
    var totalChamadasCiladas: Int {
        rideHistory.filter { $0.verdict.status == .rejected }.count
    }
    
    var totalChamadasAtencao: Int {
        rideHistory.filter { $0.verdict.status == .warning }.count
    }
    
    var percentualCorridasBoas: Int {
        guard !rideHistory.isEmpty else { return 0 }
        return Int((Double(totalChamadasAprovadas) / Double(rideHistory.count)) * 100.0)
    }
    
    // MARK: - Processamento do OCR em 2 Estágios (1º Instantâneo + 2º Apple Maps)
    
    func handleNewOCRText(_ text: String, simulatedMapOverride: MapTrafficVerification? = nil, isSimulated: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let systemStatus = self.extractSystemStatus(from: text) {
                self.handleSystemStatus(systemStatus)
                return
            }
            
            self.lastRawOCRText = text
            
            if let extractedData = self.ruleEngine.parseOCRText(text) {
                let isNewRide = (extractedData.fingerprint != self.lastRecordedFingerprint)
                
                // Se for uma NOVA corrida (ou se houver override manual do simulador), limpa o Maps da corrida anterior.
                // Se for apenas o heartbeat de 2,5s da MESMA corrida na tela, preserva o trânsito já consultado!
                if isNewRide || simulatedMapOverride != nil {
                    self.latestMapVerification = simulatedMapOverride
                }
                
                let learnedInsight = self.settings.usarAprendizadoDeMaquina
                    ? AdaptiveLearningEngine.shared.insight(for: extractedData.enderecoDestino)
                    : nil
                
                let initialVerdict = self.ruleEngine.evaluate(
                    ride: extractedData,
                    isTrafficModeEnabled: self.isTrafficModeEnabled,
                    isGoingHomeModeEnabled: self.isGoingHomeModeEnabled,
                    settings: self.settings,
                    mapVerification: self.latestMapVerification,
                    learnedInsight: learnedInsight,
                    currentDailyNetProfit: self.totalLucroLiquidoAceito
                )
                
                self.currentVerdict = initialVerdict
                self.scheduleAutoResetTimer()
                self.recordHistoryIfNeeded(data: extractedData, verdict: initialVerdict)
                
                // IMPORTANTE: Só treina a IA em corridas reais da rua (!isSimulated), nunca quando o motorista clica nos botões de teste!
                if !isSimulated && isNewRide && self.settings.usarAprendizadoDeMaquina {
                    let shouldAutoEnableTraffic = AdaptiveLearningEngine.shared.recordOfferObserved(
                        ride: extractedData,
                        wasFinanciallyApproved: initialVerdict.status == .approved,
                        isPausedForBreak: self.isPausedForBreak
                    )
                    self.learnedProfiles = AdaptiveLearningEngine.shared.sortedProfiles
                    if shouldAutoEnableTraffic && !self.isTrafficModeEnabled {
                        self.isTrafficModeEnabled = true
                    }
                }
                
                SpeechManager.shared.triggerAlertIfNeeded(
                    mode: self.audioAlertMode,
                    verdict: initialVerdict,
                    fingerprint: extractedData.fingerprint,
                    isSimulated: isSimulated,
                    voiceType: self.driverVoiceType
                )
                
                // Toda vez que tocar uma NOVA corrida, faz uma nova consulta AO VIVO do trânsito no Apple Maps!
                if isNewRide && self.settings.usarVerificacaoAppleMaps && simulatedMapOverride == nil {
                    TrafficMapService.shared.verifyRouteTraffic(
                        for: extractedData,
                        cityContext: self.settings.cidadePadrao
                    ) { [weak self] verification in
                        guard let self = self, let verification = verification else { return }
                        self.latestMapVerification = verification
                        self.reEvaluateLastText()
                    }
                }
            }
            
            self.pipManager.refreshNow()
        }
    }
    
    // MARK: - Tratamento de Mensagens de Status e Auto-Reset
    
    private func extractSystemStatus(from text: String) -> String? {
        if text.hasPrefix(SharedConstants.systemStatusPrefix) {
            return String(text.dropFirst(SharedConstants.systemStatusPrefix.count))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "AGUARDANDO CORRIDA..." || trimmed == "CAPTURA PAUSADA" || trimmed == "CAPTURA ENCERRADA" {
            return trimmed
        }
        return nil
    }
    
    private func handleSystemStatus(_ status: String) {
        autoResetTimer?.invalidate()
        TrafficMapService.shared.cancelPendingCheck()
        latestMapVerification = nil
        SpeechManager.shared.resetLastSpoken()
        
        if status == "AUTO_ACCEPTED_LAST_RIDE" {
            if !rideHistory.isEmpty && !rideHistory[0].isAccepted {
                toggleAccepted(for: rideHistory[0].id)
            }
            currentVerdict = .waiting
        } else if status == "AGUARDANDO CORRIDA..." {
            isBroadcastActive = true
            currentVerdict = .waiting
        } else if status == "CAPTURA ENCERRADA" {
            isBroadcastActive = false
            currentVerdict = .systemStatus(status)
        } else {
            currentVerdict = .systemStatus(status)
        }
        pipManager.refreshNow()
    }
    
    private func scheduleAutoResetTimer() {
        autoResetTimer?.invalidate()
        let timeout = max(3.0, settings.autoResetSeconds)
        autoResetTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentVerdict = .waiting
            self.latestMapVerification = nil
            SpeechManager.shared.resetLastSpoken()
            self.pipManager.refreshNow()
        }
    }
    
    private func reEvaluateLastText() {
        guard let extractedData = ruleEngine.parseOCRText(lastRawOCRText) else {
            pipManager.refreshNow()
            return
        }
        let learnedInsight = settings.usarAprendizadoDeMaquina
            ? AdaptiveLearningEngine.shared.insight(for: extractedData.enderecoDestino)
            : nil
        
        let verdict = ruleEngine.evaluate(
            ride: extractedData,
            isTrafficModeEnabled: isTrafficModeEnabled,
            isGoingHomeModeEnabled: isGoingHomeModeEnabled,
            settings: settings,
            mapVerification: latestMapVerification,
            learnedInsight: learnedInsight,
            currentDailyNetProfit: totalLucroLiquidoAceito
        )
        let previousStatus = currentVerdict.status
        currentVerdict = verdict
        
        if let index = rideHistory.firstIndex(where: { $0.data.fingerprint == extractedData.fingerprint }) {
            rideHistory[index].verdict = verdict
            saveHistoryToDisk()
        }
        
        // Se o Apple Maps mudou o veredito (ex: era Aprovada na Uber, mas reprovou no trânsito real do Maps), avisa no áudio!
        if previousStatus != .waiting && previousStatus != verdict.status {
            SpeechManager.shared.triggerAlertIfNeeded(
                mode: audioAlertMode,
                verdict: verdict,
                fingerprint: extractedData.fingerprint,
                isSimulated: false,
                voiceType: driverVoiceType
            )
        }
        
        pipManager.refreshNow()
    }
    
    // MARK: - Histórico, Aprendizado e Contabilização de Corridas Aceitas
    
    private func recordHistoryIfNeeded(data: RideExtractedData, verdict: RideVerdict) {
        guard data.fingerprint != lastRecordedFingerprint else {
            return
        }
        lastRecordedFingerprint = data.fingerprint
        let item = RideHistoryItem(data: data, verdict: verdict, isAccepted: false, timestamp: Date())
        rideHistory.insert(item, at: 0)
        
        if rideHistory.count > 100 {
            rideHistory.removeLast()
        }
        saveHistoryToDisk()
    }
    
    func toggleAccepted(for itemID: UUID) {
        guard let index = rideHistory.firstIndex(where: { $0.id == itemID }) else { return }
        rideHistory[index].isAccepted.toggle()
        
        if rideHistory[index].isAccepted {
            AdaptiveLearningEngine.shared.recordRideAccepted(
                ride: rideHistory[index].data,
                wasFinanciallyApproved: rideHistory[index].verdict.status == .approved
            )
            learnedProfiles = AdaptiveLearningEngine.shared.sortedProfiles
        }
        saveHistoryToDisk()
    }
    
    func deleteHistoryItem(id: UUID) {
        rideHistory.removeAll(where: { $0.id == id })
        saveHistoryToDisk()
    }
    
    func toggleAcceptCurrentRide() {
        guard !rideHistory.isEmpty,
              rideHistory[0].data.fingerprint == lastRecordedFingerprint else {
            return
        }
        toggleAccepted(for: rideHistory[0].id)
    }
    
    func clearHistory() {
        rideHistory.removeAll()
        lastRecordedFingerprint = ""
        saveHistoryToDisk()
    }
    
    private func saveHistoryToDisk() {
        do {
            let data = try JSONEncoder().encode(rideHistory)
            UserDefaults.standard.set(data, forKey: Self.historyStorageKey)
        } catch {
            print("Erro ao salvar histórico de corridas: \(error)")
        }
    }
    
    private static func loadHistoryFromDisk() -> [RideHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: historyStorageKey) else {
            return []
        }
        do {
            let items = try JSONDecoder().decode([RideHistoryItem].self, from: data)
            return items
        } catch {
            print("Erro ao restaurar histórico de corridas: \(error)")
            return []
        }
    }
    
    func clearLearnedProfiles() {
        AdaptiveLearningEngine.shared.clearAllLearnedData()
        learnedProfiles = []
        reEvaluateLastText()
    }
    
    // Gerenciamento de Zonas de Risco (Qualquer distância)
    func addDangerZoneKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !settings.dangerZoneKeywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return
        }
        settings.dangerZoneKeywords.append(trimmed)
    }
    
    func removeDangerZoneKeyword(at offsets: IndexSet) {
        settings.dangerZoneKeywords.remove(atOffsets: offsets)
    }
    
    // Gerenciamento de Lista Negra (Volta Vazia: Marialva, Iguatemi, Floriano)
    func addBlacklistedKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !settings.blacklistedKeywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return
        }
        settings.blacklistedKeywords.append(trimmed)
    }
    
    func removeBlacklistedKeyword(at offsets: IndexSet) {
        settings.blacklistedKeywords.remove(atOffsets: offsets)
    }
    
    // Gerenciamento de Mercados / Atacadões (Embarque Problema)
    func addMarketKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !settings.marketPickupKeywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return
        }
        settings.marketPickupKeywords.append(trimmed)
    }
    
    func removeMarketKeyword(at offsets: IndexSet) {
        settings.marketPickupKeywords.remove(atOffsets: offsets)
    }
    
    // Gerenciamento de Destinos Favoritos (Rumo a Casa / Maringá)
    func addFavoriteHomeKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !settings.favoriteHomeKeywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return
        }
        settings.favoriteHomeKeywords.append(trimmed)
    }
    
    func removeFavoriteHomeKeyword(at offsets: IndexSet) {
        settings.favoriteHomeKeywords.remove(atOffsets: offsets)
    }
    
    func resetSettingsToDefault() {
        settings = RideSettings()
    }
    
    // MARK: - Escuta de Notificações Darwin vindas da Broadcast Extension
    
    private func registerDarwinNotificationObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let name = CFNotificationName(SharedConstants.darwinNotificationName as CFString)
        
        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer = observer else { return }
            let viewModel = Unmanaged<RideAssistantViewModel>.fromOpaque(observer).takeUnretainedValue()
            viewModel.readLatestTextFromAppGroup()
        }
        
        CFNotificationCenterAddObserver(
            center,
            observer,
            callback,
            name.rawValue,
            nil,
            .deliverImmediately
        )
    }
    
    private func readLatestTextFromAppGroup() {
        guard let latestText = SharedConstants.readSharedOCRText() else {
            return
        }
        handleNewOCRText(latestText)
    }
}
