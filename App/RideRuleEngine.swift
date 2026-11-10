import Foundation
import SwiftUI

/// Configurações personalizáveis do motorista (persistidas via UserDefaults)
struct RideSettings: Codable, Equatable {
    // MARK: - Inteligência Nativa (Apple Maps & Aprendizado de Máquina)
    
    /// Se true, consulta o trânsito real no Apple Maps (MapKit) para corrigir estimativas de tempo da Uber
    var usarVerificacaoAppleMaps: Bool = true
    
    /// Se true, usa o Aprendizado de Máquina local para detectar bairros evitados, volta vazia e auto-trânsito
    var usarAprendizadoDeMaquina: Bool = true
    
    /// Cidade/Estado padrão usada pelo Apple Maps quando o GPS não estiver ativo (ex: "Maringá, PR")
    var cidadePadrao: String = "Maringá, PR"
    
    /// Modo Discreto ("Passageiro a Bordo"): substitui termos como "CILADA" e "PERIGO" por avisos neutros na tela e na voz
    var modoDiscretoPassageiro: Bool = false
    
    // MARK: - Custos Operacionais, Tempo de Portão e Meta Diária
    
    /// Custo operacional do veículo por km rodado (combustível + manutenção/pneus, ex: R$ 0,65/km)
    var custoPorKm: Double = 0.65
    
    /// Tempo médio (em minutos) gasto esperando o passageiro sair pelo portão e embarcar/desembarcar
    var minutosEsperaPortao: Double = 1.5
    
    /// Se true, exibe o Lucro Líquido Real (descontando combustível) na linha de detalhes do PiP
    var exibirLucroLiquidoNoPiP: Bool = true
    
    /// Meta de lucro líquido diário do motorista para o Termômetro do Turno (ex: R$ 250,00)
    var metaDiariaLiquida: Double = 250.0
    
    // MARK: - Metas Financeiras da Corrida (Maringá / Sarandi / Marialva)
    
    /// Valor mínimo bruto de uma chamada para compensar parar o carro (ex: R$ 7,50)
    var minValorCorrida: Double = 7.50
    
    /// Exigência mínima de R$/h quando o Modo Trânsito/Chuva está ativo ou velocidade < 25 km/h
    var minGanhoHoraTransito: Double = 35.0
    
    /// Meta de R$/h em condições normais (abaixo disso cai no alerta Amarelo)
    var minGanhoHoraNormal: Double = 30.0
    
    /// Meta de R$/km em condições normais dentro de Maringá / Sarandi (abaixo disso cai no alerta Amarelo)
    var minGanhoKmNormal: Double = 1.65
    
    /// Exceção de Ouro: Ganho por hora mínimo para aprovar direto como "CORRIDA TOP"
    var goldGanhoHora: Double = 50.0
    
    /// Exceção de Ouro: Ganho por km mínimo para aprovar direto como "CORRIDA TOP"
    var goldGanhoKm: Double = 2.00
    
    /// Mínimo de R$/km aceitável quando a corrida leva para um destino "Rumo a Casa" (ou retorno Sarandi/Marialva -> Maringá)
    var minGanhoKmRumoACasa: Double = 1.40
    
    // MARK: - Filtros Operacionais e de Segurança
    
    /// Tempo máximo de busca em minutos (acima disso reprova como "CILADA: BUSCA LONGA")
    var maxTempoBuscaMin: Double = 5.0
    
    /// Distância máxima de busca em KM para ir até o passageiro (ex: 2.2 km)
    var maxKmBusca: Double = 2.2
    
    /// Distância total (km) a partir da qual a viagem é considerada longa para checagem de Volta Vazia
    var maxKmViagemLonga: Double = 10.0
    
    /// Mínimo de R$/km exigido no card para destinos de Volta Vazia (Marialva, Iguatemi, Floriano) onde você volta batendo lata
    var minGanhoKmListaNegra: Double = 2.20
    
    /// Nota mínima aceitável do passageiro (ex: 4.75)
    var minNotaPassageiro: Double = 4.75
    
    /// Quantidade mínima de viagens do passageiro para não ser considerado "Conta Nova / Suspeita" (ex: 15 viagens)
    var minViagensPassageiro: Int = 15
    
    /// Se true, passageiro com nota abaixo da mínima reprova (Vermelho); se false, apenas alerta (Amarelo)
    var reprovarNotaBaixa: Bool = true
    
    /// Se true, reprova automaticamente corridas com pagamento em Dinheiro / Espécie (Modo Noturno)
    var recusarCorridasDinheiro: Bool = false
    
    /// Segundos sem leitura de card até a janela PiP voltar para "AGUARDANDO CORRIDA..."
    var autoResetSeconds: Double = 10.0
    
    // MARK: - Listas Geográficas Inteligentes (Calibradas para Maringá, Sarandi e Marialva)
    
    /// 1. Zonas de Risco / Proibidas: Reprova IMEDIATAMENTE em qualquer distância (embarque ou destino)
    var dangerZoneKeywords: [String] = ["Vila Pedreira", "Zona de Risco"]
    
    /// 2. Destinos de Volta Vazia (Soma o custo de voltar vazio até Maringá/Sarandi!): Marialva, Iguatemi, Floriano, Rural
    /// (Sarandi NÃO entra aqui pois em Sarandi toca corrida para Sarandi mesmo ou voltando para Maringá!)
    var blacklistedKeywords: [String] = ["Marialva", "Iguatemi", "Floriano", "Rural"]
    
    /// 3. Embarque Problema (Supermercados / Atacadões): Alerta de perda de tempo carregando compras no porta-malas
    var marketPickupKeywords: [String] = ["Atacadão", "Assaí", "Muffato", "Condor", "Carrefour", "Supermercado"]
    
    /// 4. Destinos Favoritos / "Rumo a Casa" (Sua Base em Maringá)
    var favoriteHomeKeywords: [String] = ["Maringá", "Centro", "Zona 7", "Zona 1"]
    
    private static let storageKey = "uber_helper_driver_settings_v4"
    
    static func load() -> RideSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(RideSettings.self, from: data) else {
            return RideSettings()
        }
        return decoded
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
    }
}

/// Dados brutos extraídos do card da Uber via Regex
struct RideExtractedData: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    let valorTotal: Double
    let tempoBuscaMin: Double
    let kmBusca: Double
    let enderecoBusca: String
    let tempoViagemMin: Double
    let kmViagem: Double
    let enderecoDestino: String
    let temParada: Bool
    let notaPassageiro: Double?
    let numeroViagensPassageiro: Int?
    let passageiroVerificado: Bool
    let pagamentoEmDinheiro: Bool
    
    // MARK: - Cálculos Matemáticos do Card (Ir Buscar + Levar)
    
    var tempoTotal: Double {
        tempoBuscaMin + tempoViagemMin
    }
    
    var kmTotal: Double {
        kmBusca + kmViagem
    }
    
    var ganhoHora: Double {
        guard tempoTotal > 0 else { return 0.0 }
        return valorTotal / (tempoTotal / 60.0)
    }
    
    var ganhoKm: Double {
        guard kmTotal > 0 else { return 0.0 }
        return valorTotal / kmTotal
    }
    
    var velocidadeMediaKmH: Double {
        guard tempoTotal > 0 else { return 0.0 }
        return kmTotal / (tempoTotal / 60.0)
    }
    
    // MARK: - Cálculos de Lucro Líquido Real (Suporta Ida + Volta Vazia para Marialva/Iguatemi/Floriano)
    
    func custoOperacional(custoPorKm: Double, extraReturnKm: Double = 0.0) -> Double {
        (kmTotal + max(0.0, extraReturnKm)) * max(0.0, custoPorKm)
    }
    
    func lucroLiquido(custoPorKm: Double, extraReturnKm: Double = 0.0) -> Double {
        max(0.0, valorTotal - custoOperacional(custoPorKm: custoPorKm, extraReturnKm: extraReturnKm))
    }
    
    func ganhoHoraLiquido(custoPorKm: Double, extraReturnKm: Double = 0.0, extraMinutes: Double = 0.0) -> Double {
        let totalMin = tempoTotal + max(0.0, extraMinutes)
        guard totalMin > 0 else { return 0.0 }
        return lucroLiquido(custoPorKm: custoPorKm, extraReturnKm: extraReturnKm) / (totalMin / 60.0)
    }
    
    /// Identificador de conteúdo da corrida para deduplicar histórico e alerta de voz
    var fingerprint: String {
        String(format: "%.2f_%.1f_%.0f_%@", valorTotal, kmTotal, tempoTotal, enderecoDestino)
    }
}

/// Status do semáforo de avaliação da corrida
enum VerdictStatus: String, Codable, Equatable {
    case waiting    // Neutro (Aguardando / Status do sistema)
    case approved   // Verde (Corrida boa ou Top)
    case goingHome  // Azul Esmeralda (Retorno p/ Maringá ou Rumo a Casa)
    case warning    // Amarelo/Laranja (Atenção: mediana, conta nova ou embarque em mercado)
    case rejected   // Vermelho (Cilada ou Zona de Risco)
}

/// Resultado final da avaliação da corrida para alimentar a janela flutuante (PiP)
struct RideVerdict: Equatable {
    let status: VerdictStatus
    let message: String
    let detailMetrics: String
    let passengerBadge: String?
    let isCashPayment: Bool
    let speechText: String?
    
    var isApproved: Bool {
        status == .approved || status == .goingHome || status == .warning || status == .waiting
    }
    
    var backgroundColor: Color {
        switch status {
        case .approved:
            return Color(red: 0.10, green: 0.65, blue: 0.25) // Verde Vibrante
        case .goingHome:
            return Color(red: 0.08, green: 0.48, blue: 0.78) // Azul Royal / Retorno Maringá
        case .warning:
            return Color(red: 0.85, green: 0.50, blue: 0.05) // Laranja / Amarelo Escuro
        case .rejected:
            return Color(red: 0.85, green: 0.15, blue: 0.15) // Vermelho Alerta
        case .waiting:
            return Color(red: 0.16, green: 0.22, blue: 0.30) // Grafite Azulado Neutro
        }
    }
    
    static let waiting = RideVerdict(
        status: .waiting,
        message: "AGUARDANDO CORRIDA...",
        detailMetrics: "Abra o app da Uber com o PiP ativo",
        passengerBadge: nil,
        isCashPayment: false,
        speechText: nil
    )
    
    static func systemStatus(_ title: String, subtitle: String = "Verifique a transmissão de tela") -> RideVerdict {
        RideVerdict(
            status: .waiting,
            message: title,
            detailMetrics: subtitle,
            passengerBadge: nil,
            isCashPayment: false,
            speechText: nil
        )
    }
}

/// Item salvo no histórico de corridas analisadas na sessão
struct RideHistoryItem: Identifiable, Equatable {
    let id: UUID
    let data: RideExtractedData
    var verdict: RideVerdict
    var isAccepted: Bool
    
    init(data: RideExtractedData, verdict: RideVerdict, isAccepted: Bool = false) {
        self.id = data.id
        self.data = data
        self.verdict = verdict
        self.isAccepted = isAccepted
    }
}

/// Motor de Decisão do App: Extrai os dados via Regex e aplica a matemática real de Maringá, Sarandi e Marialva.
final class RideRuleEngine {
    
    // MARK: - 1. Extração via Regex (Parser do OCR)
    
    func parseOCRText(_ rawText: String) -> RideExtractedData? {
        // 1. Extrair o Valor Total (R$ XX,XX ou RS XX,XX) ignorando valores seguidos por "/km" ou "/h"
        let pricePattern = #"R[\$S]\s*[\r\n]*\s*(\d+[.,]\d{2})(?!\s*\/?\s*(?:km|h))"#
        guard let valorTotal = extractFirstDouble(pattern: pricePattern, in: rawText) else {
            return nil
        }
        
        // 2. Extrair os blocos de Tempo (Horas opcionais + Minutos) + Distância + Endereço:
        // 1º bloco = Ir buscar o passageiro | 2º bloco = Levar o passageiro ao destino
        let legPattern = #"(?:(\d+)\s*h(?:oras?)?\s*)?(\d+)\s*(?:min(?:utos?)?\.?)\s*[\r\n]*\s*\(\s*(\d+(?:[.,]\d+)?)\s*km\s*\)\s*[\r\n]*\s*([^\r\n]+)"#
        let legs = extractRideLegs(pattern: legPattern, in: rawText)
        
        guard legs.count >= 2 else {
            return nil
        }
        
        let pickupLeg = legs[0]
        let tripLeg = legs[1]
        
        // 3. Checar se o texto contém a palavra "parada" ou "paradas"
        let stopPattern = #"\bparadas?\b"#
        let temParada = rawText.range(of: stopPattern, options: [.regularExpression, .caseInsensitive]) != nil
        
        // 4. Extrair Nota do Passageiro, Número de Avaliações entre parênteses "(254)" e Selo Verificado
        let ratingInfo = extractPassengerRatingAndTrips(in: rawText)
        let passageiroVerificado = rawText.range(of: #"\bverificado\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        
        // 5. Detectar se a corrida é paga em Dinheiro / Espécie
        let cashPattern = #"\b(?:dinheiro|esp[eé]cie|troco)\b"#
        let pagamentoEmDinheiro = rawText.range(of: cashPattern, options: [.regularExpression, .caseInsensitive]) != nil
        
        return RideExtractedData(
            valorTotal: valorTotal,
            tempoBuscaMin: pickupLeg.minutes,
            kmBusca: pickupLeg.kilometers,
            enderecoBusca: pickupLeg.address,
            tempoViagemMin: tripLeg.minutes,
            kmViagem: tripLeg.kilometers,
            enderecoDestino: tripLeg.address,
            temParada: temParada,
            notaPassageiro: ratingInfo.rating,
            numeroViagensPassageiro: ratingInfo.tripsCount,
            passageiroVerificado: passageiroVerificado,
            pagamentoEmDinheiro: pagamentoEmDinheiro
        )
    }
    
    // MARK: - 2. Avaliação das Regras de Negócio (Matemática Real: Maringá, Sarandi e Marialva)
    
    func evaluate(
        ride: RideExtractedData,
        isTrafficModeEnabled: Bool,
        isGoingHomeModeEnabled: Bool = false,
        settings: RideSettings = RideSettings(),
        mapVerification: MapTrafficVerification? = nil,
        learnedInsight: LearnedRideInsight? = nil,
        currentDailyNetProfit: Double = 0.0
    ) -> RideVerdict {
        let discreet = settings.modoDiscretoPassageiro
        
        // 1. Verificar se o DESTINO é de Volta Vazia (Marialva, Iguatemi, Floriano, Rural)
        // IMPORTANTE: Se o embarque já é em Marialva/Iguatemi e o destino é Maringá/Sarandi, NÃO cobra volta vazia!
        let destinationDeadheadMatch = findMatchingKeyword(in: ride.enderecoDestino, keywords: settings.blacklistedKeywords)
        let pickupDeadheadMatch = findMatchingKeyword(in: ride.enderecoBusca, keywords: settings.blacklistedKeywords)
        let isGoingToDeadheadDestination = (destinationDeadheadMatch != nil) && (pickupDeadheadMatch == nil)
        let isReturningFromOutskirts = (pickupDeadheadMatch != nil || containsKeyword(ride.enderecoBusca, in: ["Sarandi", "Marialva"]))
            && (findMatchingKeyword(in: ride.enderecoDestino, keywords: settings.favoriteHomeKeywords) != nil)
        
        // 2. Se o destino for Marialva/Iguatemi/Floriano, embutimos ~60% do trecho de viagem como retorno vazio até Sarandi/Maringá
        let extraReturnKm: Double = isGoingToDeadheadDestination ? (ride.kmViagem * 0.60) : 0.0
        let extraReturnMinutes: Double = isGoingToDeadheadDestination ? (ride.tempoViagemMin * 0.55) : 0.0
        
        // 3. Tempo da ida (usando Apple Maps se disponível) + Taxa de Portão quando aplicável
        let baseRideMinutes: Double = {
            if settings.usarVerificacaoAppleMaps, let map = mapVerification {
                return max(1.0, map.appleMapsTotalMinutes)
            }
            return max(1.0, ride.tempoTotal)
        }()
        
        let effectiveGanhoHora = ride.valorTotal / (baseRideMinutes / 60.0)
        let effectiveVelMedia = ride.kmTotal / (baseRideMinutes / 60.0)
        
        // Lucro líquido real (já descontando combustível da volta vazia caso seja Marialva/Iguatemi/Floriano!)
        let lucroLiq = ride.lucroLiquido(custoPorKm: settings.custoPorKm, extraReturnKm: extraReturnKm)
        let ganhoHoraLiqComVolta = ride.ganhoHoraLiquido(
            custoPorKm: settings.custoPorKm,
            extraReturnKm: extraReturnKm,
            extraMinutes: settings.minutosEsperaPortao + extraReturnMinutes
        )
        
        let ganhoKmStr = String(format: "%.2f", ride.ganhoKm).replacingOccurrences(of: ".", with: ",")
        let ganhoHoraStr = String(format: "%.2f", effectiveGanhoHora).replacingOccurrences(of: ".", with: ",")
        let velMediaStr = String(format: "%.0f", effectiveVelMedia)
        let lucroLiqStr = String(format: "%.2f", lucroLiq).replacingOccurrences(of: ".", with: ",")
        
        let timeLabel: String = {
            if settings.usarVerificacaoAppleMaps, let map = mapVerification, abs(map.minutesDifferenceFromUber) >= 3.0 {
                return String(format: "%.0fm Maps", baseRideMinutes)
            }
            return String(format: "%.0f min", baseRideMinutes)
        }()
        
        let metricsSummary: String = {
            if settings.exibirLucroLiquidoNoPiP {
                return String(
                    format: "Líq R$ %@ | %.1f km | %@ (%@ km/h)",
                    lucroLiqStr, ride.kmTotal, timeLabel, velMediaStr
                ).replacingOccurrences(of: ".", with: ",")
            } else {
                return String(
                    format: "R$ %.2f | %.1f km | %@ (%@ km/h)",
                    ride.valorTotal, ride.kmTotal, timeLabel, velMediaStr
                ).replacingOccurrences(of: ".", with: ",")
            }
        }()
        
        // Badge da nota + número de viagens do passageiro (ex: "★ 4,97 (254) ✓" ou "⚠️ ★ 5,00 (4)")
        let badge: String? = {
            guard let nota = ride.notaPassageiro else { return nil }
            let notaStr = String(format: "%.2f", nota).replacingOccurrences(of: ".", with: ",")
            let tripsStr = ride.numeroViagensPassageiro.map { " (\($0))" } ?? ""
            let checkStr = ride.passageiroVerificado ? " ✓" : ""
            return "★ \(notaStr)\(tripsStr)\(checkStr)"
        }()
        
        // PRIORIDADE 1: Zona de Risco / Proibida Manual (Qualquer distância, embarque ou destino)
        if let matchedDanger = findMatchingKeyword(
            in: "\(ride.enderecoBusca) \(ride.enderecoDestino)",
            keywords: settings.dangerZoneKeywords
        ) {
            return RideVerdict(
                status: .rejected,
                message: discreet ? "FORA DE ROTA: RESTRITA" : "PERIGO: \(matchedDanger.uppercased())",
                detailMetrics: discreet ? metricsSummary : "Zona Proibida • \(metricsSummary)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: discreet ? "Recusar: fora de rota." : "Perigo! Zona proibida: \(matchedDanger)."
            )
        }
        
        // PRIORIDADE 1.5: Zona Evitada Aprendida por Machine Learning
        if settings.usarAprendizadoDeMaquina, let insight = learnedInsight, insight.isLearnedDanger {
            return RideVerdict(
                status: .rejected,
                message: discreet ? "FORA DE ROTA: IA" : "🧠 IA: VOCÊ EVITA \(insight.regionName.uppercased())",
                detailMetrics: "Padrão de recusa detectado • \(metricsSummary)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: discreet ? "Recusar: região evitada." : "Alerta de aprendizado: você costuma evitar \(insight.regionName)."
            )
        }
        
        // PRIORIDADE 2: Bloqueio de Pagamento em Dinheiro (Modo Noturno / Segurança)
        if settings.recusarCorridasDinheiro && ride.pagamentoEmDinheiro {
            return RideVerdict(
                status: .rejected,
                message: discreet ? "RECUSAR: MODALIDADE" : "CILADA: PGTO EM DINHEIRO",
                detailMetrics: metricsSummary,
                passengerBadge: badge,
                isCashPayment: true,
                speechText: discreet ? "Recusar: modalidade." : "Cilada: pagamento em dinheiro."
            )
        }
        
        // PRIORIDADE 3: Múltiplas Paradas
        if ride.temParada {
            return RideVerdict(
                status: .rejected,
                message: discreet ? "RECUSAR: PARADAS" : "CILADA: TEM PARADA",
                detailMetrics: metricsSummary,
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: discreet ? "Recusar: inclui paradas." : "Cilada: tem parada."
            )
        }
        
        // PRIORIDADE 4: Nota do Passageiro Abaixo do Mínimo
        if let nota = ride.notaPassageiro, nota < settings.minNotaPassageiro, settings.reprovarNotaBaixa {
            let notaStr = String(format: "%.2f", nota).replacingOccurrences(of: ".", with: ",")
            return RideVerdict(
                status: .rejected,
                message: discreet ? "RECUSAR: CRITÉRIO (\(notaStr))" : "CILADA: NOTA BAIXA (\(notaStr))",
                detailMetrics: metricsSummary,
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: discreet ? "Recusar: critério de nota." : "Cilada: passageiro com nota baixa, \(notaStr)."
            )
        }
        
        // PRIORIDADE 5: Regra Especial Marialva / Iguatemi / Floriano (ANTES da Exceção de Ouro!)
        // Só aprova ir para Marialva/Iguatemi/Floriano se o valor for BOM DE FATO (pagando a ida + a volta vazia!)
        if isGoingToDeadheadDestination, let destName = destinationDeadheadMatch {
            if ride.ganhoKm < settings.minGanhoKmListaNegra && ganhoHoraLiqComVolta < 30.0 {
                let liqHoraStr = String(format: "%.0f", ganhoHoraLiqComVolta)
                return RideVerdict(
                    status: .rejected,
                    message: "CILADA: VOLTA VAZIA (\(destName.uppercased()))",
                    detailMetrics: "R$ \(ganhoKmStr)/km • C/ volta: Líq R$ \(lucroLiqStr) (R$\(liqHoraStr)/h)",
                    passengerBadge: badge,
                    isCashPayment: ride.pagamentoEmDinheiro,
                    speechText: discreet
                        ? "Recusar: \(destName) não compensa a volta."
                        : "Cilada para \(destName): apenas \(ganhoKmStr) por quilômetro, sobra \(lucroLiqStr) reais descontando a volta."
                )
            }
        }
        
        // PRIORIDADE 5.5: Aprendizado de Volta Vazia pela IA Local
        if settings.usarAprendizadoDeMaquina,
           let insight = learnedInsight,
           insight.isLearnedDeadhead,
           ride.ganhoKm < settings.minGanhoKmListaNegra {
            let waitMin = Int(insight.averageWaitMinutes)
            return RideVerdict(
                status: .rejected,
                message: "🧠 IA: VOLTA VAZIA (\(waitMin)m S/ CORRIDA)",
                detailMetrics: "Dest: \(insight.regionName) • R$ \(ganhoKmStr)/km",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: "Cilada aprendida: \(insight.regionName) costuma deixar \(waitMin) minutos sem corrida."
            )
        }
        
        // PRIORIDADE 6: Modo "Rumo a Casa" ou Retorno de Sarandi/Marialva -> Maringá
        if (isGoingHomeModeEnabled || isReturningFromOutskirts),
           let matchedHome = findMatchingKeyword(in: ride.enderecoDestino, keywords: settings.favoriteHomeKeywords),
           ride.ganhoKm >= settings.minGanhoKmRumoACasa,
           ride.tempoBuscaMin <= settings.maxTempoBuscaMin {
            let label = isReturningFromOutskirts ? "🏠 VOLTA P/ \(matchedHome.uppercased())" : "🏠 RUMO A CASA"
            return RideVerdict(
                status: .goingHome,
                message: "\(label): R$\(ganhoKmStr)/km",
                detailMetrics: "Dest: \(matchedHome) • Líq R$ \(lucroLiqStr)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: "Retorno para \(matchedHome)! \(ganhoKmStr) por quilômetro."
            )
        }
        
        // PRIORIDADE 7: Exceção de Ouro (Avaliada com o ganho/hora real corrigido pelo Apple Maps se disponível)
        // Nota: Se for embarque em Supermercado/Atacadão ou Conta Nova (< minViagensPassageiro), não pula para Exceção de Ouro cega,
        // garantindo que o motorista veja o alerta laranja de carrinho de compras ou conta recém-criada!
        let matchedMarket = findMatchingKeyword(in: ride.enderecoBusca, keywords: settings.marketPickupKeywords)
        let isNewAccount = (ride.numeroViagensPassageiro != nil) && (ride.numeroViagensPassageiro! < settings.minViagensPassageiro)
        let willHitDailyGoal = (currentDailyNetProfit > 0.0) &&
            (currentDailyNetProfit < settings.metaDiariaLiquida) &&
            ((currentDailyNetProfit + lucroLiq) >= settings.metaDiariaLiquida)
        let metaIntStr = String(format: "%.0f", settings.metaDiariaLiquida)
        
        if matchedMarket == nil && !isNewAccount &&
           effectiveGanhoHora >= settings.goldGanhoHora && ride.ganhoKm >= settings.goldGanhoKm && ride.valorTotal >= settings.minValorCorrida {
            let prefix: String = {
                if willHitDailyGoal {
                    return "🎯 BATE OS \(metaIntStr)"
                }
                if let destName = destinationDeadheadMatch {
                    return "🏆 \(destName.uppercased()) TOP"
                }
                return (mapVerification?.uberOverestimatedTime == true) ? "🗺️ MAPS TOP" : "CORRIDA TOP"
            }()
            return RideVerdict(
                status: .approved,
                message: "\(prefix): R$\(ganhoKmStr)/km",
                detailMetrics: "R$ \(ganhoHoraStr)/h • \(metricsSummary)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: willHitDailyGoal
                    ? "Corrida top! Com ela você bate sua meta de \(metaIntStr) reais!"
                    : "Corrida top! \(ganhoKmStr) por quilômetro, lucro \(lucroLiqStr) reais."
            )
        }
        
        // PRIORIDADE 8: Busca Longa (Por Tempo > 5 min OU por Distância > maxKmBusca)
        if ride.tempoBuscaMin > settings.maxTempoBuscaMin || ride.kmBusca > settings.maxKmBusca {
            let kmBuscaStr = String(format: "%.1f", ride.kmBusca).replacingOccurrences(of: ".", with: ",")
            return RideVerdict(
                status: .rejected,
                message: discreet ? "FORA DE META: BUSCA" : "CILADA: BUSCA LONGA",
                detailMetrics: "Busca: \(Int(ride.tempoBuscaMin)) min (\(kmBuscaStr) km) • \(metricsSummary)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: "Recusar: busca longa de \(kmBuscaStr) quilômetros."
            )
        }
        
        // PRIORIDADE 9: Corrida Mixuruca (Valor Total muito baixo, ex: < R$ 7,50)
        if ride.valorTotal < settings.minValorCorrida {
            let valStr = String(format: "%.2f", ride.valorTotal).replacingOccurrences(of: ".", with: ",")
            return RideVerdict(
                status: .warning,
                message: "🪙 VALOR BAIXO: SÓ R$ \(valStr)",
                detailMetrics: "R$ \(ganhoKmStr)/km • \(metricsSummary)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: "Atenção: valor total baixo, apenas \(valStr) reais."
            )
        }
        
        // PRIORIDADE 10: Trânsito / Chuva (Avalia tanto o modo trânsito quanto o trânsito real detectado no Apple Maps)
        if isTrafficModeEnabled || effectiveVelMedia < 25.0 || (mapVerification?.hasHiddenTrafficTrap == true) {
            if effectiveGanhoHora < settings.minGanhoHoraTransito {
                let prefix = (mapVerification?.hasHiddenTrafficTrap == true) ? "🗺️ MAPS TRÂNSITO" : "TRÂNSITO"
                return RideVerdict(
                    status: .rejected,
                    message: "\(prefix): SÓ R$\(ganhoHoraStr)/h",
                    detailMetrics: "\(timeLabel) • R$ \(ganhoKmStr)/km",
                    passengerBadge: badge,
                    isCashPayment: ride.pagamentoEmDinheiro,
                    speechText: "Reprovada no trânsito: apenas \(ganhoHoraStr) por hora."
                )
            } else {
                let prefix = (mapVerification?.uberOverestimatedTime == true) ? "🗺️ LIVRE NO MAPS" : "APROVADA NO TRÂNSITO"
                return RideVerdict(
                    status: .approved,
                    message: prefix,
                    detailMetrics: "R$ \(ganhoHoraStr)/h | \(metricsSummary)",
                    passengerBadge: badge,
                    isCashPayment: ride.pagamentoEmDinheiro,
                    speechText: "Aprovada no trânsito: \(ganhoHoraStr) por hora."
                )
            }
        }
        
        // PRIORIDADE 11: Alertas Amarelos de Rua (Embarque em Supermercado/Atacadão, Conta Nova < 15 viagens, Nota em aviso ou Ganhos Medianos)
        if let matchedMarket = findMatchingKeyword(in: ride.enderecoBusca, keywords: settings.marketPickupKeywords) {
            return RideVerdict(
                status: .warning,
                message: "🛒 EMBARQUE: \(matchedMarket.uppercased())",
                detailMetrics: "Possível compra/sacolas • R$ \(ganhoKmStr)/km",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: "Atenção: embarque em mercado, \(matchedMarket)."
            )
        }
        
        if let trips = ride.numeroViagensPassageiro, trips < settings.minViagensPassageiro {
            return RideVerdict(
                status: .warning,
                message: "🛡️ CONTA NOVA (\(trips) VIAGENS)",
                detailMetrics: "R$ \(ganhoKmStr)/km | \(metricsSummary)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: "Atenção: passageiro conta nova com apenas \(trips) viagens."
            )
        }
        
        if let nota = ride.notaPassageiro, nota < settings.minNotaPassageiro {
            let notaStr = String(format: "%.2f", nota).replacingOccurrences(of: ".", with: ",")
            return RideVerdict(
                status: .warning,
                message: "ATENÇÃO: NOTA \(notaStr)",
                detailMetrics: "R$ \(ganhoKmStr)/km | \(metricsSummary)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: "Atenção: nota \(notaStr). \(ganhoKmStr) por quilômetro."
            )
        }
        
        if ride.ganhoKm < settings.minGanhoKmNormal || effectiveGanhoHora < settings.minGanhoHoraNormal {
            return RideVerdict(
                status: .warning,
                message: "MEDIANA: R$\(ganhoKmStr)/km",
                detailMetrics: "R$ \(ganhoHoraStr)/h • \(metricsSummary)",
                passengerBadge: badge,
                isCashPayment: ride.pagamentoEmDinheiro,
                speechText: "Corrida mediana: \(ganhoKmStr) por quilômetro."
            )
        }
        
        // PRIORIDADE 12: Corrida Normal Aprovada (Verde)
        let normalMsg = willHitDailyGoal
            ? "🎯 BATE OS \(metaIntStr): R$\(ganhoKmStr)/km"
            : "R$ \(ganhoKmStr)/km | R$ \(ganhoHoraStr)/h"
        let normalSpeech = willHitDailyGoal
            ? "Aprovada! Com essa corrida você bate sua meta de \(metaIntStr) reais!"
            : "Aprovada: \(ganhoKmStr) por quilômetro, lucro \(lucroLiqStr) reais."
        
        return RideVerdict(
            status: .approved,
            message: normalMsg,
            detailMetrics: metricsSummary,
            passengerBadge: badge,
            isCashPayment: ride.pagamentoEmDinheiro,
            speechText: normalSpeech
        )
    }
    
    // MARK: - Helpers Internos de Regex
    
    private func containsKeyword(_ text: String, in keywords: [String]) -> Bool {
        findMatchingKeyword(in: text, keywords: keywords) != nil
    }
    
    private func findMatchingKeyword(in text: String, keywords: [String]) -> String? {
        let normalizedText = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        
        for keyword in keywords {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalizedKeyword = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if normalizedText.contains(normalizedKeyword) {
                return trimmed
            }
        }
        return nil
    }
    
    private func extractFirstDouble(pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let normalizedString = text[valueRange].replacingOccurrences(of: ",", with: ".")
        return Double(normalizedString)
    }
    
    private func extractPassengerRatingAndTrips(in text: String) -> (rating: Double?, tripsCount: Int?) {
        let lines = text.components(separatedBy: .newlines)
        // Captura a nota (ex: 4,97) e opcionalmente a quantidade de viagens entre parênteses ao lado: "4,97 (254)"
        let ratingPattern = #"\b([34][.,]\d{2}|5[.,]00)\b(?:\s*\(\s*(\d+)\s*\))?"#
        guard let regex = try? NSRegularExpression(pattern: ratingPattern, options: []) else {
            return (nil, nil)
        }
        
        for line in lines {
            let upper = line.uppercased()
            if upper.contains("R$") || upper.contains("RS") || upper.contains("/KM") {
                continue
            }
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: nsRange),
               match.numberOfRanges > 1,
               let ratingRange = Range(match.range(at: 1), in: line) {
                let normalized = line[ratingRange].replacingOccurrences(of: ",", with: ".")
                if let ratingValue = Double(normalized), (3.0...5.0).contains(ratingValue) {
                    var tripsCount: Int? = nil
                    if match.numberOfRanges > 2 {
                        let tripsNSRange = match.range(at: 2)
                        if tripsNSRange.location != NSNotFound, let tripsRange = Range(tripsNSRange, in: line) {
                            tripsCount = Int(line[tripsRange])
                        }
                    }
                    return (ratingValue, tripsCount)
                }
            }
        }
        return (nil, nil)
    }
    
    private struct RideLeg {
        let minutes: Double
        let kilometers: Double
        let address: String
    }
    
    private func extractRideLegs(pattern: String, in text: String) -> [RideLeg] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        
        return matches.compactMap { match in
            guard match.numberOfRanges >= 5,
                  let minRange = Range(match.range(at: 2), in: text),
                  let kmRange = Range(match.range(at: 3), in: text),
                  let addrRange = Range(match.range(at: 4), in: text) else {
                return nil
            }
            
            var hours: Double = 0.0
            let hourNSRange = match.range(at: 1)
            if hourNSRange.location != NSNotFound, let hourRange = Range(hourNSRange, in: text) {
                hours = Double(text[hourRange]) ?? 0.0
            }
            
            let minStr = text[minRange].replacingOccurrences(of: ",", with: ".")
            let kmStr = text[kmRange].replacingOccurrences(of: ",", with: ".")
            let address = String(text[addrRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let minutesPart = Double(minStr), let kilometers = Double(kmStr) else {
                return nil
            }
            
            let totalMinutes = (hours * 60.0) + minutesPart
            return RideLeg(minutes: totalMinutes, kilometers: kilometers, address: address)
        }
    }
}
