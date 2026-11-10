import Foundation
import AVKit
import AVFoundation
import SwiftUI
import UIKit

/// Gerenciador responsável por criar o player "falso" (AVSampleBufferDisplayLayer),
/// ativar a sessão de áudio em background e injetar a SwiftUI View dentro da janela flutuante do PiP.
final class PiPManager: NSObject, ObservableObject {
    
    @Published private(set) var isPiPActive: Bool = false
    
    /// Layer de vídeo sem arquivo .mp4 que mantém o Picture-in-Picture vivo
    let sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    
    private var pipController: AVPictureInPictureController?
    private var hostingController: UIHostingController<PiPOverlayView>?
    private var refreshTimer: Timer?
    private weak var viewModel: RideAssistantViewModel?
    
    /// Cache do último buffer de vídeo renderizado da SwiftUI View para evitar `UIGraphicsImageRenderer` e `CVPixelBufferCreate` a cada tick de 1s
    private var cachedRenderedImage: UIImage?
    private var cachedPixelBuffer: CVPixelBuffer?
    private var cachedFormatDescription: CMVideoFormatDescription?
    private var needsImageRedraw: Bool = true
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    /// Configura a sessão de áudio e inicializa o AVPictureInPictureController
    func setup(with viewModel: RideAssistantViewModel) {
        self.viewModel = viewModel
        configureAudioSessionForPiP()
        
        let overlayView = PiPOverlayView(viewModel: viewModel)
        let hosting = UIHostingController(rootView: overlayView)
        hosting.view.backgroundColor = .clear
        hosting.view.frame = CGRect(x: 0, y: 0, width: 380, height: 110)
        self.hostingController = hosting
        
        // Alimenta o primeiro frame no buffer para que o PiP fique pronto imediatamente
        enqueueRenderedSwiftUIFrame(forceRedraw: true)
        
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("[PiPManager] Picture-in-Picture não é suportado neste dispositivo.")
            return
        }
        
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sampleBufferDisplayLayer,
            playbackDelegate: self
        )
        
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        // Começa o PiP automaticamente quando o motorista sai do nosso app para ir para a Uber
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        // Oculta controles de avançar/retroceder 15s
        controller.requiresLinearPlayback = true
        self.pipController = controller
        
        // Mantém o stream de vídeo vivo enviando o buffer em cache a cada 1.0s (sem custo de UIGraphicsImageRenderer)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.enqueueRenderedSwiftUIFrame(forceRedraw: false)
        }
    }
    
    /// Liga ou desliga manualmente a janela flutuante
    func togglePiP() {
        guard let pipController = pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            enqueueRenderedSwiftUIFrame(forceRedraw: true)
            pipController.startPictureInPicture()
        }
    }
    
    /// Força o redesenho imediato da View no PiP assim que o OCR detecta uma corrida nova ou mudança de estado
    func refreshNow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.needsImageRedraw = true
            self.hostingController?.view.setNeedsLayout()
            self.hostingController?.view.layoutIfNeeded()
            self.enqueueRenderedSwiftUIFrame(forceRedraw: true)
        }
    }
    
    // MARK: - Sessão de Áudio obrigatória para PiP em Background
    
    private func configureAudioSessionForPiP() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback com .mixWithOthers permite o PiP e o alerta de voz funcionarem sem interromper o toque da Uber ou Spotify
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PiPManager] Falha ao configurar AVAudioSession: \(error)")
        }
    }
    
    // MARK: - Geração Otimizada de CMSampleBuffer com Cache de PixelBuffer (Zero Alocação Ociosa)
    
    /// Renderiza a `PiPOverlayView` em um `CMSampleBuffer` e envia para a `AVSampleBufferDisplayLayer`.
    /// Só executa `UIGraphicsImageRenderer` e `CVPixelBufferCreate` quando `forceRedraw` ou `needsImageRedraw` for `true`.
    private func enqueueRenderedSwiftUIFrame(forceRedraw: Bool) {
        if forceRedraw || needsImageRedraw || cachedPixelBuffer == nil || cachedFormatDescription == nil {
            guard let hostingView = hostingController?.view else { return }
            let size = CGSize(width: 380, height: 110)
            hostingView.bounds = CGRect(origin: .zero, size: size)
            
            let renderer = UIGraphicsImageRenderer(size: size)
            let rendered = renderer.image { _ in
                hostingView.drawHierarchy(in: hostingView.bounds, afterScreenUpdates: true)
            }
            cachedRenderedImage = rendered
            if let (buffer, formatDesc) = buildPixelBuffer(from: rendered) {
                cachedPixelBuffer = buffer
                cachedFormatDescription = formatDesc
            }
            needsImageRedraw = false
        }
        
        guard let buffer = cachedPixelBuffer,
              let formatDesc = cachedFormatDescription,
              let sampleBuffer = wrapInSampleBuffer(buffer: buffer, formatDesc: formatDesc) else {
            return
        }
        
        if sampleBufferDisplayLayer.status == .failed {
            sampleBufferDisplayLayer.flush()
        }
        sampleBufferDisplayLayer.enqueue(sampleBuffer)
    }
    
    private func buildPixelBuffer(from image: UIImage) -> (CVPixelBuffer, CMVideoFormatDescription)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        
        // Alinha o sistema de coordenadas do CoreGraphics com a orientação vertical do UIKit
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDesc = formatDescription else { return nil }
        return (buffer, formatDesc)
    }
    
    private func wrapInSampleBuffer(buffer: CVPixelBuffer, formatDesc: CMVideoFormatDescription) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
}

// MARK: - AVPictureInPictureControllerDelegate (Injeção da View na Janela do PiP)

extension PiPManager: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Técnica de Injeção de UIView na janela flutuante (PGHostedWindow) compatível com UIWindowScene (iOS 15+)
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let hostingView = self.hostingController?.view else {
                return
            }
            
            let allWindows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            
            guard let pipWindow = allWindows.first(where: {
                String(describing: type(of: $0)).contains("PGHostedWindow")
            }) ?? allWindows.first else {
                return
            }
            
            hostingView.frame = pipWindow.bounds
            hostingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            pipWindow.addSubview(hostingView)
        }
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // TRUQUE DE USABILIDADE: Quando o motorista toca no botão Play/Pause nativo do PiP
        // enquanto está no app da Uber, alternamos o Modo Trânsito sem precisar voltar ao nosso app!
        DispatchQueue.main.async { [weak self] in
            self?.viewModel?.isTrafficModeEnabled.toggle()
            self?.refreshNow()
        }
    }
    
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // Retorna um intervalo infinito (live stream) para que a barra de tempo não expire
        return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
