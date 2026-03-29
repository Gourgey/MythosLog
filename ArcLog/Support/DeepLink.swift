import Foundation

struct ExternalLogEvent: Sendable {
    var habitSystemKey: String?
    var statKey: StatKey?
    var value: Double
    var note: String
    var date: Date
}

enum TrainingDeepLink {
    case route(TrainingRoute)
    case externalLog(ExternalLogEvent)
}

enum DeepLinkRouter {
    static let scheme = TrainingRouteLink.scheme

    static func url(for route: TrainingRoute) -> URL {
        TrainingRouteLink.url(for: route)
    }

    static func parse(_ url: URL) -> TrainingDeepLink? {
        guard url.scheme == scheme else { return nil }

        if let route = TrainingRoute(rawValue: url.host ?? "") {
            return .route(route)
        }

        guard url.host == "log" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let value = Double(components?.queryItems?.first(where: { $0.name == "value" })?.value ?? "1") ?? 1
        let note = components?.queryItems?.first(where: { $0.name == "note" })?.value ?? ""
        let habitSystemKey = components?.queryItems?.first(where: { $0.name == "habit" })?.value
        let statKey = components?.queryItems?.first(where: { $0.name == "stat" })?.value.flatMap(StatKey.init(rawValue:))
        let dateString = components?.queryItems?.first(where: { $0.name == "date" })?.value
        let date = dateString.flatMap(ISO8601DateFormatter().date(from:)) ?? .now

        return .externalLog(
            ExternalLogEvent(
                habitSystemKey: habitSystemKey,
                statKey: statKey,
                value: value,
                note: note,
                date: date
            )
        )
    }
}
