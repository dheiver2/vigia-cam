import SwiftUI

@main
struct VigiaCamApp: App {
    @StateObject private var storage = StorageService.shared
    @StateObject private var eventService = EventService()

    var body: some Scene {
        WindowGroup {
            ContentView(storage: storage, eventService: eventService)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
