import Foundation
import Darwin

/// Constantes e Canal de Comunicação de Tempo Real entre a Broadcast Extension (ReplayKit) e o App Principal.
/// Inclui Transporte Duplo:
/// 1. UDP Loopback Local (`127.0.0.1:45829`) -> Funciona em 100% das contas Apple gratuitas (Sideloadly / AltStore) sem exigir App Group pago!
/// 2. App Group (`UserDefaults`) + Darwin Notifications -> Fallback adicional quando disponível.
enum SharedConstants {
    /// Identificador base do App Group
    static let appGroupIdentifier = "group.com.seuapp.uberhelper"
    
    /// Porta local (Loopback 127.0.0.1) usada para enviar o texto do OCR instantaneamente da Extension para o App
    static let loopbackPort: UInt16 = 45829
    
    /// Chave usada no UserDefaults compartilhado
    static let ocrTextKey = "latest_ocr_extracted_text"
    
    /// Chave para o timestamp da última leitura
    static let ocrTimestampKey = "latest_ocr_timestamp"
    
    /// Prefixo usado pela Broadcast Extension para enviar mensagens de status do sistema
    static let systemStatusPrefix = "__SYSTEM_STATUS__:"
    
    /// Nome da notificação Darwin
    static let darwinNotificationName = "com.seuapp.uberhelper.newOCRTextAvailable"
    
    /// Descobre automaticamente o Bundle ID da BroadcastExtension mesmo quando re-assinado pelo Sideloadly (ex: com.seuapp.uberhelper.5TFHKK78AX.BroadcastExtension)
    static var broadcastExtensionBundleIdentifier: String {
        let currentBundle = Bundle.main.bundleIdentifier ?? "com.seuapp.uberhelper"
        if currentBundle.hasSuffix(".BroadcastExtension") {
            return currentBundle
        }
        return "\(currentBundle).BroadcastExtension"
    }
    
    /// Descobre automaticamente o App Group dinâmico
    static var dynamicAppGroupIdentifier: String {
        let currentBundle = Bundle.main.bundleIdentifier ?? "com.seuapp.uberhelper"
        let baseBundle = currentBundle.replacingOccurrences(of: ".BroadcastExtension", with: "")
        return "group.\(baseBundle)"
    }
    
    /// Envia o texto do OCR da BroadcastExtension para o App Principal via Loopback UDP (127.0.0.1) + App Group
    static func saveSharedOCRText(_ text: String) {
        // 1. Disparo imediato via UDP Loopback (127.0.0.1) - Funciona sem App Group no Sideloadly!
        sendUDPLoopbackPacket(text)
        
        // 2. Fallback em UserDefaults (App Group) caso disponível
        let now = Date().timeIntervalSince1970
        let suites = Set([appGroupIdentifier, dynamicAppGroupIdentifier])
        for suite in suites {
            if let defaults = UserDefaults(suiteName: suite) {
                defaults.set(text, forKey: ocrTextKey)
                defaults.set(now, forKey: ocrTimestampKey)
            }
        }
    }
    
    /// Lê o texto mais recente do OCR a partir do container compartilhado caso usado via Darwin Notification
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
    
    /// Envia um datagrama UDP para 127.0.0.1:45829 (zero configuração, zero permissão especial, funciona em conta gratuita Sideloadly)
    private static func sendUDPLoopbackPacket(_ text: String) {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return }
        
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }
        
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = loopbackPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    _ = sendto(fd, baseAddress, data.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

/// Servidor UDP Loopback ultra-leve que roda no App Principal escutando `127.0.0.1:45829`
final class LocalOCRReceiver {
    static let shared = LocalOCRReceiver()
    
    private var socketFD: Int32 = -1
    private var isRunning = false
    private let listenQueue = DispatchQueue(label: "com.seuapp.uberhelper.udpReceiver", qos: .userInteractive)
    
    var onTextReceived: ((String) -> Void)?
    
    private init() {}
    
    func startListening() {
        guard !isRunning else { return }
        isRunning = true
        
        listenQueue.async { [weak self] in
            guard let self = self else { return }
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else {
                self.isRunning = false
                return
            }
            self.socketFD = fd
            
            var reuse: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
            
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = SharedConstants.loopbackPort.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            
            let bindResult = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            guard bindResult == 0 else {
                close(fd)
                self.socketFD = -1
                self.isRunning = false
                return
            }
            
            var buffer = [UInt8](repeating: 0, count: 16384)
            while self.isRunning {
                let bytesRead = recv(fd, &buffer, buffer.count - 1, 0)
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    if let message = String(data: data, encoding: .utf8), !message.isEmpty {
                        DispatchQueue.main.async {
                            self.onTextReceived?(message)
                        }
                    }
                } else if bytesRead < 0 {
                    break
                }
            }
        }
    }
}
