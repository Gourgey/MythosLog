import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        if let error = TrainingStore.persistentStoreError {
            ContentUnavailableView {
                Label("Saved data couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("Your database has been kept. Logging and syncing are paused to protect it. Close and reopen the app to retry.")
            } actions: {
                ShareLink("Share error details", item: error)
            }
        } else {
            AppRootView()
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(TrainingStore.makeModelContainer(inMemory: true))
    }
}
#endif
