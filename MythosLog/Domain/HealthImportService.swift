import Foundation
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

// Apple Health workout import: authorization, observer-driven sync, the
// supported workout-type catalog, and duplicate/overlap detection.

#if canImport(HealthKit)
enum HealthAuthorizationState: Sendable {
    case unavailable
    case notConnected
    case connected

    var title: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .notConnected:
            return "Not Connected"
        case .connected:
            return "Connected"
        }
    }
}

struct HealthSyncSummary: Sendable {
    var importedCount: Int
    var duplicateCount: Int
    var overlapCount: Int
    var ignoredCount: Int
    var syncedAt: Date

    var message: String {
        var parts: [String] = []

        if importedCount > 0 {
            parts.append("Imported \(importedCount) workout\(importedCount == 1 ? "" : "s") from Apple Health.")
        }

        if duplicateCount > 0 {
            parts.append("Skipped \(duplicateCount) duplicate workout\(duplicateCount == 1 ? "" : "s").")
        }

        if overlapCount > 0 {
            parts.append("Flagged \(overlapCount) overlapping workout\(overlapCount == 1 ? "" : "s") on Review.")
        }

        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }

        return ignoredCount > 0 ? "No new eligible Apple Health workouts were found." : "Apple Health is up to date. No new workouts were imported."
    }
}

struct SupportedWorkoutType: Identifiable, Sendable {
    enum Category: String, Sendable, CaseIterable {
        case strength
        case cardio
        case sport
        case mindBody

        var title: String {
            switch self {
            case .strength: "Strength"
            case .cardio: "Cardio"
            case .sport: "Sports"
            case .mindBody: "Mind & Body"
            }
        }
    }

    let activityType: HKWorkoutActivityType
    let displayName: String
    let category: Category
    let statKey: StatKey
    let sessionType: String

    var id: UInt { activityType.rawValue }
    var key: String { String(activityType.rawValue) }

    static let all: [SupportedWorkoutType] = [
        SupportedWorkoutType(activityType: .traditionalStrengthTraining, displayName: "Strength Training", category: .strength, statKey: .strength, sessionType: "Strength"),
        SupportedWorkoutType(activityType: .functionalStrengthTraining, displayName: "Functional Strength", category: .strength, statKey: .strength, sessionType: "Strength"),
        SupportedWorkoutType(activityType: .coreTraining, displayName: "Core Training", category: .strength, statKey: .strength, sessionType: "Strength"),

        SupportedWorkoutType(activityType: .running, displayName: "Running", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .walking, displayName: "Walking", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .cycling, displayName: "Cycling", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .swimming, displayName: "Swimming", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .rowing, displayName: "Rowing", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .elliptical, displayName: "Elliptical", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .stairClimbing, displayName: "Stair Climbing", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .hiking, displayName: "Hiking", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .mixedCardio, displayName: "Mixed Cardio", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .highIntensityIntervalTraining, displayName: "HIIT", category: .cardio, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .jumpRope, displayName: "Jump Rope", category: .cardio, statKey: .cardio, sessionType: "Cardio"),

        SupportedWorkoutType(activityType: .tennis, displayName: "Tennis", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .badminton, displayName: "Badminton", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .basketball, displayName: "Basketball", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .soccer, displayName: "Soccer", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .volleyball, displayName: "Volleyball", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .tableTennis, displayName: "Table Tennis", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .racquetball, displayName: "Racquetball", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .squash, displayName: "Squash", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .pickleball, displayName: "Pickleball", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .boxing, displayName: "Boxing", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .kickboxing, displayName: "Kickboxing", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .martialArts, displayName: "Martial Arts", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .climbing, displayName: "Climbing", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .surfingSports, displayName: "Surfing", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .paddleSports, displayName: "Paddle Sports", category: .sport, statKey: .cardio, sessionType: "Cardio"),
        SupportedWorkoutType(activityType: .snowSports, displayName: "Snow Sports", category: .sport, statKey: .cardio, sessionType: "Cardio"),

        SupportedWorkoutType(activityType: .yoga, displayName: "Yoga", category: .mindBody, statKey: .focus, sessionType: "Focus"),
        SupportedWorkoutType(activityType: .pilates, displayName: "Pilates", category: .mindBody, statKey: .focus, sessionType: "Focus"),
        SupportedWorkoutType(activityType: .mindAndBody, displayName: "Mind & Body", category: .mindBody, statKey: .focus, sessionType: "Focus"),
        SupportedWorkoutType(activityType: .flexibility, displayName: "Flexibility", category: .mindBody, statKey: .focus, sessionType: "Focus"),
        SupportedWorkoutType(activityType: .barre, displayName: "Barre", category: .mindBody, statKey: .focus, sessionType: "Focus")
    ]

    static func key(for activityType: HKWorkoutActivityType) -> String {
        String(activityType.rawValue)
    }

    static func mapping(for activityType: HKWorkoutActivityType) -> WorkoutMapping? {
        guard let entry = all.first(where: { $0.activityType == activityType }) else { return nil }
        return WorkoutMapping(statKey: entry.statKey, sessionType: entry.sessionType)
    }
}

struct WorkoutMapping: Sendable {
    var statKey: StatKey
    var sessionType: String
}

@MainActor
enum HealthImportService {

    private struct HealthWorkoutCandidate {
        var workout: HKWorkout
        var mapping: WorkoutMapping
        var habit: Habit?
        var value: Double
        var awaitingAssignment: Bool
    }

    private enum SyncScope {
        case anchored
        case yearBackfill
    }

    private static let healthStore = HKHealthStore()
    private static let connectedDefaultsKey = "training.arc.health.connected"
    private static let lastYearBackfillDefaultsKey = "training.arc.health.lastYearBackfillAt"
    private static var workoutObserverQuery: HKObserverQuery?

    /// Guards against overlapping `performSync` runs. Many entry points can
    /// fire at once — the app `.task`, every `scenePhase` activation, the
    /// HKObserverQuery callback, and the Settings/Dashboard "Sync now" buttons.
    /// Two concurrent runs would each read the same baseline of existing
    /// records and import the same new workouts twice. Because the whole enum
    /// is `@MainActor`, this flag is only ever read/written between `await`
    /// points on the main actor, so no lock is needed.
    private static var isSyncing = false

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
    }

    private static var workoutType: HKWorkoutType {
        HKObjectType.workoutType()
    }

    static func authorizationState() -> HealthAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        // HealthKit intentionally never reports *read* authorization (that would
        // leak whether the user has the data), so "connected" is our own record
        // that the user granted access at least once. If they later revoke it in
        // Settings this stays true and syncs simply return no samples.
        if defaults.bool(forKey: connectedDefaultsKey) {
            return .connected
        }

        return .notConnected
    }

    static func requestAuthorizationAndSync() async -> String {
        guard HKHealthStore.isHealthDataAvailable() else {
            return "Apple Health is not available on this device."
        }

        do {
            try await requestAuthorization()
            defaults.set(true, forKey: connectedDefaultsKey)
            let message = try await syncNow()
            startWorkoutObserverIfEnabled()
            return message
        } catch {
            return "Apple Health permission was not granted."
        }
    }

    static func startWorkoutObserverIfEnabled() {
        guard HKHealthStore.isHealthDataAvailable(), workoutObserverQuery == nil else { return }

        let context = ModelContext(TrainingStore.sharedModelContainer)
        guard
            let settings = try? TrainingStore.fetchSettings(context: context),
            settings.hasCompletedOnboarding,
            settings.healthAutoImportEnabled,
            authorizationState() == .connected
        else {
            return
        }

        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { _, completionHandler, error in
            if error == nil {
                Task { @MainActor in
                    await syncIfEnabled()
                }
            }

            completionHandler()
        }

        workoutObserverQuery = query
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .hourly) { _, _ in }
    }

    static func stopWorkoutObserver() {
        guard let workoutObserverQuery else { return }
        healthStore.stop(workoutObserverQuery)
        self.workoutObserverQuery = nil
        // Release the paired background wake-ups too; otherwise the system keeps
        // launching us hourly after the user has turned auto-import off.
        healthStore.disableBackgroundDelivery(for: workoutType) { _, _ in }
    }

    static func syncIfEnabled() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let context = ModelContext(TrainingStore.sharedModelContainer)
        guard
            let settings = try? TrainingStore.fetchSettings(context: context),
            settings.hasCompletedOnboarding,
            settings.healthAutoImportEnabled,
            authorizationState() == .connected
        else {
            stopWorkoutObserver()
            return
        }

        startWorkoutObserverIfEnabled()
        let scope: SyncScope = shouldRunYearBackfill() ? .yearBackfill : .anchored
        _ = try? await performSync(context: context, settings: settings, scope: scope)
    }

    static func syncNow() async throws -> String {
        guard HKHealthStore.isHealthDataAvailable() else {
            return "Apple Health is not available on this device."
        }

        let context = ModelContext(TrainingStore.sharedModelContainer)
        let settings = try TrainingStore.fetchSettings(context: context)
        guard settings.hasCompletedOnboarding else {
            return "Finish onboarding before syncing Apple Health."
        }

        guard authorizationState() == .connected else {
            return "Connect Apple Health first."
        }

        guard !isSyncing else {
            return "Apple Health sync is already in progress."
        }

        let summary = try await performSync(context: context, settings: settings, scope: .yearBackfill)
        return summary.message
    }

    private static func requestAuthorization() async throws {
        let readTypes: Set<HKObjectType> = [workoutType]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
    }

    private static func performSync(context: ModelContext, settings: AppSettings, scope: SyncScope) async throws -> HealthSyncSummary {
        // See `isSyncing`. A second overlapping call returns a no-op summary
        // rather than racing the in-flight import.
        guard !isSyncing else {
            return HealthSyncSummary(
                importedCount: 0,
                duplicateCount: 0,
                overlapCount: 0,
                ignoredCount: 0,
                syncedAt: settings.lastHealthSyncAt ?? .now
            )
        }
        isSyncing = true
        defer { isSyncing = false }

        let anchor = scope == .anchored ? loadAnchor() : nil
        let predicate: NSPredicate? = anchor == nil
            ? HKQuery.predicateForSamples(withStart: yearBackfillStartDate(), end: nil, options: .strictStartDate)
            : nil
        let (workouts, newAnchor) = try await fetchWorkouts(anchor: anchor, predicate: predicate)
        let activeStats = try TrainingStore.fetchActiveStats(context: context)

        // The self-healing normalization pass is O(n^2) over every imported
        // record. Only pay for it when the fetch actually returned new samples;
        // cross-device duplicates arrive through CloudKit and are reconciled by
        // TrainingStore.reconcileSyncedData, not here.
        let existingRecords: [HealthImportedWorkout] = workouts.isEmpty
            ? try TrainingStore.fetchImportedHealthWorkouts(context: context)
            : try normalizeExistingHealthImports(context: context)

        let priorHabitKeyByWorkoutTitle = TrainingStore.priorHealthImportAssignments(from: existingRecords)
        var existingWorkoutIDs = Set(existingRecords.map(\.workoutUUID))
        var processedRecords = existingRecords
            .filter { $0.wasImported || $0.isDuplicate }
            .sorted { $0.startDate < $1.startDate }
        var importedCount = 0
        var duplicateCount = 0
        var overlapCount = 0
        var ignoredCount = 0

        let disabledTypeKeys = settings.disabledHealthWorkoutTypeKeys
        let candidates = workouts
            .compactMap {
                candidate(
                    for: $0,
                    activeStats: activeStats,
                    disabledTypeKeys: disabledTypeKeys,
                    priorHabitKeyByWorkoutTitle: priorHabitKeyByWorkoutTitle
                )
            }
            .sorted { $0.workout.startDate < $1.workout.startDate }

        for candidate in candidates {
            let workout = candidate.workout
            let workoutID = workout.uuid.uuidString
            if existingWorkoutIDs.contains(workoutID) {
                continue
            }

            if let duplicateRecord = processedRecords.first(where: { isDuplicate(candidate, of: $0) }) {
                let record = healthRecord(
                    for: candidate,
                    wasImported: false,
                    isDuplicate: true,
                    overlapsImportedWorkout: false,
                    relatedWorkoutUUID: duplicateRecord.workoutUUID
                )
                context.insert(record)
                try context.save()
                TrainingStore.recordLocalWrite(reason: "recorded duplicate Health workout")
                processedRecords.append(record)
                existingWorkoutIDs.insert(workoutID)
                duplicateCount += 1
                continue
            }

            guard candidate.value > 0 else {
                ignoredCount += 1
                continue
            }

            let overlappingRecord = processedRecords.first(where: { overlaps(candidate, with: $0) && !isDuplicate(candidate, of: $0) })

            if candidate.awaitingAssignment {
                let record = healthRecord(
                    for: candidate,
                    wasImported: false,
                    isDuplicate: false,
                    overlapsImportedWorkout: overlappingRecord != nil,
                    relatedWorkoutUUID: overlappingRecord?.workoutUUID,
                    awaitingHabitAssignment: true
                )
                context.insert(record)
                try context.save()
                TrainingStore.recordLocalWrite(reason: "queued Health workout awaiting habit assignment")
                processedRecords.append(record)
                existingWorkoutIDs.insert(workoutID)
                continue
            }

            guard let matchedHabit = candidate.habit else {
                ignoredCount += 1
                continue
            }

            let sourceName = workout.sourceRevision.source.name
            let note = "Imported from Apple Health\(sourceName.isEmpty ? "" : " via \(sourceName)")"
            _ = try TrainingStore.log(
                habit: matchedHabit,
                value: candidate.value,
                date: workout.endDate,
                sessionType: candidate.mapping.sessionType,
                note: note,
                source: .health,
                healthWorkoutUUID: workout.uuid.uuidString,
                refreshProgressAfterSave: false,
                context: context
            )

            let record = healthRecord(
                for: candidate,
                wasImported: true,
                isDuplicate: false,
                overlapsImportedWorkout: overlappingRecord != nil,
                relatedWorkoutUUID: overlappingRecord?.workoutUUID
            )
            context.insert(record)
            try context.save()
            TrainingStore.recordLocalWrite(reason: "recorded imported Health workout")

            processedRecords.append(record)
            existingWorkoutIDs.insert(workoutID)
            importedCount += 1
            if overlappingRecord != nil {
                overlapCount += 1
            }
        }

        if importedCount > 0 {
            try TrainingStore.refreshAllProgress(context: context, reason: .logMutation)
        }

        if let newAnchor {
            saveAnchor(newAnchor)
        }

        if scope == .yearBackfill {
            defaults.set(Date(), forKey: lastYearBackfillDefaultsKey)
        }

        // Persisting the sync timestamp bumps settings.updatedAt, which is a
        // CloudKit write that itself provokes more sync traffic. Skip it on idle
        // background checks: only stamp when something changed, when the user or
        // weekly backfill explicitly requested a full sync, or hourly at most.
        let didChange = importedCount + duplicateCount + overlapCount > 0
        let stampIsStale = settings.lastHealthSyncAt.map { Date().timeIntervalSince($0) > 3600 } ?? true
        if didChange || scope == .yearBackfill || stampIsStale {
            settings.lastHealthSyncAt = .now
            settings.updatedAt = .now
            try context.save()
            TrainingStore.recordLocalWrite(reason: "updated Health sync timestamp")
        }

        if didChange {
            try TrainingStore.refreshWidgetSnapshot(context: context)
            TrainingStore.refreshHomeScreenQuickActions()
        }

        return HealthSyncSummary(
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            overlapCount: overlapCount,
            ignoredCount: ignoredCount,
            syncedAt: settings.lastHealthSyncAt ?? .now
        )
    }

    private static func candidate(
        for workout: HKWorkout,
        activeStats: [StatDomain],
        disabledTypeKeys: Set<String>,
        priorHabitKeyByWorkoutTitle: [String: String]
    ) -> HealthWorkoutCandidate? {
        guard
            let mapping = mapping(for: workout),
            !disabledTypeKeys.contains(SupportedWorkoutType.key(for: workout.workoutActivityType)),
            let stat = activeStats.first(where: { $0.statKey == mapping.statKey })
        else {
            return nil
        }

        let habits = TrainingStore.activeHabits(for: stat)
        let displayName = SupportedWorkoutType.all
            .first(where: { $0.activityType == workout.workoutActivityType })?
            .displayName ?? ""
        var matched = matchHabit(in: habits, workoutDisplayName: displayName)
        let titleKey = TrainingStore.healthImportAssignmentKey(
            statKeyRaw: mapping.statKey.rawValue,
            activityTypeRaw: Int(workout.workoutActivityType.rawValue)
        )
        if matched == nil,
           let priorHabitKey = priorHabitKeyByWorkoutTitle[titleKey] {
            matched = habits.first { $0.systemKey == priorHabitKey }
        }

        // When the skill has a single habit there is no ambiguity, so log the
        // workout directly rather than parking it in the unmatched queue. This
        // is what lets e.g. a Tennis workout count toward a one-habit Cardio
        // skill without manual assignment.
        if matched == nil, habits.count == 1 {
            matched = habits.first
        }

        let value: Double
        if let matched {
            value = loggedValue(for: workout, habit: matched)
        } else {
            value = max(1, (workout.duration / 60).rounded())
        }

        return HealthWorkoutCandidate(
            workout: workout,
            mapping: mapping,
            habit: matched,
            value: value,
            awaitingAssignment: matched == nil
        )
    }

    private static func matchHabit(in habits: [Habit], workoutDisplayName: String) -> Habit? {
        let needle = workoutDisplayName.lowercased()
        guard !needle.isEmpty else { return nil }
        if let exact = habits.first(where: { $0.name.lowercased() == needle }) {
            return exact
        }
        return habits.first(where: {
            let n = $0.name.lowercased()
            guard !n.isEmpty else { return false }
            return needle.contains(n) || n.contains(needle)
        })
    }

    private static func healthRecord(
        for candidate: HealthWorkoutCandidate,
        wasImported: Bool,
        isDuplicate: Bool,
        overlapsImportedWorkout: Bool,
        relatedWorkoutUUID: String?,
        awaitingHabitAssignment: Bool = false
    ) -> HealthImportedWorkout {
        let workout = candidate.workout
        return HealthImportedWorkout(
            workoutUUID: workout.uuid.uuidString,
            statKeyRaw: candidate.mapping.statKey.rawValue,
            habitSystemKey: candidate.habit?.systemKey,
            sourceName: workout.sourceRevision.source.name,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            activityTypeRaw: Int(workout.workoutActivityType.rawValue),
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationMinutes: workout.duration / 60,
            wasImported: wasImported,
            isDuplicate: isDuplicate,
            overlapsImportedWorkout: overlapsImportedWorkout,
            relatedWorkoutUUID: relatedWorkoutUUID,
            awaitingHabitAssignment: awaitingHabitAssignment
        )
    }

    /// Self-heals the stored import records: demotes any imported record that
    /// duplicates an earlier one (deleting its logged entry) and recomputes the
    /// overlap flags. Only writes to the store when something actually changed,
    /// so an idle sync doesn't churn CloudKit.
    private static func normalizeExistingHealthImports(context: ModelContext) throws -> [HealthImportedWorkout] {
        let records = try TrainingStore.fetchImportedHealthWorkouts(context: context)
            .sorted { $0.startDate < $1.startDate }
        var didMutate = false

        // Pass 1: keep the earliest of any duplicate cluster; demote the rest.
        var importedRecords: [HealthImportedWorkout] = []
        for record in records where record.wasImported && !record.isDuplicate {
            if let duplicateRecord = importedRecords.first(where: { isDuplicate(record, of: $0) }) {
                try deleteImportedHealthLog(for: record, context: context)
                record.wasImported = false
                record.isDuplicate = true
                record.overlapsImportedWorkout = false
                record.relatedWorkoutUUID = duplicateRecord.workoutUUID
                didMutate = true
            } else {
                importedRecords.append(record)
            }
        }

        // Pass 2: recompute overlap flags among the survivors, writing only the
        // records whose flag or related-UUID actually differs.
        for index in importedRecords.indices {
            let record = importedRecords[index]
            let overlapping = importedRecords[..<index].first { overlaps(record, with: $0) && !isDuplicate(record, of: $0) }
            let flag = overlapping != nil
            let related = overlapping?.workoutUUID
            if record.overlapsImportedWorkout != flag || record.relatedWorkoutUUID != related {
                record.overlapsImportedWorkout = flag
                record.relatedWorkoutUUID = related
                didMutate = true
            }
        }

        guard didMutate else { return records }

        try context.save()
        TrainingStore.recordLocalWrite(reason: "normalized Health import records")
        return try TrainingStore.fetchImportedHealthWorkouts(context: context)
    }

    private static func deleteImportedHealthLog(for record: HealthImportedWorkout, context: ModelContext) throws {
        let logs = try TrainingStore.fetchLogs(context: context)

        // Prefer an exact match on the workout UUID that was stamped onto the log
        // at import time — robust even when two short workouts sit seconds apart.
        if let log = logs.first(where: { $0.sourceType == .health && $0.healthWorkoutUUID == record.workoutUUID }) {
            try TrainingStore.delete(log, context: context)
            return
        }

        // Fallback for any legacy log written before UUIDs were stamped: match
        // the same habit within a two-minute window of the workout's end.
        guard let habitSystemKey = record.habitSystemKey else { return }
        let nearest = logs
            .filter { log in
                log.sourceType == .health &&
                log.habit?.systemKey == habitSystemKey &&
                abs(log.date.timeIntervalSince(record.endDate)) < 120
            }
            .min { abs($0.date.timeIntervalSince(record.endDate)) < abs($1.date.timeIntervalSince(record.endDate)) }

        if let nearest {
            try TrainingStore.delete(nearest, context: context)
        }
    }

    static func purgeDeprecatedAutoMappings(context: ModelContext) throws -> Bool {
        let danceRawValues: Set<Int> = [
            Int(HKWorkoutActivityType.cardioDance.rawValue),
            Int(HKWorkoutActivityType.socialDance.rawValue)
        ]
        let records = try TrainingStore.fetchImportedHealthWorkouts(context: context)
            .filter { danceRawValues.contains($0.activityTypeRaw) && $0.wasImported && !$0.isDuplicate }
        guard !records.isEmpty else { return false }

        for record in records {
            try deleteImportedHealthLog(for: record, context: context)
            record.wasImported = false
            record.overlapsImportedWorkout = false
        }
        return true
    }

    private static func shouldRunYearBackfill(now: Date = .now) -> Bool {
        guard let lastBackfill = defaults.object(forKey: lastYearBackfillDefaultsKey) as? Date else {
            return true
        }

        return now.timeIntervalSince(lastBackfill) > 7 * 24 * 60 * 60
    }

    nonisolated static func yearBackfillStartDate(now: Date = .now) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 60 * 60)
    }

    private static func isDuplicate(_ candidate: HealthWorkoutCandidate, of record: HealthImportedWorkout) -> Bool {
        guard candidate.mapping.statKey.rawValue == record.statKeyRaw else { return false }
        return isDuplicate(
            startDate: candidate.workout.startDate,
            endDate: candidate.workout.endDate,
            durationMinutes: candidate.workout.duration / 60,
            of: record
        )
    }

    private static func isDuplicate(_ record: HealthImportedWorkout, of otherRecord: HealthImportedWorkout) -> Bool {
        guard record.statKeyRaw == otherRecord.statKeyRaw, record.workoutUUID != otherRecord.workoutUUID else { return false }
        return isDuplicate(
            startDate: record.startDate,
            endDate: record.endDate,
            durationMinutes: record.durationMinutes,
            of: otherRecord
        )
    }

    private static func isDuplicate(
        startDate: Date,
        endDate: Date,
        durationMinutes: Double,
        of record: HealthImportedWorkout
    ) -> Bool {
        let startDelta = abs(startDate.timeIntervalSince(record.startDate))
        let endDelta = abs(endDate.timeIntervalSince(record.endDate))
        let durationDelta = abs(durationMinutes - record.durationMinutes)
        if startDelta <= 10 * 60, endDelta <= 10 * 60, durationDelta <= 10 {
            return true
        }

        let overlapRatio = overlapRatio(
            firstStart: startDate,
            firstEnd: endDate,
            secondStart: record.startDate,
            secondEnd: record.endDate
        )
        return overlapRatio >= 0.85 && durationDelta <= 15
    }

    private static func overlaps(_ candidate: HealthWorkoutCandidate, with record: HealthImportedWorkout) -> Bool {
        overlapDuration(
            firstStart: candidate.workout.startDate,
            firstEnd: candidate.workout.endDate,
            secondStart: record.startDate,
            secondEnd: record.endDate
        ) > 0
    }

    private static func overlaps(_ record: HealthImportedWorkout, with otherRecord: HealthImportedWorkout) -> Bool {
        guard record.workoutUUID != otherRecord.workoutUUID else { return false }
        return overlapDuration(
            firstStart: record.startDate,
            firstEnd: record.endDate,
            secondStart: otherRecord.startDate,
            secondEnd: otherRecord.endDate
        ) > 0
    }

    nonisolated static func overlapRatio(firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date) -> Double {
        let overlap = overlapDuration(firstStart: firstStart, firstEnd: firstEnd, secondStart: secondStart, secondEnd: secondEnd)
        let shorterDuration = min(firstEnd.timeIntervalSince(firstStart), secondEnd.timeIntervalSince(secondStart))
        guard shorterDuration > 0 else { return 0 }
        return overlap / shorterDuration
    }

    nonisolated static func overlapDuration(firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date) -> TimeInterval {
        max(0, min(firstEnd, secondEnd).timeIntervalSince(max(firstStart, secondStart)))
    }

    private static func fetchWorkouts(
        anchor: HKQueryAnchor?,
        predicate: NSPredicate?
    ) async throws -> ([HKWorkout], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: workoutType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: (workouts, newAnchor))
            }

            healthStore.execute(query)
        }
    }

    private static func mapping(for workout: HKWorkout) -> WorkoutMapping? {
        SupportedWorkoutType.mapping(for: workout.workoutActivityType)
    }

    private static func loggedValue(for workout: HKWorkout, habit: Habit) -> Double {
        TrainingStore.loggedValue(durationMinutes: workout.duration / 60, habit: habit)
    }

    private static func loadAnchor() -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: AppIdentity.healthWorkoutAnchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func saveAnchor(_ anchor: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        defaults.set(data, forKey: AppIdentity.healthWorkoutAnchorKey)
    }
}
#endif
