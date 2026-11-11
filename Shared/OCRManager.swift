import Foundation
import Vision
import CoreMedia
import CoreVideo

/// Gerenciador responsável por executar o OCR (Reconhecimento de Texto) em tempo real usando o Vision Framework.
/// Também detecta automaticamente na tela da Uber se o motorista ACEITOU ou RECUSOU a última corrida para treinar a IA!
final class OCRManager {
    
    static let shared = OCRManager()
    
    /// Fila dedicada para processamento do Vision sem travar a thread de captura de vídeo
    private let visionQueue = DispatchQueue(label: "com.seuapp.uberhelper.visionQueue", qos: .userInteractive)
    
    /// Lock para sincronizar acesso concorrente entre a thread do ReplayKit e a visionQueue
    private let stateLock = NSLock()
    
    /// Controle de concorrência para descartar frames enquanto um frame já está sendo processado
    private var isProcessingFrame = false
    
    /// Controle de throttling adaptativo:
    /// - 0.35s quando há card ativo na tela (resposta instantânea)
    /// - 0.55s quando está apenas monitorando o mapa vazio (economiza bateria e reduz aquecimento no painel)
    private var lastProcessedTime: CFAbsoluteTime = 0
    private let activeCardInterval: CFAbsoluteTime = 0.35
    private let idleMonitoringInterval: CFAbsoluteTime = 0.55
    
    /// Deduplicação de IPC: guarda o último texto enviado e quando foi enviado
    private var lastPublishedText: String = ""
    private var lastPublishedTime: CFAbsoluteTime = 0
    private let duplicateHeartbeatInterval: CFAbsoluteTime = 2.50
    
    /// Contador de frames consecutivos sem card na tela para notificar limpeza rápida e detectar Aceite/Recusa
    private var consecutiveEmptyFrames: Int = 0
    private var hadActiveCardOnScreen: Bool = false
    
    /// Callback acionado sempre que um texto válido é extraído do frame
    var onTextRecognized: ((String) -> Void)?
    
    private init() {}
    
    /// Reseta o estado interno de deduplicação (chamado ao iniciar/retomar o broadcast)
    func resetState() {
        stateLock.lock()
        defer { stateLock.unlock() }
        isProcessingFrame = false
        lastProcessedTime = 0
        lastPublishedText = ""
        lastPublishedTime = 0
        consecutiveEmptyFrames = 0
        hadActiveCardOnScreen = false
    }
    
    /// Processa o `CMSampleBuffer` vindo do ReplayKit e extrai o texto via `VNRecognizeTextRequest`.
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        stateLock.lock()
        let requiredInterval = hadActiveCardOnScreen ? activeCardInterval : idleMonitoringInterval
        guard !isProcessingFrame, (currentTime - lastProcessedTime) >= requiredInterval else {
            stateLock.unlock()
            return
        }
        isProcessingFrame = true
        lastProcessedTime = currentTime
        stateLock.unlock()
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            stateLock.lock()
            isProcessingFrame = false
            stateLock.unlock()
            return
        }
        
        visionQueue.async { [weak self] in
            autoreleasepool {
                guard let self = self else { return }
                defer {
                    self.stateLock.lock()
                    self.isProcessingFrame = false
                    self.stateLock.unlock()
                }
                
                let request = VNRecognizeTextRequest { [weak self] request, error in
                    guard let self = self, error == nil else {
                        return
                    }
                    
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let recognizedLines = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }
                    
                    // FILTRO CRÍTICO ANTI-FEEDBACK LOOP:
                    // Remove do OCR qualquer linha que venha do nosso próprio PiP ou Banner de Notificação,
                    // evitando que o app leia a si mesmo em loop infinito e infle os números!
                    let filteredLines = recognizedLines.filter { line in
                        let up = line.uppercased()
                        if up.contains("GANHO / KM") || up.contains("GANHO / HORA") || up.contains("LUCRO LIVRE") { return false }
                        if up.contains("CILADA:") || up.contains("PERIGO:") || up.contains("CORRIDA TOP") || up.contains("BATE OS") { return false }
                        if up.contains("LÍQ R$") || up.contains("LIQ R$") || up.contains("HOJE LÍQ") { return false }
                        if up.contains("COPILOTO UBER") || up.contains("AGUARDANDO CORRIDA") { return false }
                        return true
                    }
                    
                    let fullText = filteredLines.joined(separator: "\n")
                    let lowerText = fullText.lowercased()
                    
                    // Verifica se há um card de oferta de corrida na tela ("R$" + "km")
                    let looksLikeRideCard = (fullText.contains("R$") || fullText.contains("RS")) && lowerText.contains("km")
                    
                    if looksLikeRideCard {
                        self.handleRecognizedCardText(fullText)
                    } else {
                        self.handlePostCardScreen(lowerText: lowerText)
                    }
                }
                
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                // Ignora textos minúsculos de nomes de ruas no mapa de fundo, focando nas letras do card (2x mais rápido e menos calor!)
                request.minimumTextHeight = 0.018
                request.recognitionLanguages = ["pt-BR", "en-US"]
                // Foca apenas na metade inferior da tela onde o card da Uber sobe (ignora topo com notificações e PiP flutuante no topo)
                request.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.65)
                
                let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                do {
                    try requestHandler.perform([request])
                } catch {
                    print("[OCRManager] Erro ao executar VNRecognizeTextRequest: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Deduplicação e Detecção Automática de Aceite vs. Recusa na Tela da Uber
    
    private func handleRecognizedCardText(_ fullText: String) {
        let now = CFAbsoluteTimeGetCurrent()
        
        stateLock.lock()
        consecutiveEmptyFrames = 0
        hadActiveCardOnScreen = true
        
        let isSameText = (fullText == lastPublishedText)
        let timeSinceLastPublish = now - lastPublishedTime
        
        if isSameText && timeSinceLastPublish < duplicateHeartbeatInterval {
            stateLock.unlock()
            return
        }
        
        lastPublishedText = fullText
        lastPublishedTime = now
        stateLock.unlock()
        
        onTextRecognized?(fullText)
        publishToAppGroup(text: fullText)
    }
    
    /// Analisa o que aparece na tela da Uber logo após o card sumir:
    /// - Se aparecer tela de navegação de embarque ("iniciar viagem", "embarque", "buscar", "a caminho"), o motorista ACEITOU!
    /// - Se voltar para "você está online" / "procurando viagens", o motorista RECUSOU!
    private func handlePostCardScreen(lowerText: String) {
        stateLock.lock()
        guard hadActiveCardOnScreen else {
            stateLock.unlock()
            return
        }
        
        // Detecta palavras típicas da tela de navegação da Uber após aceitar uma corrida
        let acceptedPatterns = ["iniciar", "embarque", "encontrando", "a caminho", "deslize", "cheguei"]
        let didAcceptRide = acceptedPatterns.contains { lowerText.contains($0) }
        
        if didAcceptRide {
            hadActiveCardOnScreen = false
            consecutiveEmptyFrames = 0
            lastPublishedText = ""
            stateLock.unlock()
            publishToAppGroup(text: "\(SharedConstants.systemStatusPrefix)AUTO_ACCEPTED_LAST_RIDE")
            return
        }
        
        consecutiveEmptyFrames += 1
        if consecutiveEmptyFrames >= 4 {
            hadActiveCardOnScreen = false
            consecutiveEmptyFrames = 0
            lastPublishedText = ""
            stateLock.unlock()
            publishToAppGroup(text: "\(SharedConstants.systemStatusPrefix)AGUARDANDO CORRIDA...")
        } else {
            stateLock.unlock()
        }
    }
    
    /// Publica o texto extraído no container compartilhado (App Group) e avisa o App Principal via Darwin Notification.
    private func publishToAppGroup(text: String) {
        SharedConstants.saveSharedOCRText(text)
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let notificationName = CFNotificationName(SharedConstants.darwinNotificationName as CFString)
        CFNotificationCenterPostNotification(center, notificationName, nil, nil, true)
    }
}
