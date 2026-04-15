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
        todayHabits: []
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
