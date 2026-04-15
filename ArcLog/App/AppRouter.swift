import Foundation
import Combine
import SwiftUI

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedRoute: TrainingRoute = .dashboard
    @Published var rootPath = NavigationPath()

    func open(_ route: TrainingRoute) {
        selectedRoute = route
        rootPath = NavigationPath()
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
            rootPath = NavigationPath()
            DispatchQueue.main.async { [weak self] in
                self?.rootPath.append(DashboardNavigationDestination.skillDetail(skill))
            }
        }
    }
}
