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
            
            VStack(spacing: 6) {
                // Linha superior: Modo ativo, Nota/Viagens do Passageiro, Alerta de Dinheiro e Ícone de Som
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isTrafficModeEnabled ? "cloud.heavyrain.fill" : "bolt.car.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(viewModel.isTrafficModeEnabled ? "TRÂNSITO" : "ATIVO")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.30))
                    .cornerRadius(6)
                    
                    if viewModel.isGoingHomeModeEnabled {
                        HStack(spacing: 3) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("CASA")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.32))
                        .cornerRadius(6)
                    }
                    
                    if let passengerBadge = viewModel.currentVerdict.passengerBadge {
                        Text(passengerBadge)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.36))
                            .cornerRadius(6)
                    }
                    
                    if viewModel.currentVerdict.isCashPayment {
                        Text("💵 DINHEIRO")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.42))
                            .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.audioAlertMode.iconName)
                            .font(.system(size: 10, weight: .bold))
                        Text("R$ \(Int(viewModel.totalLucroLiquidoAceito))/\(Int(viewModel.settings.metaDiariaLiquida))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.28))
                    .cornerRadius(6)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                
                // Mensagem Principal do Veredito
                Text(viewModel.currentVerdict.message)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                
                // Linha de métricas complementares (inclui Lucro Líquido Real)
                Text(viewModel.currentVerdict.detailMetrics)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 380, height: 110)
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
