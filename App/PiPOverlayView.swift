import SwiftUI
import ReplayKit

/// View injetada dentro da janela flutuante do Picture-in-Picture (PiP).
/// Desenhada com alto contraste (Semáforo Verde / Azul Rumo a Casa / Amarelo / Vermelho / Neutro) e fontes grandes.
struct PiPOverlayView: View {
    @ObservedObject var viewModel: RideAssistantViewModel
    
    var body: some View {
        ZStack {
            // Cor de fundo dinâmica
            viewModel.currentVerdict.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 5) {
                // Linha superior: Badges de Modo Trânsito, Rumo a Casa, Dinheiro, Nota do Passageiro e Toggle
                HStack(spacing: 5) {
                    Label(
                        viewModel.isTrafficModeEnabled ? "TRÂNSITO" : "NORMAL",
                        systemImage: viewModel.isTrafficModeEnabled ? "cloud.heavyrain.fill" : "car.fill"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.28))
                    .cornerRadius(6)
                    
                    if viewModel.isGoingHomeModeEnabled {
                        Label("CASA", systemImage: "house.fill")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.32))
                            .cornerRadius(6)
                    }
                    
                    if let passengerBadge = viewModel.currentVerdict.passengerBadge {
                        Text(passengerBadge)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(6)
                    }
                    
                    if viewModel.currentVerdict.isCashPayment {
                        Text("💵 DINHEIRO")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.40))
                            .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    Image(systemName: viewModel.audioAlertMode.iconName)
                        .font(.system(size: 10, weight: .bold))
                        .padding(4)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Circle())
                    
                    // Toggle interativo (funciona no app e caso a janela receba toque)
                    Toggle("Trânsito", isOn: $viewModel.isTrafficModeEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .yellow))
                        .scaleEffect(0.70)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                
                // Mensagem Principal do Veredito
                Text(viewModel.currentVerdict.message)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                
                // Linha de métricas complementares (inclui Lucro Líquido Real)
                Text(viewModel.currentVerdict.detailMetrics)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 6)
        }
        // Proporção panorâmica compacta ideal para janela flutuante no topo da tela
        .frame(width: 380, height: 110)
    }
}

/// Botão nativo do ReplayKit (RPSystemBroadcastPickerView) encapsulado para SwiftUI
struct BroadcastPickerRepresentable: UIViewRepresentable {
    /// Bundle Identifier do target da sua Broadcast Upload Extension
    let extensionBundleIdentifier: String
    
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = extensionBundleIdentifier
        picker.showsMicrophoneButton = false
        return picker
    }
    
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
