import SwiftUI
import AVKit
import UIKit

/// UIView customizada que avisa o `PiPManager` assim que entra na `UIWindow` real do iPhone,
/// garantindo que o `AVPictureInPictureController` habilite o PiP imediatamente.
final class LayerContainerUIView: UIView {
    var displayLayer: AVSampleBufferDisplayLayer?
    var onMovedToWindow: (() -> Void)?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer?.frame = bounds
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onMovedToWindow?()
        }
    }
}

/// Hospeda a `AVSampleBufferDisplayLayer` visível na tela principal para ancorar o Picture-in-Picture
struct SampleBufferLayerHostView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer
    let onAttached: () -> Void
    
    func makeUIView(context: Context) -> LayerContainerUIView {
        let view = LayerContainerUIView()
        view.backgroundColor = .clear
        displayLayer.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        displayLayer.videoGravity = .resizeAspectFill
        view.displayLayer = displayLayer
        view.onMovedToWindow = onAttached
        view.layer.addSublayer(displayLayer)
        return view
    }
    
    func updateUIView(_ uiView: LayerContainerUIView, context: Context) {
        displayLayer.frame = uiView.bounds
    }
}

/// Abas principais na barra inferior nativa do iOS (`TabView`)
private enum MainTab: Hashable {
    case cockpit
    case goalAndHistory
    case simulator
    case settingsAndAI
}

/// Tela principal com Design Automotivo Dark Mode e Navegação Nativa em 4 Abas
struct ContentView: View {
    @StateObject private var viewModel = RideAssistantViewModel()
    @State private var activeTab: MainTab = .cockpit
    @State private var broadcastTriggerCount: Int = 0
    
    @State private var newDangerKeyword: String = ""
    @State private var newBlacklistKeyword: String = ""
    @State private var newMarketKeyword: String = ""
    @State private var newHomeKeyword: String = ""
    
    var body: some View {
        TabView(selection: $activeTab) {
            // ABA 1: COCKPIT DE RUA (OPERAÇÃO PRINCIPAL)
            NavigationView {
                cockpitTabView
                    .navigationBarHidden(true)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Copiloto", systemImage: "car.circle.fill")
            }
            .tag(MainTab.cockpit)
            
            // ABA 2: META 250+ & HISTÓRICO DE CORRIDAS
            NavigationView {
                goalAndHistoryTabView
                    .navigationTitle("Meta 250+ & Turno")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Meta 250+", systemImage: "flame.fill")
            }
            .tag(MainTab.goalAndHistory)
            
            // ABA 3: SIMULADOR DE ROTAS (MARINGÁ • SARANDI • MARIALVA)
            NavigationView {
                simulatorTabView
                    .navigationTitle("Simulador de Rotas")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Simulador", systemImage: "bolt.horizontal.circle.fill")
            }
            .tag(MainTab.simulator)
            
            // ABA 4: AJUSTES, LISTAS E IA LOCAL
            NavigationView {
                settingsAndAITabView
                    .navigationTitle("Ajustes & IA")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Ajustes", systemImage: "slider.horizontal.3")
            }
            .tag(MainTab.settingsAndAI)
        }
        .preferredColorScheme(.dark)
        .accentColor(.cyan)
    }
    
    // MARK: - ABA 1: Cockpit Principal (Design Automotivo Limpo e Direto)
    
    private var cockpitTabView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Cabeçalho Compacto do Cockpit
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("COPILOTO UBER")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.isBroadcastActive ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(viewModel.isBroadcastActive ? "Leitor de Tela Ativo" : "Passo 1: Ligue o Leitor de Tela")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Mini Pílula da Meta 250+ (Toque leva para a aba Meta 250+)
                    Button {
                        activeTab = .goalAndHistory
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.isMetaDiariaBatida ? "trophy.fill" : "flame.fill")
                                .foregroundColor(viewModel.isMetaDiariaBatida ? .mint : .orange)
                                .font(.caption.bold())
                            Text("\(formatCurrency(viewModel.totalLucroLiquidoAceito)) / R$ \(Int(viewModel.settings.metaDiariaLiquida))+")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                }
                .padding(.top, 6)
                
                // Visor Ao Vivo (Player Real + Overlay do Semáforo)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("VISOR EM TEMPO REAL (PiP)", systemImage: "viewfinder")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if viewModel.currentVerdict.status != .waiting {
                            Button {
                                viewModel.toggleAcceptCurrentRide()
                            } label: {
                                Label(
                                    viewModel.isCurrentRideAccepted ? "Contabilizada" : "Marcar Aceita",
                                    systemImage: viewModel.isCurrentRideAccepted ? "checkmark.circle.fill" : "plus.circle.fill"
                                )
                                .font(.caption2.bold())
                                .foregroundColor(viewModel.isCurrentRideAccepted ? .green : .cyan)
                            }
                            
                            Text("•")
                                .foregroundColor(.secondary)
                            
                            Button("Limpar") {
                                viewModel.handleNewOCRText("AGUARDANDO CORRIDA...", isSimulated: true)
                            }
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    ZStack {
                        // A layer de vídeo fica visível (opacity 1.0) atrás do overlay para que o iOS libere o PiP na hora!
                        SampleBufferLayerHostView(
                            displayLayer: viewModel.pipManager.sampleBufferDisplayLayer,
                            onAttached: {
                                viewModel.pipManager.notifyLayerMovedToWindow()
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 175)
                        .cornerRadius(16)
                        
                        PiPOverlayView(viewModel: viewModel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 175)
                            .cornerRadius(16)
                            .allowsHitTesting(false)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(viewModel.currentVerdict.backgroundColor.opacity(0.85), lineWidth: 2)
                    )
                    .shadow(color: viewModel.currentVerdict.backgroundColor.opacity(0.35), radius: 10, x: 0, y: 4)
                }
                
                // 2 Botões Principais de Partida (Grandes, Modernos e 100% Responsivos)
                HStack(spacing: 12) {
                    // Botão 1: Iniciar Captura de Tela ReplayKit
                    Button {
                        broadcastTriggerCount += 1
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.22))
                                    .frame(width: 40, height: 40)
                                Image(systemName: viewModel.isBroadcastActive ? "record.circle.fill" : "dot.radiowaves.left.and.right")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.red)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PASSO 1")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundColor(.red)
                                Text(viewModel.isBroadcastActive ? "Captura Ativa" : "Iniciar Captura")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.18, green: 0.08, blue: 0.10), Color(red: 0.12, green: 0.12, blue: 0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.red.opacity(0.55), lineWidth: 1.5)
                        )
                    }
                    .background(
                        BroadcastPickerRepresentable(triggerId: broadcastTriggerCount)
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                            .allowsHitTesting(false)
                    )
                    
                    // Botão 2: Abrir / Fechar Janela Flutuante (PiP)
                    Button {
                        viewModel.pipManager.togglePiP()
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill((viewModel.pipManager.isPiPActive ? Color.green : Color.cyan).opacity(0.22))
                                    .frame(width: 40, height: 40)
                                Image(systemName: viewModel.pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(viewModel.pipManager.isPiPActive ? .green : .cyan)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PASSO 2")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundColor(viewModel.pipManager.isPiPActive ? .green : .cyan)
                                Text(viewModel.pipManager.isPiPActive ? "PiP Flutuando" : "Ativar Janela PiP")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(
                            LinearGradient(
                                colors: viewModel.pipManager.isPiPActive
                                    ? [Color(red: 0.06, green: 0.24, blue: 0.14), Color(red: 0.10, green: 0.14, blue: 0.12)]
                                    : [Color(red: 0.06, green: 0.18, blue: 0.28), Color(red: 0.10, green: 0.12, blue: 0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke((viewModel.pipManager.isPiPActive ? Color.green : Color.cyan).opacity(0.65), lineWidth: 1.5)
                        )
                    }
                }
                
                // Grid 2x2 de Modos Rápidos (Botões de Toque Inteiro - Sem texto quebrado!)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MODOS DE RUA (TOQUE PARA ATIVAR)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        cockpitModeButton(
                            title: "Trânsito / Chuva",
                            subtitle: "Exige R$ \(Int(viewModel.settings.minGanhoHoraTransito))/h",
                            icon: "cloud.heavyrain.fill",
                            activeColor: .orange,
                            isOn: $viewModel.isTrafficModeEnabled
                        )
                        
                        cockpitModeButton(
                            title: "Rumo a Casa",
                            subtitle: "Prioriza Maringá",
                            icon: "house.fill",
                            activeColor: .blue,
                            isOn: $viewModel.isGoingHomeModeEnabled
                        )
                        
                        cockpitModeButton(
                            title: "Modo Discreto",
                            subtitle: "Passageiro a bordo",
                            icon: "eye.slash.fill",
                            activeColor: .purple,
                            isOn: $viewModel.settings.modoDiscretoPassageiro
                        )
                        
                        cockpitModeButton(
                            title: "Sem Dinheiro",
                            subtitle: "Bloqueia espécie",
                            icon: "banknote.fill",
                            activeColor: .green,
                            isOn: $viewModel.settings.recusarCorridasDinheiro
                        )
                    }
                }
                
                // Seletor de Alerta Sonoro em 3 Botões Limpos (Sem texto cortado!)
                VStack(alignment: .leading, spacing: 8) {
                    Text("AVISO SONORO NO FONE / CARRO")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(AudioAlertMode.allCases) { mode in
                            let isSelected = (viewModel.audioAlertMode == mode)
                            Button {
                                viewModel.audioAlertMode = mode
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.iconName)
                                        .font(.system(size: 13, weight: .bold))
                                    Text(mode == .beep ? "Bipe" : (mode == .voice ? "Voz Falada" : "Mudo"))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(isSelected ? Color.cyan.opacity(0.22) : Color(.secondarySystemBackground))
                                .foregroundColor(isSelected ? .cyan : .secondary)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 1.5)
                                )
                            }
                        }
                    }
                }
                
                // Card de Pausa / Café compacto
                Button {
                    viewModel.isPausedForBreak.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(viewModel.isPausedForBreak ? .yellow : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isPausedForBreak ? "MODO PAUSA / CAFÉ ATIVO" : "Modo Pausa / Abastecimento")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Pausa o treino da IA enquanto você abastece ou descansa")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(viewModel.isPausedForBreak ? "LIGADO" : "OFF")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.isPausedForBreak ? Color.yellow.opacity(0.25) : Color.black.opacity(0.3))
                            .foregroundColor(viewModel.isPausedForBreak ? .yellow : .secondary)
                            .cornerRadius(6)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - ABA 2: Termômetro da Meta 250+ & Histórico do Turno
    
    private var goalAndHistoryTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Card Principal da Meta 250+
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            viewModel.isMetaDiariaBatida
                                ? "🔥 MODO 250+ ATIVO (META BATIDA!)"
                                : "META DIÁRIA LÍQUIDA (R$ 250+)",
                            systemImage: viewModel.isMetaDiariaBatida ? "trophy.fill" : "flame.fill"
                        )
                        .font(.caption.bold())
                        .foregroundColor(viewModel.isMetaDiariaBatida ? .mint : .orange)
                        
                        Spacer()
                        
                        Text("\(viewModel.percentualRealMetaDiaria)%")
                            .font(.headline.bold())
                            .foregroundColor(.green)
                    }
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatCurrency(viewModel.totalLucroLiquidoAceito))
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.green)
                        Text("líquidos hoje")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    ProgressView(value: viewModel.progressoMetaDiaria)
                        .tint(viewModel.isMetaDiariaBatida ? .mint : .green)
                        .scaleEffect(x: 1, y: 1.8, anchor: .center)
                    
                    HStack {
                        if viewModel.isMetaDiariaBatida {
                            Text("Bônus acima de R$ \(Int(viewModel.settings.metaDiariaLiquida)): +\(formatCurrency(viewModel.valorExcedenteMetaDiaria))")
                                .font(.caption.bold())
                                .foregroundColor(.mint)
                        } else {
                            Text("Faltam \(formatCurrency(viewModel.faltaParaMetaDiaria)) para bater R$ \(Int(viewModel.settings.metaDiariaLiquida)),00")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(viewModel.acceptedRides.count) aceitas")
                            .font(.caption.bold())
                            .foregroundColor(.cyan)
                    }
                    
                    Divider()
                    
                    HStack {
                        summaryStat(title: "Bruto Aceito", value: formatCurrency(viewModel.totalBrutoAceito))
                        Spacer()
                        summaryStat(title: "Gasolina/KM", value: "- " + formatCurrency(viewModel.totalCustoCombustivelAceito))
                        Spacer()
                        summaryStat(title: "KM Rodados", value: String(format: "%.1f km", viewModel.totalKmAceito).replacingOccurrences(of: ".", with: ","))
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                
                // Lista de Ofertas Recebidas
                HStack {
                    Text("HISTÓRICO DE CHAMADAS (\(viewModel.rideHistory.count))")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !viewModel.rideHistory.isEmpty {
                        Button("Zerar Turno", role: .destructive) {
                            viewModel.clearHistory()
                        }
                        .font(.caption.bold())
                    }
                }
                
                if viewModel.rideHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "car.2.fill")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Nenhuma corrida registrada neste turno.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                } else {
                    ForEach(viewModel.rideHistory) { item in
                        let lucroItem = item.data.lucroLiquido(custoPorKm: viewModel.settings.custoPorKm)
                        HStack(spacing: 12) {
                            Circle()
                                .fill(item.verdict.backgroundColor)
                                .frame(width: 12, height: 12)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.verdict.message)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    if let badge = item.verdict.passengerBadge {
                                        Text(badge)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(.tertiarySystemBackground))
                                            .cornerRadius(4)
                                    }
                                }
                                
                                Text("Bruto: \(formatCurrency(item.data.valorTotal)) • Líquido: \(formatCurrency(lucroItem))")
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                                
                                Text("Destino: \(item.data.enderecoDestino)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Button {
                                viewModel.toggleAccepted(for: item.id)
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: item.isAccepted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                    Text(item.isAccepted ? "Aceita" : "Somar")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(item.isAccepted ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - ABA 3: Simulador de Rotas Reais (Maringá • Sarandi • Marialva)
    
    private var simulatorTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Mini Visor no Topo do Simulador para ver o resultado na hora sem trocar de aba
                PiPOverlayView(viewModel: viewModel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 175)
                    .cornerRadius(14)
                    .shadow(radius: 6)
                
                Text("Toque em qualquer cenário abaixo para testar a matemática e o alerta de voz (não afeta o treino real da IA):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                simulatorCardButton(
                    title: "Maringá → Maringá (Tiro Curto Top)",
                    subtitle: "R$ 12,91 • 3,7 km (11 min) • Zona 7 → Centro",
                    badgeText: "APROVA",
                    badgeColor: .green
                ) {
                    viewModel.handleNewOCRText("""
                    R$ 12,91
                    Est. de R$3,49/km
                    4,97 (254) Verificado
                    2 min (0.4 km) Av. Maringá, Zona 7
                    9 minutos (3.3 km) Av. Brasil, Centro
                    """, isSimulated: true)
                }
                
                simulatorCardButton(
                    title: "Maringá → Sarandi (Corrida Boa)",
                    subtitle: "R$ 20,35 • 11 km (18 min) • Sem penalidade de volta vazia!",
                    badgeText: "APROVA",
                    badgeColor: .green
                ) {
                    viewModel.handleNewOCRText("""
                    R$ 20,35
                    4,94 (190) Verificado
                    2 min (0.8 km) Av. Colombo, Zona 7
                    16 minutos (10.2 km) Av. Londrina, Sarandi
                    """, isSimulated: true)
                }
                
                simulatorCardButton(
                    title: "Sarandi → Maringá (Retorno p/ Base)",
                    subtitle: "R$ 16,50 • 11 km (18 min) • Passageiro pagando sua volta!",
                    badgeText: "VOLTA P/ MGA",
                    badgeColor: .blue
                ) {
                    viewModel.handleNewOCRText("""
                    R$ 16,50
                    4,92 (140) Verificado
                    2 min (0.7 km) Av. Maringá, Sarandi
                    16 minutos (10.3 km) Av. Brasil, Zona 1, Maringá
                    """, isSimulated: true)
                }
                
                simulatorCardButton(
                    title: "Maringá → Marialva (Comum Fraca)",
                    subtitle: "R$ 26,00 • 18 km (24 min) • Desconta a volta vazia (Sobra R$ 7,67)",
                    badgeText: "CILADA",
                    badgeColor: .red
                ) {
                    viewModel.handleNewOCRText("""
                    R$ 26,00
                    4,95 (310) Verificado
                    3 min (1.0 km) Av. Brasil, Centro
                    21 minutos (17.0 km) Centro, Marialva
                    """, isSimulated: true)
                }
                
                simulatorCardButton(
                    title: "Maringá → Marialva (Valor Bom de Fato!)",
                    subtitle: "R$ 42,00 • 18 km (24 min) • Compensa ida + volta (Líq R$ 23,67)",
                    badgeText: "MARIALVA TOP",
                    badgeColor: .mint
                ) {
                    viewModel.handleNewOCRText("""
                    R$ 42,00
                    4,98 (420) Verificado
                    3 min (1.0 km) Av. Brasil, Centro
                    21 minutos (17.0 km) Centro, Marialva
                    """, isSimulated: true)
                }
                
                simulatorCardButton(
                    title: "Embarque em Supermercado / Atacadão",
                    subtitle: "R$ 10,50 • 4,4 km • Alerta de carrinho cheio e perda de tempo",
                    badgeText: "MERCADO",
                    badgeColor: .orange
                ) {
                    viewModel.handleNewOCRText("""
                    R$ 10,50
                    4,91 (110) Verificado
                    2 min (0.6 km) Atacadão, Av. Colombo
                    9 minutos (3.8 km) Jardim Alvorada
                    """, isSimulated: true)
                }
                
                simulatorCardButton(
                    title: "Passageiro Conta Nova (Só 4 viagens)",
                    subtitle: "R$ 12,00 • Nota 5,00 (4) • Alerta de segurança para conta recém-criada",
                    badgeText: "CONTA NOVA",
                    badgeColor: .orange
                ) {
                    viewModel.handleNewOCRText("""
                    R$ 12,00
                    5,00 (4)
                    2 min (0.5 km) Zona 5
                    9 minutos (4.0 km) Jardim América
                    """, isSimulated: true)
                }
                
                simulatorCardButton(
                    title: "Apple Maps: Uber exagerou os minutos",
                    subtitle: "R$ 10,00 • 20m na Uber mas apenas 6m livres no Apple Maps!",
                    badgeText: "MAPS TOP",
                    badgeColor: .cyan
                ) {
                    let overOCR = """
                    R$ 10,00
                    4,96 (210) Verificado
                    2 min (1.0 km) Av. Brasil, Centro
                    18 minutos (1.0 km) Av. São Paulo, Zona 1
                    """
                    let mapOverride = MapTrafficVerification(
                        appleMapsTotalMinutes: 6.0,
                        appleMapsTotalKm: 2.0,
                        minutesDifferenceFromUber: -14.0
                    )
                    viewModel.handleNewOCRText(overOCR, simulatedMapOverride: mapOverride, isSimulated: true)
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - ABA 4: Ajustes, Custos, Apple Maps e IA Local
    
    private var settingsAndAITabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Bloco 1: Custo do Carro e Meta 250+
                VStack(alignment: .leading, spacing: 12) {
                    Text("💰 SEU CARRO & META DIÁRIA (250+)")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                    
                    Stepper(value: $viewModel.settings.metaDiariaLiquida, in: 100.0...1000.0, step: 25.0) {
                        metricRow(title: "Meta Diária Base (250+)", value: formatCurrency(viewModel.settings.metaDiariaLiquida))
                    }
                    
                    Stepper(value: $viewModel.settings.custoPorKm, in: 0.20...2.00, step: 0.05) {
                        metricRow(title: "Custo de Combustível/KM", value: formatCurrency(viewModel.settings.custoPorKm) + "/km")
                    }
                    
                    Stepper(value: $viewModel.settings.minutosEsperaPortao, in: 0.0...5.0, step: 0.5) {
                        metricRow(title: "Taxa de Espera no Portão", value: String(format: "%.1f min", viewModel.settings.minutosEsperaPortao).replacingOccurrences(of: ".", with: ","))
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)
                
                // Bloco 2: Critérios de Aprovação (Maringá / Sarandi / Marialva)
                VStack(alignment: .leading, spacing: 12) {
                    Text("🎯 METAS DE APROVAÇÃO DA CORRIDA")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                    
                    Stepper(value: $viewModel.settings.minValorCorrida, in: 5.0...20.0, step: 0.50) {
                        metricRow(title: "Valor Mínimo da Chamada", value: formatCurrency(viewModel.settings.minValorCorrida))
                    }
                    
                    Stepper(value: $viewModel.settings.minGanhoKmNormal, in: 1.0...4.0, step: 0.05) {
                        metricRow(title: "Mínimo R$/km (Maringá/Sarandi)", value: formatCurrency(viewModel.settings.minGanhoKmNormal) + "/km")
                    }
                    
                    Stepper(value: $viewModel.settings.minGanhoKmListaNegra, in: 1.50...4.50, step: 0.10) {
                        metricRow(title: "Mínimo R$/km (Marialva/Volta Vazia)", value: formatCurrency(viewModel.settings.minGanhoKmListaNegra) + "/km")
                    }
                    
                    Stepper(value: $viewModel.settings.minGanhoHoraTransito, in: 20.0...100.0, step: 2.5) {
                        metricRow(title: "Mínimo R$/h no Trânsito", value: formatCurrency(viewModel.settings.minGanhoHoraTransito) + "/h")
                    }
                    
                    Stepper(value: $viewModel.settings.maxKmBusca, in: 0.5...8.0, step: 0.2) {
                        metricRow(title: "Distância Máxima de Busca", value: String(format: "%.1f km", viewModel.settings.maxKmBusca).replacingOccurrences(of: ".", with: ","))
                    }
                    
                    Stepper(value: $viewModel.settings.minNotaPassageiro, in: 4.40...4.95, step: 0.05) {
                        metricRow(title: "Nota Mínima do Passageiro", value: String(format: "★ %.2f", viewModel.settings.minNotaPassageiro).replacingOccurrences(of: ".", with: ","))
                    }
                    
                    Stepper(value: $viewModel.settings.minViagensPassageiro, in: 5...50, step: 5) {
                        metricRow(title: "Alerta Conta Nova (Mín. Viagens)", value: "\(viewModel.settings.minViagensPassageiro) viagens")
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)
                
                // Bloco 3: Inteligência Artificial & Apple Maps
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("🧠 APPLE MAPS & APRENDIZADO IA")
                            .font(.caption.bold())
                            .foregroundColor(.cyan)
                        Spacer()
                        if !viewModel.learnedProfiles.isEmpty {
                            Button("Limpar Memória IA", role: .destructive) {
                                viewModel.clearLearnedProfiles()
                            }
                            .font(.caption2.bold())
                        }
                    }
                    
                    Toggle("🗺️ Consultar Trânsito Real no Apple Maps", isOn: $viewModel.settings.usarVerificacaoAppleMaps)
                        .font(.subheadline.bold())
                    
                    Toggle("🧠 Aprender Bairros Evitados e Volta Vazia", isOn: $viewModel.settings.usarAprendizadoDeMaquina)
                        .font(.subheadline.bold())
                    
                    HStack {
                        Text("Cidade Base:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("Ex: Maringá, PR", text: $viewModel.settings.cidadePadrao)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)
                
                // Bloco 4: Listas de Cidades e Bairros
                VStack(alignment: .leading, spacing: 16) {
                    keywordListEditor(
                        title: "⚠️ DESTINOS DE VOLTA VAZIA (SOMA IDA + VOLTA)",
                        placeholder: "Ex: Marialva, Iguatemi, Floriano...",
                        textBinding: $newBlacklistKeyword,
                        items: viewModel.settings.blacklistedKeywords,
                        icon: "arrow.uturn.backward.circle.fill",
                        iconColor: .orange,
                        onAdd: {
                            viewModel.addBlacklistedKeyword(newBlacklistKeyword)
                            newBlacklistKeyword = ""
                        },
                        onDelete: { index in
                            viewModel.removeBlacklistedKeyword(at: IndexSet(integer: index))
                        }
                    )
                    
                    keywordListEditor(
                        title: "🛒 MERCADOS / ATACADÕES (AVISO DE COMPRAS)",
                        placeholder: "Ex: Atacadão, Assaí, Muffato...",
                        textBinding: $newMarketKeyword,
                        items: viewModel.settings.marketPickupKeywords,
                        icon: "cart.fill",
                        iconColor: .yellow,
                        onAdd: {
                            viewModel.addMarketKeyword(newMarketKeyword)
                            newMarketKeyword = ""
                        },
                        onDelete: { index in
                            viewModel.removeMarketKeyword(at: IndexSet(integer: index))
                        }
                    )
                    
                    keywordListEditor(
                        title: "🏠 SUA BASE PRINCIPAL / RUMO A CASA",
                        placeholder: "Ex: Maringá, Centro, Zona 7...",
                        textBinding: $newHomeKeyword,
                        items: viewModel.settings.favoriteHomeKeywords,
                        icon: "house.circle.fill",
                        iconColor: .blue,
                        onAdd: {
                            viewModel.addFavoriteHomeKeyword(newHomeKeyword)
                            newHomeKeyword = ""
                        },
                        onDelete: { index in
                            viewModel.removeFavoriteHomeKeyword(at: IndexSet(integer: index))
                        }
                    )
                    
                    keywordListEditor(
                        title: "🛑 ZONAS PROIBIDAS (REPROVA SEMPRE)",
                        placeholder: "Adicionar bairro proibido...",
                        textBinding: $newDangerKeyword,
                        items: viewModel.settings.dangerZoneKeywords,
                        icon: "exclamationmark.octagon.fill",
                        iconColor: .red,
                        onAdd: {
                            viewModel.addDangerZoneKeyword(newDangerKeyword)
                            newDangerKeyword = ""
                        },
                        onDelete: { index in
                            viewModel.removeDangerZoneKeyword(at: IndexSet(integer: index))
                        }
                    )
                    
                    Button(role: .destructive) {
                        viewModel.resetSettingsToDefault()
                    } label: {
                        Label("Restaurar Padrões de Fábrica", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)
            }
            .padding(16)
        }
    }
    
    // MARK: - Componentes Visuais Automotivos
    
    private func cockpitModeButton(
        title: String,
        subtitle: String,
        icon: String,
        activeColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isOn.wrappedValue ? activeColor : .secondary)
                    Spacer()
                    Text(isOn.wrappedValue ? "ATIVO" : "OFF")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isOn.wrappedValue ? activeColor.opacity(0.25) : Color.black.opacity(0.25))
                        .foregroundColor(isOn.wrappedValue ? activeColor : .secondary)
                        .cornerRadius(6)
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn.wrappedValue ? activeColor.opacity(0.14) : Color(.secondarySystemBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isOn.wrappedValue ? activeColor.opacity(0.8) : Color.white.opacity(0.06), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func simulatorCardButton(
        title: String,
        subtitle: String,
        badgeText: String,
        badgeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(badgeColor)
                    .frame(width: 5, height: 42)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(badgeText)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(badgeColor.opacity(0.20))
                    .foregroundColor(badgeColor)
                    .cornerRadius(8)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func keywordListEditor(
        title: String,
        placeholder: String,
        textBinding: Binding<String>,
        items: [String],
        icon: String,
        iconColor: Color,
        onAdd: @escaping () -> Void,
        onDelete: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
            
            HStack {
                TextField(placeholder, text: textBinding)
                    .textFieldStyle(.roundedBorder)
                
                Button("Adicionar", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .disabled(textBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            ForEach(Array(items.enumerated()), id: \.offset) { index, keyword in
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                    Text(keyword)
                        .font(.subheadline)
                    Spacer()
                    Button(role: .destructive) {
                        onDelete(index)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
    }
    
    private func summaryStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }
    
    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.cyan)
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        String(format: "R$ %.2f", value).replacingOccurrences(of: ".", with: ",")
    }
}
