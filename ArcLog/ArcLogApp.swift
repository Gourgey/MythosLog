import SwiftUI
import SwiftData

@main
struct ArcLogApp: App {
    private let sharedModelContainer = TrainingStore.sharedModelContainer
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            TrainingStore.refreshAppState()
        }
    }
}
