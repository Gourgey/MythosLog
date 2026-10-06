import Foundation
import SwiftData

// CloudKit reconciliation: dedupes records that synced from other devices and
// runs one-time data migrations. Keeper selection prefers newest updatedAt.

extension TrainingStore {
    /// Save the local copy before deleting the legacy cloud row. A crash or a
    /// failed second save is safe to retry, and a more recent local assignment
    /// always wins over a legacy record imported from another device.
    @discardableResult
    static func moveLegacyHealthImportsToLocalStore(context: ModelContext) throws -> Bool {
        let legacy = try context.fetch(FetchDescriptor<HealthImportedWorkout>())
        guard !legacy.isEmpty else { return false }
        var existing = Set(try fetchImportedHealthWorkouts(context: context).map(\.workoutUUID))
        for record in legacy where existing.insert(record.workoutUUID).inserted {
            context.insert(LocalHealthImportedWorkout(legacy: record))
        }
        try context.save()
        for record in legacy { context.delete(record) }
        try context.save()
        return true
    }

    /// The interim build already created a local store using the legacy entity
    /// name. Read that store without writing to it; keep it as a recovery copy.
    static func importPreviousLocalHealthStore(beside storeURL: URL, context: ModelContext) throws {
        let directory = storeURL.deletingLastPathComponent()
        let sourceURL = directory.appendingPathComponent("\(AppIdentity.internalProjectName)-LocalOnly.store")
        let markerURL = directory.appendingPathComponent("health-local-v2-imported")
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              !FileManager.default.fileExists(atPath: markerURL.path) else { return }
        // SwiftData may update store metadata even with an unchanged entity.
        // Open a complete scratch copy so those writes cannot touch the source.
        let scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyHealthRead-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }
        let scratchURL = scratchDirectory.appendingPathComponent("Health.store")
        try copyPersistentStore(from: sourceURL, to: scratchURL)
        let records: [LocalHealthImportedWorkout] = try autoreleasepool {
            let legacySchema = Schema([HealthImportedWorkout.self])
            let source = try ModelContainer(for: legacySchema, configurations: [
                ModelConfiguration("LocalOnly", schema: legacySchema, url: scratchURL, cloudKitDatabase: .none)
            ])
            let sourceContext = ModelContext(source)
            sourceContext.autosaveEnabled = false
            return try sourceContext.fetch(FetchDescriptor<HealthImportedWorkout>()).map(LocalHealthImportedWorkout.init(legacy:))
        }
        var existing = Set(try fetchImportedHealthWorkouts(context: context).map(\.workoutUUID))
        for record in records {
            if existing.insert(record.workoutUUID).inserted {
                context.insert(record)
            }
        }
        try context.save()
        // Commit the marker only after the destination save. If interrupted,
        // the UUID check makes the next attempt idempotent.
        try Data("Copied successfully; original retained.\n".utf8).write(to: markerURL, options: .atomic)
    }

    @discardableResult
    static func reconcileSyncedData(context: ModelContext) throws -> Bool {
        var didMutate = try moveLegacyHealthImportsToLocalStore(context: context)
        didMutate = try reconcileSettings(context: context) || didMutate
        didMutate = try reconcileStats(context: context) || didMutate
        didMutate = try reconcileHabits(context: context) || didMutate
        didMutate = try reconcileLogs(context: context) || didMutate
        didMutate = try reconcileHealthImports(context: context) || didMutate
        didMutate = try reconcileWeeklyResolutions(context: context) || didMutate
        didMutate = try reconcileGoals(context: context) || didMutate
        didMutate = try migrateSkillActivation(context: context) || didMutate
        #if canImport(HealthKit)
        didMutate = try HealthImportService.purgeDeprecatedAutoMappings(context: context) || didMutate
        #endif

        if didMutate || context.hasChanges {
            try context.save()
            recordLocalWrite(reason: "reconciled synced duplicate records")
        }

        return didMutate
    }

    /// CloudKit dedupe keeper policy: newest updatedAt wins; ties fall back
    /// to newest createdAt.
    private static func newestRecord<T>(
        of items: [T],
        updatedAt: (T) -> Date,
        createdAt: (T) -> Date
    ) -> T? {
        items.max {
            if updatedAt($0) == updatedAt($1) {
                return createdAt($0) < createdAt($1)
            }
            return updatedAt($0) < updatedAt($1)
        }
    }

    private static func reconcileSettings(context: ModelContext) throws -> Bool {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        guard settings.count > 1 else { return false }

        let keeper = newestRecord(of: settings, updatedAt: \.updatedAt, createdAt: \.createdAt)

        guard let keeper else { return false }

        for duplicate in settings where duplicate !== keeper {
            context.delete(duplicate)
        }

        return true
    }

    /// One record per logical skill while CloudKit imports are still arriving.
    /// Use the same winner for display and persistent reconciliation.
    static func canonicalStats(_ stats: [StatDomain]) -> [StatDomain] {
        Dictionary(grouping: stats, by: \.key).values.compactMap { records in
            records.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.key < rhs.key
        }
    }

    private static func reconcileStats(context: ModelContext) throws -> Bool {
        var didMutate = false
        let groupedStats = Dictionary(grouping: try fetchStats(context: context), by: \.key)

        for stats in groupedStats.values where stats.count > 1 {
            let keeper = canonicalStats(stats).first

            guard let keeper else { continue }

            for duplicate in stats where duplicate !== keeper {
                for habit in duplicate.habits ?? [] {
                    habit.statDomain = keeper
                }
                for resolution in duplicate.weeklyResolutions ?? [] {
                    resolution.statDomain = keeper
                    resolution.statKey = keeper.key
                    resolution.statName = keeper.name
                }
                context.delete(duplicate)
                didMutate = true
            }
        }

        return didMutate
    }

    private static let skillActivationMigratedKey = "training.arc.skillActivationMigrated.v1"

    /// Backfills the skill-activation flags on existing rows and, on first run,
    /// archives optional skills (Reading, Curiosity) that have no logged history.
    /// Idempotent: the flag backfill always re-derives from the catalog; the
    /// one-time auto-archive is guarded so a user who re-enables an empty optional
    /// skill is never re-archived.
    @discardableResult
    private static func migrateSkillActivation(context: ModelContext) throws -> Bool {
        let stats = try fetchStats(context: context)
        guard !stats.isEmpty else { return false }

        let defaults = UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
        let firstRun = !defaults.bool(forKey: skillActivationMigratedKey)
        var didMutate = false

        for stat in stats {
            guard let key = stat.statKey else { continue }
            let core = TrainingArcConfig.isCoreSkill(key)
            var changed = false

            if stat.isCore != core {
                stat.isCore = core
                changed = true
            }

            let parentRaw = TrainingArcConfig.parentSkillKey(for: key)?.rawValue
            if stat.parentSkillKeyRaw != parentRaw {
                stat.parentSkillKeyRaw = parentRaw
                changed = true
            }

            if core {
                // Core skills are always part of the active set.
                if !stat.isEnabled {
                    stat.isEnabled = true
                    changed = true
                }
            } else if firstRun {
                let hasLogs = (stat.habits ?? []).contains { !($0.logs ?? []).isEmpty }
                if hasLogs {
                    // Keep optional skills the user already trains.
                    if !stat.isEnabled {
                        stat.isEnabled = true
                        changed = true
                    }
                } else if stat.isEnabled || !stat.isArchived {
                    // Optional skill with no history → archive it by default.
                    stat.isEnabled = false
                    stat.isArchived = true
                    changed = true
                }
            }

            if changed {
                stat.updatedAt = .now
                didMutate = true
            }
        }

        if firstRun {
            defaults.set(true, forKey: skillActivationMigratedKey)
        }

        return didMutate
    }

    private static func reconcileHabits(context: ModelContext) throws -> Bool {
        var didMutate = false

        for habits in Dictionary(grouping: try fetchHabits(context: context), by: \.id).values where habits.count > 1 {
            didMutate = mergeDuplicateHabits(habits, context: context) || didMutate
        }

        let systemHabits = try fetchHabits(context: context).filter { $0.systemKey != nil }
        for habits in Dictionary(grouping: systemHabits, by: { $0.systemKey ?? "" }).values where habits.count > 1 {
            didMutate = mergeDuplicateHabits(habits, context: context) || didMutate
        }

        return didMutate
    }

    private static func mergeDuplicateHabits(_ habits: [Habit], context: ModelContext) -> Bool {
        guard habits.count > 1 else { return false }

        let keeper = newestRecord(of: habits, updatedAt: \.updatedAt, createdAt: \.createdAt)

        guard let keeper else { return false }

        for duplicate in habits where duplicate !== keeper {
            for log in duplicate.logs ?? [] {
                log.habit = keeper
            }
            if keeper.statDomain == nil {
                keeper.statDomain = duplicate.statDomain
            }
            context.delete(duplicate)
        }

        return true
    }

    private static func reconcileLogs(context: ModelContext) throws -> Bool {
        var didMutate = false

        for logs in Dictionary(grouping: try fetchLogs(context: context), by: \.id).values where logs.count > 1 {
            let keeper = logs.max {
                if $0.createdAt == $1.createdAt {
                    return $0.date < $1.date
                }
                return $0.createdAt < $1.createdAt
            }

            guard let keeper else { continue }

            for duplicate in logs where duplicate !== keeper {
                if keeper.habit == nil {
                    keeper.habit = duplicate.habit
                }
                context.delete(duplicate)
                didMutate = true
            }
        }

        // Two devices can import the same Health workout before either sees
        // the other's log. Keep the earliest; the id tiebreak makes every
        // device pick the same keeper.
        let healthLogs = try fetchLogs(context: context).filter { $0.sourceType == .health && $0.healthWorkoutUUID != nil }
        for logs in Dictionary(grouping: healthLogs, by: { $0.healthWorkoutUUID ?? "" }).values where logs.count > 1 {
            let keeper = logs.min {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }

            guard let keeper else { continue }

            for duplicate in logs where duplicate !== keeper {
                context.delete(duplicate)
                didMutate = true
            }
        }

        return didMutate
    }

    private static func reconcileHealthImports(context: ModelContext) throws -> Bool {
        var didMutate = false

        for records in Dictionary(grouping: try fetchImportedHealthWorkouts(context: context), by: \.workoutUUID).values where records.count > 1 {
            let keeper = records.max {
                let lhs = healthImportSortKey($0)
                let rhs = healthImportSortKey($1)
                if lhs.priority == rhs.priority {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.priority < rhs.priority
            }

            guard let keeper else { continue }

            for duplicate in records where duplicate !== keeper {
                removeDuplicateHealthLog(for: duplicate, keeping: keeper, context: context)
                context.delete(duplicate)
                didMutate = true
            }
        }

        didMutate = try applyRemoteHealthDecisions(context: context) || didMutate

        let records = try fetchImportedHealthWorkouts(context: context)
        didMutate = try applyPriorHealthImportAssignments(records: records, context: context) || didMutate

        return didMutate
    }

    /// Settles local workouts still awaiting a habit when another device has
    /// since logged or dismissed them (visible here through synced tables).
    private static func applyRemoteHealthDecisions(context: ModelContext) throws -> Bool {
        var didMutate = false

        let dismissals = try context.fetch(FetchDescriptor<DismissedHealthWorkout>())
        for duplicates in Dictionary(grouping: dismissals, by: \.workoutUUID).values where duplicates.count > 1 {
            for duplicate in duplicates.dropFirst() {
                context.delete(duplicate)
                didMutate = true
            }
        }

        let pending = try fetchImportedHealthWorkouts(context: context).filter(\.awaitingHabitAssignment)
        guard !pending.isEmpty else { return didMutate }

        let healthLogsByWorkoutID = try fetchHealthLogsByWorkoutID(context: context)
        let dismissedWorkoutIDs = Set(dismissals.map(\.workoutUUID))
        for record in pending {
            if let log = healthLogsByWorkoutID[record.workoutUUID] {
                record.habitSystemKey = log.habit?.systemKey
                record.wasImported = true
                record.awaitingHabitAssignment = false
                didMutate = true
            } else if dismissedWorkoutIDs.contains(record.workoutUUID) {
                record.habitSystemKey = nil
                record.wasImported = false
                record.awaitingHabitAssignment = false
                didMutate = true
            }
        }

        return didMutate
    }

    private static func applyPriorHealthImportAssignments(records: [LocalHealthImportedWorkout], context: ModelContext) throws -> Bool {
        let priorHabitKeyByWorkoutTitle = priorHealthImportAssignments(from: records)
        guard !priorHabitKeyByWorkoutTitle.isEmpty else { return false }

        var habitsBySystemKey: [String: Habit] = [:]
        for habit in try fetchActiveHabits(context: context) {
            guard let key = habit.systemKey, habitsBySystemKey[key] == nil else { continue }
            habitsBySystemKey[key] = habit
        }

        var didMutate = false
        for record in records where record.awaitingHabitAssignment && !record.isDuplicate {
            let titleKey = healthImportAssignmentKey(statKeyRaw: record.statKeyRaw, activityTypeRaw: record.activityTypeRaw)
            guard
                let habitKey = priorHabitKeyByWorkoutTitle[titleKey],
                let habit = habitsBySystemKey[habitKey]
            else {
                continue
            }

            let note = "Imported from Apple Health\(record.sourceName.map { " via \($0)" } ?? "")"
            guard (try? log(
                habit: habit,
                value: loggedValue(for: record, habit: habit),
                date: record.endDate,
                sessionType: record.sourceName ?? "Apple Health",
                note: note,
                source: .health,
                healthWorkoutUUID: record.workoutUUID,
                refreshProgressAfterSave: false,
                context: context
            )) != nil else {
                continue
            }

            record.habitSystemKey = habit.systemKey
            record.wasImported = true
            record.awaitingHabitAssignment = false
            didMutate = true
        }

        if didMutate {
            try refreshAllProgress(context: context, reason: .logMutation)
        }

        return didMutate
    }

    static func priorHealthImportAssignments(from records: [LocalHealthImportedWorkout]) -> [String: String] {
        var assignments: [String: (habitKey: String, decidedAt: Date)] = [:]

        for record in records where record.wasImported && !record.isDuplicate && !record.awaitingHabitAssignment {
            guard let habitKey = record.habitSystemKey, !habitKey.isEmpty else { continue }

            let titleKey = healthImportAssignmentKey(statKeyRaw: record.statKeyRaw, activityTypeRaw: record.activityTypeRaw)
            let decidedAt = max(record.createdAt, record.endDate)
            if let current = assignments[titleKey], current.decidedAt >= decidedAt {
                continue
            }

            assignments[titleKey] = (habitKey, decidedAt)
        }

        return assignments.mapValues { $0.habitKey }
    }

    static func healthImportAssignmentKey(statKeyRaw: String, activityTypeRaw: Int) -> String {
        "\(statKeyRaw)|\(activityTypeRaw)"
    }

    private static func loggedValue(for record: LocalHealthImportedWorkout, habit: Habit) -> Double {
        loggedValue(durationMinutes: record.durationMinutes, habit: habit)
    }

    private static func healthImportSortKey(_ record: LocalHealthImportedWorkout) -> (priority: Int, createdAt: Date) {
        let priority: Int
        if record.wasImported && !record.isDuplicate {
            priority = 2
        } else if record.wasImported {
            priority = 1
        } else {
            priority = 0
        }
        return (priority, record.createdAt)
    }

    private static func removeDuplicateHealthLog(for duplicate: LocalHealthImportedWorkout, keeping keeper: LocalHealthImportedWorkout, context: ModelContext) {
        guard duplicate.wasImported, duplicate !== keeper else { return }
        guard let habitSystemKey = duplicate.habitSystemKey else { return }

        let matchingLogs = ((try? fetchLogs(context: context)) ?? [])
            .filter { log in
                log.sourceType == .health &&
                log.habit?.systemKey == habitSystemKey &&
                abs(log.date.timeIntervalSince(duplicate.endDate)) < 120
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.date > rhs.date
                }
                return lhs.createdAt > rhs.createdAt
            }

        if matchingLogs.count > 1, let newestDuplicateLog = matchingLogs.first {
            context.delete(newestDuplicateLog)
        }
    }

    private static func reconcileWeeklyResolutions(context: ModelContext) throws -> Bool {
        var didMutate = false
        let resolutions = try fetchResolutions(context: context)
        let grouped = Dictionary(grouping: resolutions) {
            "\($0.statKey)|\($0.weekStartDate.timeIntervalSinceReferenceDate)"
        }

        for resolutions in grouped.values where resolutions.count > 1 {
            let keeper = resolutions.max { $0.createdAt < $1.createdAt }
            guard let keeper else { continue }

            for duplicate in resolutions where duplicate !== keeper {
                if keeper.statDomain == nil {
                    keeper.statDomain = duplicate.statDomain
                }
                context.delete(duplicate)
                didMutate = true
            }
        }

        return didMutate
    }

    private static func reconcileGoals(context: ModelContext) throws -> Bool {
        var didMutate = false
        for goals in Dictionary(grouping: try fetchGoals(context: context), by: \.id).values where goals.count > 1 {
            let keeper = newestRecord(of: goals, updatedAt: \.updatedAt, createdAt: \.createdAt)
            guard let keeper else { continue }
            for duplicate in goals where duplicate !== keeper {
                context.delete(duplicate)
                didMutate = true
            }
        }
        return didMutate
    }
}
