import SwiftUI

struct ContentView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject var eventService: EventService
    @ObservedObject private var auth = AuthService.shared
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
        }
        .onChange(of: storage.camerasVersao) {
            cameras = storage.carregarCameras()
            AlarmService.shared.configure(eventService: eventService, cameras: cameras)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("VIGIA").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.white)
                    Text(".").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(VigiaTheme.accent)
                }
                Text("v2.2.0 • macOS").font(.system(size: 9)).foregroundColor(VigiaTheme.muted)
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
        case "events": EventListView(eventService: eventService, usuario: usuario)
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
