import Foundation
import AVKit
import AVFoundation
import CoreMedia
import SwiftUI
import UIKit

/// Gerenciador responsável por alimentar a `AVSampleBufferDisplayLayer`,
/// ativar a sessão de áudio em background e controlar a janela flutuante do Picture-in-Picture (PiP).
/// IMPORTANTE: Nunca defina `sampleBufferDisplayLayer.controlTimebase` manualmente, pois o
/// `AVPictureInPictureController` gerencia o timebase internamente (defini-lo manualmente causa NSInvalidArgumentException).
final class PiPManager: NSObject, ObservableObject {
    
    @Published private(set) var isPiPActive: Bool = false
    @Published private(set) var isPiPReady: Bool = false
    
    /// Layer de vídeo que exibe o card do Copiloto e sustenta o Picture-in-Picture
    let sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    
    private var pipController: AVPictureInPictureController?
    private var hostingController: UIHostingController<PiPOverlayView>?
    private var refreshTimer: Timer?
    private weak var viewModel: RideAssistantViewModel?
    private var possibleObservation: NSKeyValueObservation?
    private var pendingManualStart: Bool = false
    
    /// Cache do último buffer de vídeo renderizado da SwiftUI View
    private var cachedRenderedImage: UIImage?
    private var cachedPixelBuffer: CVPixelBuffer?
    private var cachedFormatDescription: CMVideoFormatDescription?
    private var needsImageRedraw: Bool = true
    
    deinit {
        refreshTimer?.invalidate()
        possibleObservation?.invalidate()
    }
    
    /// Configura a sessão de áudio e prepara o gerador de frames (o `AVPictureInPictureController` é criado quando a view entra na janela)
    func setup(with viewModel: RideAssistantViewModel) {
        self.viewModel = viewModel
        configureAudioSessionForPiP()
        
        let overlayView = PiPOverlayView(viewModel: viewModel)
        let hosting = UIHostingController(rootView: overlayView)
        hosting.view.backgroundColor = .clear
        hosting.view.frame = CGRect(x: 0, y: 0, width: 380, height: 110)
        self.hostingController = hosting
        
        // Mantém o stream vivo enviando frames constantes a cada 0.5s
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.enqueueRenderedSwiftUIFrame(forceRedraw: false)
        }
    }
    
    /// Chamado pela `SampleBufferLayerHostView` assim que a layer entra na `UIWindow` real do iPhone
    func notifyLayerMovedToWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.configureAudioSessionForPiP()
            self.enqueueRenderedSwiftUIFrame(forceRedraw: true)
            self.initializePiPControllerIfNeeded()
        }
    }
    
    private func initializePiPControllerIfNeeded() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        
        if pipController == nil {
            let contentSource = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: sampleBufferDisplayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.requiresLinearPlayback = true
            self.pipController = controller
            
            possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] ctrl, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isPiPReady = ctrl.isPictureInPicturePossible
                    if ctrl.isPictureInPicturePossible && self.pendingManualStart {
                        self.pendingManualStart = false
                        ctrl.startPictureInPicture()
                    }
                }
            }
        }
        
        pipController?.invalidatePlaybackState()
    }
    
    /// Liga ou desliga manualmente a janela flutuante quando o motorista toca no botão
    func togglePiP() {
        configureAudioSessionForPiP()
        enqueueRenderedSwiftUIFrame(forceRedraw: true)
        initializePiPControllerIfNeeded()
        
        guard let pipController = pipController else { return }
        
        if pipController.isPictureInPictureActive {
            pendingManualStart = false
            pipController.stopPictureInPicture()
        } else if pipController.isPictureInPicturePossible {
            pendingManualStart = false
            pipController.startPictureInPicture()
        } else {
            pendingManualStart = true
            pipController.invalidatePlaybackState()
            for delay in [0.15, 0.35, 0.65] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, let ctrl = self.pipController else { return }
                    self.enqueueRenderedSwiftUIFrame(forceRedraw: true)
                    ctrl.invalidatePlaybackState()
                    if self.pendingManualStart && ctrl.isPictureInPicturePossible {
                        self.pendingManualStart = false
                        ctrl.startPictureInPicture()
                    }
                }
            }
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
            self.pipController?.invalidatePlaybackState()
        }
    }
    
    // MARK: - Sessão de Áudio obrigatória para PiP em Background
    
    private func configureAudioSessionForPiP() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PiPManager] Falha ao configurar AVAudioSession: \(error)")
        }
    }
    
    // MARK: - Geração de CMSampleBuffer
    
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

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
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
            }) else {
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
        DispatchQueue.main.async { [weak self] in
            self?.viewModel?.isTrafficModeEnabled.toggle()
            self?.refreshNow()
        }
    }
    
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
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
