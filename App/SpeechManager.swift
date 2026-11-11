import Foundation
import AVFoundation
import AudioToolbox
import UserNotifications

/// Tipos de voz selecionáveis para falar os alertas
enum DriverVoiceType: String, CaseIterable, Codable, Identifiable {
    case femaleNatural = "Feminina Suave"
    case maleFelipe = "Masculina (Felipe)"
    case systemAuto = "Automática (iOS)"
    
    var id: String { rawValue }
}

/// Modos de alerta sonoro disponíveis para o motorista
enum AudioAlertMode: String, CaseIterable, Codable, Identifiable {
    case off = "Silencioso"
    case beep = "Bipe Rápido"
    case voice = "Voz (TTS)"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .off: return "speaker.slash.fill"
        case .beep: return "bell.badge.fill"
        case .voice: return "speaker.wave.2.fill"
        }
    }
}

/// Gerenciador de Voz, Bipes e Banners Topo de Tela (Padrão GigU iOS).
/// Inclui trava anti-gagueira por Preço + Cooldown de 12 segundos para que variações de OCR
/// entre frames consecutivos da Uber NUNCA interrompam ou repitam a fala no meio!
final class SpeechManager: NSObject, UNUserNotificationCenterDelegate {
    
    static let shared = SpeechManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var lastAlertedFingerprint: String = ""
    private var lastAlertedPrice: Double = -1.0
    private var lastAlertedTime: CFAbsoluteTime = 0
    private var lastAlertedStatus: VerdictStatus = .waiting
    
    /// Tempo mínimo (em segundos) de trava para não repetir a voz na mesma corrida de mesmo valor
    private let samePriceCooldownSeconds: CFAbsoluteTime = 12.0
    
    private override init() {
        super.init()
        configureNotificationBannerPermission()
    }
    
    private func configureNotificationBannerPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }
    
    /// Exibe o banner no topo mesmo se o PiP estiver ativo
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
    
    /// Dispara o alerta sonoro (Voz Estilo GigU ou Bipe) + Banner de Topo Estilo GigU,
    /// com blindagem total contra repetição/corte durante os frames do OCR da Uber.
    func triggerAlertIfNeeded(
        mode: AudioAlertMode,
        verdict: RideVerdict,
        fingerprint: String,
        isSimulated: Bool = false,
        voiceType: DriverVoiceType = .maleFelipe
    ) {
        let status = verdict.status
        guard status != .waiting else { return }
        
        let now = CFAbsoluteTimeGetCurrent()
        let isSamePriceWithinCooldown = !isSimulated
            && (verdict.ridePrice > 0)
            && (abs(verdict.ridePrice - lastAlertedPrice) < 0.05)
            && ((now - lastAlertedTime) < samePriceCooldownSeconds)
        
        let isSameFingerprint = (fingerprint == lastAlertedFingerprint)
        let didStatusFlip = (isSameFingerprint || isSamePriceWithinCooldown)
            && (status != lastAlertedStatus)
            && (lastAlertedStatus != .waiting)
        
        // Se for a mesma corrida (mesmo preço dentro de 12s ou mesmo fingerprint) e o status não mudou, ignora!
        if !isSimulated && (isSameFingerprint || isSamePriceWithinCooldown) && !didStatusFlip {
            return
        }
        
        // Se o sintetizador já está falando na rua e ainda é a mesma corrida, NUNCA corta a fala no meio!
        if !isSimulated && synthesizer.isSpeaking && isSamePriceWithinCooldown {
            return
        }
        
        lastAlertedFingerprint = fingerprint
        lastAlertedPrice = verdict.ridePrice
        lastAlertedTime = now
        lastAlertedStatus = status
        
        // 1. Dispara Banner de Topo Estilo GigU (quando em corrida real na Uber)
        if !isSimulated {
            postGiguTopBanner(for: verdict)
        }
        
        // 2. Dispara Áudio (Bipe ou Voz limpa estilo GigU)
        guard mode != .off else { return }
        
        switch mode {
        case .off:
            // Modo Silencioso / Mudo: nenhum som ou fala
            break
        case .beep:
            // Apenas o Bipe do sistema: zero voz
            playSystemBeep(for: status)
        case .voice:
            // Apenas a Voz da Siri / Felipe: zero bipe
            if let text = verdict.speechText, !text.isEmpty {
                speakGiguStyle(text, forceInterrupt: isSimulated, voiceType: voiceType)
            }
        }
    }
    
    private func playSystemBeep(for status: VerdictStatus) {
        switch status {
        case .approved, .goingHome:
            AudioServicesPlaySystemSound(1057) // Suave e positivo
        case .warning:
            AudioServicesPlaySystemSound(1106) // Alerta atenção
        case .rejected:
            AudioServicesPlaySystemSound(1073) // Alerta grave
        case .waiting:
            break
        }
    }
    
    /// Seleciona a voz em pt-BR de acordo com a preferência do motorista
    private func selectConfiguredVoice(preferredType: DriverVoiceType = .maleFelipe) -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let ptVoices = allVoices.filter { $0.language == "pt-BR" || $0.language.hasPrefix("pt") }
        
        switch preferredType {
        case .maleFelipe:
            // 1. Procura primeiro por vozes masculinas naturais (Felipe, Daniel ou Siri masculina)
            if let male = ptVoices.first(where: {
                $0.name.localizedCaseInsensitiveContains("felipe") ||
                $0.name.localizedCaseInsensitiveContains("daniel") ||
                $0.gender == .male
            }) {
                return male
            }
        case .femaleNatural:
            // Procura voz feminina aprimorada (não compacta/robô)
            if let female = ptVoices.first(where: {
                ($0.quality == .premium || $0.quality == .enhanced) && $0.gender == .female
            }) {
                return female
            }
        case .systemAuto:
            break
        }
        
        // Vozes Siri ou aprimoradas do iOS
        if let enhanced = ptVoices.first(where: { $0.quality == .premium || $0.quality == .enhanced }) {
            return enhanced
        }
        
        // Padrão do sistema pt-BR
        return AVSpeechSynthesisVoice(language: "pt-BR") ?? ptVoices.first
    }
    
    private func speakGiguStyle(_ text: String, forceInterrupt: Bool, voiceType: DriverVoiceType = .maleFelipe) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("[SpeechManager] Erro AVAudioSession: \(error)")
        }
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectConfiguredVoice(preferredType: voiceType)
        
        // Modulação confortável: velocidade 0.48 com pitch 0.95 = voz encorpada, rápida e natural
        utterance.rate = 0.48
        utterance.pitchMultiplier = 0.96
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
    }
    
    /// Dispara o Banner de Notificação Local Instantâneo no topo do iPhone igual ao GigU no iOS
    private func postGiguTopBanner(for verdict: RideVerdict) {
        let emoji: String = {
            switch verdict.status {
            case .approved: return "🟢"
            case .goingHome: return "🔵"
            case .warning: return "🟡"
            case .rejected: return "🔴"
            case .waiting: return "⚪️"
            }
        }()
        
        let content = UNMutableNotificationContent()
        content.title = "\(emoji) \(verdict.ganhoPorKmText)/km  •  \(verdict.ganhoPorHoraText)  •  Líq \(verdict.lucroLiquidoText)"
        content.subtitle = verdict.message
        content.body = "\(verdict.tempoEDistanciaText) \(verdict.rotaResumoText)"
        content.sound = nil // O som já é controlado pela Voz/Bipe do Copiloto
        
        let request = UNNotificationRequest(
            identifier: "gigu_ride_banner_latest",
            content: content,
            trigger: nil // Entrega imediata no topo da tela!
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    /// Chamado quando o card some da tela. Mantém a trava de preço caso tenha falado há menos de 6s
    /// para evitar que piscadas de frame na tela da Uber façam a voz repetir a mesma corrida!
    func resetLastSpoken() {
        let now = CFAbsoluteTimeGetCurrent()
        if (now - lastAlertedTime) > 6.0 {
            lastAlertedFingerprint = ""
            lastAlertedPrice = -1.0
            lastAlertedStatus = .waiting
        }
    }
}
