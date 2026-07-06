import SwiftUI

/// Navegação principal com tabs — equivalente à Janela do Python.
struct ContentView: View {
    @ObservedObject var storage: StorageService
    @ObservedObject var rbac: RBACService
    @ObservedObject var eventService: EventService
    @State private var selectedTab = 0
    @State private var currentTime = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Tab content
            TabView(selection: $selectedTab) {
                CameraListView(storage: storage)
                    .tag(0)
                    .tabItem {
                        Label("Ao Vivo", systemImage: "video.fill")
                    }

                DashboardView(storage: storage, eventService: eventService)
                    .tag(1)
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }

                EventListView(eventService: eventService)
                    .tag(2)
                    .tabItem {
                        Label("Eventos", systemImage: "bolt.fill")
                    }

                ConfigView(storage: storage, rbac: rbac)
                    .tag(3)
                    .tabItem {
                        Label("Config", systemImage: "gearshape.fill")
                    }
            }
            .tint(VigiaTheme.accent)
        }
        .background(VigiaTheme.bg)
        .onReceive(timer) { _ in
            updateTime()
        }
        .onAppear {
            updateTime()
            configurarTabBar()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("VIGIA")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(".")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(VigiaTheme.accent)
                }
                Text("MONITORAMENTO INTELIGENTE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(VigiaTheme.muted)
                    .tracking(1.5)
            }

            Spacer()

            // Clock
            Text(currentTime)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(VigiaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(VigiaTheme.border, lineWidth: 1)
                )

            // User badge
            if let user = rbac.usuarioAtual {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 14))
                    Text(user.usuario)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(VigiaTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(VigiaTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(VigiaTheme.border, lineWidth: 1)
                )
            }

            // Logout
            Button(action: { rbac.logout() }) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14))
                    .foregroundColor(VigiaTheme.danger)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(VigiaTheme.headerGradient)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VigiaTheme.border)
                .frame(height: 1)
        }
    }

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        currentTime = formatter.string(from: Date())
    }

    private func configurarTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(VigiaTheme.panel)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(VigiaTheme.muted),
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(VigiaTheme.accent),
            .font: UIFont.systemFont(ofSize: 10, weight: .bold)
        ]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
