import Foundation
import AVKit
import AVFoundation
import CoreMedia
import SwiftUI
import UIKit

/// Gerenciador responsável por alimentar a `AVSampleBufferDisplayLayer`,
/// ativar a sessão de áudio em background e controlar a janela flutuante do Picture-in-Picture (PiP) no padrão GigU.
/// IMPORTANTE: Nunca defina `sampleBufferDisplayLayer.controlTimebase` manualmente, pois o
/// `AVPictureInPictureController` gerencia o timebase internamente.
final class PiPManager: NSObject, ObservableObject {
    
    @Published private(set) var isPiPActive: Bool = false
    @Published private(set) var isPiPReady: Bool = false
    
    /// Layer de vídeo que exibe o card do Copiloto (3 Colunas GigU) e sustenta o Picture-in-Picture
    let sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    
    private var pipController: AVPictureInPictureController?
    private var refreshTimer: Timer?
    private weak var viewModel: RideAssistantViewModel?
    private var possibleObservation: NSKeyValueObservation?
    private var pendingManualStart: Bool = false
    private var hasConfiguredAudioSession: Bool = false
    
    /// Cache do último buffer de vídeo renderizado
    private var cachedPixelBuffer: CVPixelBuffer?
    private var cachedFormatDescription: CMVideoFormatDescription?
    private var needsImageRedraw: Bool = true
    
    deinit {
        refreshTimer?.invalidate()
        possibleObservation?.invalidate()
    }
    
    /// Configura a sessão de áudio e prepara o gerador de frames
    func setup(with viewModel: RideAssistantViewModel) {
        self.viewModel = viewModel
        configureAudioSessionForPiP(force: true)
        
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
            self.configureAudioSessionForPiP(force: false)
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
        configureAudioSessionForPiP(force: false)
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
            self.enqueueRenderedSwiftUIFrame(forceRedraw: true)
            self.pipController?.invalidatePlaybackState()
        }
    }
    
    // MARK: - Sessão de Áudio obrigatória para PiP + Voz sem engasgos
    
    private func configureAudioSessionForPiP(force: Bool) {
        guard force || !hasConfiguredAudioSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            hasConfiguredAudioSession = true
        } catch {
            print("[PiPManager] Falha ao configurar AVAudioSession: \(error)")
        }
    }
    
    // MARK: - Geração de CMSampleBuffer (Funciona 100% em Background sobre a Uber e 100% em Pé!)
    
    private func enqueueRenderedSwiftUIFrame(forceRedraw: Bool) {
        if forceRedraw || needsImageRedraw || cachedPixelBuffer == nil || cachedFormatDescription == nil {
            guard let viewModel = viewModel else { return }
            // Desenho 100% UIKit/CoreGraphics: funciona com o app em segundo plano atrás da Uber
            let rendered = PiPCardRenderer.render(PiPCardRenderer.Input(
                verdict: viewModel.currentVerdict,
                metaAtual: viewModel.totalLucroLiquidoAceito,
                metaTotal: viewModel.settings.metaDiariaLiquida,
                minGanhoKm: viewModel.settings.minGanhoKmNormal,
                minGanhoHora: viewModel.settings.minGanhoHoraNormal,
                isTrafficMode: viewModel.isTrafficModeEnabled
            ))
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
        
        // Em CGBitmapContext, context.draw(cgImage) sem flip já coloca o topo da imagem no byte 0 (topo do vídeo = 100% EM PÉ!)
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
        
        if let sb = sampleBuffer,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as? [NSMutableDictionary],
           let first = attachments.first {
            first[kCMSampleAttachmentKey_DisplayImmediately] = kCFBooleanTrue
        }
        
        return sampleBuffer
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
        refreshNow()
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
