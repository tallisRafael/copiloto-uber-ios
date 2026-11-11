import SwiftUI
import ReplayKit
import UIKit

/// Janela Flutuante (PiP) desenhada no padrão clássico do GigU:
/// - Topo com Semáforo Vibrante + Veredito + Nota/Viagens do Passageiro
/// - Centro dividido nas 3 Caixas Grandes Lado a Lado: [R$/KM] | [R$/HORA] | [LUCRO LÍQ.]
/// - Rodapé com Tempo, Distância Total, KM de Busca e Destino
struct PiPOverlayView: View {
    @ObservedObject var viewModel: RideAssistantViewModel
    
    var body: some View {
        let verdict = viewModel.currentVerdict
        let statusColor = verdict.backgroundColor
        
        ZStack {
            // Fundo escuro automotivo com borda grossa na cor do Semáforo (estilo GigU)
            Color(red: 0.07, green: 0.09, blue: 0.12)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. FAIXA DE TOPO (CABEÇALHO SEMÁFORO GIGU)
                HStack(spacing: 8) {
                    Text(verdict.message)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    
                    Spacer(minLength: 4)
                    
                    if verdict.isCashPayment {
                        Text("💵 DINHEIRO")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(6)
                    }
                    
                    if let badge = verdict.passengerBadge {
                        Text(badge)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.38))
                            .cornerRadius(6)
                    } else {
                        Text("META R$\(Int(viewModel.totalLucroLiquidoAceito))/\(Int(viewModel.settings.metaDiariaLiquida))")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(statusColor)
                
                // 2. MIOLO CENTRAL: OS 3 BLOCOS GIGANTES DO GIGU (R$/KM | R$/HORA | LÍQUIDO)
                if verdict.status == .waiting {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        HStack(spacing: 10) {
                            giguMetricBox(
                                title: "GANHO / KM",
                                value: "R$ \(String(format: "%.2f", viewModel.settings.minGanhoKmNormal).replacingOccurrences(of: ".", with: ","))+",
                                accentColor: .green
                            )
                            giguMetricBox(
                                title: "GANHO / HORA",
                                value: "R$ \(Int(viewModel.settings.minGanhoHoraNormal))+",
                                accentColor: .cyan
                            )
                            giguMetricBox(
                                title: "META 250+",
                                value: "R$ \(Int(viewModel.totalLucroLiquidoAceito))",
                                accentColor: .orange
                            )
                        }
                        .padding(.horizontal, 12)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: 10) {
                        giguMetricBox(
                            title: "GANHO / KM",
                            value: verdict.ganhoPorKmText,
                            accentColor: statusColor
                        )
                        
                        giguMetricBox(
                            title: "GANHO / HORA",
                            value: verdict.ganhoPorHoraText,
                            accentColor: statusColor
                        )
                        
                        giguMetricBox(
                            title: "LUCRO LIVRE",
                            value: verdict.lucroLiquidoText,
                            accentColor: statusColor
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity)
                }
                
                // 3. FAIXA INFERIOR: TEMPO, KM DE BUSCA E DESTINO
                HStack(spacing: 8) {
                    Text(verdict.tempoEDistanciaText)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    
                    Spacer(minLength: 4)
                    
                    Text(verdict.rotaResumoText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.55))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusColor, lineWidth: 5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func giguMetricBox(title: String, value: String, accentColor: Color) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
            
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(accentColor.opacity(0.22))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.85), lineWidth: 2)
        )
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
