import SwiftUI

@main
struct VigiaCamApp: App {
    @StateObject private var storage = StorageService.shared
    @StateObject private var rbac = RBACService()
    @StateObject private var eventService = EventService()
    @State private var isLoggedIn = false

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                ContentView(storage: storage, rbac: rbac, eventService: eventService)
                    .preferredColorScheme(.dark)
            } else {
                LoginView(rbac: rbac, isLoggedIn: $isLoggedIn)
                    .preferredColorScheme(.dark)
                    .frame(width: 420, height: 560)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
