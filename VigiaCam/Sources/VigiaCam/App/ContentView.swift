import SwiftUI

struct ContentView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject var eventService: EventService
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var updates = UpdateService.shared
    @State private var selectedTab = "cameras"
    @State private var currentTime = ""
    @State private var cameras: [Camera] = []
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var categorias: [String] { Set(cameras.map { $0.categoria }).sorted() }
    private var papel: Papel { auth.logado?.papel ?? .visualizador }
    private var usuario: String { auth.logado?.nome ?? "sistema" }

    var body: some View {
        Group {
            if auth.logado == nil {
                LoginView()
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detail
                }
            }
        }
        .background(VigiaTheme.bg)
        .frame(minWidth: 900, minHeight: 600)
        .onReceive(timer) { _ in updateTime() }
        .onAppear {
            updateTime()
            cameras = storage.carregarCameras()
            AlarmService.shared.configure(eventService: eventService, cameras: cameras)
            LPRService.shared.configure(eventService: eventService)
            // Saúde das câmeras deixa de depender de a aba "Ao Vivo" estar
            // aberta (o Dashboard mostrava "Online: 0" por construção).
            CameraHealthMonitor.shared.configurar(cameras: cameras)
            // Retenção: `limparRetencao` existia, era testada e NUNCA era
            // chamada — o disco crescia para sempre e o prazo prometido na
            // tela de Configurações não valia nada (inclusive para LGPD).
            let dias = storage.carregarConfig().retencaoDias
            DispatchQueue.global(qos: .utility).async {
                storage.limparRetencao(dias: dias)
            }
        }
        .onChange(of: storage.camerasVersao) {
            cameras = storage.carregarCameras()
            AlarmService.shared.configure(eventService: eventService, cameras: cameras)
            CameraHealthMonitor.shared.configurar(cameras: cameras)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("VIGIA").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.white)
                    Text(".").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(VigiaTheme.accent)
                }
                // Lê do bundle: a string fixa aqui dizia "v2.3.0" enquanto o
                // app já era 2.4.0 — e ia continuar mentindo a cada release.
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") • macOS")
                    .font(.system(size: 9)).foregroundColor(VigiaTheme.muted)
            }.padding(.horizontal, 16).padding(.vertical, 12)

            Divider().background(VigiaTheme.border)

            sidebarButton("Ao Vivo", icon: "video.fill", tag: "cameras")
            sidebarButton("Mapa", icon: "map.fill", tag: "map")
            sidebarButton("Alarmes", icon: "bell.fill", tag: "alarms")
            sidebarButton("Placas", icon: "text.rectangle.page", tag: "lpr")
            sidebarButton("Negócio", icon: "chart.line.uptrend.xyaxis", tag: "business")
            sidebarButton("Dashboard", icon: "chart.bar.fill", tag: "dashboard")
            sidebarButton("Eventos", icon: "bolt.fill", tag: "events")
            sidebarButton("Gravações", icon: "film.stack", tag: "recordings")
            sidebarButton("Relatórios", icon: "doc.richtext.fill", tag: "reports")
            if papel.podeConfigurar {
                sidebarButton("Configurações", icon: "gearshape.fill", tag: "config")
            }

            Spacer()

            bannerUpdate

            Divider().background(VigiaTheme.border)
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 16)).foregroundColor(VigiaTheme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(usuario).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    Text(papel.label).font(.system(size: 9)).foregroundColor(VigiaTheme.muted)
                }
                Spacer()
                Button(action: { auth.logout(); selectedTab = "cameras" }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12)).foregroundColor(VigiaTheme.muted)
                }.buttonStyle(.plain).help("Sair")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 200)
        .background(VigiaTheme.panel)
    }

    /// Rodapé de auto-update: só aparece quando há versão nova no GitHub.
    @ViewBuilder
    private var bannerUpdate: some View {
        switch updates.estado {
        case .disponivel(let versao):
            Button(action: { updates.baixarEInstalar() }) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Versão \(versao) disponível", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.black)
                    Text("Clique para atualizar e reabrir").font(.system(size: 9)).foregroundColor(.black.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(VigiaTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 6)
        case .baixando:
            rodapeUpdate("Baixando atualização…", "arrow.down.circle")
        case .instalando:
            rodapeUpdate("Instalando…", "gearshape.arrow.triangle.2.circlepath")
        case .atualizado:
            rodapeUpdate("Atualizado — reabrindo…", "checkmark.circle.fill")
        case .falha(let msg):
            rodapeUpdate("Update falhou: \(msg)", "exclamationmark.triangle")
        default:
            EmptyView()
        }
    }

    private func rodapeUpdate(_ texto: String, _ icone: String) -> some View {
        Label(texto, systemImage: icone)
            .font(.system(size: 10)).foregroundColor(VigiaTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.bottom, 6)
            .lineLimit(2)
    }

    private func sidebarButton(_ title: String, icon: String, tag: String) -> some View {
        Button(action: { selectedTab = tag }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(selectedTab == tag ? VigiaTheme.accent : VigiaTheme.muted)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selectedTab == tag ? .bold : .medium))
                    .foregroundColor(selectedTab == tag ? .white : VigiaTheme.muted)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(selectedTab == tag ? VigiaTheme.accentGlow : Color.clear)
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case "cameras": LiveWallView(storage: storage)
        case "map": CameraMapView(storage: storage)
        case "alarms": AlarmsView(categorias: categorias)
        case "lpr": LPRView(podeGerenciar: papel.podeOperar)
        case "business": BusinessDashboardView()
        case "dashboard": DashboardView(storage: storage, eventService: eventService)
        case "events": EventListView(eventService: eventService, usuario: usuario,
                                     podeOperar: papel.podeOperar)
        case "recordings": RecordingsBrowserView(usuario: usuario, podeOperar: papel.podeOperar)
        case "reports": ReportsView(eventService: eventService, totalCameras: cameras.count,
                                     usuario: usuario)
        case "config" where papel.podeConfigurar: ConfigView(storage: storage)
        default: LiveWallView(storage: storage)
        }
    }

    private func updateTime() {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; currentTime = f.string(from: Date())
    }
}
