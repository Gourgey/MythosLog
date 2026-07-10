import Foundation
import CoreData
import CloudKit
import OSLog
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
enum TrainingStore {
    private static let syncLogger = Logger(subsystem: "studio.curateddesign.MythosLog", category: "SwiftDataCloudKit")
    private static let lastLocalWriteDefaultsKey = "mythoslog.syncDiagnostics.lastLocalWriteAt"
    private static let lastLocalWriteReasonDefaultsKey = "mythoslog.syncDiagnostics.lastLocalWriteReason"
    private static let lastCloudKitEventDefaultsKey = "mythoslog.syncDiagnostics.lastCloudKitEvent"
    private static let lastCloudKitEventDateDefaultsKey = "mythoslog.syncDiagnostics.lastCloudKitEventDate"
    private static var cloudKitEventObserver: NSObjectProtocol?

    private struct PersistentStoreCandidate {
        let configuration: ModelConfiguration
        let storeURL: URL?
        let usesCloudKit: Bool
        let usesAppGroup: Bool
        let isInMemory: Bool
        let allowsStoreReset: Bool
    }

    struct RuntimeStoreInfo: Equatable {
        var storeURL: URL?
        var cloudKitContainerIdentifier: String?
        var usesCloudKit: Bool
        var usesAppGroup: Bool
        var isInMemory: Bool
        var allowsStoreReset: Bool
        var createdAt: Date
        var fallbackReason: String?
    }

    struct ModelCounts: Equatable {
        var stats: Int
        var habits: Int
        var logs: Int
        var weeklyResolutions: Int
        var settings: Int
        var healthImports: Int
        var goals: Int = 0
    }

    private(set) static var runtimeStoreInfo = RuntimeStoreInfo(
        storeURL: nil,
        cloudKitContainerIdentifier: nil,
        usesCloudKit: false,
        usesAppGroup: false,
        isInMemory: false,
        allowsStoreReset: false,
        createdAt: .now,
        fallbackReason: "ModelContainer has not been created yet."
    )

    static let schema = Schema([
        StatDomain.self,
        Habit.self,
        HabitLog.self,
        WeeklyResolution.self,
        AppSettings.self,
        HealthImportedWorkout.self,
        Goal.self
    ])

    static let sharedModelContainer = makeModelContainer()

    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        let fileManager = FileManager.default
        let canUseAppGroup = !inMemory && fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentity.appGroupIdentifier
        ) != nil

        let candidates: [PersistentStoreCandidate]
        if inMemory {
            candidates = [
                makeConfigurationCandidate(inMemory: true, useAppGroup: false, useCloudKit: false, allowsStoreReset: false)
            ]
        } else {
            let canUseCloudKit = canAttemptCloudKitPersistence()
            candidates = [
                canUseCloudKit ? makeConfigurationCandidate(inMemory: false, useAppGroup: canUseAppGroup, useCloudKit: true, allowsStoreReset: false) : nil,
                canUseCloudKit ? makeConfigurationCandidate(inMemory: false, useAppGroup: false, useCloudKit: true, allowsStoreReset: false) : nil,
                makeConfigurationCandidate(inMemory: false, useAppGroup: canUseAppGroup, useCloudKit: false, allowsStoreReset: true),
                makeConfigurationCandidate(inMemory: false, useAppGroup: false, useCloudKit: false, allowsStoreReset: true)
            ].compactMap(\.self)
        }
        var lastError: Error?

        for candidate in candidates {
            logStoreCandidate(candidate)
            do {
                let container = try ModelContainer(for: schema, configurations: candidate.configuration)
                recordRuntimeStoreInfo(candidate: candidate, fallbackReason: fallbackReason(for: candidate, lastError: lastError))
                logICloudAccountState()
                return container
            } catch {
                lastError = error
                logStoreCandidateFailure(candidate, error: error)

                guard candidate.allowsStoreReset, let storeURL = candidate.storeURL else {
                    continue
                }

                do {
                    try resetPersistentStore(at: storeURL)
                    let container = try ModelContainer(for: schema, configurations: candidate.configuration)
                    recordRuntimeStoreInfo(candidate: candidate, fallbackReason: "Created after local store reset. Previous error: \(String(describing: error))")
                    logICloudAccountState()
                    return container
                } catch {
                    lastError = error
                    logStoreCandidateFailure(candidate, error: error)
                    continue
                }
            }
        }

        let message = lastError.map { String(describing: $0) } ?? "Unknown SwiftData error"
        fatalError("Unable to create ModelContainer. \(message)")
    }

    nonisolated static func canAttemptCloudKitPersistence() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }

        return true
    }

    private static func makeConfigurationCandidate(
        inMemory: Bool,
        useAppGroup: Bool,
        useCloudKit: Bool,
        allowsStoreReset: Bool
    ) -> PersistentStoreCandidate {
        if inMemory {
            return PersistentStoreCandidate(
                configuration: ModelConfiguration(
                    AppIdentity.displayName,
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                ),
                storeURL: nil,
                usesCloudKit: false,
                usesAppGroup: false,
                isInMemory: true,
                allowsStoreReset: allowsStoreReset
            )
        }

        let storeURL = persistentStoreURL(useAppGroup: useAppGroup)
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        return PersistentStoreCandidate(
            configuration: ModelConfiguration(
                AppIdentity.displayName,
                schema: schema,
                url: storeURL,
                cloudKitDatabase: useCloudKit ? .private(AppIdentity.iCloudContainerIdentifier) : .none
            ),
            storeURL: storeURL,
            usesCloudKit: useCloudKit,
            usesAppGroup: useAppGroup,
            isInMemory: false,
            allowsStoreReset: allowsStoreReset
        )
    }

    private static func fallbackReason(for candidate: PersistentStoreCandidate, lastError: Error?) -> String? {
        guard !candidate.usesCloudKit, let lastError else { return nil }
        return "CloudKit store candidate failed before falling back to local-only persistence: \(String(describing: lastError))"
    }

    private static func recordRuntimeStoreInfo(candidate: PersistentStoreCandidate, fallbackReason: String?) {
        runtimeStoreInfo = RuntimeStoreInfo(
            storeURL: candidate.storeURL,
            cloudKitContainerIdentifier: candidate.usesCloudKit ? AppIdentity.iCloudContainerIdentifier : nil,
            usesCloudKit: candidate.usesCloudKit,
            usesAppGroup: candidate.usesAppGroup,
            isInMemory: candidate.isInMemory,
            allowsStoreReset: candidate.allowsStoreReset,
            createdAt: .now,
            fallbackReason: fallbackReason
        )

        #if DEBUG
        syncLogger.info("""
        ModelContainer created. storeURL=\(candidate.storeURL?.path ?? "in-memory", privacy: .public) \
        cloudKit=\(candidate.usesCloudKit ? "private(\(AppIdentity.iCloudContainerIdentifier))" : "none", privacy: .public) \
        appGroup=\(candidate.usesAppGroup) resetAllowed=\(candidate.allowsStoreReset) \
        ubiquityTokenPresent=\(FileManager.default.ubiquityIdentityToken != nil)
        """)
        if let fallbackReason {
            syncLogger.error("\(fallbackReason, privacy: .public)")
        }
        #endif
    }

    private static func logStoreCandidate(_ candidate: PersistentStoreCandidate) {
        #if DEBUG
        syncLogger.info("""
        Trying ModelContainer candidate. storeURL=\(candidate.storeURL?.path ?? "in-memory", privacy: .public) \
        cloudKit=\(candidate.usesCloudKit ? "private(\(AppIdentity.iCloudContainerIdentifier))" : "none", privacy: .public) \
        appGroup=\(candidate.usesAppGroup) inMemory=\(candidate.isInMemory)
        """)
        #endif
    }

    private static func logStoreCandidateFailure(_ candidate: PersistentStoreCandidate, error: Error) {
        #if DEBUG
        syncLogger.error("""
        ModelContainer candidate failed. storeURL=\(candidate.storeURL?.path ?? "in-memory", privacy: .public) \
        cloudKit=\(candidate.usesCloudKit ? "private(\(AppIdentity.iCloudContainerIdentifier))" : "none", privacy: .public) \
        error=\(String(describing: error), privacy: .public)
        """)
        #endif
    }

    private static func logICloudAccountState() {
        #if DEBUG
        syncLogger.info("ubiquityIdentityToken present: \(FileManager.default.ubiquityIdentityToken != nil)")
        CKContainer(identifier: AppIdentity.iCloudContainerIdentifier).accountStatus { status, error in
            Task { @MainActor in
                if let error {
                    syncLogger.error("CloudKit accountStatus error: \(String(describing: error), privacy: .public)")
                    return
                }
                syncLogger.info("CloudKit accountStatus for \(AppIdentity.iCloudContainerIdentifier, privacy: .public): \(String(describing: status), privacy: .public)")
            }
        }
        #endif
    }

    static func startCloudKitEventObserver() {
        guard cloudKitEventObserver == nil else { return }
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event
            else {
                return
            }

            Task { @MainActor in
                recordCloudKitEvent(event)
            }
        }
    }

    private static func recordCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        let type: String
        switch event.type {
        case .setup:
            type = "setup"
        case .import:
            type = "import"
        case .export:
            type = "export"
        @unknown default:
            type = "unknown"
        }

        var summary = "\(type) \(event.succeeded ? "succeeded" : "failed")"
        if let endDate = event.endDate {
            summary += " at \(endDate.formatted(date: .abbreviated, time: .standard))"
        }
        if let error = event.error {
            summary += " error=\(error.localizedDescription)"
        }

        diagnosticDefaults.set(summary, forKey: lastCloudKitEventDefaultsKey)
        diagnosticDefaults.set(Date(), forKey: lastCloudKitEventDateDefaultsKey)

        #if DEBUG
        syncLogger.info("CloudKit event: \(summary, privacy: .public)")
        #endif
    }

    static func recordLocalWrite(reason: String) {
        diagnosticDefaults.set(Date(), forKey: lastLocalWriteDefaultsKey)
        diagnosticDefaults.set(reason, forKey: lastLocalWriteReasonDefaultsKey)

        #if DEBUG
        syncLogger.info("Local SwiftData write: \(reason, privacy: .public)")
        #endif
    }

    static var lastLocalWriteAt: Date? {
        diagnosticDefaults.object(forKey: lastLocalWriteDefaultsKey) as? Date
    }

    static var lastLocalWriteReason: String? {
        diagnosticDefaults.string(forKey: lastLocalWriteReasonDefaultsKey)
    }

    static var lastCloudKitEventSummary: String? {
        diagnosticDefaults.string(forKey: lastCloudKitEventDefaultsKey)
    }

    static var lastCloudKitEventAt: Date? {
        diagnosticDefaults.object(forKey: lastCloudKitEventDateDefaultsKey) as? Date
    }

    private static var diagnosticDefaults: UserDefaults {
        UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
    }

    private static func persistentStoreURL(useAppGroup: Bool) -> URL {
        let baseDirectory: URL

        if useAppGroup,
           let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentity.appGroupIdentifier
           ) {
            baseDirectory = appGroupURL.appendingPathComponent("Application Support", isDirectory: true)
        } else {
            baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent(AppIdentity.internalProjectName, isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(AppIdentity.internalProjectName, isDirectory: true)
        }

        return baseDirectory.appendingPathComponent("\(AppIdentity.internalProjectName).store")
    }

    private static func resetPersistentStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let candidateURLs = [
            storeURL,
            storeURL.appendingPathExtension("sqlite"),
            storeURL.appendingPathExtension("sqlite-shm"),
            storeURL.appendingPathExtension("sqlite-wal"),
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]

        for candidateURL in Set(candidateURLs) where fileManager.fileExists(atPath: candidateURL.path) {
            try fileManager.removeItem(at: candidateURL)
        }
    }

    static func refreshAppState() {
        let context = ModelContext(sharedModelContainer)
        _ = try? reconcileSyncedData(context: context)
        try? synchronizeCatalog(context: context)
        _ = try? drainQuickLogQueue(context: context)
        try? refreshAllProgress(context: context, reason: .appRefresh)
        try? refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
    }

    /// Applies any quick logs queued by the interactive widget. Runs synchronously
    /// on the main actor so two drain points (cold launch + foreground) can't
    /// double-apply: the first call persists and clears, the second sees an empty
    /// queue. Boolean-session habits get one log per counted session.
    @discardableResult
    static func drainQuickLogQueue(context: ModelContext) throws -> Int {
        let pending = QuickLogQueue.pending()
        guard !pending.isEmpty else { return 0 }

        let habits = try fetchActiveHabits(context: context)
        var appliedCount = 0

        for (habitIDString, amount) in pending {
            guard
                amount > 0,
                let habitID = UUID(uuidString: habitIDString),
                let habit = habits.first(where: { $0.id == habitID })
            else {
                continue
            }

            if habit.measurementType == .booleanSession {
                let sessions = max(1, Int(amount.rounded()))
                for _ in 0..<sessions {
                    _ = try log(habit: habit, value: 1, date: .now, note: "Quick log", source: .widget, context: context)
                }
            } else {
                _ = try log(habit: habit, value: amount, date: .now, note: "Quick log", source: .widget, context: context)
            }
            appliedCount += 1
        }

        QuickLogQueue.clear()
        return appliedCount
    }

    static func fetchSettings(context: ModelContext) throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let settings = try context.fetch(descriptor).first {
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        recordLocalWrite(reason: "created default AppSettings")
        return settings
    }

    static func fetchExistingSettings(context: ModelContext) throws -> AppSettings? {
        let descriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    static func fetchStats(context: ModelContext) throws -> [StatDomain] {
        let descriptor = FetchDescriptor<StatDomain>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    static func fetchActiveStats(context: ModelContext) throws -> [StatDomain] {
        try fetchStats(context: context).filter { $0.isActive }
    }

    /// All non-archived but disabled, plus archived, skills — i.e. everything that
    /// could be turned on from the Skill Library.
    static func fetchArchivedStats(context: ModelContext) throws -> [StatDomain] {
        try fetchStats(context: context).filter { !$0.isActive }
    }

    static func fetchHabits(context: ModelContext) throws -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    static func fetchActiveHabits(context: ModelContext) throws -> [Habit] {
        try fetchHabits(context: context).filter(\.active)
    }

    static func fetchLogs(context: ModelContext) throws -> [HabitLog] {
        let descriptor = FetchDescriptor<HabitLog>(sortBy: [SortDescriptor(\.date, order: .forward)])
        return try context.fetch(descriptor)
    }

    static func fetchResolutions(context: ModelContext) throws -> [WeeklyResolution] {
        let descriptor = FetchDescriptor<WeeklyResolution>(sortBy: [SortDescriptor(\.weekStartDate, order: .forward)])
        return try context.fetch(descriptor)
    }

    static func fetchImportedHealthWorkouts(context: ModelContext) throws -> [HealthImportedWorkout] {
        let descriptor = FetchDescriptor<HealthImportedWorkout>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        return try context.fetch(descriptor)
    }

    static func awaitingAttributionStatKeys(context: ModelContext) throws -> Set<String> {
        let descriptor = FetchDescriptor<HealthImportedWorkout>(
            predicate: #Predicate { record in
                record.awaitingHabitAssignment == true && record.isDuplicate == false
            }
        )
        let records = try context.fetch(descriptor)
        return Set(records.map(\.statKeyRaw))
    }

    static func unmatchedWorkoutCount(forStatKey statKey: String, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<HealthImportedWorkout>(
            predicate: #Predicate { record in
                record.statKeyRaw == statKey &&
                record.awaitingHabitAssignment == true &&
                record.isDuplicate == false
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func fetchGoals(context: ModelContext) throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(sortBy: [
            SortDescriptor(\.statusRaw),
            SortDescriptor(\.createdAt, order: .reverse)
        ])
        return try context.fetch(descriptor)
    }

    static func fetchActiveGoals(context: ModelContext) throws -> [Goal] {
        try fetchGoals(context: context).filter { $0.status == .active }
    }

    static func fetchGoals(for statKey: StatKey, context: ModelContext) throws -> [Goal] {
        try fetchGoals(context: context).filter { $0.linkedStatKey == statKey }
    }

    @discardableResult
    static func createGoal(
        title: String,
        notes: String = "",
        scope: GoalScope,
        linkedStatKey: StatKey? = nil,
        linkedHabitID: UUID? = nil,
        type: GoalType,
        measurementType: MeasurementType,
        targetValue: Double,
        startDate: Date = .now,
        endDate: Date? = nil,
        priority: GoalPriority = .normal,
        affectsMetrics: Bool = false,
        affectsProgression: Bool = false,
        isRecoveryMode: Bool = false,
        context: ModelContext
    ) throws -> Goal {
        let goal = Goal(
            title: title,
            notes: notes,
            scope: scope,
            linkedStatKey: linkedStatKey,
            linkedHabitID: linkedHabitID,
            type: type,
            measurementType: measurementType,
            targetValue: targetValue,
            startDate: startDate,
            endDate: endDate,
            status: .active,
            priority: priority,
            affectsMetrics: affectsMetrics,
            affectsProgression: affectsProgression,
            isRecoveryMode: isRecoveryMode
        )
        context.insert(goal)
        try context.save()
        recordLocalWrite(reason: "created goal")
        return goal
    }

    static func updateGoal(_ goal: Goal, context: ModelContext) throws {
        goal.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "updated goal")
    }

    static func setGoalStatus(_ goal: Goal, status: GoalStatus, context: ModelContext) throws {
        let previous = goal.status
        goal.status = status
        if status == .completed, goal.completedAt == nil {
            goal.completedAt = .now
        }
        if status != .completed, previous == .completed {
            goal.completedAt = nil
        }
        goal.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "changed goal status to \(status.rawValue)")
    }

    static func deleteGoal(_ goal: Goal, context: ModelContext) throws {
        context.delete(goal)
        try context.save()
        recordLocalWrite(reason: "deleted goal")
    }

    /// Recurring goals treat their end date as a "stop tracking" boundary rather
    /// than a pass/fail line, so they are archived (not failed) once it passes.
    private static let recurringGoalTypes: Set<GoalType> = [.weeklyTarget, .monthlyTotal]

    /// Moves active goals whose end date has passed into a terminal state:
    /// achievable goals complete when met and fail when not; recurring goals are
    /// archived without judgment. Returns the number of goals transitioned.
    @discardableResult
    static func applyAutomaticGoalTransitions(context: ModelContext, now: Date = .now) throws -> Int {
        let activeGoals = try fetchGoals(context: context).filter { $0.status == .active }
        var transitioned = 0

        for goal in activeGoals {
            guard let endDate = goal.endDate, endDate < now else { continue }

            let newStatus: GoalStatus
            if recurringGoalTypes.contains(goal.type) {
                newStatus = .archived
            } else {
                let progress = goalProgress(for: goal, context: context, now: now)
                newStatus = progress.progressRatio >= 1 ? .completed : .failed
            }

            // Preserve the real completion moment so weekly recaps attribute it
            // to the week the goal actually ended.
            if newStatus == .completed {
                goal.completedAt = endDate
            }
            try setGoalStatus(goal, status: newStatus, context: context)
            transitioned += 1
        }

        return transitioned
    }

    static func goalProgress(for goal: Goal, context: ModelContext, now: Date = .now) -> GoalProgressSnapshot {
        let currentValue = computeGoalCurrentValue(for: goal, context: context, now: now)
        let target = max(goal.targetValue, 0)
        let ratio: Double
        if target > 0 {
            ratio = min(max(currentValue / target, 0), 1)
        } else {
            ratio = goal.status == .completed ? 1 : 0
        }
        let remaining = max(target - currentValue, 0)

        let paceStatus = goalPaceStatus(
            goal: goal,
            currentValue: currentValue,
            target: target,
            now: now
        )

        return GoalProgressSnapshot(
            id: goal.id,
            goal: goal,
            currentValue: currentValue,
            targetValue: target,
            progressRatio: ratio,
            remainingValue: remaining,
            paceStatus: paceStatus,
            timeRemainingLabel: goalTimeRemainingLabel(for: goal, now: now),
            statusLabel: goalStatusLabel(goal: goal, currentValue: currentValue, target: target, paceStatus: paceStatus)
        )
    }

    static func goalProgressSnapshots(context: ModelContext, now: Date = .now) throws -> [GoalProgressSnapshot] {
        try fetchGoals(context: context).map { goal in
            goalProgress(for: goal, context: context, now: now)
        }
    }

    // MARK: - Dashboard sections (Phase 7)

    static func dashboardSections(
        context: ModelContext,
        settings: AppSettings?,
        now: Date = .now
    ) throws -> DashboardSections {
        let stats = try fetchActiveStats(context: context).sorted { $0.sortOrder < $1.sortOrder }
        let goalSnapshots = (try? goalProgressSnapshots(context: context, now: now)) ?? []

        return DashboardSections(
            weeklyStatus: computeWeeklyStatus(stats: stats, settings: settings, reviewReady: false, now: now),
            highlights: computeDashboardHighlights(stats: stats),
            goals: computeGoalsSummary(snapshots: goalSnapshots, settings: settings, now: now)
        )
    }

    /// Day-aware pace for the in-progress week. Unlike `pacingStatus`, this scales
    /// the baseline by how much of the week has elapsed so an empty Monday does
    /// not read as "behind."
    private static func weeklyPaceRatio(for stat: StatDomain, settings: AppSettings?, now: Date) -> Double? {
        let baseline = Double(stat.currentBaseline)
        guard baseline > 0 else { return nil }
        let interval = currentWeekInterval(settings: settings, now: now)
        let elapsed = now.timeIntervalSince(interval.start)
        let fraction = min(max(elapsed / interval.duration, 1.0 / 7.0), 1.0)
        let expectedSoFar = baseline * fraction
        guard expectedSoFar > 0 else { return nil }
        let actual = currentWeekTotal(for: stat, settings: settings, now: now)
        return actual / expectedSoFar
    }

    /// Count of active skills that are behind their day-aware pace for the current
    /// week. Used to decide whether to schedule the behind-pace reminder.
    static func skillsBehindPaceCount(context: ModelContext, settings: AppSettings?, now: Date = .now) -> Int {
        let stats = (try? fetchActiveStats(context: context)) ?? []
        return stats.filter { stat in
            guard let ratio = weeklyPaceRatio(for: stat, settings: settings, now: now) else { return false }
            return ratio < 0.7
        }.count
    }

    private static func computeWeeklyStatus(
        stats: [StatDomain],
        settings: AppSettings?,
        reviewReady: Bool,
        now: Date
    ) -> DashboardWeeklyStatus {
        var ahead = 0
        var onPace = 0
        var behind = 0
        var totalActual: Double = 0

        for stat in stats {
            totalActual += currentWeekTotal(for: stat, settings: settings, now: now)
            guard let ratio = weeklyPaceRatio(for: stat, settings: settings, now: now) else {
                onPace += 1
                continue
            }
            if ratio < 0.7 {
                behind += 1
            } else if ratio < 1.05 {
                onPace += 1
            } else {
                ahead += 1
            }
        }

        let detail = "\(ahead) ahead · \(onPace) on pace · \(behind) behind"

        let kind: DashboardWeeklyStatus.Kind
        let headline: String
        if reviewReady {
            kind = .reviewReady
            headline = "Last week is ready to resolve"
        } else if stats.isEmpty || totalActual == 0 {
            kind = .noActivity
            headline = "Fresh week — nothing logged yet"
        } else if behind > ahead + onPace {
            kind = .atRisk
            headline = "Behind pace this week"
        } else if ahead > 0, behind == 0 {
            kind = .ahead
            headline = "Ahead of pace this week"
        } else {
            kind = .onPace
            headline = "On pace this week"
        }

        return DashboardWeeklyStatus(
            kind: kind,
            aheadCount: ahead,
            onPaceCount: onPace,
            behindCount: behind,
            headline: headline,
            detail: kind == .reviewReady
                ? "Open Review to apply your weekly rank check."
                : (kind == .noActivity ? "Log a session to start building this week." : detail)
        )
    }

    private static func computeDashboardHighlights(stats: [StatDomain]) -> [DashboardHighlight] {
        let chargeMaximum = DashboardChargeDots.slotsPerSide
        var highlights: [DashboardHighlight] = []

        for stat in stats {
            guard let statKey = stat.statKey else { continue }
            let charge = stat.chargeValue
            let isAtMax = stat.rankLevel >= TrainingArcConfig.maximumRankLevel

            if let pending = stat.pendingRankChange, pending.direction == .up {
                highlights.append(
                    DashboardHighlight(
                        id: "rankedup-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        kind: .rankedUp,
                        text: "Ranked up to \(pending.toTitle)"
                    )
                )
            } else if charge >= chargeMaximum - 1, charge > 0, !isAtMax {
                highlights.append(
                    DashboardHighlight(
                        id: "nearrank-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        kind: .nearRankUp,
                        text: "One strong week from ranking up"
                    )
                )
            } else if charge <= -2 {
                highlights.append(
                    DashboardHighlight(
                        id: "momentum-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        kind: .losingMomentum,
                        text: "Losing momentum — close to ranking down"
                    )
                )
            }
        }

        return highlights.sorted { lhs, rhs in
            if lhs.kind.order != rhs.kind.order {
                return lhs.kind.order < rhs.kind.order
            }
            return lhs.statName < rhs.statName
        }
    }

    private static func computeGoalsSummary(
        snapshots: [GoalProgressSnapshot],
        settings: AppSettings?,
        now: Date
    ) -> DashboardGoalsSummary {
        let weekInterval = currentWeekInterval(settings: settings, now: now)
        var active = 0
        var atRisk = 0
        var completedThisWeek = 0
        var close = 0

        for snapshot in snapshots {
            switch snapshot.goal.status {
            case .active:
                active += 1
                if snapshot.paceStatus == .atRisk || snapshot.paceStatus == .behind {
                    atRisk += 1
                }
                if snapshot.progressRatio >= 0.8, snapshot.paceStatus != .complete {
                    close += 1
                }
            case .completed:
                if let completedAt = snapshot.goal.completedAt, weekInterval.contains(completedAt) {
                    completedThisWeek += 1
                }
            default:
                break
            }
        }

        return DashboardGoalsSummary(
            activeCount: active,
            atRiskCount: atRisk,
            completedThisWeekCount: completedThisWeek,
            closeToCompletionCount: close,
            totalCount: snapshots.count
        )
    }

    // MARK: - Weekly recap (Phase 8)

    static func weeklyRecap(
        weekStart: Date,
        context: ModelContext,
        settings: AppSettings?,
        now: Date = .now
    ) throws -> WeeklyRecap {
        let calendar = progressionCalendar()
        let weekResolutions = try fetchResolutions(context: context)
            .filter { calendar.isDate($0.weekStartDate, inSameDayAs: weekStart) }

        let best = weekResolutions.filter { $0.weeklyDelta > 0 }.max { $0.weeklyDelta < $1.weeklyDelta }
        let neglected = weekResolutions.filter { $0.weeklyDelta < 0 }.min { $0.weeklyDelta < $1.weeklyDelta }

        let gainedChargeSkills = weekResolutions
            .filter { $0.chargesEarned > 0 || $0.didLevelUp }
            .sorted { $0.chargesEarned > $1.chargesEarned }
            .map(\.statName)
        let lostChargeSkills = weekResolutions
            .filter { $0.chargesEarned < 0 || $0.didRegress }
            .sorted { $0.chargesEarned < $1.chargesEarned }
            .map(\.statName)

        let start = calendar.startOfDay(for: weekStart)
        let weekInterval = DateInterval(
            start: start,
            end: calendar.date(byAdding: .day, value: 7, to: start) ?? start
        )
        let goals = (try? fetchGoals(context: context)) ?? []

        let goalsCompleted = goals.compactMap { goal -> String? in
            guard goal.status == .completed,
                  let completedAt = goal.completedAt,
                  weekInterval.contains(completedAt) else { return nil }
            return goal.displayTitle
        }

        let skillsWithActivity = Set(weekResolutions.filter { $0.actualCompletedValue > 0 }.map(\.statKey))
        let goalsProgressedCount = goals.filter { goal in
            guard goal.status == .active else { return false }
            if let statKey = goal.linkedStatKey {
                return skillsWithActivity.contains(statKey.rawValue)
            }
            return !skillsWithActivity.isEmpty
        }.count

        let goalsAtRiskCount = goals.filter { goal in
            guard goal.status == .active else { return false }
            let snapshot = goalProgress(for: goal, context: context, now: now)
            return snapshot.paceStatus == .atRisk || snapshot.paceStatus == .behind
        }.count

        return WeeklyRecap(
            bestSkillName: best?.statName,
            bestSkillDetail: best.map { "+\(MetricFormatting.shortMetric($0.weeklyDelta)) above baseline" },
            neglectedSkillName: neglected?.statName,
            neglectedSkillDetail: neglected.map { "\(MetricFormatting.shortMetric(abs($0.weeklyDelta))) below baseline" },
            gainedChargeSkills: gainedChargeSkills,
            lostChargeSkills: lostChargeSkills,
            goalsCompleted: goalsCompleted,
            goalsProgressedCount: goalsProgressedCount,
            goalsAtRiskCount: goalsAtRiskCount
        )
    }

    static func trainTodayRecommendations(
        context: ModelContext,
        settings: AppSettings?,
        now: Date = .now,
        limit: Int = 3
    ) throws -> [TrainTodayRecommendation] {
        var output: [TrainTodayRecommendation] = []

        let stats = try fetchActiveStats(context: context)
        let goalsAffectPacing = settings?.goalsAffectPacing ?? true
        let goalSnapshots = goalsAffectPacing ? ((try? goalProgressSnapshots(context: context, now: now)) ?? []) : []
        let activeGoalsByStat: [String: [GoalProgressSnapshot]] = Dictionary(
            grouping: goalSnapshots.filter { $0.goal.status == .active && $0.goal.linkedStatKeyRaw != nil },
            by: { $0.goal.linkedStatKeyRaw ?? "" }
        )

        for stat in stats {
            guard let statKey = stat.statKey else { continue }
            let actual = currentWeekTotal(for: stat, settings: settings, now: now)
            let baseline = Double(stat.currentBaseline)
            let pace = pacingStatus(for: stat, settings: settings, now: now)
            let charge = stat.chargeValue
            let lastLog = recentLogs(for: stat).first?.date
            let unit = weeklyUnitLabel(for: stat)

            if let goalsForStat = activeGoalsByStat[statKey.rawValue] {
                for snapshot in goalsForStat where snapshot.paceStatus == .atRisk || snapshot.paceStatus == .behind {
                    let remaining = max(snapshot.targetValue - snapshot.currentValue, 0)
                    let remainingLabel = MetricFormatting.shortMetric(remaining)
                    output.append(
                        TrainTodayRecommendation(
                            id: "goal-\(snapshot.goal.id.uuidString)",
                            statKeyRaw: statKey.rawValue,
                            statName: stat.name,
                            colorToken: stat.colorToken,
                            iconName: stat.iconName,
                            headline: "\(stat.name) goal at risk",
                            detail: "\(remainingLabel) more needed for: \(snapshot.goal.displayTitle)",
                            reason: .goalAtRisk,
                            priority: 80,
                            hasReviewReady: false
                        )
                    )
                }
            }

            if baseline > 0, actual == 0 {
                output.append(
                    TrainTodayRecommendation(
                        id: "nolog-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        iconName: stat.iconName,
                        headline: "\(stat.name) has no logs this week",
                        detail: "Add the first entry to keep momentum.",
                        reason: .noLogsThisWeek,
                        priority: 70,
                        hasReviewReady: false
                    )
                )
                continue
            }

            if pace == .behind, baseline > 0 {
                let remaining = max(baseline - actual, 0)
                let remainingLabel = MetricFormatting.shortMetric(remaining)
                output.append(
                    TrainTodayRecommendation(
                        id: "behind-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        iconName: stat.iconName,
                        headline: "\(stat.name) behind pace",
                        detail: "\(remainingLabel) \(unit) needed to stay on baseline.",
                        reason: .behindBaseline,
                        priority: 60,
                        hasReviewReady: false
                    )
                )
                continue
            }

            if charge <= -2 {
                output.append(
                    TrainTodayRecommendation(
                        id: "lowcharge-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        iconName: stat.iconName,
                        headline: "\(stat.name) losing momentum",
                        detail: "Charge is at \(charge). One strong week resets the trend.",
                        reason: .lowCharge,
                        priority: 55,
                        hasReviewReady: false
                    )
                )
                continue
            }

            if charge >= 3, stat.rankLevel < TrainingArcConfig.maximumRankLevel {
                output.append(
                    TrainTodayRecommendation(
                        id: "ranking-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        iconName: stat.iconName,
                        headline: "\(stat.name) close to rank up",
                        detail: "Hold this week to lock in the new rank.",
                        reason: .nearRankUp,
                        priority: 30,
                        hasReviewReady: false
                    )
                )
                continue
            }

            if let lastLog, now.timeIntervalSince(lastLog) > 14 * 86_400 {
                let days = Int(now.timeIntervalSince(lastLog) / 86_400)
                output.append(
                    TrainTodayRecommendation(
                        id: "stale-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        iconName: stat.iconName,
                        headline: "\(stat.name) hasn't been logged in \(days) days",
                        detail: "Even a small session restarts the trend.",
                        reason: .staleSkill,
                        priority: 40,
                        hasReviewReady: false
                    )
                )
            }
        }

        let sorted = output.sorted { $0.priority > $1.priority }
        return Array(sorted.prefix(limit))
    }

    static func activeWeeklyGoalTarget(for goals: [Goal], week: WeekRange) -> Int? {
        activeWeeklyGoal(for: goals, week: week).map { Int($0.targetValue.rounded()) }
    }

    static func activeWeeklyGoal(for goals: [Goal], week: WeekRange) -> Goal? {
        let weekInterval = WeekMath.dateInterval(for: week, calendar: progressionCalendar())
        let eligible = goals.filter { goal in
            guard goal.affectsProgression else { return false }
            guard goal.type == .weeklyTarget else { return false }
            guard goal.status == .active || goal.status == .completed else { return false }
            if goal.startDate > weekInterval.end { return false }
            if let endDate = goal.endDate, endDate < weekInterval.start { return false }
            return goal.targetValue > 0
        }
        return eligible.max(by: { $0.targetValue < $1.targetValue })
    }

    private static func computeGoalCurrentValue(for goal: Goal, context: ModelContext, now: Date) -> Double {
        switch goal.type {
        case .reachLevel, .reachRank:
            guard
                let statKey = goal.linkedStatKey,
                let stat = try? fetchStats(context: context).first(where: { $0.statKey == statKey })
            else {
                return 0
            }
            return Double(stat.rankLevel)
        case .weeklyTarget:
            return totalForGoal(goal, in: progressionWeekInterval(containing: now), context: context)
        case .monthlyTotal:
            return totalForGoal(goal, in: monthInterval(containing: now), context: context)
        case .consistency, .maintainBaseline, .improveBalance, .custom:
            let interval = goalDateInterval(for: goal, now: now)
            return totalForGoal(goal, in: interval, context: context)
        }
    }

    private static func totalForGoal(_ goal: Goal, in interval: DateInterval, context: ModelContext) -> Double {
        let allLogs = (try? fetchLogs(context: context)) ?? []
        let filtered = allLogs.filter { log in
            guard interval.contains(log.date) else { return false }
            if let habitID = goal.linkedHabitID {
                return log.habit?.id == habitID
            }
            if let statKey = goal.linkedStatKey {
                return log.habit?.statDomain?.statKey == statKey
            }
            return true
        }
        return filtered.reduce(0) { $0 + $1.numericValue }
    }

    private static func goalDateInterval(for goal: Goal, now: Date) -> DateInterval {
        let start = goal.startDate
        let end = goal.endDate ?? now
        if end <= start {
            return DateInterval(start: start, end: max(now, start))
        }
        return DateInterval(start: start, end: end)
    }

    private static func monthInterval(containing date: Date) -> DateInterval {
        let calendar = progressionCalendar()
        let comps = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: comps) ?? date
        let endExclusive = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        return DateInterval(start: start, end: endExclusive)
    }

    private static func goalPaceStatus(goal: Goal, currentValue: Double, target: Double, now: Date) -> GoalPaceStatus {
        if goal.status == .completed || (target > 0 && currentValue >= target) {
            return .complete
        }
        guard target > 0 else { return .onPace }

        let interval = goalDateInterval(for: goal, now: now)
        let totalDuration = interval.duration
        guard totalDuration > 0 else { return .onPace }

        let elapsed = max(min(now.timeIntervalSince(interval.start), totalDuration), 0)
        let expectedRatio = elapsed / totalDuration
        let actualRatio = currentValue / target

        if actualRatio >= expectedRatio + 0.15 {
            return .ahead
        }
        if actualRatio >= expectedRatio - 0.05 {
            return .onPace
        }
        if actualRatio >= expectedRatio - 0.20 {
            return .atRisk
        }
        return .behind
    }

    private static func goalTimeRemainingLabel(for goal: Goal, now: Date) -> String {
        guard let endDate = goal.endDate else { return "Ongoing" }
        let remaining = endDate.timeIntervalSince(now)
        if remaining <= 0 { return "Ended" }
        let days = Int(remaining / 86_400)
        if days >= 14 {
            let weeks = days / 7
            return "\(weeks) weeks left"
        }
        if days >= 1 {
            return "\(days)d left"
        }
        let hours = Int(remaining / 3_600)
        return "\(max(hours, 1))h left"
    }

    private static func goalStatusLabel(goal: Goal, currentValue: Double, target: Double, paceStatus: GoalPaceStatus) -> String {
        switch goal.status {
        case .completed:
            return "Completed"
        case .paused:
            return "Paused"
        case .archived:
            return "Archived"
        case .failed:
            return "Missed"
        case .active:
            if target > 0, currentValue >= target {
                return "Target met"
            }
            return paceStatus.label
        }
    }

    static func modelCounts(context: ModelContext) -> ModelCounts {
        ModelCounts(
            stats: ((try? context.fetch(FetchDescriptor<StatDomain>())) ?? []).count,
            habits: ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).count,
            logs: ((try? context.fetch(FetchDescriptor<HabitLog>())) ?? []).count,
            weeklyResolutions: ((try? context.fetch(FetchDescriptor<WeeklyResolution>())) ?? []).count,
            settings: ((try? context.fetch(FetchDescriptor<AppSettings>())) ?? []).count,
            healthImports: ((try? context.fetch(FetchDescriptor<HealthImportedWorkout>())) ?? []).count,
            goals: ((try? context.fetch(FetchDescriptor<Goal>())) ?? []).count
        )
    }

    static func seedDefaultProfile(
        context: ModelContext,
        baselines: [StatKey: Int] = [:],
        selectedHabitKeys: Set<String> = [],
        completeOnboarding: Bool = true
    ) throws {
        guard try fetchStats(context: context).isEmpty else {
            try synchronizeCatalog(context: context)
            let settings = try fetchSettings(context: context)
            settings.hasCompletedOnboarding = completeOnboarding
            settings.updatedAt = .now
            try context.save()
            recordLocalWrite(reason: "updated existing default profile during onboarding")
            try refreshWidgetSnapshot(context: context)
            return
        }

        var statIndex: [StatKey: StatDomain] = [:]
        for (offset, template) in TrainingArcConfig.statTemplates.enumerated() {
            let baseline = max(TrainingArcConfig.minimumBaseline, baselines[template.key] ?? template.defaultBaseline)
            let startingLevel = TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(baseline))
            let stat = StatDomain(
                key: template.key.rawValue,
                name: template.key.displayName,
                iconName: template.iconName,
                colorToken: template.colorToken,
                descriptor: TrainingArcConfig.overview(for: template.key),
                sortOrder: offset,
                currentLevel: startingLevel,
                currentTierName: TrainingArcConfig.rankTitle(for: template.key, level: startingLevel),
                startingBaseline: baseline,
                currentBaseline: baseline,
                storedCharges: 0,
                bankedProgressUnits: 0,
                lastAcknowledgedLevel: startingLevel,
                isArchived: !template.isCore,
                isCore: template.isCore,
                isEnabled: template.isCore,
                parentSkillKeyRaw: template.parentKey?.rawValue
            )
            updateDerivedFields(for: stat)
            context.insert(stat)
            statIndex[template.key] = stat
        }

        // Only core skills get a starter habit by default. Optional skills start
        // archived; enabling one later creates its habit (see enableSkill).
        let coreStatKeys = Set(TrainingArcConfig.coreSkillKeys.map(\.rawValue))
        let selectedKeys = selectedHabitKeys.isEmpty ? Set(TrainingArcConfig.defaultHabitTemplates.map(\.systemKey)) : selectedHabitKeys

        for (offset, template) in TrainingArcConfig.defaultHabitTemplates.enumerated()
        where selectedKeys.contains(template.systemKey) && coreStatKeys.contains(template.statKey.rawValue) {
            let habit = Habit(
                systemKey: template.systemKey,
                name: template.name,
                notes: template.notes,
                measurementType: template.measurementType,
                unitLabel: template.unitLabel,
                scheduleType: template.scheduleType,
                targetPerPeriod: template.targetPerPeriod,
                active: true,
                sortOrder: offset,
                statDomain: statIndex[template.statKey]
            )
            context.insert(habit)
        }

        let settings = try fetchSettings(context: context)
        settings.hasCompletedOnboarding = completeOnboarding
        settings.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "seeded default onboarding profile")
        try refreshAllProgress(context: context, reason: .onboarding)
        try refreshWidgetSnapshot(context: context)
    }

    static func clearAll(context: ModelContext) throws {
        for item in try fetchImportedHealthWorkouts(context: context) { context.delete(item) }
        for item in try fetchLogs(context: context) { context.delete(item) }
        for item in try fetchResolutions(context: context) { context.delete(item) }
        for item in try fetchGoals(context: context) { context.delete(item) }
        for item in try fetchHabits(context: context) { context.delete(item) }
        for item in try fetchStats(context: context) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<AppSettings>()) { context.delete(item) }
        try context.save()
        recordLocalWrite(reason: "cleared all local SwiftData records")
        let defaults = UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
        defaults.removeObject(forKey: AppIdentity.healthWorkoutAnchorKey)
        defaults.removeObject(forKey: "training.arc.health.lastYearBackfillAt")
        try refreshWidgetSnapshot(context: context)
    }

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

    fileprivate static func priorHealthImportAssignments(from records: [HealthImportedWorkout]) -> [String: String] {
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

    fileprivate static func healthImportAssignmentKey(statKeyRaw: String, activityTypeRaw: Int) -> String {
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

    static func updateDerivedFields(for stat: StatDomain) {
        guard let key = stat.statKey else { return }
        let resolvedLevel = TrainingArcConfig.clampedRankLevel(stat.currentLevel)
        let resolvedTitle = TrainingArcConfig.rankTitle(for: key, level: resolvedLevel)
        let resolvedDescriptor = TrainingArcConfig.overview(for: key)
        let didMutate =
            stat.currentLevel != resolvedLevel ||
            stat.currentTierName != resolvedTitle ||
            stat.descriptor != resolvedDescriptor

        stat.rankLevel = resolvedLevel
        stat.rankTitle = resolvedTitle
        stat.descriptor = resolvedDescriptor
        stat.chargeValue = DashboardChargeDots.clampedCharge(stat.chargeValue)
        stat.acknowledgedRankLevel = max(stat.acknowledgedRankLevel, TrainingArcConfig.minimumRankLevel)

        if didMutate {
            stat.updatedAt = .now
        }
    }

    static func synchronizeCatalog(context: ModelContext) throws {
        let existingStats = try fetchStats(context: context)
        guard !existingStats.isEmpty else { return }

        var didMutate = false
        var statLookup = Dictionary(uniqueKeysWithValues: existingStats.compactMap { stat -> (StatKey, StatDomain)? in
            guard let key = stat.statKey else { return nil }
            return (key, stat)
        })

        for template in TrainingArcConfig.statTemplates {
            if let existing = statLookup[template.key] {
                let parentRaw = template.parentKey?.rawValue
                let didChange =
                    existing.name != template.key.displayName ||
                    existing.iconName != template.iconName ||
                    existing.colorToken != template.colorToken ||
                    existing.isCore != template.isCore ||
                    existing.parentSkillKeyRaw != parentRaw
                existing.name = template.key.displayName
                existing.iconName = template.iconName
                existing.colorToken = template.colorToken
                existing.isCore = template.isCore
                existing.parentSkillKeyRaw = parentRaw
                updateDerivedFields(for: existing)
                didMutate = didMutate || didChange
                continue
            }

            let nextSortOrder = (statLookup.values.map(\.sortOrder).max() ?? -1) + 1
            let stat = StatDomain(
                key: template.key.rawValue,
                name: template.key.displayName,
                iconName: template.iconName,
                colorToken: template.colorToken,
                descriptor: TrainingArcConfig.overview(for: template.key),
                sortOrder: nextSortOrder,
                currentLevel: TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(template.defaultBaseline)),
                currentTierName: TrainingArcConfig.rankTitle(
                    for: template.key,
                    level: TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(template.defaultBaseline))
                ),
                startingBaseline: template.defaultBaseline,
                currentBaseline: template.defaultBaseline,
                storedCharges: 0,
                bankedProgressUnits: 0,
                lastAcknowledgedLevel: TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(template.defaultBaseline)),
                isArchived: !template.isCore,
                isCore: template.isCore,
                isEnabled: template.isCore,
                parentSkillKeyRaw: template.parentKey?.rawValue
            )
            updateDerivedFields(for: stat)
            context.insert(stat)
            statLookup[template.key] = stat
            didMutate = true

            // Optional skills are created archived with no habit; enabling one
            // later creates its starter habit on demand.
            if template.isCore {
                let starter = TrainingArcConfig.definition(for: template.key).starterHabit
                let habit = Habit(
                    systemKey: starter.systemKey,
                    name: starter.name,
                    notes: starter.notes,
                    measurementType: starter.measurementType,
                    unitLabel: starter.unitLabel,
                    scheduleType: starter.scheduleType,
                    targetPerPeriod: starter.targetPerPeriod,
                    active: true,
                    sortOrder: (try? fetchHabits(context: context).count) ?? 0,
                    statDomain: stat
                )
                context.insert(habit)
            }
        }

        if didMutate {
            try context.save()
            recordLocalWrite(reason: "synchronized catalog")
            try refreshAllProgress(context: context, reason: .appRefresh)
        }
    }

    @discardableResult
    static func log(
        habit: Habit,
        value: Double,
        date: Date,
        sessionType: String? = nil,
        note: String,
        source: LogSourceType,
        healthWorkoutUUID: String? = nil,
        context: ModelContext
    ) throws -> HabitLog {
        let numericValue = habit.measurementType == .booleanSession ? 1 : max(0, value)
        let log = HabitLog(
            date: date,
            numericValue: numericValue,
            sessionType: normalizedSessionType(sessionType),
            note: note,
            sourceType: source,
            healthWorkoutUUID: healthWorkoutUUID,
            habit: habit
        )
        habit.updatedAt = .now
        context.insert(log)
        try context.save()
        recordLocalWrite(reason: "logged habit entry")
        if let stat = habit.statDomain {
            try refreshProgress(for: stat, context: context, reason: .logMutation, now: max(date, .now))
        }
        try refreshWidgetSnapshot(context: context)
        return log
    }

    static func delete(_ log: HabitLog, context: ModelContext) throws {
        let stat = log.habit?.statDomain
        let affectedDate = log.date
        context.delete(log)
        try context.save()
        recordLocalWrite(reason: "deleted habit entry")
        if let stat {
            try refreshProgress(for: stat, context: context, reason: .deleteMutation, now: max(affectedDate, .now))
        }
        try refreshWidgetSnapshot(context: context)
    }

    static func total(for habit: Habit, in interval: DateInterval) -> Double {
        (habit.logs ?? [])
            .filter { interval.contains($0.date) }
            .reduce(0) { $0 + $1.numericValue }
    }

    static func total(for stat: StatDomain, in interval: DateInterval) -> Double {
        (stat.habits ?? [])
            .filter(\.active)
            .reduce(0) { total, habit in
                total + self.total(for: habit, in: interval)
            }
    }

    static func activeHabits(for stat: StatDomain) -> [Habit] {
        (stat.habits ?? [])
            .filter(\.active)
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    static func primaryHabit(for stat: StatDomain) -> Habit? {
        activeHabits(for: stat).first
    }

    static func recentLogs(for stat: StatDomain) -> [HabitLog] {
        activeHabits(for: stat)
            .flatMap { $0.logs ?? [] }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.date > rhs.date
            }
    }

    static func recentLogSnapshots(
        for stat: StatDomain,
        limit: Int? = nil,
        since: Date? = nil,
        context: ModelContext? = nil
    ) -> [SkillLogEntrySnapshot] {
        let logs = recentLogs(for: stat)
            .filter { log in
                guard let since else { return true }
                return log.date >= since
            }
        let trimmed = limit.map { Array(logs.prefix($0)) } ?? logs
        let resolver = context.map { healthAttributionContext(context: $0) }
        return trimmed.map { logSnapshot(for: $0, resolver: resolver) }
    }

    static func logSnapshot(for log: HabitLog, resolver: HealthAttributionContext? = nil) -> SkillLogEntrySnapshot {
        SkillLogEntrySnapshot(
            id: log.id,
            habitName: log.habit?.name ?? "Session",
            valueLabel: MetricFormatting.metric(log.numericValue, unit: log.habit?.unitLabel ?? ""),
            date: log.date,
            note: log.note,
            sessionType: normalizedSessionType(log.sessionType),
            sourceType: log.sourceType,
            healthAttribution: resolver?.attribution(for: log)
        )
    }

    /// Snapshot of Apple Health import metadata, prepared once and reused across
    /// many logs so per-row attribution stays cheap. Built on the main actor and
    /// kept entirely out of the value-type snapshots it produces.
    struct HealthAttributionContext {
        var recordsByUUID: [String: HealthImportedWorkout]
        var recordsByHabitKey: [String: [HealthImportedWorkout]]
        var statsByKey: [String: StatDomain]
        var goalAffectsAllSkills: Bool
        var goalSkillKeys: Set<String>
        var goalHabitIDs: Set<UUID>

        @MainActor
        func attribution(for log: HabitLog) -> HealthLogAttribution? {
            guard log.sourceType == .health else { return nil }

            let record = matchedRecord(for: log)
            let statKeyRaw = record?.statKeyRaw ?? log.habit?.statDomain?.statKey?.rawValue ?? ""
            let stat = statsByKey[statKeyRaw]
            let skillName = stat?.name
                ?? StatKey(rawValue: statKeyRaw)?.displayName
                ?? "Workout"
            let colorToken = stat?.colorToken ?? (statKeyRaw.isEmpty ? "focus" : statKeyRaw)

            let countedTowardWeekly = record.map { $0.wasImported && !$0.isDuplicate } ?? true
            let ignoredAsDuplicate = record?.isDuplicate ?? false
            let needsReview = record?.overlapsImportedWorkout ?? false
            let sourceName = record?.sourceName

            return HealthLogAttribution(
                sourceAppName: (sourceName?.isEmpty == false) ? sourceName : nil,
                mappedSkillName: skillName,
                mappedSkillColorToken: colorToken,
                sessionType: TrainingStore.normalizedSessionType(log.sessionType),
                durationMinutes: record?.durationMinutes ?? 0,
                countedTowardWeeklyProgress: countedTowardWeekly && !ignoredAsDuplicate,
                ignoredAsDuplicate: ignoredAsDuplicate,
                needsReview: needsReview,
                affectedGoal: affectsGoal(statKeyRaw: statKeyRaw, habitID: log.habit?.id)
            )
        }

        private func matchedRecord(for log: HabitLog) -> HealthImportedWorkout? {
            if let uuid = log.healthWorkoutUUID, let record = recordsByUUID[uuid] {
                return record
            }
            guard let habitKey = log.habit?.systemKey else { return nil }
            return recordsByHabitKey[habitKey]?
                .filter { abs($0.endDate.timeIntervalSince(log.date)) < 120 }
                .min { abs($0.endDate.timeIntervalSince(log.date)) < abs($1.endDate.timeIntervalSince(log.date)) }
        }

        private func affectsGoal(statKeyRaw: String, habitID: UUID?) -> Bool {
            if goalAffectsAllSkills { return true }
            if !statKeyRaw.isEmpty, goalSkillKeys.contains(statKeyRaw) { return true }
            if let habitID, goalHabitIDs.contains(habitID) { return true }
            return false
        }
    }

    /// Goal types whose progress is derived by summing logs (so a fresh log can
    /// "affect" them). Level/rank goals read the stat directly, not the logs.
    private static let logDerivedGoalTypes: Set<GoalType> = [
        .weeklyTarget, .monthlyTotal, .consistency, .maintainBaseline, .improveBalance, .custom
    ]

    static func healthAttributionContext(context: ModelContext) -> HealthAttributionContext {
        let records = (try? fetchImportedHealthWorkouts(context: context)) ?? []
        let recordsByUUID = Dictionary(records.map { ($0.workoutUUID, $0) }) { lhs, _ in lhs }
        let recordsByHabitKey = Dictionary(grouping: records.compactMap { record -> (String, HealthImportedWorkout)? in
            guard let key = record.habitSystemKey else { return nil }
            return (key, record)
        }, by: \.0).mapValues { $0.map(\.1) }

        let stats = (try? fetchStats(context: context)) ?? []
        let statsByKey = Dictionary(stats.compactMap { stat -> (String, StatDomain)? in
            guard let key = stat.statKey?.rawValue else { return nil }
            return (key, stat)
        }) { lhs, _ in lhs }

        let activeGoals = ((try? fetchGoals(context: context)) ?? [])
            .filter { $0.status == .active && logDerivedGoalTypes.contains($0.type) }
        let goalAffectsAllSkills = activeGoals.contains { $0.linkedStatKey == nil && $0.linkedHabitID == nil }
        let goalSkillKeys = Set(activeGoals.compactMap { $0.linkedStatKey?.rawValue })
        let goalHabitIDs = Set(activeGoals.compactMap { $0.linkedHabitID })

        return HealthAttributionContext(
            recordsByUUID: recordsByUUID,
            recordsByHabitKey: recordsByHabitKey,
            statsByKey: statsByKey,
            goalAffectsAllSkills: goalAffectsAllSkills,
            goalSkillKeys: goalSkillKeys,
            goalHabitIDs: goalHabitIDs
        )
    }

    static func progressionCalendar() -> Calendar {
        WeekMath.calendar(weekStartsOnMonday: true)
    }

    static func progressionWeek(containing date: Date) -> WeekRange {
        WeekMath.weekRange(containing: date, weekStartsOnMonday: true)
    }

    static func progressionWeekInterval(containing date: Date) -> DateInterval {
        WeekMath.dateInterval(for: progressionWeek(containing: date), calendar: progressionCalendar())
    }

    static func currentWeekInterval(settings: AppSettings?, now: Date = .now) -> DateInterval {
        progressionWeekInterval(containing: now)
    }

    static func currentWeekTotal(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Double {
        total(for: stat, in: currentWeekInterval(settings: settings, now: now))
    }

    static func currentCharge(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Int {
        stat.chargeValue
    }

    static func currentChargeProgress(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Double {
        guard let key = stat.statKey else { return 0 }
        return TrainingArcConfig.chargeProgress(for: key, bankedUnits: stat.bankedProgressUnits, level: stat.rankLevel)
    }

    static func weeklyCounterLabel(for stat: StatDomain) -> String {
        switch primaryHabit(for: stat)?.measurementType {
        case .booleanSession:
            return "Weekly Sessions"
        case .pages:
            return "Weekly Pages"
        case .minutes:
            return "Weekly Minutes"
        case .count:
            return "Weekly Count"
        case .customNumber:
            return "Weekly Progress"
        case .none:
            return "Weekly Total"
        }
    }

    static func weeklyCounterValueLabel(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> String {
        let actual = currentWeekTotal(for: stat, settings: settings, now: now)
        return "\(MetricFormatting.shortMetric(actual)) / \(MetricFormatting.shortMetric(Double(stat.currentBaseline)))"
    }

    static func weeklyUnitLabel(for stat: StatDomain) -> String {
        switch primaryHabit(for: stat)?.measurementType {
        case .booleanSession:
            return "sessions"
        case .pages:
            return "pages"
        case .minutes:
            return "minutes"
        case .count:
            return "counts"
        case .customNumber:
            return "points"
        case .none:
            return "logs"
        }
    }

    static func nextEvaluationLabel(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE 'at' HH:mm"
        return "Resolves \(formatter.string(from: nextWeeklyEvaluationDate(now: now)))"
    }

    static func bankCountdownLabel(now: Date = .now) -> String {
        let evaluationDate = nextWeeklyEvaluationDate(now: now)
        let remaining = max(Int(evaluationDate.timeIntervalSince(now)), 0)
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return "Resolves in \(days)d \(hours)h"
        }
        if hours > 0 {
            return "Resolves in \(hours)h \(minutes)m"
        }
        return "Resolves in \(max(minutes, 1))m"
    }

    static func nextWeeklyEvaluationDate(now: Date = .now) -> Date {
        let currentWeek = progressionWeek(containing: now)
        let calendar = progressionCalendar()
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: currentWeek.end) ?? currentWeek.end
        return calendar.date(byAdding: .second, value: -1, to: endExclusive) ?? endExclusive
    }

    static func chargeExplanation(
        for stat: StatDomain,
        chargeValue: Int,
        nextRank: RankLevelDefinition?,
        now: Date = .now
    ) -> String {
        guard let statKey = stat.statKey else {
            return "Charge moves 1 step toward zero each completed week, then your latest week adds or removes charge."
        }

        let currentLevel = stat.rankLevel
        let currentTarget = TrainingArcConfig.effectiveWeeklyTarget(for: statKey, level: currentLevel)
        let nextTarget = TrainingArcConfig.nextRankChargeRequirement(for: statKey, level: currentLevel)
        let lowerTarget = TrainingArcConfig.previousRankChargeRequirement(for: statKey, level: currentLevel)
        let positiveStep = TrainingArcConfig.positiveChargeStep(for: statKey, level: currentLevel)
        let negativeStep = TrainingArcConfig.negativeChargeStep(for: statKey, level: currentLevel)
        let unitSingular = singularWeeklyUnitLabel(for: stat)

        if let nextTarget, let lowerTarget, let positiveStep, let negativeStep {
            let positiveExample = currentTarget + (positiveStep * 2)
            let negativeExample = max(currentTarget - (negativeStep * 2), 0)

            return """
            Level \(currentLevel) is based on \(currentTarget) \(pluralize(unitSingular, count: currentTarget)) per week. Level \(currentLevel + 1) starts at \(nextTarget), so every \(positiveStep) \(pluralize(unitSingular, count: positiveStep)) above \(currentTarget) adds +1 charge. Level \(currentLevel - 1) starts at \(lowerTarget), so every \(negativeStep) \(pluralize(unitSingular, count: negativeStep)) below \(currentTarget) adds -1 charge. Example: \(positiveExample) \(pluralize(unitSingular, count: positiveExample)) this week is +2 charge, while \(negativeExample) is -2 charge. At the end of each completed week charge decays 1 step toward zero. +4 ranks you up and -4 ranks you down.
            """
        }

        if let nextTarget, let positiveStep {
            return "Level \(currentLevel) is based on \(currentTarget) \(pluralize(unitSingular, count: currentTarget)) per week. Level \(currentLevel + 1) starts at \(nextTarget), so every \(positiveStep) \(pluralize(unitSingular, count: positiveStep)) above \(currentTarget) adds +1 charge. Charge still decays 1 step toward zero each completed week."
        }

        if let lowerTarget, let negativeStep {
            let nextRankText = nextRank?.title ?? "this rank"
            return "You are already at the maximum rank, \(nextRankText). Level \(currentLevel) is held by \(currentTarget) \(pluralize(unitSingular, count: currentTarget)) per week, and every \(negativeStep) \(pluralize(unitSingular, count: negativeStep)) below that adds -1 charge toward the \(lowerTarget)-\(pluralize(unitSingular, count: lowerTarget)) tier. Negative charge still decays 1 step toward zero each completed week."
        }

        return "This opening rank only builds upward. Charge decays 1 step toward zero at the end of each completed week."
    }

    static func pacingStatus(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> SkillPacingStatus {
        let actual = currentWeekTotal(for: stat, settings: settings, now: now)
        let baseline = Double(stat.currentBaseline)

        guard baseline > 0 else {
            return actual > 0 ? .ahead : .onPace
        }

        let ratio = actual / baseline
        switch ratio {
        case ..<0.7:
            return .behind
        case ..<1.05:
            return .onPace
        default:
            return .ahead
        }
    }

    static func focusState(
        for stat: StatDomain,
        settings: AppSettings?,
        chargeProgress: Double,
        now: Date = .now
    ) -> SkillEngagementState {
        if stat.pendingRankChange != nil {
            return .pendingRankChange
        }

        if stat.chargeValue <= -2 {
            return .behindTarget
        }
        let pacing = pacingStatus(for: stat, settings: settings, now: now)
        if pacing == .behind {
            return .behindTarget
        }
        if chargeProgress >= 0.72 {
            return .nearCharge
        }
        if pacing == .ahead {
            return .aheadOfTarget
        }
        return .neutral
    }

    private static func progressUnitLabel(for stat: StatDomain) -> String {
        guard let habit = primaryHabit(for: stat) else { return "entry" }

        switch habit.measurementType {
        case .booleanSession:
            return "session"
        case .pages:
            return "page"
        case .minutes:
            return "minute"
        case .count, .customNumber:
            return habit.unitLabel.isEmpty ? "point" : habit.unitLabel
        }
    }

    static func nextRankStatusLabel(
        for stat: StatDomain,
        chargeValue: Int,
        nextRank: RankLevelDefinition?
    ) -> String {
        let chargeLimit = DashboardChargeDots.slotsPerSide

        if chargeValue <= -(chargeLimit - 1), stat.rankLevel > TrainingArcConfig.minimumRankLevel {
            let remainingDebt = chargeLimit - abs(chargeValue)
            let nextLowerLevel = max(stat.rankLevel - 1, TrainingArcConfig.minimumRankLevel)
            return remainingDebt == 1
                ? "One more weak week will drop \(stat.name) to Level \(nextLowerLevel)."
                : "\(remainingDebt) more negative charge steps will drop this skill a rank."
        }

        guard let nextRank else { return "You have reached the current maximum rank." }
        let remaining = max(chargeLimit - max(chargeValue, 0), 0)
        if remaining == 0 {
            return "The next completed week will resolve this skill into \(nextRank.title)."
        }
        let unit = remaining == 1 ? "charge step" : "charge steps"
        return "\(remaining) more positive \(unit) will unlock \(nextRank.title)."
    }

    static func nextActionLabel(
        for stat: StatDomain,
        settings: AppSettings?,
        nextRank: RankLevelDefinition?,
        chargeValue: Int,
        now: Date = .now
    ) -> String {
        if let pending = stat.pendingRankChange {
            return pending.direction == .up ? "Open this skill to reveal the new rank." : "Open this skill to review the rank drop."
        }

        let actual = currentWeekTotal(for: stat, settings: settings, now: now)
        let baseline = Double(stat.currentBaseline)
        let unitLabel = progressUnitLabel(for: stat)

        if baseline > 0, actual < baseline {
            let needed = MetricFormatting.shortMetric(baseline - actual)
            let suffix = needed == "1" ? unitLabel : "\(unitLabel)s"
            return "Log \(needed) more \(suffix) this week to stay on pace."
        }

        if nextRank == nil {
            if chargeValue < 0 {
                return "A steadier week will pull this charge back toward zero."
            }
            return "Keep matching this pace to hold the maximum rank."
        }

        let remainingCharges = max(DashboardChargeDots.slotsPerSide - max(chargeValue, 0), 0)
        if remainingCharges == 0 {
            return "Hold a strong week to convert this rank-up."
        }
        if remainingCharges == 1 {
            return "One more strong week can land the final positive charge."
        }

        let pacing = pacingStatus(for: stat, settings: settings, now: now)
        if pacing == .ahead {
            return "You are ahead of pace. Keep stacking surplus for more positive charge."
        }

        return "\(remainingCharges) more positive charge steps stand between you and \(nextRank?.title ?? "the next rank")."
    }

    static func normalizedSessionType(_ sessionType: String?) -> String? {
        guard let trimmed = sessionType?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func weekSnapshot(
        for stat: StatDomain,
        week: WeekRange,
        now: Date = .now,
        context: ModelContext? = nil
    ) -> SkillWeekSnapshot {
        let calendar = progressionCalendar()
        let interval = WeekMath.dateInterval(for: week, calendar: calendar)
        let logs = activeHabits(for: stat)
            .flatMap { $0.logs ?? [] }
            .filter { interval.contains($0.date) }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.date > rhs.date
            }

        let daySummaries: [DayLogSummary] = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let dayInterval = DateInterval(
                start: calendar.startOfDay(for: date),
                end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
            )
            let dayLogs = logs.filter { dayInterval.contains($0.date) }
            let total = dayLogs.reduce(0) { $0 + $1.numericValue }
            return DayLogSummary(
                date: date,
                totalValue: total,
                logCount: dayLogs.count,
                totalLabel: MetricFormatting.shortMetric(total),
                isToday: calendar.isDateInToday(date)
            )
        }

        let total = logs.reduce(0) { $0 + $1.numericValue }
        let resolver = context.map { healthAttributionContext(context: $0) }
        return SkillWeekSnapshot(
            week: week,
            daySummaries: daySummaries,
            totalValue: total,
            totalLabel: MetricFormatting.shortMetric(total),
            logEntries: logs.map { logSnapshot(for: $0, resolver: resolver) }
        )
    }

    static func progressSnapshot(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> SkillProgressSnapshot {
        let definition = stat.statKey.map { TrainingArcConfig.definition(for: $0) } ?? TrainingArcConfig.habitDefinitions[0]
        let currentLevel = stat.rankLevel
        let currentRank = TrainingArcConfig.rankDefinition(for: definition.key, level: currentLevel)
        let nextRank = TrainingArcConfig.nextRankDefinition(for: definition.key, level: currentLevel)
        let currentWeekActual = currentWeekTotal(for: stat, settings: settings, now: now)
        let chargeValue = currentCharge(for: stat, settings: settings, now: now)
        let chargeProgress = currentChargeProgress(for: stat, settings: settings, now: now)
        let pacing = pacingStatus(for: stat, settings: settings, now: now)
        let chargeMaximum = DashboardChargeDots.slotsPerSide
        let focusState = focusState(for: stat, settings: settings, chargeProgress: chargeProgress, now: now)
        let weeklyTarget = max(Double(stat.currentBaseline), 1)
        let weeklyTargetProgress = min(max(currentWeekActual / weeklyTarget, 0), 1)
        let rankChangeIndicatorVisible = stat.pendingRankChange != nil && stat.pendingRankChangeViewedAt == nil

        return SkillProgressSnapshot(
            rank: RankSnapshot(
                level: currentLevel,
                maximumLevel: TrainingArcConfig.maximumRankLevel,
                title: currentRank.title,
                nextTitle: nextRank?.title,
                progressValue: Double(max(chargeValue, 0)),
                progressValueLabel: DashboardChargeDots.summaryLabel(for: chargeValue),
                progressRequiredLabel: nextRank == nil ? "Maximum rank" : "\(chargeMaximum) positive charge steps",
                progressToNextLevel: chargeProgress,
                isAtMaximumRank: currentLevel >= TrainingArcConfig.maximumRankLevel,
                image: currentRank.image
            ),
            charge: ChargeSnapshot(
                current: chargeValue,
                maximum: chargeMaximum,
                progress: chargeProgress,
                label: definition.charge.label
            ),
            overview: definition.overview,
            currentWeekActual: currentWeekActual,
            baseline: stat.currentBaseline,
            bankedProgressUnits: stat.bankedProgressUnits,
            nextEvaluationDate: nextWeeklyEvaluationDate(now: now),
            pendingRankChange: stat.pendingRankChange,
            rankChangeIndicatorVisible: rankChangeIndicatorVisible,
            weeklyTargetProgress: weeklyTargetProgress,
            weeklyCounterLabel: weeklyCounterLabel(for: stat),
            weeklyCounterValueLabel: weeklyCounterValueLabel(for: stat, settings: settings, now: now),
            chargeExplanation: chargeExplanation(
                for: stat,
                chargeValue: chargeValue,
                nextRank: nextRank,
                now: now
            ),
            nextEvaluationLabel: nextEvaluationLabel(now: now),
            nextRankImage: nextRank.map { _ in
                TrainingArcConfig.progressionImage(
                    for: definition.key,
                    level: currentLevel + 1,
                    currentLevel: currentLevel
                ) ?? nextRank?.image
            } ?? nil,
            bankedChargeLabel: nextRank == nil && chargeValue == 0
                ? "Stable at maximum rank"
                : DashboardChargeDots.summaryLabel(for: chargeValue),
            nextRankStatusLabel: nextRankStatusLabel(
                for: stat,
                chargeValue: chargeValue,
                nextRank: nextRank
            ),
            focusState: focusState,
            nextActionLabel: nextActionLabel(
                for: stat,
                settings: settings,
                nextRank: nextRank,
                chargeValue: chargeValue,
                now: now
            ),
            pacingStatus: pacing,
            bankCountdownLabel: bankCountdownLabel(now: now)
        )
    }

    static func dashboardCardPreview(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> DashboardCardPreview {
        let snapshot = progressSnapshot(for: stat, settings: settings, now: now)
        let definition = stat.statKey.map { TrainingArcConfig.definition(for: $0) } ?? TrainingArcConfig.habitDefinitions[0]
        let weeklyTarget = TrainingArcConfig.effectiveWeeklyTarget(for: definition.key, level: stat.rankLevel)
        let nextRequirement = TrainingArcConfig.nextRankChargeRequirement(for: definition.key, level: stat.rankLevel)
        let currentWeekValue = currentWeekTotal(for: stat, settings: settings, now: now)
        let remainingToTarget = max(Double(stat.currentBaseline) - currentWeekValue, 0)
        let unitLabel = weeklyUnitLabel(for: stat)
        let bankedChargeSummary = DashboardChargeDots.summaryLabel(for: snapshot.charge.current)
        let stayOnTargetSummary: String = {
            if remainingToTarget <= 0 {
                return "On target this week"
            }
            return "\(MetricFormatting.shortMetric(remainingToTarget)) \(unitLabel) needed to stay on target"
        }()
        let levelUpSummary: String = {
            guard let nextRequirement else { return "No further level-ups available" }
            return "\(nextRequirement) \(unitLabel) per week needed to level up"
        }()

        return DashboardCardPreview(
            rankSummary: "LV \(snapshot.rank.level) · \(snapshot.rank.title)",
            bankedChargeSummary: bankedChargeSummary,
            stayOnTargetSummary: stayOnTargetSummary,
            weeklyTargetSummary: "\(weeklyTarget) \(unitLabel) weekly target",
            levelUpSummary: levelUpSummary
        )
    }

    static func refreshAllProgress(
        context: ModelContext,
        reason: RankChangeReason,
        now: Date = .now
    ) throws {
        _ = try? applyAutomaticGoalTransitions(context: context, now: now)
        let stats = try fetchActiveStats(context: context)
        var didChange = false

        for stat in stats {
            if try refreshProgress(for: stat, context: context, reason: reason, now: now, autosave: false) {
                didChange = true
            }
        }

        if didChange || context.hasChanges {
            try context.save()
            recordLocalWrite(reason: "refreshed all progress")
        }
    }

    @discardableResult
    static func refreshProgress(
        for stat: StatDomain,
        context: ModelContext,
        reason: RankChangeReason,
        now: Date = .now,
        autosave: Bool = true
    ) throws -> Bool {
        guard let statKey = stat.statKey else { return false }

        let previousLevel = stat.rankLevel
        let previousBaseline = stat.currentBaseline
        let previousCharge = stat.chargeValue
        let previousBankedUnits = stat.bankedProgressUnits
        let previousResolvedWeek = stat.lastResolvedWeekStart
        let previousPending = stat.pendingRankChange
        let existingResolutions = stat.weeklyResolutions ?? []
        let hadExistingResolutions = !existingResolutions.isEmpty

        for resolution in existingResolutions {
            context.delete(resolution)
        }

        var state = ProgressionEngine.initialState(for: statKey, startingBaseline: stat.startingBaseline)
        let completedWeeks = completedProgressionWeeks(for: stat, now: now)
        let settings = (try? fetchExistingSettings(context: context))
        let influenceEnabled = settings?.goalsCanAffectProgression ?? false
        let goalsForStat: [Goal] = influenceEnabled ? ((try? fetchGoals(for: statKey, context: context)) ?? []) : []
        let allowRankDown = settings?.regressionBehavior.allowsRankDown ?? true

        for week in completedWeeks {
            let actual = total(for: stat, in: WeekMath.dateInterval(for: week, calendar: progressionCalendar()))
            let activeGoal = activeWeeklyGoal(for: goalsForStat, week: week)
            let result = ProgressionEngine.evaluateWeek(
                statKey: statKey,
                state: state,
                actualTotal: actual,
                activeGoalTarget: activeGoal.map { Int($0.targetValue.rounded()) },
                isRecoveryGoal: activeGoal?.isRecoveryMode ?? false,
                allowRankDown: allowRankDown
            )
            let resolution = WeeklyResolution(
                statKey: stat.key,
                statName: stat.name,
                weekStartDate: week.start,
                weekEndDate: week.end,
                baselineAtStart: state.expectedWeeklyTarget,
                expectedTotal: result.expectedTotal,
                actualCompletedValue: result.actualTotal,
                weeklyDelta: result.weeklyDelta,
                excessValue: result.weeklyDelta,
                chargesEarned: result.weeklyChargeDelta,
                chargesSpentOnLevelUp: (result.didLevelUp || result.didLevelDown) ? DashboardChargeDots.slotsPerSide : 0,
                bankedUnitsBefore: result.bankedUnitsBefore,
                bankedUnitsAfter: result.bankedUnitsAfter,
                levelBefore: result.levelBefore,
                levelAfter: result.levelAfter,
                storedChargesAfter: result.visibleChargesAfter,
                didDecay: result.didDecayTowardZero,
                didLevelUp: result.didLevelUp,
                didStagnate: result.weeklyChargeDelta == 0,
                didRegress: result.didLevelDown,
                summaryText: summaryText(for: stat, week: week, result: result),
                statDomain: stat
            )
            context.insert(resolution)
            state = result.state
        }

        stat.rankLevel = state.level
        stat.currentBaseline = state.expectedWeeklyTarget
        stat.bankedProgressUnits = state.bankedProgressUnits
        stat.chargeValue = ProgressionEngine.visibleCharge(statKey: statKey, state: state)
        stat.lastResolvedWeekStart = completedWeeks.last?.start

        let acknowledgedLevel = stat.acknowledgedRankLevel
        if stat.rankLevel == acknowledgedLevel {
            stat.clearPendingRankChange()
        } else {
            stat.setPendingRankChange(
                from: acknowledgedLevel,
                to: stat.rankLevel,
                direction: stat.rankLevel > acknowledgedLevel ? .up : .down,
                reason: reason,
                recordedAt: now
            )
        }

        updateDerivedFields(for: stat)

        let didChange =
            previousLevel != stat.rankLevel ||
            previousBaseline != stat.currentBaseline ||
            previousCharge != stat.chargeValue ||
            previousBankedUnits != stat.bankedProgressUnits ||
            previousResolvedWeek != stat.lastResolvedWeekStart ||
            previousPending != stat.pendingRankChange ||
            hadExistingResolutions

        if didChange {
            stat.updatedAt = .now
        }

        if autosave, (didChange || context.hasChanges) {
            try context.save()
            recordLocalWrite(reason: "refreshed skill progress")
        }

        return didChange || context.hasChanges
    }

    static func acknowledgePendingRankChange(for stat: StatDomain, context: ModelContext) throws {
        stat.acknowledgedRankLevel = stat.rankLevel
        stat.clearPendingRankChange()
        updateDerivedFields(for: stat)
        try context.save()
        recordLocalWrite(reason: "acknowledged rank change")
        try refreshWidgetSnapshot(context: context)
    }

    static func markRankChangeSeen(for stat: StatDomain, context: ModelContext, now: Date = .now) throws {
        guard stat.pendingRankChange != nil, stat.pendingRankChangeViewedAt == nil else { return }
        stat.pendingRankChangeViewedAt = now
        stat.updatedAt = now
        try context.save()
        recordLocalWrite(reason: "marked rank change seen on dashboard tile")
        try refreshWidgetSnapshot(context: context)
    }

    static func latestRankChangeResolution(for stat: StatDomain) -> WeeklyResolution? {
        guard let pending = stat.pendingRankChange else { return nil }
        let resolutions = (stat.weeklyResolutions ?? []).sorted { $0.weekStartDate > $1.weekStartDate }
        switch pending.direction {
        case .up:
            return resolutions.first(where: { $0.didLevelUp }) ?? resolutions.first
        case .down:
            return resolutions.first(where: { $0.didRegress }) ?? resolutions.first
        }
    }

    static func completedProgressionWeeks(for stat: StatDomain, now: Date = .now) -> [WeekRange] {
        guard let lastCompletedWeek = lastCompletedProgressionWeek(before: now) else { return [] }
        let earliestLogDate = activeHabits(for: stat).flatMap { $0.logs ?? [] }.map(\.date).min()
        let earliestRelevantDate = min(earliestLogDate ?? stat.createdAt, stat.createdAt)
        var week = progressionWeek(containing: earliestRelevantDate)

        guard week.start <= lastCompletedWeek.start else { return [] }

        var completedWeeks: [WeekRange] = []
        let calendar = progressionCalendar()
        while week.start <= lastCompletedWeek.start {
            completedWeeks.append(week)
            guard
                let nextStart = calendar.date(byAdding: .day, value: 7, to: week.start),
                let nextEnd = calendar.date(byAdding: .day, value: 6, to: nextStart)
            else {
                break
            }
            week = WeekRange(start: nextStart, end: nextEnd)
        }

        return completedWeeks
    }

    static func lastCompletedProgressionWeek(before now: Date) -> WeekRange? {
        let currentWeek = progressionWeek(containing: now)
        guard let previousWeekStart = progressionCalendar().date(byAdding: .day, value: -7, to: currentWeek.start) else {
            return nil
        }
        return progressionWeek(containing: previousWeekStart)
    }

    static func summaryText(for stat: StatDomain, week: WeekRange, result: WeeklyProgressionResult) -> String {
        let actualLabel = MetricFormatting.shortMetric(result.actualTotal)
        let expectedLabel = MetricFormatting.shortMetric(result.expectedTotal)
        let goalSuffix = result.goalBonusApplied
            ? " Goal target met added +1 bonus charge."
            : (result.goalTargetMet ? " Goal target met." : "")

        if result.didLevelUp {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) advanced \(stat.name) to Level \(result.levelAfter) after reaching +4 charge.\(goalSuffix)"
        }
        if result.didLevelDown {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) dropped \(stat.name) to Level \(result.levelAfter) after reaching -4 charge.\(goalSuffix)"
        }
        if result.weeklyChargeDelta > 0 {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) added +\(result.weeklyChargeDelta) charge.\(goalSuffix)"
        }
        if result.weeklyChargeDelta < 0 {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) added \(result.weeklyChargeDelta) charge."
        }
        if result.didDecayTowardZero {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) held steady while charge drifted 1 step back toward zero.\(goalSuffix)"
        }
        return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) held this rank steady.\(goalSuffix)"
    }

    private static func singularWeeklyUnitLabel(for stat: StatDomain) -> String {
        switch primaryHabit(for: stat)?.measurementType {
        case .booleanSession:
            return "session"
        case .pages:
            return "page"
        case .minutes:
            return "minute"
        case .count:
            return "count"
        case .customNumber:
            return "point"
        case .none:
            return "log"
        }
    }

    private static func pluralize(_ singular: String, count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }

    static func pendingWeek(context: ModelContext, now: Date = .now) throws -> WeekRange? {
        guard let week = lastCompletedProgressionWeek(before: now) else { return nil }
        let stats = try fetchActiveStats(context: context)
        guard !stats.isEmpty else { return nil }

        let allResolved = stats.allSatisfy { $0.lastResolvedWeekStart == week.start }
        return allResolved ? nil : week
    }

    static func latestResolvedWeek(context: ModelContext) throws -> WeekRange? {
        guard let latest = try fetchResolutions(context: context).last else { return nil }
        return WeekRange(start: latest.weekStartDate, end: latest.weekEndDate)
    }

    @discardableResult
    static func resolvePendingWeek(context: ModelContext, now: Date = .now) throws -> WeeklyReviewBatch? {
        try refreshAllProgress(context: context, reason: .appRefresh, now: now)
        try refreshWidgetSnapshot(context: context, now: now)
        guard let week = lastCompletedProgressionWeek(before: now) else { return nil }
        let resolutions = try fetchResolutions(context: context)
            .filter { $0.weekStartDate == week.start }
            .sorted { $0.statName < $1.statName }

        guard !resolutions.isEmpty else { return nil }
        return WeeklyReviewBatch(week: week, resolutions: resolutions)
    }

    static func momentum(context: ModelContext, now: Date = .now) throws -> MomentumStatus {
        let interval = currentWeekInterval(settings: nil, now: now)
        let stats = try fetchActiveStats(context: context)
        guard !stats.isEmpty else {
            return MomentumStatus(title: "Unformed", subtitle: "Run onboarding to create the first build.", score: 0)
        }

        let ratios = stats.map { stat -> Double in
            let actual = total(for: stat, in: interval)
            let baseline = max(Double(stat.currentBaseline), 1)
            return min(actual / baseline, 1.5)
        }
        let score = ratios.reduce(0, +) / Double(ratios.count)

        switch score {
        case ..<0.65:
            return MomentumStatus(title: "Momentum Low", subtitle: "A few core skills are under baseline. Rebuild this week.", score: score)
        case ..<1.05:
            return MomentumStatus(title: "Form Stable", subtitle: "You are holding your current build.", score: score)
        default:
            return MomentumStatus(title: "Momentum Rising", subtitle: "You are pushing beyond baseline and building positive charge.", score: score)
        }
    }

    static func weakestStat(context: ModelContext, now: Date = .now) throws -> StatDomain? {
        let interval = currentWeekInterval(settings: nil, now: now)
        return try fetchActiveStats(context: context).min { lhs, rhs in
            let lhsRatio = total(for: lhs, in: interval) / max(Double(lhs.currentBaseline), 1)
            let rhsRatio = total(for: rhs, in: interval) / max(Double(rhs.currentBaseline), 1)
            return lhsRatio < rhsRatio
        }
    }

    static func setDashboardLayoutMode(_ mode: DashboardLayoutMode, context: ModelContext) throws {
        let settings = try fetchSettings(context: context)
        guard settings.dashboardLayoutMode != mode else { return }
        settings.dashboardLayoutMode = mode
        settings.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "updated dashboard layout mode")
        refreshHomeScreenQuickActions()
    }

    static func setSkillOrder(_ orderedStatIDs: [UUID], context: ModelContext) throws {
        let activeStats = try fetchActiveStats(context: context)
        let statsByID = Dictionary(uniqueKeysWithValues: activeStats.map { ($0.id, $0) })
        let orderedIDs = orderedStatIDs.filter { statsByID[$0] != nil }
        let remainingIDs = activeStats.map(\.id).filter { !orderedIDs.contains($0) }

        for (offset, id) in (orderedIDs + remainingIDs).enumerated() {
            guard let stat = statsByID[id] else { continue }
            if stat.sortOrder != offset {
                stat.sortOrder = offset
                stat.updatedAt = .now
            }
        }

        try context.save()
        recordLocalWrite(reason: "updated skill order")
        try refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
    }

    // MARK: - Skill activation management

    /// Ensures an archived/optional skill has its starter habit (optional skills
    /// are created without one). No-op if any habit already exists.
    private static func ensureStarterHabit(for stat: StatDomain, context: ModelContext) {
        guard let key = stat.statKey else { return }
        let hasHabit = !(stat.habits ?? []).isEmpty
        guard !hasHabit else { return }
        let starter = TrainingArcConfig.definition(for: key).starterHabit
        let habit = Habit(
            systemKey: starter.systemKey,
            name: starter.name,
            notes: starter.notes,
            measurementType: starter.measurementType,
            unitLabel: starter.unitLabel,
            scheduleType: starter.scheduleType,
            targetPerPeriod: starter.targetPerPeriod,
            active: true,
            sortOrder: (try? fetchHabits(context: context).count) ?? 0,
            statDomain: stat
        )
        context.insert(habit)
    }

    /// Turns a skill on: enabled, not archived, with a starter habit if it had
    /// none. Appends it to the end of the active order. Data is never deleted.
    static func enableSkill(_ stat: StatDomain, context: ModelContext) throws {
        stat.isEnabled = true
        stat.isArchived = false
        ensureStarterHabit(for: stat, context: context)
        let maxOrder = (try fetchStats(context: context).map(\.sortOrder).max()) ?? 0
        stat.sortOrder = maxOrder + 1
        stat.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "enabled skill \(stat.key)")
        try refreshAllProgress(context: context, reason: .appRefresh)
        try refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
    }

    /// Hides a skill from the active experience while keeping all logs, goals, and
    /// history intact. Fully reversible via `restoreSkill`.
    static func archiveSkill(_ stat: StatDomain, context: ModelContext) throws {
        stat.isArchived = true
        stat.isEnabled = false
        stat.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "archived skill \(stat.key)")
        try refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
    }

    /// Brings an archived skill back into the active set. Identical to enabling.
    static func restoreSkill(_ stat: StatDomain, context: ModelContext) throws {
        try enableSkill(stat, context: context)
    }

    static func workFocusAnalysis(
        context: ModelContext,
        settings: AppSettings?,
        now: Date = .now
    ) throws -> WorkFocusAnalysis {
        let stats = try fetchActiveStats(context: context)
        guard !stats.isEmpty else {
            return WorkFocusAnalysis(
                headline: "Build your first skill set by completing onboarding and logging a few sessions.",
                focusSkillName: "No Skills Yet",
                recommendations: ["Complete onboarding to unlock the first dashboard build."]
            )
        }

        let ranked = stats
            .map { stat in (stat: stat, snapshot: progressSnapshot(for: stat, settings: settings, now: now), actual: currentWeekTotal(for: stat, settings: settings, now: now)) }
            .sorted { lhs, rhs in
                let lhsRatio = lhs.actual / max(Double(lhs.stat.currentBaseline), 1)
                let rhsRatio = rhs.actual / max(Double(rhs.stat.currentBaseline), 1)
                return lhsRatio < rhsRatio
            }

        let focus = ranked.first!
        let recommendations = Array(ranked.prefix(3)).map { item in
            "\(item.stat.name): \(item.snapshot.nextActionLabel)"
        }

        return WorkFocusAnalysis(
            headline: "\(focus.stat.name) is the cleanest place to reclaim momentum right now.",
            focusSkillName: focus.stat.name,
            recommendations: recommendations
        )
    }

    static func monthlyImprovementAnalysis(
        context: ModelContext,
        settings: AppSettings?,
        now: Date = .now
    ) throws -> MonthlyImprovementAnalysis {
        let calendar = progressionCalendar()
        let currentWindow = DateInterval(
            start: calendar.date(byAdding: .day, value: -30, to: now) ?? now,
            end: now
        )
        let previousWindow = DateInterval(
            start: calendar.date(byAdding: .day, value: -60, to: now) ?? now,
            end: calendar.date(byAdding: .day, value: -30, to: now) ?? now
        )

        let stats = try fetchActiveStats(context: context)
        let deltas = stats.map { stat in
            let current = total(for: stat, in: currentWindow)
            let previous = total(for: stat, in: previousWindow)
            return (stat: stat, delta: current - previous, current: current)
        }
        .sorted { $0.delta > $1.delta }

        let rankUps = try fetchResolutions(context: context)
            .filter { currentWindow.contains($0.weekEndDate) && $0.didLevelUp }

        let headline: String
        if let best = deltas.first, best.delta > 0 {
            headline = "\(best.stat.name) improved the most over the last month."
        } else {
            headline = "The last month was more about maintenance than breakthrough gains."
        }

        var bullets = deltas
            .filter { $0.current > 0 || $0.delta != 0 }
            .prefix(3)
            .map { item in
                let deltaLabel = item.delta >= 0 ? "+\(MetricFormatting.shortMetric(item.delta))" : MetricFormatting.shortMetric(item.delta)
                return "\(item.stat.name): \(deltaLabel) compared with the previous month."
            }

        if rankUps.isEmpty == false {
            bullets.append("Rank gains landed in \(rankUps.map(\.statName).joined(separator: ", ")).")
        }

        if bullets.isEmpty {
            bullets = ["Log a few clean weeks to give the monthly analysis more signal."]
        }

        let summary = rankUps.isEmpty
            ? "No monthly rank-up spikes were recorded, so the strongest signal comes from raw activity deltas."
            : "\(rankUps.count) weekly rank-up checks converted into level gains this month."

        return MonthlyImprovementAnalysis(
            headline: headline,
            summary: summary,
            improvedSkills: bullets
        )
    }

    static func standardDayAnalysis(
        context: ModelContext,
        settings: AppSettings?,
        now: Date = .now
    ) throws -> StandardDayAnalysis {
        let stats = try fetchActiveStats(context: context)
        let logs = stats
            .flatMap(recentLogs(for:))
            .filter { $0.date >= (Calendar.current.date(byAdding: .day, value: -21, to: now) ?? now) }

        guard !logs.isEmpty else {
            return StandardDayAnalysis(
                headline: "A standard day will appear once you build a few weeks of logs.",
                rhythmSummary: "There is not enough recent timing data yet.",
                suggestions: ["Log sessions close to when they happen so the day planner can learn your rhythm."]
            )
        }

        let calendar = Calendar.current
        let hours = logs.map { calendar.component(.hour, from: $0.date) }.sorted()
        let medianHour = hours[hours.count / 2]
        let weekdayCounts = Dictionary(grouping: logs, by: { calendar.component(.weekday, from: $0.date) })
            .mapValues(\.count)
        let mostActiveWeekday = weekdayCounts.max(by: { $0.value < $1.value })?.key ?? calendar.component(.weekday, from: now)

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale.current
        let weekdayName = weekdayFormatter.weekdaySymbols[max(0, mostActiveWeekday - 1)]

        let hourLabel = formattedHour(medianHour)
        let summary = "Most recent sessions cluster around \(hourLabel), with the strongest activity pattern landing on \(weekdayName)s."

        return StandardDayAnalysis(
            headline: "Your current rhythm is strongest around \(hourLabel).",
            rhythmSummary: summary,
            suggestions: [
                "Protect a recurring \(hourLabel) block for the skill you most often skip.",
                "Front-load one easy win before your usual training hour so momentum starts earlier in the day.",
                "If recovery feels thin, keep the same rhythm but trim one low-value late session each week."
            ]
        )
    }

    static func selfSummary(from stats: [StatDomain]) -> String {
        let summary = stats.reduce(into: [String]()) { items, stat in
            guard let key = stat.statKey else { return }
            items.append("\(key.displayName): \(stat.rankTitle)")
        }
        return summary.joined(separator: ". ") + "."
    }

    static func refreshWidgetSnapshot(context: ModelContext, now: Date = .now) throws {
        _ = try fetchSettings(context: context)
        let interval = currentWeekInterval(settings: nil, now: now)
        let stats = try fetchActiveStats(context: context)
        let habits = try fetchActiveHabits(context: context)
        let momentum = try momentum(context: context, now: now)
        let weakest = try weakestStat(context: context, now: now)
        let weakestSnapshot = weakest.map { progressSnapshot(for: $0, settings: nil, now: now) }
        let pending = try pendingWeek(context: context, now: now) != nil

        let statSnapshots = stats.map { stat in
            let progress = stat.statKey.map {
                ProgressionEngine.progressToNextRank(
                    statKey: $0,
                    state: WeeklyProgressionState(
                        level: stat.rankLevel,
                        expectedWeeklyTarget: stat.currentBaseline,
                        bankedProgressUnits: stat.bankedProgressUnits
                    )
                )
            } ?? 0
            return TrainingWidgetStat(
                id: stat.id,
                name: stat.name,
                descriptor: stat.rankTitle,
                level: stat.rankLevel,
                baseline: stat.currentBaseline,
                storedCharges: stat.chargeValue,
                weekActual: total(for: stat, in: interval),
                progressToNextLevel: progress,
                colorToken: stat.colorToken
            )
        }

        let todayInterval = DateInterval(
            start: Calendar.current.startOfDay(for: now),
            end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        )

        let habitSnapshots = habits.prefix(4).map { habit in
            TrainingWidgetHabit(
                id: habit.id,
                name: habit.name,
                unitLabel: habit.unitLabel,
                todayValue: total(for: habit, in: todayInterval),
                targetPerPeriod: habit.targetPerPeriod,
                measurementTypeRaw: habit.measurementType.rawValue
            )
        }

        let motivationTitle: String
        let motivationMessage: String
        let motivationColorToken: String

        if pending {
            motivationTitle = "Weekly review ready"
            motivationMessage = "Last week was finalized. Open Review to see what changed."
            motivationColorToken = weakest?.colorToken ?? "focus"
        } else if let weakest, let weakestSnapshot {
            motivationTitle = "Focus on \(weakest.name)"
            motivationMessage = weakestSnapshot.nextActionLabel
            motivationColorToken = weakest.colorToken
        } else {
            motivationTitle = momentum.title
            motivationMessage = momentum.subtitle
            motivationColorToken = "focus"
        }

        let settings = try? fetchExistingSettings(context: context)
        let recommendations = (try? trainTodayRecommendations(context: context, settings: settings, now: now, limit: 1)) ?? []
        let topRec = recommendations.first
        let goalSnapshots = (try? goalProgressSnapshots(context: context, now: now)) ?? []
        let activeGoalCount = goalSnapshots.filter { $0.goal.status == .active }.count
        let atRiskGoalSnapshots = goalSnapshots.filter {
            $0.goal.status == .active && ($0.paceStatus == .atRisk || $0.paceStatus == .behind)
        }
        let goalsAtRiskCount = atRiskGoalSnapshots.count
        let topGoalAtRisk = atRiskGoalSnapshots.sorted { $0.progressRatio < $1.progressRatio }.first

        let snapshot = TrainingWidgetSnapshot(
            generatedAt: now,
            appName: AppIdentity.displayName,
            momentumTitle: momentum.title,
            momentumSubtitle: momentum.subtitle,
            characterSummary: selfSummary(from: stats),
            motivationTitle: motivationTitle,
            motivationMessage: motivationMessage,
            motivationColorToken: motivationColorToken,
            pendingWeeklyReview: pending,
            weakestStat: statSnapshots.first(where: { $0.id == weakest?.id }),
            stats: statSnapshots,
            todayHabits: Array(habitSnapshots),
            trainTodayHeadline: topRec?.headline,
            trainTodayDetail: topRec?.detail,
            trainTodayColorToken: topRec?.colorToken,
            activeGoalCount: activeGoalCount,
            goalsAtRiskCount: goalsAtRiskCount,
            topGoalAtRiskTitle: topGoalAtRisk?.goal.displayTitle,
            topGoalAtRiskDetail: topGoalAtRisk.map { goalAtRiskWidgetDetail(for: $0) }
        )

        WidgetSnapshotStore.save(snapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private static func goalAtRiskWidgetDetail(for snapshot: GoalProgressSnapshot) -> String {
        let remaining = MetricFormatting.shortMetric(snapshot.remainingValue)
        if snapshot.timeRemainingLabel.isEmpty {
            return "\(remaining) to go"
        }
        return "\(remaining) to go · \(snapshot.timeRemainingLabel)"
    }

    static func exportBundle(context: ModelContext) throws -> TrainingExportBundle {
        let stats = try fetchStats(context: context)
        let habits = try fetchHabits(context: context)
        let logs = try fetchLogs(context: context)
        let resolutions = try fetchResolutions(context: context)
        let settings = try fetchSettings(context: context)
        let goals = try fetchGoals(context: context)

        return TrainingExportBundle(
            exportedAt: .now,
            stats: stats.map {
                StatExport(
                    id: $0.id,
                    key: $0.key,
                    name: $0.name,
                    iconName: $0.iconName,
                    colorToken: $0.colorToken,
                    descriptor: $0.descriptor,
                    sortOrder: $0.sortOrder,
                    currentLevel: $0.currentLevel,
                    currentTierName: $0.currentTierName,
                    startingBaseline: $0.startingBaseline,
                    currentBaseline: $0.currentBaseline,
                    targetValue: $0.targetValue,
                    personalMaxValue: $0.personalMaxValue,
                    maintenanceFloor: $0.maintenanceFloor,
                    storedCharges: $0.storedCharges,
                    bankedProgressUnits: $0.bankedProgressUnits,
                    lastResolvedWeekStart: $0.lastResolvedWeekStart,
                    lastAcknowledgedLevel: $0.lastAcknowledgedLevel,
                    pendingRankChangeDirectionRaw: $0.pendingRankChangeDirectionRaw,
                    pendingRankChangeFromLevel: $0.pendingRankChangeFromLevel,
                    pendingRankChangeToLevel: $0.pendingRankChangeToLevel,
                    pendingRankChangeRecordedAt: $0.pendingRankChangeRecordedAt,
                    pendingRankChangeReasonRaw: $0.pendingRankChangeReasonRaw,
                    pendingRankChangeViewedAt: $0.pendingRankChangeViewedAt,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    isArchived: $0.isArchived,
                    isCore: $0.isCore,
                    isEnabled: $0.isEnabled,
                    isCustom: $0.isCustom,
                    parentSkillKeyRaw: $0.parentSkillKeyRaw
                )
            },
            habits: habits.map {
                HabitExport(
                    id: $0.id,
                    systemKey: $0.systemKey,
                    name: $0.name,
                    notes: $0.notes,
                    measurementTypeRaw: $0.measurementTypeRaw,
                    unitLabel: $0.unitLabel,
                    scheduleTypeRaw: $0.scheduleTypeRaw,
                    targetPerPeriod: $0.targetPerPeriod,
                    active: $0.active,
                    sortOrder: $0.sortOrder,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    statID: $0.statDomain?.id
                )
            },
            logs: logs.map {
                HabitLogExport(
                    id: $0.id,
                    habitID: $0.habit?.id,
                    date: $0.date,
                    numericValue: $0.numericValue,
                    sessionType: $0.sessionType,
                    note: $0.note,
                    sourceTypeRaw: $0.sourceTypeRaw,
                    healthWorkoutUUID: $0.healthWorkoutUUID,
                    createdAt: $0.createdAt
                )
            },
            resolutions: resolutions.map {
                WeeklyResolutionExport(
                    id: $0.id,
                    statID: $0.statDomain?.id,
                    statKey: $0.statKey,
                    statName: $0.statName,
                    weekStartDate: $0.weekStartDate,
                    weekEndDate: $0.weekEndDate,
                    baselineAtStart: $0.baselineAtStart,
                    expectedTotal: $0.expectedTotal,
                    actualCompletedValue: $0.actualCompletedValue,
                    weeklyDelta: $0.weeklyDelta,
                    excessValue: $0.excessValue,
                    chargesEarned: $0.chargesEarned,
                    chargesSpentOnLevelUp: $0.chargesSpentOnLevelUp,
                    bankedUnitsBefore: $0.bankedUnitsBefore,
                    bankedUnitsAfter: $0.bankedUnitsAfter,
                    levelBefore: $0.levelBefore,
                    levelAfter: $0.levelAfter,
                    storedChargesAfter: $0.storedChargesAfter,
                    didDecay: $0.didDecay,
                    didLevelUp: $0.didLevelUp,
                    didStagnate: $0.didStagnate,
                    didRegress: $0.didRegress,
                    summaryText: $0.summaryText,
                    createdAt: $0.createdAt
                )
            },
            settings: SettingsExport(
                hasCompletedOnboarding: settings.hasCompletedOnboarding,
                enableDecay: settings.enableDecay,
                decaySensitivity: settings.decaySensitivity,
                dailyReminderEnabled: settings.dailyReminderEnabled,
                eveningReminderEnabled: settings.eveningReminderEnabled,
                weeklyReviewReminderEnabled: settings.weeklyReviewReminderEnabled,
                weekStartsOnMonday: settings.weekStartsOnMonday,
                hapticsEnabled: settings.hapticsEnabled,
                lockInWeeklyReview: settings.lockInWeeklyReview,
                healthAutoImportEnabled: settings.healthAutoImportEnabled,
                lastHealthSyncAt: settings.lastHealthSyncAt,
                themePreferenceRaw: settings.themePreferenceRaw,
                dashboardLayoutModeRaw: settings.dashboardLayoutModeRaw,
                disabledHealthWorkoutTypeKeysRaw: settings.disabledHealthWorkoutTypeKeysRaw,
                progressionStrictnessRaw: settings.progressionStrictnessRaw,
                goalsCanAffectProgression: settings.goalsCanAffectProgression,
                showPersonalMaxInUI: settings.showPersonalMaxInUI,
                goalAtRiskReminderEnabled: settings.goalAtRiskReminderEnabled,
                regressionBehaviorRaw: settings.regressionBehaviorRaw,
                skillBehindPaceReminderEnabled: settings.skillBehindPaceReminderEnabled,
                goalsAffectPacing: settings.goalsAffectPacing
            ),
            goals: goals.map {
                GoalExport(
                    id: $0.id,
                    title: $0.title,
                    notes: $0.notes,
                    goalScopeRaw: $0.goalScopeRaw,
                    linkedStatKeyRaw: $0.linkedStatKeyRaw,
                    linkedHabitIDRaw: $0.linkedHabitIDRaw,
                    goalTypeRaw: $0.goalTypeRaw,
                    measurementTypeRaw: $0.measurementTypeRaw,
                    targetValue: $0.targetValue,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    statusRaw: $0.statusRaw,
                    priorityRaw: $0.priorityRaw,
                    affectsMetrics: $0.affectsMetrics,
                    affectsProgression: $0.affectsProgression,
                    isRecoveryMode: $0.isRecoveryMode,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    completedAt: $0.completedAt
                )
            }
        )
    }

    static func importBundle(_ bundle: TrainingExportBundle, context: ModelContext) throws {
        try clearAll(context: context)

        var statLookup: [UUID: StatDomain] = [:]
        for exported in bundle.stats {
            let importedKey = StatKey(rawValue: exported.key)
            let stat = StatDomain(
                id: exported.id,
                key: exported.key,
                name: exported.name,
                iconName: exported.iconName,
                colorToken: exported.colorToken,
                descriptor: exported.descriptor,
                sortOrder: exported.sortOrder,
                currentLevel: exported.currentLevel,
                currentTierName: exported.currentTierName,
                startingBaseline: exported.startingBaseline,
                currentBaseline: exported.currentBaseline,
                targetValue: exported.targetValue,
                personalMaxValue: exported.personalMaxValue,
                maintenanceFloor: exported.maintenanceFloor,
                storedCharges: exported.storedCharges,
                bankedProgressUnits: exported.bankedProgressUnits,
                lastResolvedWeekStart: exported.lastResolvedWeekStart,
                lastAcknowledgedLevel: exported.lastAcknowledgedLevel,
                pendingRankChangeDirectionRaw: exported.pendingRankChangeDirectionRaw,
                pendingRankChangeFromLevel: exported.pendingRankChangeFromLevel,
                pendingRankChangeToLevel: exported.pendingRankChangeToLevel,
                pendingRankChangeRecordedAt: exported.pendingRankChangeRecordedAt,
                pendingRankChangeReasonRaw: exported.pendingRankChangeReasonRaw,
                pendingRankChangeViewedAt: exported.pendingRankChangeViewedAt,
                createdAt: exported.createdAt,
                updatedAt: exported.updatedAt,
                isArchived: exported.isArchived,
                isCore: exported.isCore ?? (importedKey.map(TrainingArcConfig.isCoreSkill) ?? false),
                isEnabled: exported.isEnabled ?? true,
                isCustom: exported.isCustom ?? false,
                parentSkillKeyRaw: exported.parentSkillKeyRaw ?? importedKey.flatMap { TrainingArcConfig.parentSkillKey(for: $0)?.rawValue }
            )
            updateDerivedFields(for: stat)
            statLookup[exported.id] = stat
            context.insert(stat)
        }

        var habitLookup: [UUID: Habit] = [:]
        for exported in bundle.habits {
            let habit = Habit(
                id: exported.id,
                systemKey: exported.systemKey,
                name: exported.name,
                notes: exported.notes,
                measurementType: MeasurementType(rawValue: exported.measurementTypeRaw) ?? .booleanSession,
                unitLabel: exported.unitLabel,
                scheduleType: ScheduleType(rawValue: exported.scheduleTypeRaw) ?? .weekly,
                targetPerPeriod: exported.targetPerPeriod,
                active: exported.active,
                sortOrder: exported.sortOrder,
                createdAt: exported.createdAt,
                updatedAt: exported.updatedAt,
                statDomain: exported.statID.flatMap { statLookup[$0] }
            )
            habitLookup[exported.id] = habit
            context.insert(habit)
        }

        for exported in bundle.logs {
            let log = HabitLog(
                id: exported.id,
                date: exported.date,
                numericValue: exported.numericValue,
                sessionType: exported.sessionType,
                note: exported.note,
                sourceType: LogSourceType(rawValue: exported.sourceTypeRaw) ?? .manual,
                healthWorkoutUUID: exported.healthWorkoutUUID,
                createdAt: exported.createdAt,
                habit: exported.habitID.flatMap { habitLookup[$0] }
            )
            context.insert(log)
        }

        for exported in bundle.resolutions {
            let resolution = WeeklyResolution(
                id: exported.id,
                statKey: exported.statKey,
                statName: exported.statName,
                weekStartDate: exported.weekStartDate,
                weekEndDate: exported.weekEndDate,
                baselineAtStart: exported.baselineAtStart,
                expectedTotal: exported.expectedTotal,
                actualCompletedValue: exported.actualCompletedValue,
                weeklyDelta: exported.weeklyDelta,
                excessValue: exported.excessValue,
                chargesEarned: exported.chargesEarned,
                chargesSpentOnLevelUp: exported.chargesSpentOnLevelUp,
                bankedUnitsBefore: exported.bankedUnitsBefore,
                bankedUnitsAfter: exported.bankedUnitsAfter,
                levelBefore: exported.levelBefore,
                levelAfter: exported.levelAfter,
                storedChargesAfter: exported.storedChargesAfter,
                didDecay: exported.didDecay,
                didLevelUp: exported.didLevelUp,
                didStagnate: exported.didStagnate,
                didRegress: exported.didRegress,
                summaryText: exported.summaryText,
                createdAt: exported.createdAt,
                statDomain: exported.statID.flatMap { statLookup[$0] }
            )
            context.insert(resolution)
        }

        let settings = AppSettings(
            hasCompletedOnboarding: bundle.settings.hasCompletedOnboarding,
            enableDecay: bundle.settings.enableDecay,
            decaySensitivity: bundle.settings.decaySensitivity,
            dailyReminderEnabled: bundle.settings.dailyReminderEnabled,
            eveningReminderEnabled: bundle.settings.eveningReminderEnabled,
            weeklyReviewReminderEnabled: bundle.settings.weeklyReviewReminderEnabled,
            weekStartsOnMonday: bundle.settings.weekStartsOnMonday,
            hapticsEnabled: bundle.settings.hapticsEnabled,
            lockInWeeklyReview: bundle.settings.lockInWeeklyReview,
            healthAutoImportEnabled: bundle.settings.healthAutoImportEnabled ?? true,
            lastHealthSyncAt: bundle.settings.lastHealthSyncAt,
            dashboardLayoutMode: DashboardLayoutMode(rawValue: bundle.settings.dashboardLayoutModeRaw) ?? .gameGrid,
            disabledHealthWorkoutTypeKeys: (bundle.settings.disabledHealthWorkoutTypeKeysRaw ?? "")
                .split(separator: ",", omittingEmptySubsequences: true)
                .map(String.init)
        )
        if let strictnessRaw = bundle.settings.progressionStrictnessRaw,
           let strictness = ProgressionStrictness(rawValue: strictnessRaw) {
            settings.progressionStrictness = strictness
        }
        settings.goalsCanAffectProgression = bundle.settings.goalsCanAffectProgression ?? false
        settings.showPersonalMaxInUI = bundle.settings.showPersonalMaxInUI ?? true
        settings.goalAtRiskReminderEnabled = bundle.settings.goalAtRiskReminderEnabled ?? false
        if let regressionRaw = bundle.settings.regressionBehaviorRaw,
           let regression = RegressionBehavior(rawValue: regressionRaw) {
            settings.regressionBehavior = regression
        }
        settings.skillBehindPaceReminderEnabled = bundle.settings.skillBehindPaceReminderEnabled ?? false
        settings.goalsAffectPacing = bundle.settings.goalsAffectPacing ?? true
        context.insert(settings)

        for exported in bundle.goals ?? [] {
            let goal = Goal(
                id: exported.id,
                title: exported.title,
                notes: exported.notes,
                scope: GoalScope(rawValue: exported.goalScopeRaw) ?? .skill,
                linkedStatKey: exported.linkedStatKeyRaw.flatMap(StatKey.init(rawValue:)),
                linkedHabitID: exported.linkedHabitIDRaw.flatMap(UUID.init(uuidString:)),
                type: GoalType(rawValue: exported.goalTypeRaw) ?? .weeklyTarget,
                measurementType: MeasurementType(rawValue: exported.measurementTypeRaw) ?? .count,
                targetValue: exported.targetValue,
                startDate: exported.startDate,
                endDate: exported.endDate,
                status: GoalStatus(rawValue: exported.statusRaw) ?? .active,
                priority: GoalPriority(rawValue: exported.priorityRaw) ?? .normal,
                affectsMetrics: exported.affectsMetrics,
                affectsProgression: exported.affectsProgression,
                isRecoveryMode: exported.isRecoveryMode ?? false,
                createdAt: exported.createdAt,
                updatedAt: exported.updatedAt,
                completedAt: exported.completedAt
            )
            context.insert(goal)
        }

        try context.save()
        recordLocalWrite(reason: "imported JSON bundle")
        try synchronizeCatalog(context: context)
        try refreshAllProgress(context: context, reason: .appRefresh)
        try refreshWidgetSnapshot(context: context)
        let atRiskCount = ((try? goalProgressSnapshots(context: context)) ?? []).filter {
            $0.goal.status == .active && ($0.paceStatus == .atRisk || $0.paceStatus == .behind)
        }.count
        let behindPaceCount = skillsBehindPaceCount(context: context, settings: settings)
        NotificationService.refreshNotifications(using: settings, goalsAtRiskCount: atRiskCount, skillsBehindPaceCount: behindPaceCount)
    }

    static func seedSampleGoals(context: ModelContext, now: Date = .now) throws {
        let stats = try fetchActiveStats(context: context)
        let calendar = Calendar.current
        let inEightWeeks = calendar.date(byAdding: .weekOfYear, value: 8, to: now)
        let inFourWeeks = calendar.date(byAdding: .weekOfYear, value: 4, to: now)
        let inThreeMonths = calendar.date(byAdding: .month, value: 3, to: now)

        func makeGoal(
            title: String,
            statKey: StatKey?,
            type: GoalType,
            measurementType: MeasurementType,
            targetValue: Double,
            endDate: Date?,
            priority: GoalPriority = .normal,
            affectsProgression: Bool = false
        ) -> Goal {
            Goal(
                title: title,
                scope: statKey == nil ? .overall : .skill,
                linkedStatKey: statKey,
                type: type,
                measurementType: measurementType,
                targetValue: targetValue,
                startDate: now,
                endDate: endDate,
                priority: priority,
                affectsMetrics: false,
                affectsProgression: affectsProgression
            )
        }

        var seeded: [Goal] = []

        if let strength = stats.first(where: { $0.statKey == .strength }) {
            let target = max(Double(strength.targetValue ?? (strength.currentBaseline + 1)), Double(strength.currentBaseline + 1))
            seeded.append(makeGoal(
                title: "\(Int(target)) gym sessions per week",
                statKey: .strength,
                type: .weeklyTarget,
                measurementType: .booleanSession,
                targetValue: target,
                endDate: inEightWeeks,
                priority: .high,
                affectsProgression: true
            ))
        }
        if stats.contains(where: { $0.statKey == .cardio }) {
            seeded.append(makeGoal(
                title: "90 cardio minutes per week",
                statKey: .cardio,
                type: .weeklyTarget,
                measurementType: .minutes,
                targetValue: 90,
                endDate: inEightWeeks
            ))
        }
        if stats.contains(where: { $0.statKey == .reading }) {
            seeded.append(makeGoal(
                title: "Read 300 pages this month",
                statKey: .reading,
                type: .monthlyTotal,
                measurementType: .pages,
                targetValue: 300,
                endDate: inFourWeeks
            ))
        }
        if stats.contains(where: { $0.statKey == .focus }) {
            seeded.append(makeGoal(
                title: "Reach Focus Level 5",
                statKey: .focus,
                type: .reachLevel,
                measurementType: .customNumber,
                targetValue: 5,
                endDate: inThreeMonths,
                priority: .normal
            ))
        }
        seeded.append(makeGoal(
            title: "Log 20 total sessions this month",
            statKey: nil,
            type: .monthlyTotal,
            measurementType: .count,
            targetValue: 20,
            endDate: inFourWeeks
        ))

        for goal in seeded {
            context.insert(goal)
        }
        try context.save()
        recordLocalWrite(reason: "seeded sample goals")
    }

    static func seedSampleData(context: ModelContext, profile: SampleProfile, now: Date = .now) throws {
        switch profile {
        case .newUser:
            try clearAll(context: context)
            try seedDefaultProfile(context: context, completeOnboarding: true)
        case .streaking:
            try clearAll(context: context)
            try seedDefaultProfile(context: context, completeOnboarding: true)
            try seedHistoricalProgress(context: context, style: .streaking, now: now)
        case .stagnating:
            try clearAll(context: context)
            try seedDefaultProfile(context: context, completeOnboarding: true)
            try seedHistoricalProgress(context: context, style: .stagnating, now: now)
        case .levelUpWeek:
            try clearAll(context: context)
            try seedDefaultProfile(context: context, completeOnboarding: true)
            try seedHistoricalProgress(context: context, style: .levelUpWeek, now: now)
        }
    }

    static func refreshHomeScreenQuickActions() {
        #if canImport(UIKit)
        HomeScreenQuickActionService.refresh(using: sharedModelContainer)
        #endif
    }

    private enum HistoricalSeedStyle {
        case streaking
        case stagnating
        case levelUpWeek
    }

    private static func seedHistoricalProgress(context: ModelContext, style: HistoricalSeedStyle, now: Date) throws {
        let currentWeekStart = progressionWeek(containing: now).start
        let calendar = progressionCalendar()
        let habits = try fetchActiveHabits(context: context)

        func createWeek(at offset: Int, multiplier: Double) throws {
            guard let weekStart = calendar.date(byAdding: .day, value: -(offset * 7), to: currentWeekStart) else { return }
            for habit in habits {
                try addSeededLogs(for: habit, weekStart: weekStart, total: habit.targetPerPeriod * multiplier, context: context)
            }
        }

        switch style {
        case .streaking:
            try createWeek(at: 3, multiplier: 1.4)
            try createWeek(at: 2, multiplier: 1.3)
            try createWeek(at: 1, multiplier: 1.25)
            for habit in habits {
                try addSeededLogs(for: habit, weekStart: currentWeekStart, total: habit.targetPerPeriod * 0.8, context: context)
            }
        case .stagnating:
            try createWeek(at: 5, multiplier: 1.3)
            try createWeek(at: 4, multiplier: 1.1)
            try createWeek(at: 3, multiplier: 0.4)
            try createWeek(at: 2, multiplier: 0)
            try createWeek(at: 1, multiplier: 0)
            for habit in habits {
                try addSeededLogs(for: habit, weekStart: currentWeekStart, total: 0, context: context)
            }
        case .levelUpWeek:
            for habit in habits {
                let previousWeek = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
                try addSeededLogs(for: habit, weekStart: previousWeek, total: habit.targetPerPeriod * 4, context: context)
            }
        }

        try context.save()
        recordLocalWrite(reason: "seeded historical sample progress")
        try refreshAllProgress(context: context, reason: .appRefresh, now: now)
        try refreshWidgetSnapshot(context: context)
    }

    private static func addSeededLogs(for habit: Habit, weekStart: Date, total: Double, context: ModelContext) throws {
        guard total > 0 else { return }

        let calendar = Calendar.current
        let entries = habit.measurementType == .booleanSession ? Int(total.rounded(.down)) : min(4, max(1, Int(total.rounded(.up) / max(1, habit.measurementType.defaultIncrement))))
        let chunk = habit.measurementType == .booleanSession ? 1.0 : total / Double(entries)

        for index in 0..<entries {
            let date = calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
            let log = HabitLog(date: date, numericValue: chunk, note: "Seeded sample", sourceType: .debug, habit: habit)
            context.insert(log)
        }
    }

    private static func formattedHour(_ hour: Int) -> String {
        let safeHour = min(max(hour, 0), 23)
        let components = DateComponents(calendar: Calendar.current, hour: safeHour)
        let date = components.date ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

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
        let anchor = scope == .anchored ? loadAnchor() : nil
        let predicate: NSPredicate? = anchor == nil
            ? HKQuery.predicateForSamples(withStart: yearBackfillStartDate(), end: nil, options: .strictStartDate)
            : nil
        let (workouts, newAnchor) = try await fetchWorkouts(anchor: anchor, predicate: predicate)
        let activeStats = try TrainingStore.fetchActiveStats(context: context)
        let existingRecords = try normalizeExistingHealthImports(context: context)
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

        if let newAnchor {
            saveAnchor(newAnchor)
        }

        if scope == .yearBackfill {
            defaults.set(Date(), forKey: lastYearBackfillDefaultsKey)
        }

        settings.lastHealthSyncAt = .now
        settings.updatedAt = .now
        try context.save()
        TrainingStore.recordLocalWrite(reason: "updated Health sync timestamp")
        try TrainingStore.refreshWidgetSnapshot(context: context)
        TrainingStore.refreshHomeScreenQuickActions()

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

    private static func normalizeExistingHealthImports(context: ModelContext) throws -> [HealthImportedWorkout] {
        var records = try TrainingStore.fetchImportedHealthWorkouts(context: context)
            .sorted { $0.startDate < $1.startDate }
        var importedRecords: [HealthImportedWorkout] = []

        for record in records where record.wasImported && !record.isDuplicate {
            if let duplicateRecord = importedRecords.first(where: { isDuplicate(record, of: $0) }) {
                try deleteImportedHealthLog(for: record, context: context)
                record.wasImported = false
                record.isDuplicate = true
                record.overlapsImportedWorkout = false
                record.relatedWorkoutUUID = duplicateRecord.workoutUUID
            } else {
                importedRecords.append(record)
            }
        }

        importedRecords = records
            .filter { $0.wasImported && !$0.isDuplicate }
            .sorted { $0.startDate < $1.startDate }

        for record in importedRecords {
            record.overlapsImportedWorkout = false
            record.relatedWorkoutUUID = nil
        }

        for index in importedRecords.indices {
            let record = importedRecords[index]
            guard let overlappingRecord = importedRecords[..<index].first(where: { overlaps(record, with: $0) && !isDuplicate(record, of: $0) }) else {
                continue
            }

            record.overlapsImportedWorkout = true
            record.relatedWorkoutUUID = overlappingRecord.workoutUUID
        }

        try context.save()
        TrainingStore.recordLocalWrite(reason: "normalized Health import records")
        records = try TrainingStore.fetchImportedHealthWorkouts(context: context)
        return records
    }

    private static func deleteImportedHealthLog(for record: HealthImportedWorkout, context: ModelContext) throws {
        guard let habitSystemKey = record.habitSystemKey else { return }
        let matchingLogs = try TrainingStore.fetchLogs(context: context)
            .filter { log in
                log.sourceType == .health &&
                log.habit?.systemKey == habitSystemKey &&
                abs(log.date.timeIntervalSince(record.endDate)) < 120
            }
            .sorted { abs($0.date.timeIntervalSince(record.endDate)) < abs($1.date.timeIntervalSince(record.endDate)) }

        if let log = matchingLogs.first {
            try TrainingStore.delete(log, context: context)
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

    private static func yearBackfillStartDate(now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 60 * 60)
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

    private static func overlapRatio(firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date) -> Double {
        let overlap = overlapDuration(firstStart: firstStart, firstEnd: firstEnd, secondStart: secondStart, secondEnd: secondEnd)
        let shorterDuration = min(firstEnd.timeIntervalSince(firstStart), secondEnd.timeIntervalSince(secondStart))
        guard shorterDuration > 0 else { return 0 }
        return overlap / shorterDuration
    }

    private static func overlapDuration(firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date) -> TimeInterval {
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
        switch habit.measurementType {
        case .booleanSession:
            return 1
        case .minutes:
            return max(1, (workout.duration / 60).rounded())
        case .count, .customNumber, .pages:
            return 1
        }
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
