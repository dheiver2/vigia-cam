import SwiftUI

struct ContentView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject var rbac: RBACService
    @ObservedObject var eventService: EventService
    @State private var selectedTab = "cameras"
    @State private var currentTime = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(VigiaTheme.bg)
        .frame(minWidth: 900, minHeight: 600)
        .onReceive(timer) { _ in updateTime() }
        .onAppear { updateTime() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("VIGIA").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.white)
                    Text(".").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(VigiaTheme.accent)
                }
                Text("v2.0.0 • macOS").font(.system(size: 9)).foregroundColor(VigiaTheme.muted)
            }.padding(.horizontal, 16).padding(.vertical, 12)

            Divider().background(VigiaTheme.border)

            sidebarButton("Ao Vivo", icon: "video.fill", tag: "cameras")
            sidebarButton("Dashboard", icon: "chart.bar.fill", tag: "dashboard")
            sidebarButton("Eventos", icon: "bolt.fill", tag: "events")
            sidebarButton("Configurações", icon: "gearshape.fill", tag: "config")

            Spacer()

            Divider().background(VigiaTheme.border)

            if let user = rbac.usuarioAtual {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill").font(.system(size: 16)).foregroundColor(VigiaTheme.accent)
                    Text(user.usuario).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    Button(action: { rbac.logout() }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12)).foregroundColor(VigiaTheme.danger)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
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
        case "cameras": CameraListView(storage: storage)
        case "dashboard": DashboardView(storage: storage, eventService: eventService, rbac: rbac)
        case "events": EventListView(eventService: eventService)
        case "config": ConfigView(storage: storage, rbac: rbac)
        default: CameraListView(storage: storage)
        }
    }

    private func updateTime() {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; currentTime = f.string(from: Date())
    }
}
