import SwiftUI

struct ConfigView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject private var alarmes = AlarmService.shared
    @ObservedObject private var lpr = LPRService.shared
    @State private var config: AppConfig = .default
    @State private var cameras: [Camera] = []
    @State private var showingAddCamera = false
    @State private var selectedTab = 0
    @State private var modeloAtivo = ModelProvider.tipoAtivo
    @State private var avisoConfig: String?
    @State private var cameraParaRemover: Camera?
    @State private var modoNoturno = NightBoost.modo

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                Text("Detecção").tag(0); Text("Câmeras").tag(1); Text("Alarmes").tag(2)
                Text("Usuários").tag(3); Text("Auditoria").tag(4)
            }
                .pickerStyle(.segmented).padding(16)
            switch selectedTab {
            case 0: configTab
            case 1: camerasTab
            case 2: alarmesTab
            case 3: UsersAdminView()
            case 4: AuditLogView()
            default: configTab
            }
        }
        .background(VigiaTheme.bg)
        .onAppear { config = storage.carregarConfig(); cameras = storage.carregarCameras() }
    }

    /// Opções de resposta a alarme e integrações — o webhook existia no motor
    /// desde sempre, mas nenhuma tela o expunha.
    private var alarmesTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                configRow(title: "Som ao disparar", value: alarmes.somAtivo ? "ligado" : "desligado") {
                    Toggle("", isOn: $alarmes.somAtivo).toggleStyle(.switch).tint(VigiaTheme.accent).labelsHidden()
                }
                configRow(title: "Notificação do sistema (macOS)", value: alarmes.notificacaoSistema ? "ligada" : "desligada") {
                    Toggle("", isOn: $alarmes.notificacaoSistema).toggleStyle(.switch).tint(VigiaTheme.accent).labelsHidden()
                }
                configRow(title: "Snapshot automático de evidência", value: alarmes.autoSnapshot ? "ligado" : "desligado") {
                    Toggle("", isOn: $alarmes.autoSnapshot).toggleStyle(.switch).tint(VigiaTheme.accent).labelsHidden()
                }
                configRow(title: "LPR — leitura de placas", value: lpr.ativo ? "ligado" : "desligado") {
                    Toggle("", isOn: $lpr.ativo).toggleStyle(.switch).tint(VigiaTheme.accent).labelsHidden()
                }
                configRow(title: "Webhook (POST JSON por alarme)", value: alarmes.webhookURL.isEmpty ? "—" : "ativo") {
                    TextField("https://sua-central/webhook", text: $alarmes.webhookURL)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("Testar envio") { alarmes.testarWebhook() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(alarmes.webhookURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let ultimo = alarmes.ultimoWebhook {
                            Text(ultimo).font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ultimo.contains("OK") ? VigiaTheme.ok : VigiaTheme.danger)
                        } else {
                            Text("Nenhum envio nesta sessão.").font(.system(size: 10))
                                .foregroundColor(VigiaTheme.muted)
                        }
                    }
                }
                configRow(title: "Atualizações", value: "v\(UpdateService.shared.versaoAtual)") {
                    UpdateStatusRow()
                }
            }.padding(16)
        }
    }

    private var configTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                configRow(title: "FPS Máximo", value: "\(config.fpsMax)") { Stepper("", value: $config.fpsMax, in: 1...60).labelsHidden() }
                configRow(title: "Confiança Mínima", value: String(format: "%.0f%%", config.confianca * 100)) { Slider(value: $config.confianca, in: 0.05...0.95, step: 0.05).tint(VigiaTheme.accent) }
                // "Resolução Inferência" saiu daqui: o detector usa a resolução
                // fixa do .mlpackage (ModelProvider.inputSize), então o campo
                // nunca teve efeito nenhum — quem muda a resolução é a escolha
                // do modelo, logo abaixo.
                configRow(title: "Retenção (dias)", value: "\(config.retencaoDias)") { Stepper("", value: $config.retencaoDias, in: 1...365).labelsHidden() }
                configRow(title: "Modelo de detecção (padrão)", value: modeloAtivo.rotulo) {
                    Picker("", selection: Binding(
                        get: { modeloAtivo },
                        set: { ModelProvider.tipoAtivo = $0; modeloAtivo = $0 }
                    )) {
                        ForEach(TipoModelo.allCases, id: \.self) { Text($0.rotulo).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text("Eval COCO do repo (12 imagens, 52 classes): v8n 63% precisão / 46% recall; yolo11s 60% / 54%; 960px 54% / 58% (melhor recall de objeto distante, ~2,2× o custo). É a resolução do modelo que define a resolução de inferência. Cada câmera pode sobrescrever este padrão na própria tela.")
                        .font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                }
                configRow(title: "Modo noturno (detecção)", value: modoNoturno.titulo) {
                    Picker("", selection: Binding(
                        get: { modoNoturno },
                        set: { NightBoost.modo = $0; modoNoturno = $0 }
                    )) {
                        ForEach(NightBoost.Modo.allCases, id: \.self) { Text($0.titulo).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text("Realce de baixa luz aplicado ao frame antes do YOLO (sombras + exposição + gamma + redução de ruído). Em \"Auto\", só entra quando a cena está escura de fato (luminância média < 25%) — de dia não custa nada.")
                        .font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
                }
                Button(action: salvar) {
                    Text("Salvar").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if let avisoConfig {
                    Text(avisoConfig).font(.system(size: 11))
                        .foregroundColor(avisoConfig.hasPrefix("Falha") ? VigiaTheme.danger : VigiaTheme.ok)
                }
            }.padding(16)
        }
    }

    /// Salvar não dava retorno nenhum (nem em falha de cifra) e as câmeras já
    /// rodando continuavam com a config antiga, porque o ViewModel só a lia no
    /// init. A notificação faz as sessões vivas reagirem na hora.
    private func salvar() {
        let validada = config.validated()
        storage.salvarConfig(validada)
        config = validada
        NotificationCenter.default.post(name: .configAlterada, object: nil)
        avisoConfig = "Configurações salvas e aplicadas às câmeras em execução."
    }

    private func configRow<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white); Spacer()
                Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(VigiaTheme.accent) }
            content()
        }.padding(12).background(VigiaTheme.card).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var camerasTab: some View {
        VStack(spacing: 0) {
            Button(action: { showingAddCamera = true }) {
                Label("Adicionar Câmera", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(VigiaTheme.accentGradient).clipShape(RoundedRectangle(cornerRadius: 10))
            }.padding(.horizontal, 16).padding(.vertical, 12)
            .sheet(isPresented: $showingAddCamera) { addCameraSheet }
            if cameras.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.badge.plus").font(.system(size: 48)).foregroundColor(VigiaTheme.border)
                    Text("Nenhuma câmera cadastrada").font(.system(size: 14, weight: .semibold)).foregroundColor(VigiaTheme.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List { ForEach(cameras) { camera in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(camera.nome).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                            Text(camera.url).font(.system(size: 11, design: .monospaced)).foregroundColor(VigiaTheme.muted).lineLimit(1)
                        }
                        Spacer()
                        Text(camera.categoria).font(.system(size: 10, weight: .bold)).foregroundColor(VigiaTheme.accent2)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(VigiaTheme.accent2Glow).clipShape(RoundedRectangle(cornerRadius: 4))
                        // Remoção era imediata e sem desfazer, num item que
                        // pode ter meses de gravação e configuração associadas.
                        Button(action: { cameraParaRemover = camera }) {
                            Image(systemName: "trash").font(.system(size: 12)).foregroundColor(VigiaTheme.danger)
                        }.buttonStyle(.plain)
                    }.listRowBackground(VigiaTheme.card).listRowSeparator(.hidden)
                }}.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .confirmationDialog("Remover câmera?",
                            isPresented: Binding(get: { cameraParaRemover != nil },
                                                 set: { if !$0 { cameraParaRemover = nil } }),
                            presenting: cameraParaRemover) { cam in
            Button("Remover \(cam.nome)", role: .destructive) {
                cameras.removeAll { $0.id == cam.id }
                storage.salvarCameras(cameras)
                cameraParaRemover = nil
            }
            Button("Cancelar", role: .cancel) { cameraParaRemover = nil }
        } message: { cam in
            Text("As gravações e capturas já feitas continuam no disco, mas a câmera sai do videowall, do mapa e dos painéis.\n\n\(cam.url)")
        }
    }

    private var addCameraSheet: some View {
        AddCameraSheet(
            // Eram os ids (UUID) e o sheet compara com a URL: o aviso de
            // "essa URL já está cadastrada" era inalcançável.
            existentes: cameras.map(\.url),
            onCancel: { showingAddCamera = false },
            onAdd: { nova in
                cameras.append(nova)
                storage.salvarCameras(cameras)
                showingAddCamera = false
            }
        )
    }

}
