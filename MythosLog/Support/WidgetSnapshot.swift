import Foundation

struct TrainingWidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var appName: String
    var momentumTitle: String
    var momentumSubtitle: String
    var characterSummary: String
    var motivationTitle: String
    var motivationMessage: String
    var motivationColorToken: String
    var pendingWeeklyReview: Bool
    var weakestStat: TrainingWidgetStat?
    var stats: [TrainingWidgetStat]
    var todayHabits: [TrainingWidgetHabit]
    var trainTodayHeadline: String?
    var trainTodayDetail: String?
    var trainTodayColorToken: String?
    var activeGoalCount: Int
    var goalsAtRiskCount: Int
    var topGoalAtRiskTitle: String?
    var topGoalAtRiskDetail: String?

    enum CodingKeys: String, CodingKey {
        case generatedAt, appName, momentumTitle, momentumSubtitle, characterSummary,
             motivationTitle, motivationMessage, motivationColorToken, pendingWeeklyReview,
             weakestStat, stats, todayHabits,
             trainTodayHeadline, trainTodayDetail, trainTodayColorToken,
             activeGoalCount, goalsAtRiskCount,
             topGoalAtRiskTitle, topGoalAtRiskDetail
    }

    init(
        generatedAt: Date,
        appName: String,
        momentumTitle: String,
        momentumSubtitle: String,
        characterSummary: String,
        motivationTitle: String,
        motivationMessage: String,
        motivationColorToken: String,
        pendingWeeklyReview: Bool,
        weakestStat: TrainingWidgetStat?,
        stats: [TrainingWidgetStat],
        todayHabits: [TrainingWidgetHabit],
        trainTodayHeadline: String? = nil,
        trainTodayDetail: String? = nil,
        trainTodayColorToken: String? = nil,
        activeGoalCount: Int = 0,
        goalsAtRiskCount: Int = 0,
        topGoalAtRiskTitle: String? = nil,
        topGoalAtRiskDetail: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.appName = appName
        self.momentumTitle = momentumTitle
        self.momentumSubtitle = momentumSubtitle
        self.characterSummary = characterSummary
        self.motivationTitle = motivationTitle
        self.motivationMessage = motivationMessage
        self.motivationColorToken = motivationColorToken
        self.pendingWeeklyReview = pendingWeeklyReview
        self.weakestStat = weakestStat
        self.stats = stats
        self.todayHabits = todayHabits
        self.trainTodayHeadline = trainTodayHeadline
        self.trainTodayDetail = trainTodayDetail
        self.trainTodayColorToken = trainTodayColorToken
        self.activeGoalCount = activeGoalCount
        self.goalsAtRiskCount = goalsAtRiskCount
        self.topGoalAtRiskTitle = topGoalAtRiskTitle
        self.topGoalAtRiskDetail = topGoalAtRiskDetail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        appName = try c.decode(String.self, forKey: .appName)
        momentumTitle = try c.decode(String.self, forKey: .momentumTitle)
        momentumSubtitle = try c.decode(String.self, forKey: .momentumSubtitle)
        characterSummary = try c.decode(String.self, forKey: .characterSummary)
        motivationTitle = try c.decode(String.self, forKey: .motivationTitle)
        motivationMessage = try c.decode(String.self, forKey: .motivationMessage)
        motivationColorToken = try c.decode(String.self, forKey: .motivationColorToken)
        pendingWeeklyReview = try c.decode(Bool.self, forKey: .pendingWeeklyReview)
        weakestStat = try c.decodeIfPresent(TrainingWidgetStat.self, forKey: .weakestStat)
        stats = try c.decode([TrainingWidgetStat].self, forKey: .stats)
        todayHabits = try c.decode([TrainingWidgetHabit].self, forKey: .todayHabits)
        trainTodayHeadline = try c.decodeIfPresent(String.self, forKey: .trainTodayHeadline)
        trainTodayDetail = try c.decodeIfPresent(String.self, forKey: .trainTodayDetail)
        trainTodayColorToken = try c.decodeIfPresent(String.self, forKey: .trainTodayColorToken)
        activeGoalCount = try c.decodeIfPresent(Int.self, forKey: .activeGoalCount) ?? 0
        goalsAtRiskCount = try c.decodeIfPresent(Int.self, forKey: .goalsAtRiskCount) ?? 0
        topGoalAtRiskTitle = try c.decodeIfPresent(String.self, forKey: .topGoalAtRiskTitle)
        topGoalAtRiskDetail = try c.decodeIfPresent(String.self, forKey: .topGoalAtRiskDetail)
    }

    static let empty = TrainingWidgetSnapshot(
        generatedAt: .now,
        appName: AppIdentity.displayName,
        momentumTitle: "No data yet",
        momentumSubtitle: "Complete onboarding to begin training.",
        characterSummary: "Build the first version of yourself.",
        motivationTitle: "Start your training",
        motivationMessage: "Log your first session to build momentum.",
        motivationColorToken: "focus",
        pendingWeeklyReview: false,
        weakestStat: nil,
        stats: [],
        todayHabits: [],
        trainTodayHeadline: nil,
        trainTodayDetail: nil,
        trainTodayColorToken: nil,
        activeGoalCount: 0,
        goalsAtRiskCount: 0,
        topGoalAtRiskTitle: nil,
        topGoalAtRiskDetail: nil
    )
}

struct TrainingWidgetStat: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var descriptor: String
    var level: Int
    var baseline: Int
    var storedCharges: Int
    var weekActual: Double
    var progressToNextLevel: Double
    var colorToken: String
}

struct TrainingWidgetHabit: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var unitLabel: String
    var todayValue: Double
    var targetPerPeriod: Double
    var measurementTypeRaw: String
}

enum WidgetSnapshotStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppIdentity.appGroupIdentifier)
    }

    static func snapshotURL() -> URL? {
        let fm = FileManager.default
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroupIdentifier) {
            return container.appendingPathComponent(AppIdentity.widgetSnapshotFileName)
        }

        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return support?.appendingPathComponent(AppIdentity.widgetSnapshotFileName)
    }

    static func load() -> TrainingWidgetSnapshot {
        let decoder = JSONDecoder()

        if
            let url = snapshotURL(),
            let data = try? Data(contentsOf: url),
            let snapshot = try? decoder.decode(TrainingWidgetSnapshot.self, from: data)
        {
            return snapshot
        }

        if
            let data = defaults?.data(forKey: AppIdentity.widgetSnapshotDefaultsKey),
            let snapshot = try? decoder.decode(TrainingWidgetSnapshot.self, from: data)
        {
            return snapshot
        }

        return .empty
    }

    static func save(_ snapshot: TrainingWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: AppIdentity.widgetSnapshotDefaultsKey)

        guard let url = snapshotURL() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
