import SwiftUI
import AVKit

/// View container que hospeda a `AVSampleBufferDisplayLayer` na tela principal do app
/// (necessário no iOS para que o sistema saiba de onde ancorar e iniciar o Picture-in-Picture).
struct SampleBufferLayerHostView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        displayLayer.frame = CGRect(x: 0, y: 0, width: 380, height: 110)
        displayLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(displayLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        displayLayer.frame = uiView.bounds
    }
}

/// Abas da tela principal para organizar Simulador, Meta/Histórico, IA/Maps e Configurações
private enum DashboardTab: String, CaseIterable, Identifiable {
    case simulator = "Simulador"
    case history = "Meta & Histórico"
    case learning = "IA & Maps"
    case settings = "Ajustes"
    
    var id: String { rawValue }
}

/// Tela principal do aplicativo auxiliar do motorista
struct ContentView: View {
    @StateObject private var viewModel = RideAssistantViewModel()
    @State private var selectedTab: DashboardTab = .simulator
    
    @State private var newDangerKeyword: String = ""
    @State private var newBlacklistKeyword: String = ""
    @State private var newMarketKeyword: String = ""
    @State private var newHomeKeyword: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // 1. Preview em Tempo Real do Card do PiP + Ações Rápidas da Corrida Atual
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("PRÉVIA DA JANELA FLUTUANTE (PiP)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if viewModel.currentVerdict.status != .waiting {
                                Button {
                                    viewModel.toggleAcceptCurrentRide()
                                } label: {
                                    Label(
                                        viewModel.isCurrentRideAccepted ? "Corrida Contabilizada" : "Aceitei Corrida",
                                        systemImage: viewModel.isCurrentRideAccepted ? "checkmark.circle.fill" : "plus.circle"
                                    )
                                    .font(.caption.bold())
                                    .foregroundColor(viewModel.isCurrentRideAccepted ? .green : .blue)
                                }
                                
                                Text("•")
                                    .foregroundColor(.secondary)
                                
                                Button("Limpar") {
                                    viewModel.handleNewOCRText("AGUARDANDO CORRIDA...")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            }
                        }
                        
                        ZStack {
                            SampleBufferLayerHostView(displayLayer: viewModel.pipManager.sampleBufferDisplayLayer)
                                .frame(width: 380, height: 110)
                                .opacity(0.01)
                            
                            PiPOverlayView(viewModel: viewModel)
                                .cornerRadius(14)
                                .shadow(radius: 6)
                        }
                    }
                    
                    // 2. Controles Rápidos de Operação
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Toggle(isOn: $viewModel.isTrafficModeEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("Trânsito/Chuva", systemImage: "cloud.heavyrain.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                    Text(formatCurrency(viewModel.settings.minGanhoHoraTransito) + "/h")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                            
                            Toggle(isOn: $viewModel.isGoingHomeModeEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("Rumo a Casa", systemImage: "house.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.blue)
                                    Text("Priorizar Maringá")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        
                        HStack(spacing: 10) {
                            Toggle(isOn: $viewModel.settings.modoDiscretoPassageiro) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("Modo Discreto", systemImage: "eye.slash.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.purple)
                                    Text("Passageiro a bordo")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                            
                            Toggle(isOn: $viewModel.isPausedForBreak) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("Pausa / Café", systemImage: "cup.and.saucer.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.brown)
                                    Text("Pausar treino IA")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        
                        Toggle(isOn: $viewModel.settings.recusarCorridasDinheiro) {
                            HStack {
                                Image(systemName: "banknote.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text("Bloquear Pagamento em Dinheiro (Modo Noturno)")
                                        .font(.caption.bold())
                                    Text("Reprova automaticamente chamadas em espécie/troco")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        
                        HStack {
                            Label("Alerta:", systemImage: viewModel.audioAlertMode.iconName)
                                .font(.caption.bold())
                            Spacer()
                            Picker("Modo de Áudio", selection: $viewModel.audioAlertMode) {
                                ForEach(AudioAlertMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 240)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        
                        HStack(spacing: 14) {
                            VStack {
                                BroadcastPickerRepresentable(
                                    extensionBundleIdentifier: "com.seuapp.uberhelper.BroadcastExtension"
                                )
                                .frame(width: 48, height: 48)
                                
                                Text("1. Iniciar Captura")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            
                            Button {
                                viewModel.pipManager.togglePiP()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: viewModel.pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                                        .font(.system(size: 24))
                                    Text(viewModel.pipManager.isPiPActive ? "Fechar Janela PiP" : "2. Ativar Janela PiP")
                                        .font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .background(viewModel.pipManager.isPiPActive ? Color.green : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                    }
                    
                    // 3. Seletor de Abas
                    Picker("Seção", selection: $selectedTab) {
                        ForEach(DashboardTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    switch selectedTab {
                    case .simulator:
                        simulatorSection
                    case .history:
                        historyAndGoalSection
                    case .learning:
                        learningAndMapsSection
                    case .settings:
                        settingsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Copiloto Uber iOS")
        }
    }
    
    // MARK: - Seção 1: Simulador OCR (Focado em Maringá, Sarandi e Marialva)
    
    private var simulatorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SIMULADOR DE ROTAS REAIS (MARINGÁ • SARANDI • MARIALVA)")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            Button("🟢 Maringá -> Maringá (Tiro Curto Z7 -> Centro: R$ 12,91)") {
                let sampleOCR = """
                R$ 12,91
                Est. de R$3,49/km
                4,97 (254) Verificado
                2 min (0.4 km) Av. Maringá, Zona 7
                9 minutos (3.3 km) Av. Brasil, Centro
                """
                viewModel.handleNewOCRText(sampleOCR)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            
            Button("🟢 Maringá -> Sarandi (Boa: R$ 20,35 | 11 km -> Fica/Toca em Sarandi)") {
                let mgaSarandiGood = """
                R$ 20,35
                4,94 (190) Verificado
                2 min (0.8 km) Av. Colombo, Zona 7
                16 minutos (10.2 km) Av. Londrina, Sarandi
                """
                viewModel.handleNewOCRText(mgaSarandiGood)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            
            Button("🔵 Sarandi -> Maringá (Voltando p/ Base Maringá: R$ 16,50)") {
                let sarandiToMga = """
                R$ 16,50
                4,92 (140) Verificado
                2 min (0.7 km) Av. Maringá, Sarandi
                16 minutos (10.3 km) Av. Brasil, Zona 1, Maringá
                """
                viewModel.handleNewOCRText(sarandiToMga)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            
            Button("🔴 Maringá -> Marialva (Comum Fraca R$ 26,00 -> Cobra Volta Vazia!)") {
                let marialvaWeak = """
                R$ 26,00
                4,95 (310) Verificado
                3 min (1.0 km) Av. Brasil, Centro
                21 minutos (17.0 km) Centro, Marialva
                """
                viewModel.handleNewOCRText(marialvaWeak)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            
            Button("🏆 Maringá -> Marialva (Valor BOM DE FATO no Dinâmico: R$ 42,00)") {
                let marialvaTop = """
                R$ 42,00
                4,98 (420) Verificado
                3 min (1.0 km) Av. Brasil, Centro
                21 minutos (17.0 km) Centro, Marialva
                """
                viewModel.handleNewOCRText(marialvaTop)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            
            Button("🛒 Alerta de Embarque em Mercado (Atacadão / Compras)") {
                let marketOCR = """
                R$ 10,50
                4,91 (110) Verificado
                2 min (0.6 km) Atacadão, Av. Colombo
                9 minutos (3.8 km) Jardim Alvorada
                """
                viewModel.handleNewOCRText(marketOCR)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            
            Button("🛡️ Alerta de Conta Nova / Suspeita (★ 5,00 mas só 4 viagens!)") {
                let newAccountOCR = """
                R$ 12,00
                5,00 (4)
                2 min (0.5 km) Zona 5
                9 minutos (4.0 km) Jardim América
                """
                viewModel.handleNewOCRText(newAccountOCR)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            
            Button("🗺️ Apple Maps: Uber exagerou (20m na Uber -> 6m livres no Maps)") {
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
                viewModel.handleNewOCRText(overOCR, simulatedMapOverride: mapOverride)
            }
            .buttonStyle(.bordered)
            .tint(.teal)
            
            Button("🔴 Perigo Manual: Zona Proibida (Vila Pedreira)") {
                let dangerOCR = """
                R$ 14,00
                4,89 (42)
                2 min (0.5 km) Av. Brasil
                7 minutos (2.5 km) Rua das Pedras, Vila Pedreira
                """
                viewModel.handleNewOCRText(dangerOCR)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Seção 2: Termômetro da Meta Diária & Histórico da Sessão
    
    private var historyAndGoalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        viewModel.isMetaDiariaBatida
                            ? "🔥 MODO 250+ ATIVO (META BASE BATIDA!)"
                            : "TERMÔMETRO DA META DIÁRIA (250+)",
                        systemImage: viewModel.isMetaDiariaBatida ? "trophy.fill" : "flame.fill"
                    )
                    .font(.caption.bold())
                    .foregroundColor(viewModel.isMetaDiariaBatida ? .mint : .orange)
                    
                    Spacer()
                    
                    Text("\(viewModel.percentualRealMetaDiaria)%")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                
                ProgressView(value: viewModel.progressoMetaDiaria)
                    .tint(viewModel.isMetaDiariaBatida ? .mint : .green)
                
                HStack {
                    Text("Lucro Líquido: \(formatCurrency(viewModel.totalLucroLiquidoAceito))")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                    Spacer()
                    if viewModel.isMetaDiariaBatida {
                        Text("Bônus 250+: +\(formatCurrency(viewModel.valorExcedenteMetaDiaria))")
                            .font(.caption.bold())
                            .foregroundColor(.mint)
                    } else {
                        Text("Faltam \(formatCurrency(viewModel.faltaParaMetaDiaria)) p/ \(formatCurrency(viewModel.settings.metaDiariaLiquida))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                HStack {
                    summaryStat(title: "Bruto Aceito", value: formatCurrency(viewModel.totalBrutoAceito))
                    Spacer()
                    summaryStat(title: "Combustível/KM", value: "- " + formatCurrency(viewModel.totalCustoCombustivelAceito))
                    Spacer()
                    summaryStat(title: "Distância", value: String(format: "%.1f km", viewModel.totalKmAceito).replacingOccurrences(of: ".", with: ","))
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            
            HStack {
                Text("OFERTAS RECEBIDAS (\(viewModel.rideHistory.count))")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !viewModel.rideHistory.isEmpty {
                    Button("Limpar Histórico", role: .destructive) {
                        viewModel.clearHistory()
                    }
                    .font(.caption.bold())
                }
            }
            
            if viewModel.rideHistory.isEmpty {
                Text("Nenhuma corrida analisada nesta sessão ainda.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.rideHistory) { item in
                    let lucroItem = item.data.lucroLiquido(custoPorKm: viewModel.settings.custoPorKm)
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.verdict.backgroundColor)
                            .frame(width: 12, height: 12)
                        
                        VStack(alignment: .leading, spacing: 3) {
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
                                .foregroundColor(.primary)
                            
                            Text("Destino: \(item.data.enderecoDestino)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Button {
                            viewModel.toggleAccepted(for: item.id)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: item.isAccepted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                Text(item.isAccepted ? "Aceita" : "Aceitar")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(item.isAccepted ? .green : .secondary)
                            .padding(.leading, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Seção 3: Painel de Inteligência Artificial (Aprendizado Local) e Apple Maps
    
    private var learningAndMapsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INTELIGÊNCIA NATIVA (APPLE MAPS + MACHINE LEARNING)")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            VStack(spacing: 10) {
                Toggle("🗺️ Consultar Trânsito Real no Apple Maps (MapKit)", isOn: $viewModel.settings.usarVerificacaoAppleMaps)
                    .font(.subheadline.bold())
                
                Text("Compara os minutos informados pela Uber com o trânsito real da rua no Apple Maps para descobrir se a Uber exagerou no tempo ou escondeu um engarrafamento.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Text("Cidade Padrão:")
                        .font(.caption.bold())
                    TextField("Ex: Maringá, PR", text: $viewModel.settings.cidadePadrao)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                
                Divider()
                
                Toggle("🧠 Aprendizado Automático de Bairros e Trânsito", isOn: $viewModel.settings.usarAprendizadoDeMaquina)
                    .font(.subheadline.bold())
                
                Text("Aprende sozinho quais regiões você evita mesmo pagando bem (Segurança), mede o tempo ocioso após cada desembarque (Volta Vazia) e liga o Modo Trânsito quando a velocidade média das chamadas cai.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            
            HStack {
                Text("MEMÓRIA DE BAIRROS APRENDIDA (\(viewModel.learnedProfiles.count))")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.learnedProfiles.isEmpty {
                    Button("Zerar Memória IA", role: .destructive) {
                        viewModel.clearLearnedProfiles()
                    }
                    .font(.caption.bold())
                }
            }
            
            if viewModel.learnedProfiles.isEmpty {
                Text("O motor de aprendizado ainda está coletando dados. Conforme você aceita ou ignora corridas no dia a dia, os perfis de cada bairro aparecem aqui.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(viewModel.learnedProfiles) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(profile.displayName)
                                .font(.subheadline.bold())
                            Spacer()
                            if profile.isLearnedDangerZone {
                                Text("🚨 EVITADO / RISCO")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.2))
                                    .foregroundColor(.red)
                                    .cornerRadius(4)
                            } else if profile.isLearnedDeadheadZone {
                                Text("🛣️ VOLTA VAZIA")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            } else {
                                Text("✓ NORMAL")
                                    .font(.caption2.bold())
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Text("Ofertas: \(profile.totalOffersCount) • Aceitas: \(profile.acceptedCount) • Recusadas pagando bem: \(profile.rejectedWhenGoodCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if !profile.deadheadWaitMinutesSamples.isEmpty {
                            Text(String(format: "Média de espera após desembarque: %.0f min sem corrida", profile.averageDeadheadMinutes))
                                .font(.caption2.bold())
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(10)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Seção 4: Custos, Metas e Mapas Geográficos Manuais
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CUSTO DO CARRO E METAS")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Restaurar Padrão") {
                    viewModel.resetSettingsToDefault()
                }
                .font(.caption)
            }
            
            VStack(spacing: 10) {
                Stepper(
                    value: $viewModel.settings.custoPorKm,
                    in: 0.20...2.50,
                    step: 0.05
                ) {
                    metricRow(title: "Custo do Carro (Combustível/KM)", value: formatCurrency(viewModel.settings.custoPorKm) + "/km")
                }
                
                Stepper(
                    value: $viewModel.settings.minValorCorrida,
                    in: 5.0...15.0,
                    step: 0.50
                ) {
                    metricRow(title: "Valor Mínimo da Chamada", value: formatCurrency(viewModel.settings.minValorCorrida))
                }
                
                Stepper(
                    value: $viewModel.settings.metaDiariaLiquida,
                    in: 50.0...1000.0,
                    step: 25.0
                ) {
                    metricRow(title: "Meta Diária Líquida", value: formatCurrency(viewModel.settings.metaDiariaLiquida))
                }
                
                Divider()
                
                Stepper(
                    value: $viewModel.settings.minGanhoKmNormal,
                    in: 1.0...4.0,
                    step: 0.05
                ) {
                    metricRow(title: "Meta Maringá/Sarandi (R$/km)", value: formatCurrency(viewModel.settings.minGanhoKmNormal) + "/km")
                }
                
                Stepper(
                    value: $viewModel.settings.minGanhoKmListaNegra,
                    in: 1.50...4.0,
                    step: 0.10
                ) {
                    metricRow(title: "Mínimo Marialva/Floriano (R$/km)", value: formatCurrency(viewModel.settings.minGanhoKmListaNegra) + "/km")
                }
                
                Stepper(
                    value: $viewModel.settings.minGanhoHoraTransito,
                    in: 25.0...90.0,
                    step: 2.50
                ) {
                    metricRow(title: "Mínimo no Trânsito/Chuva", value: formatCurrency(viewModel.settings.minGanhoHoraTransito) + "/h")
                }
                
                Stepper(
                    value: $viewModel.settings.maxTempoBuscaMin,
                    in: 2.0...15.0,
                    step: 1.0
                ) {
                    metricRow(title: "Busca Máxima (Minutos)", value: "\(Int(viewModel.settings.maxTempoBuscaMin)) min")
                }
                
                Stepper(
                    value: $viewModel.settings.maxKmBusca,
                    in: 0.5...5.0,
                    step: 0.2
                ) {
                    metricRow(title: "Busca Máxima (Distância KM)", value: String(format: "%.1f km", viewModel.settings.maxKmBusca).replacingOccurrences(of: ".", with: ","))
                }
                
                Divider()
                
                Stepper(
                    value: $viewModel.settings.minNotaPassageiro,
                    in: 4.00...4.95,
                    step: 0.05
                ) {
                    metricRow(title: "Nota Mínima Passageiro", value: String(format: "★ %.2f", viewModel.settings.minNotaPassageiro))
                }
                
                Stepper(
                    value: $viewModel.settings.minViagensPassageiro,
                    in: 5...50,
                    step: 5
                ) {
                    metricRow(title: "Mínimo Viagens (Conta Nova)", value: "\(viewModel.settings.minViagensPassageiro) viagens")
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            
            keywordListEditor(
                title: "🚨 ZONAS DE RISCO / PROIBIDAS (REPROVA SEMPRE)",
                placeholder: "Adicionar local perigoso...",
                textBinding: $newDangerKeyword,
                items: viewModel.settings.dangerZoneKeywords,
                icon: "exclamationmark.triangle.fill",
                iconColor: .red,
                onAdd: {
                    viewModel.addDangerZoneKeyword(newDangerKeyword)
                    newDangerKeyword = ""
                },
                onDelete: { index in
                    viewModel.removeDangerZoneKeyword(at: IndexSet(integer: index))
                }
            )
            
            keywordListEditor(
                title: "🛣️ VOLTA VAZIA: MARIALVA / IGUATEMI / FLORIANO (EXIGE >= \(formatCurrency(viewModel.settings.minGanhoKmListaNegra))/KM)",
                placeholder: "Adicionar cidade/distrito sem volta...",
                textBinding: $newBlacklistKeyword,
                items: viewModel.settings.blacklistedKeywords,
                icon: "mappin.slash.circle.fill",
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
                title: "🛒 MERCADOS / ATACADÕES (ALERTA DE COMPRAS NO EMBARQUE)",
                placeholder: "Adicionar supermercado/atacadão...",
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
                title: "🏠 SUA BASE PRINCIPAL / RUMO A CASA (MARINGÁ)",
                placeholder: "Adicionar bairro de Maringá...",
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Componentes Visuais Auxiliares
    
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
                .font(.caption.bold())
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
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
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
                .foregroundColor(.blue)
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        String(format: "R$ %.2f", value).replacingOccurrences(of: ".", with: ",")
    }
}
