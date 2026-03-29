import Foundation

struct TrainingWidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var appName: String
    var momentumTitle: String
    var momentumSubtitle: String
    var characterSummary: String
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
    static func snapshotURL() -> URL? {
        let fm = FileManager.default
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroupIdentifier) {
            return container.appendingPathComponent(AppIdentity.widgetSnapshotFileName)
        }

        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return support?.appendingPathComponent(AppIdentity.widgetSnapshotFileName)
    }

    static func load() -> TrainingWidgetSnapshot {
        guard
            let url = snapshotURL(),
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(TrainingWidgetSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: TrainingWidgetSnapshot) {
        guard let url = snapshotURL() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
