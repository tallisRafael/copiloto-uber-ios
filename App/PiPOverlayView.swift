import SwiftUI
import ReplayKit
import UIKit

/// View injetada dentro da janela flutuante do Picture-in-Picture (PiP).
/// Desenhada com estética Automotiva Premium (alto contraste, leitura em 0.3s e sem poluição visual).
struct PiPOverlayView: View {
    @ObservedObject var viewModel: RideAssistantViewModel
    
    var body: some View {
        ZStack {
            // Cor de fundo dinâmica do Semáforo
            viewModel.currentVerdict.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                // Linha superior: Modo ativo, Nota/Viagens do Passageiro, Alerta de Dinheiro e Meta
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isTrafficModeEnabled ? "cloud.heavyrain.fill" : "bolt.car.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(viewModel.isTrafficModeEnabled ? "TRÂNSITO" : "ATIVO")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.32))
                    .cornerRadius(8)
                    
                    if viewModel.isGoingHomeModeEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("CASA")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.34))
                        .cornerRadius(8)
                    }
                    
                    if let passengerBadge = viewModel.currentVerdict.passengerBadge {
                        Text(passengerBadge)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.40))
                            .cornerRadius(8)
                    }
                    
                    if viewModel.currentVerdict.isCashPayment {
                        Text("💵 DINHEIRO")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.audioAlertMode.iconName)
                            .font(.system(size: 12, weight: .bold))
                        Text("R$\(Int(viewModel.totalLucroLiquidoAceito))/\(Int(viewModel.settings.metaDiariaLiquida))")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.32))
                    .cornerRadius(8)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                
                Spacer(minLength: 0)
                
                // Mensagem Principal do Veredito (GIGANTE para bater o olho no suporte do carro)
                Text(viewModel.currentVerdict.message)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                
                Spacer(minLength: 0)
                
                // Linha de métricas complementares (Lucro Líquido Real, KM e Tempo)
                Text(viewModel.currentVerdict.detailMetrics)
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.98))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.25))
            }
            .padding(.top, 12)
        }
        .frame(width: 400, height: 200)
    }
}

/// Container UIKit que dispara o `RPSystemBroadcastPickerView` ao tocar em qualquer parte do botão
/// sem vazar área de toque para outros elementos da tela e usando o Bundle ID dinâmico do Sideloadly.
final class BroadcastButtonContainerView: UIView {
    private let picker = RPSystemBroadcastPickerView(frame: .zero)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
        
        picker.preferredExtension = SharedConstants.broadcastExtensionBundleIdentifier
        picker.showsMicrophoneButton = false
        picker.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picker)
        
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: centerXAnchor),
            picker.centerYAnchor.constraint(equalTo: centerYAnchor),
            picker.widthAnchor.constraint(equalToConstant: 44),
            picker.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Aciona programaticamente o seletor nativo de gravação de tela do iOS
    func triggerPicker() {
        picker.preferredExtension = SharedConstants.broadcastExtensionBundleIdentifier
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                button.sendActions(for: .allTouchEvents)
                break
            }
        }
    }
}

/// Representable invisível/compacto que permite acionar o ReplayKit por um botão SwiftUI moderno
struct BroadcastPickerRepresentable: UIViewRepresentable {
    let triggerId: Int
    
    func makeUIView(context: Context) -> BroadcastButtonContainerView {
        BroadcastButtonContainerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    }
    
    func updateUIView(_ uiView: BroadcastButtonContainerView, context: Context) {
        if context.coordinator.lastTriggerId != triggerId {
            context.coordinator.lastTriggerId = triggerId
            uiView.triggerPicker()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(lastTriggerId: triggerId)
    }
    
    final class Coordinator {
        var lastTriggerId: Int
        init(lastTriggerId: Int) {
            self.lastTriggerId = lastTriggerId
        }
    }
}
