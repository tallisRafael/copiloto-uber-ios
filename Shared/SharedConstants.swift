import Foundation

/// Constantes compartilhadas entre o App Principal e o Broadcast Upload Extension (ReplayKit).
/// IMPORTANTE: Em "Target Membership" no Xcode, marque TANTO o App Principal QUANTO a Broadcast Extension.
enum SharedConstants {
    /// Identificador do App Group configurado em "Signing & Capabilities" nos dois targets
    static let appGroupIdentifier = "group.com.seuapp.uberhelper"
    
    /// Chave usada no UserDefaults compartilhado para trafegar o último texto extraído pelo OCR
    static let ocrTextKey = "latest_ocr_extracted_text"
    
    /// Chave para o timestamp da última leitura
    static let ocrTimestampKey = "latest_ocr_timestamp"
    
    /// Prefixo usado pela Broadcast Extension para enviar mensagens de status do sistema (ex: pausa/fim)
    static let systemStatusPrefix = "__SYSTEM_STATUS__:"
    
    /// Nome da notificação Darwin (IPC ultra-rápido entre processos no iOS)
    static let darwinNotificationName = "com.seuapp.uberhelper.newOCRTextAvailable"
    
    /// Descobre automaticamente o Bundle ID base do app mesmo quando assinado via Sideloadly / AltStore no Windows
    static var dynamicAppGroupIdentifier: String {
        let currentBundle = Bundle.main.bundleIdentifier ?? "com.seuapp.uberhelper"
        let baseBundle = currentBundle.replacingOccurrences(of: ".BroadcastExtension", with: "")
        return "group.\(baseBundle)"
    }
    
    /// Salva o texto do OCR em todos os containers compartilhados disponíveis (compatível com Xcode e Sideloadly no Windows)
    static func saveSharedOCRText(_ text: String) {
        let now = Date().timeIntervalSince1970
        let suites = Set([appGroupIdentifier, dynamicAppGroupIdentifier])
        for suite in suites {
            if let defaults = UserDefaults(suiteName: suite) {
                defaults.set(text, forKey: ocrTextKey)
                defaults.set(now, forKey: ocrTimestampKey)
            }
        }
    }
    
    /// Lê o texto mais recente do OCR a partir do container compartilhado ativo
    static func readSharedOCRText() -> String? {
        let suites = [dynamicAppGroupIdentifier, appGroupIdentifier]
        for suite in suites {
            if let defaults = UserDefaults(suiteName: suite),
               let text = defaults.string(forKey: ocrTextKey),
               !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
