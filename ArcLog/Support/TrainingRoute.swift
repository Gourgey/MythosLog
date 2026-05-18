import Foundation

enum TrainingRoute: String, CaseIterable, Identifiable, Codable, Sendable {
    case dashboard
    case weeklyReview
    case more
    case goals

    var id: String { rawValue }
}

enum TrainingRouteLink {
    static let scheme = "trainingarc"

    static func url(for route: TrainingRoute) -> URL {
        URL(string: "\(scheme)://\(route.rawValue)")!
    }
}

struct PendingSkillDestination: Codable, Equatable, Hashable, Identifiable, Sendable {
    var statKeyRaw: String
    var openLogSheet: Bool

    var id: String { "\(statKeyRaw)-\(openLogSheet)" }
}

enum DashboardNavigationDestination: Hashable, Sendable {
    case skillDetail(PendingSkillDestination)
}

struct PendingAppDestination: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case route
        case skillDetail
    }

    var kind: Kind
    var route: TrainingRoute
    var skill: PendingSkillDestination?

    init(route: TrainingRoute) {
        self.kind = .route
        self.route = route
        self.skill = nil
    }

    init(skillDetail skill: PendingSkillDestination) {
        self.kind = .skillDetail
        self.route = .dashboard
        self.skill = skill
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = try container.decode(TrainingRoute.self, forKey: .route)
        skill = try container.decodeIfPresent(PendingSkillDestination.self, forKey: .skill)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? (skill == nil ? .route : .skillDetail)
    }
}

enum PendingDestinationStore {
    static let didQueueNotification = Notification.Name("PendingDestinationStore.didQueue")

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
    }

    private static var inProcessDestination: PendingAppDestination?

    static func queue(_ destination: PendingAppDestination) {
        inProcessDestination = destination
        guard let data = try? JSONEncoder().encode(destination) else { return }
        defaults.set(data, forKey: AppIdentity.pendingDestinationKey)
        NotificationCenter.default.post(name: didQueueNotification, object: nil)
    }

    static func consume() -> PendingAppDestination? {
        if let inProcessDestination {
            self.inProcessDestination = nil
            defaults.removeObject(forKey: AppIdentity.pendingDestinationKey)
            return inProcessDestination
        }

        guard let data = defaults.data(forKey: AppIdentity.pendingDestinationKey) else { return nil }
        defaults.removeObject(forKey: AppIdentity.pendingDestinationKey)
        return try? JSONDecoder().decode(PendingAppDestination.self, from: data)
    }
}
