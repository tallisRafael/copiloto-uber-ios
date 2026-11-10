import ReplayKit

/// Classe principal do target "Broadcast Upload Extension".
/// O iOS instancia esta classe automaticamente quando o motorista inicia a transmissão de tela.
final class SampleHandler: RPBroadcastSampleHandler {

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        // Chamado quando o usuário inicia a gravação/transmissão da tela
        OCRManager.shared.resetState()
        publishStatusToApp(status: "AGUARDANDO CORRIDA...")
    }
    
    override func broadcastPaused() {
        publishStatusToApp(status: "CAPTURA PAUSADA")
    }
    
    override func broadcastResumed() {
        OCRManager.shared.resetState()
        publishStatusToApp(status: "AGUARDANDO CORRIDA...")
    }
    
    override func broadcastFinished() {
        OCRManager.shared.resetState()
        publishStatusToApp(status: "CAPTURA ENCERRADA")
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            // Envia apenas os frames de vídeo da tela para o nosso cérebro (Vision OCR)
            OCRManager.shared.processSampleBuffer(sampleBuffer)
        case .audioApp, .audioMic:
            // Ignora áudio para economizar recursos
            break
        @unknown default:
            break
        }
    }
    
    private func publishStatusToApp(status: String) {
        let payload = "\(SharedConstants.systemStatusPrefix)\(status)"
        SharedConstants.saveSharedOCRText(payload)
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(SharedConstants.darwinNotificationName as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
    }
}
