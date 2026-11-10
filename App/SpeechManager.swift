import Foundation
import AVFoundation
import AudioToolbox

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

/// Gerenciador de alertas sonoros: suporta tanto Bipes Rápidos de Sistema (AudioToolbox)
/// quanto Síntese de Voz completa (AVSpeechSynthesizer) em Português do Brasil.
final class SpeechManager {
    
    static let shared = SpeechManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var lastAlertedFingerprint: String = ""
    private var lastAlertedStatus: VerdictStatus = .waiting
    
    private init() {}
    
    /// Dispara o alerta sonoro (Bipe ou Voz) de acordo com a preferência do motorista,
    /// garantindo deduplicação para não repetir enquanto o mesmo card permanece na tela,
    /// mas permitindo um aviso de correção se o Apple Maps mudar o status da corrida (ex: de Aprovada para Reprovada no trânsito).
    func triggerAlertIfNeeded(
        mode: AudioAlertMode,
        status: VerdictStatus,
        speechText: String?,
        fingerprint: String
    ) {
        let isSameRide = (fingerprint == lastAlertedFingerprint)
        let didStatusFlip = isSameRide && (status != lastAlertedStatus) && (status != .waiting)
        
        guard mode != .off, (!isSameRide || didStatusFlip) else {
            return
        }
        
        lastAlertedFingerprint = fingerprint
        lastAlertedStatus = status
        
        switch mode {
        case .off:
            break
        case .beep:
            playSystemBeep(for: status)
        case .voice:
            if let text = speechText, !text.isEmpty {
                speak(text)
            } else {
                playSystemBeep(for: status)
            }
        }
    }
    
    private func playSystemBeep(for status: VerdictStatus) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        switch status {
        case .approved, .goingHome:
            // Som curto positivo / cristalino (Payment Success / Tweet)
            AudioServicesPlaySystemSound(1057)
        case .warning:
            // Som curto de atenção
            AudioServicesPlaySystemSound(1106)
        case .rejected:
            // Som grave de alerta / erro
            AudioServicesPlaySystemSound(1073)
        case .waiting:
            break
        }
    }
    
    private func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = 0.53 // Velocidade levemente acelerada para leitura ágil
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
    }
    
    /// Limpa o último fingerprint alertado quando o card some da tela
    func resetLastSpoken() {
        lastAlertedFingerprint = ""
        lastAlertedStatus = .waiting
    }
}
