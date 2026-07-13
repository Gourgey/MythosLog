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

@MainActor
enum PendingDestinationStore {
    nonisolated static let didQueueNotification = Notification.Name("PendingDestinationStore.didQueue")
    nonisolated static let didQueueGoalNotification = Notification.Name("PendingDestinationStore.didQueueGoal")
    nonisolated static let didQueueNewGoalNotification = Notification.Name("PendingDestinationStore.didQueueNewGoal")

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
    }

    // Cross-process handoff (widget/quick-action -> app) rides UserDefaults;
    // the in-process cache lets the same-process producer/consumer skip a
    // round-trip. Both are main-actor state, so isolate the whole store.
    private static var inProcessDestination: PendingAppDestination?
    private static var inProcessGoalID: UUID?
    private static var inProcessNewGoalStatKey: String?

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

    static func queueGoal(_ goalID: UUID) {
        inProcessGoalID = goalID
        NotificationCenter.default.post(name: didQueueGoalNotification, object: nil)
    }

    static func consumeGoal() -> UUID? {
        let value = inProcessGoalID
        inProcessGoalID = nil
        return value
    }

    /// Queues a request to open a *new* goal editor pre-seeded for a skill.
    static func queueNewGoal(statKeyRaw: String) {
        inProcessNewGoalStatKey = statKeyRaw
        NotificationCenter.default.post(name: didQueueNewGoalNotification, object: nil)
    }

    static func consumeNewGoal() -> String? {
        let value = inProcessNewGoalStatKey
        inProcessNewGoalStatKey = nil
        return value
    }
}
