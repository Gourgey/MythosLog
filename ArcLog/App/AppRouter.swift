import Foundation
import Combine
import SwiftUI

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedRoute: TrainingRoute = .dashboard
    @Published var rootPath: [DashboardNavigationDestination] = []

    func open(_ route: TrainingRoute) {
        selectedRoute = route
        rootPath = []
    }

    func open(_ destination: PendingAppDestination) {
        switch destination.kind {
        case .route:
            open(destination.route)
        case .skillDetail:
            guard let skill = destination.skill else {
                open(destination.route)
                return
            }

            selectedRoute = .dashboard
            rootPath = [.skillDetail(skill)]
        }
    }
}
