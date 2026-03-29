import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedRoute: TrainingRoute = .dashboard

    func open(_ route: TrainingRoute) {
        selectedRoute = route
    }
}
