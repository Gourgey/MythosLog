import Foundation
import SwiftData

// CloudKit reconciliation: dedupes records that synced from other devices and
// runs one-time data migrations. Keeper selection prefers newest updatedAt.

extension TrainingStore {
    @discardableResult
    static func reconcileSyncedData(context: ModelContext) throws -> Bool {
        var didMutate = false
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

    private static func reconcileSettings(context: ModelContext) throws -> Bool {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        guard settings.count > 1 else { return false }

        let keeper = settings.max {
            if $0.updatedAt == $1.updatedAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.updatedAt < $1.updatedAt
        }

        guard let keeper else { return false }

        for duplicate in settings where duplicate !== keeper {
            context.delete(duplicate)
        }

        return true
    }

    private static func reconcileStats(context: ModelContext) throws -> Bool {
        var didMutate = false
        let groupedStats = Dictionary(grouping: try fetchStats(context: context), by: \.key)

        for stats in groupedStats.values where stats.count > 1 {
            let keeper = stats.max {
                if $0.updatedAt == $1.updatedAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.updatedAt < $1.updatedAt
            }

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

        let keeper = habits.max {
            if $0.updatedAt == $1.updatedAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.updatedAt < $1.updatedAt
        }

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

        let records = try fetchImportedHealthWorkouts(context: context)
        didMutate = try applyPriorHealthImportAssignments(records: records, context: context) || didMutate

        return didMutate
    }

    private static func applyPriorHealthImportAssignments(records: [HealthImportedWorkout], context: ModelContext) throws -> Bool {
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
                context: context
            )) != nil else {
                continue
            }

            record.habitSystemKey = habit.systemKey
            record.wasImported = true
            record.awaitingHabitAssignment = false
            didMutate = true
        }

        return didMutate
    }

    static func priorHealthImportAssignments(from records: [HealthImportedWorkout]) -> [String: String] {
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

    private static func loggedValue(for record: HealthImportedWorkout, habit: Habit) -> Double {
        switch habit.measurementType {
        case .booleanSession: return 1
        case .minutes: return max(1, record.durationMinutes.rounded())
        case .count, .customNumber, .pages: return 1
        }
    }

    private static func healthImportSortKey(_ record: HealthImportedWorkout) -> (priority: Int, createdAt: Date) {
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

    private static func removeDuplicateHealthLog(for duplicate: HealthImportedWorkout, keeping keeper: HealthImportedWorkout, context: ModelContext) {
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
            let keeper = goals.max {
                if $0.updatedAt == $1.updatedAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.updatedAt < $1.updatedAt
            }
            guard let keeper else { continue }
            for duplicate in goals where duplicate !== keeper {
                context.delete(duplicate)
                didMutate = true
            }
        }
        return didMutate
    }
}
