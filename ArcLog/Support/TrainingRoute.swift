import Foundation

enum TrainingRoute: String, CaseIterable, Identifiable {
    case dashboard
    case weeklyReview
    case more

    var id: String { rawValue }
}

enum TrainingRouteLink {
    static let scheme = "trainingarc"

    static func url(for route: TrainingRoute) -> URL {
        URL(string: "\(scheme)://\(route.rawValue)")!
    }
}
