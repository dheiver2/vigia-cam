#if canImport(UIKit)
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
            }
        }
    }
}
#endif
