import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        AppRootView()
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
