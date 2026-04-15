import Foundation
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
enum TrainingStore {
    private struct PersistentStoreCandidate {
        let configuration: ModelConfiguration
        let storeURL: URL?
    }

    static let schema = Schema([
        StatDomain.self,
        Habit.self,
        HabitLog.self,
        WeeklyResolution.self,
        AppSettings.self,
        HealthImportedWorkout.self
    ])

    static let sharedModelContainer = makeModelContainer()

    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        let fileManager = FileManager.default
        let canUseAppGroup = !inMemory && fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentity.appGroupIdentifier
        ) != nil

        let candidates: [PersistentStoreCandidate] = [
            makeConfigurationCandidate(inMemory: inMemory, useAppGroup: canUseAppGroup),
            makeConfigurationCandidate(inMemory: inMemory, useAppGroup: false)
        ]
        var lastError: Error?

        for candidate in candidates {
            do {
                return try ModelContainer(for: schema, configurations: candidate.configuration)
            } catch {
                lastError = error

                guard !inMemory, let storeURL = candidate.storeURL else {
                    continue
                }

                do {
                    try resetPersistentStore(at: storeURL)
                    return try ModelContainer(for: schema, configurations: candidate.configuration)
                } catch {
                    lastError = error
                    continue
                }
            }
        }

        let message = lastError.map { String(describing: $0) } ?? "Unknown SwiftData error"
        fatalError("Unable to create ModelContainer. \(message)")
    }

    private static func makeConfigurationCandidate(inMemory: Bool, useAppGroup: Bool) -> PersistentStoreCandidate {
        if inMemory {
            return PersistentStoreCandidate(
                configuration: ModelConfiguration(
                    AppIdentity.displayName,
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                ),
                storeURL: nil
            )
        }

        let storeURL = persistentStoreURL(useAppGroup: useAppGroup)
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        return PersistentStoreCandidate(
            configuration: ModelConfiguration(
                AppIdentity.displayName,
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            ),
            storeURL: storeURL
        )
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
        try? synchronizeCatalog(context: context)
        try? refreshAllProgress(context: context, reason: .appRefresh)
        try? refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
    }

    static func fetchSettings(context: ModelContext) throws -> AppSettings {
        if let settings = try context.fetch(FetchDescriptor<AppSettings>()).first {
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }

    static func fetchStats(context: ModelContext) throws -> [StatDomain] {
        let descriptor = FetchDescriptor<StatDomain>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    static func fetchActiveStats(context: ModelContext) throws -> [StatDomain] {
        try fetchStats(context: context).filter { !$0.isArchived }
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
                lastAcknowledgedLevel: startingLevel
            )
            updateDerivedFields(for: stat)
            context.insert(stat)
            statIndex[template.key] = stat
        }

        let selectedKeys = selectedHabitKeys.isEmpty ? Set(TrainingArcConfig.defaultHabitTemplates.map(\.systemKey)) : selectedHabitKeys

        for (offset, template) in TrainingArcConfig.defaultHabitTemplates.enumerated() where selectedKeys.contains(template.systemKey) {
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
        try refreshAllProgress(context: context, reason: .onboarding)
        try refreshWidgetSnapshot(context: context)
    }

    static func clearAll(context: ModelContext) throws {
        for item in try fetchImportedHealthWorkouts(context: context) { context.delete(item) }
        for item in try fetchLogs(context: context) { context.delete(item) }
        for item in try fetchResolutions(context: context) { context.delete(item) }
        for item in try fetchHabits(context: context) { context.delete(item) }
        for item in try fetchStats(context: context) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<AppSettings>()) { context.delete(item) }
        try context.save()
        let defaults = UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
        defaults.removeObject(forKey: AppIdentity.healthWorkoutAnchorKey)
        try refreshWidgetSnapshot(context: context)
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

        for (offset, template) in TrainingArcConfig.statTemplates.enumerated() {
            if let existing = statLookup[template.key] {
                let didChange =
                    existing.name != template.key.displayName ||
                    existing.iconName != template.iconName ||
                    existing.colorToken != template.colorToken
                existing.name = template.key.displayName
                existing.iconName = template.iconName
                existing.colorToken = template.colorToken
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
                lastAcknowledgedLevel: TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(template.defaultBaseline))
            )
            updateDerivedFields(for: stat)
            context.insert(stat)
            statLookup[template.key] = stat
            didMutate = true

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

        if didMutate {
            try context.save()
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
        context: ModelContext
    ) throws -> HabitLog {
        let numericValue = habit.measurementType == .booleanSession ? 1 : max(0, value)
        let log = HabitLog(
            date: date,
            numericValue: numericValue,
            sessionType: normalizedSessionType(sessionType),
            note: note,
            sourceType: source,
            habit: habit
        )
        habit.updatedAt = .now
        context.insert(log)
        try context.save()
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
        if let stat {
            try refreshProgress(for: stat, context: context, reason: .deleteMutation, now: max(affectedDate, .now))
        }
        try refreshWidgetSnapshot(context: context)
    }

    static func total(for habit: Habit, in interval: DateInterval) -> Double {
        habit.logs
            .filter { interval.contains($0.date) }
            .reduce(0) { $0 + $1.numericValue }
    }

    static func total(for stat: StatDomain, in interval: DateInterval) -> Double {
        stat.habits
            .filter(\.active)
            .reduce(0) { total, habit in
                total + self.total(for: habit, in: interval)
            }
    }

    static func activeHabits(for stat: StatDomain) -> [Habit] {
        stat.habits
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
            .flatMap(\.logs)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.date > rhs.date
            }
    }

    static func recentLogSnapshots(for stat: StatDomain, limit: Int? = nil, since: Date? = nil) -> [SkillLogEntrySnapshot] {
        let logs = recentLogs(for: stat)
            .filter { log in
                guard let since else { return true }
                return log.date >= since
            }
        let trimmed = limit.map { Array(logs.prefix($0)) } ?? logs
        return trimmed.map(logSnapshot(for:))
    }

    static func logSnapshot(for log: HabitLog) -> SkillLogEntrySnapshot {
        SkillLogEntrySnapshot(
            id: log.id,
            habitName: log.habit?.name ?? "Session",
            valueLabel: MetricFormatting.metric(log.numericValue, unit: log.habit?.unitLabel ?? ""),
            date: log.date,
            note: log.note,
            sessionType: normalizedSessionType(log.sessionType)
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
        return "Banks \(formatter.string(from: nextWeeklyEvaluationDate(now: now)))"
    }

    static func bankCountdownLabel(now: Date = .now) -> String {
        let evaluationDate = nextWeeklyEvaluationDate(now: now)
        let remaining = max(Int(evaluationDate.timeIntervalSince(now)), 0)
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return "Banking in \(days)d \(hours)h"
        }
        if hours > 0 {
            return "Banking in \(hours)h \(minutes)m"
        }
        return "Banking in \(max(minutes, 1))m"
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
            return remainingDebt == 1
                ? "One more weak week will drop this skill a rank."
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
        now: Date = .now
    ) -> SkillWeekSnapshot {
        let calendar = progressionCalendar()
        let interval = WeekMath.dateInterval(for: week, calendar: calendar)
        let logs = activeHabits(for: stat)
            .flatMap(\.logs)
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
        return SkillWeekSnapshot(
            week: week,
            daySummaries: daySummaries,
            totalValue: total,
            totalLabel: MetricFormatting.shortMetric(total),
            logEntries: logs.map(logSnapshot(for:))
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
        let stats = try fetchActiveStats(context: context)
        var didChange = false

        for stat in stats {
            if try refreshProgress(for: stat, context: context, reason: reason, now: now, autosave: false) {
                didChange = true
            }
        }

        if didChange || context.hasChanges {
            try context.save()
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
        let hadExistingResolutions = !stat.weeklyResolutions.isEmpty

        for resolution in stat.weeklyResolutions {
            context.delete(resolution)
        }

        var state = ProgressionEngine.initialState(for: statKey, startingBaseline: stat.startingBaseline)
        let completedWeeks = completedProgressionWeeks(for: stat, now: now)

        for week in completedWeeks {
            let actual = total(for: stat, in: WeekMath.dateInterval(for: week, calendar: progressionCalendar()))
            let result = ProgressionEngine.evaluateWeek(statKey: statKey, state: state, actualTotal: actual)
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
        }

        return didChange || context.hasChanges
    }

    static func acknowledgePendingRankChange(for stat: StatDomain, context: ModelContext) throws {
        stat.acknowledgedRankLevel = stat.rankLevel
        stat.clearPendingRankChange()
        updateDerivedFields(for: stat)
        try context.save()
        try refreshWidgetSnapshot(context: context)
    }

    static func completedProgressionWeeks(for stat: StatDomain, now: Date = .now) -> [WeekRange] {
        guard let lastCompletedWeek = lastCompletedProgressionWeek(before: now) else { return [] }
        let earliestLogDate = activeHabits(for: stat).flatMap(\.logs).map(\.date).min()
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
        if result.didLevelUp {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) advanced \(stat.name) to Level \(result.levelAfter) after reaching +4 charge."
        }
        if result.didLevelDown {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) dropped \(stat.name) to Level \(result.levelAfter) after reaching -4 charge."
        }
        if result.weeklyChargeDelta > 0 {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) added +\(result.weeklyChargeDelta) charge."
        }
        if result.weeklyChargeDelta < 0 {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) added \(result.weeklyChargeDelta) charge."
        }
        if result.didDecayTowardZero {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) held steady while charge drifted 1 step back toward zero."
        }
        return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) held this rank steady."
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
        try refreshWidgetSnapshot(context: context)
        refreshHomeScreenQuickActions()
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
            switch stat.statKey {
            case .strength:
                items.append("Strength: \(stat.rankTitle)")
            case .intellect:
                items.append("Intellect: \(stat.rankTitle)")
            case .creativity:
                items.append("Creativity: \(stat.rankTitle)")
            case .emotional:
                items.append("Emotional: \(stat.rankTitle)")
            case .focus:
                items.append("Focus: \(stat.rankTitle)")
            case .curiosity:
                items.append("Curiosity: \(stat.rankTitle)")
            case .cardio:
                items.append("Cardio: \(stat.rankTitle)")
            case .none:
                break
            }
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
            motivationMessage = "Lock in last week so your progress and charge carry forward cleanly."
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
            todayHabits: Array(habitSnapshots)
        )

        WidgetSnapshotStore.save(snapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func exportBundle(context: ModelContext) throws -> TrainingExportBundle {
        let stats = try fetchStats(context: context)
        let habits = try fetchHabits(context: context)
        let logs = try fetchLogs(context: context)
        let resolutions = try fetchResolutions(context: context)
        let settings = try fetchSettings(context: context)

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
                    storedCharges: $0.storedCharges,
                    bankedProgressUnits: $0.bankedProgressUnits,
                    lastResolvedWeekStart: $0.lastResolvedWeekStart,
                    lastAcknowledgedLevel: $0.lastAcknowledgedLevel,
                    pendingRankChangeDirectionRaw: $0.pendingRankChangeDirectionRaw,
                    pendingRankChangeFromLevel: $0.pendingRankChangeFromLevel,
                    pendingRankChangeToLevel: $0.pendingRankChangeToLevel,
                    pendingRankChangeRecordedAt: $0.pendingRankChangeRecordedAt,
                    pendingRankChangeReasonRaw: $0.pendingRankChangeReasonRaw,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    isArchived: $0.isArchived
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
                dashboardLayoutModeRaw: settings.dashboardLayoutModeRaw
            )
        )
    }

    static func importBundle(_ bundle: TrainingExportBundle, context: ModelContext) throws {
        try clearAll(context: context)

        var statLookup: [UUID: StatDomain] = [:]
        for exported in bundle.stats {
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
                storedCharges: exported.storedCharges,
                bankedProgressUnits: exported.bankedProgressUnits,
                lastResolvedWeekStart: exported.lastResolvedWeekStart,
                lastAcknowledgedLevel: exported.lastAcknowledgedLevel,
                pendingRankChangeDirectionRaw: exported.pendingRankChangeDirectionRaw,
                pendingRankChangeFromLevel: exported.pendingRankChangeFromLevel,
                pendingRankChangeToLevel: exported.pendingRankChangeToLevel,
                pendingRankChangeRecordedAt: exported.pendingRankChangeRecordedAt,
                pendingRankChangeReasonRaw: exported.pendingRankChangeReasonRaw,
                createdAt: exported.createdAt,
                updatedAt: exported.updatedAt,
                isArchived: exported.isArchived
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
            themePreference: ThemePreference(rawValue: bundle.settings.themePreferenceRaw) ?? .dark,
            dashboardLayoutMode: DashboardLayoutMode(rawValue: bundle.settings.dashboardLayoutModeRaw) ?? .compactGrid
        )
        context.insert(settings)

        try context.save()
        try synchronizeCatalog(context: context)
        try refreshAllProgress(context: context, reason: .appRefresh)
        try refreshWidgetSnapshot(context: context)
        NotificationService.refreshNotifications(using: settings)
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
    var ignoredCount: Int
    var syncedAt: Date

    var message: String {
        if importedCount > 0 {
            return "Imported \(importedCount) workout\(importedCount == 1 ? "" : "s") from Apple Health."
        }

        if duplicateCount > 0 && ignoredCount == 0 {
            return "Apple Health is up to date. No new workouts were imported."
        }

        return "No new eligible Apple Health workouts were found."
    }
}

@MainActor
enum HealthImportService {
    private struct WorkoutMapping {
        var statKey: StatKey
        var sessionType: String
    }

    private static let healthStore = HKHealthStore()
    private static let connectedDefaultsKey = "training.arc.health.connected"
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
        _ = try? await performSync(context: context, settings: settings)
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

        let summary = try await performSync(context: context, settings: settings)
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

    private static func performSync(context: ModelContext, settings: AppSettings) async throws -> HealthSyncSummary {
        let anchor = loadAnchor()
        let initialWeekStart = TrainingStore.currentWeekInterval(settings: settings).start
        let predicate = anchor == nil
            ? HKQuery.predicateForSamples(withStart: initialWeekStart, end: nil, options: .strictStartDate)
            : nil
        let (workouts, newAnchor) = try await fetchWorkouts(anchor: anchor, predicate: predicate)
        let activeStats = try TrainingStore.fetchActiveStats(context: context)
        let existingRecords = try TrainingStore.fetchImportedHealthWorkouts(context: context)
        var existingWorkoutIDs = Set(existingRecords.map(\.workoutUUID))
        var importedCount = 0
        var duplicateCount = 0
        var ignoredCount = 0

        for workout in workouts.sorted(by: { $0.startDate < $1.startDate }) {
            let workoutID = workout.uuid.uuidString
            if existingWorkoutIDs.contains(workoutID) {
                duplicateCount += 1
                continue
            }

            guard
                let mapping = mapping(for: workout),
                let stat = activeStats.first(where: { $0.statKey == mapping.statKey }),
                let habit = TrainingStore.primaryHabit(for: stat)
            else {
                ignoredCount += 1
                continue
            }

            let value = loggedValue(for: workout, habit: habit)
            guard value > 0 else {
                ignoredCount += 1
                continue
            }

            let sourceName = workout.sourceRevision.source.name
            let note = "Imported from Apple Health\(sourceName.isEmpty ? "" : " via \(sourceName)")"
            _ = try TrainingStore.log(
                habit: habit,
                value: value,
                date: workout.endDate,
                sessionType: mapping.sessionType,
                note: note,
                source: .health,
                context: context
            )

            context.insert(
                HealthImportedWorkout(
                    workoutUUID: workoutID,
                    statKeyRaw: mapping.statKey.rawValue,
                    habitSystemKey: habit.systemKey,
                    sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
                    activityTypeRaw: Int(workout.workoutActivityType.rawValue),
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    durationMinutes: workout.duration / 60
                )
            )
            try context.save()

            existingWorkoutIDs.insert(workoutID)
            importedCount += 1
        }

        if let newAnchor {
            saveAnchor(newAnchor)
        }

        settings.lastHealthSyncAt = .now
        settings.updatedAt = .now
        try context.save()
        try TrainingStore.refreshWidgetSnapshot(context: context)
        TrainingStore.refreshHomeScreenQuickActions()

        return HealthSyncSummary(
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            ignoredCount: ignoredCount,
            syncedAt: settings.lastHealthSyncAt ?? .now
        )
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
        switch workout.workoutActivityType {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining:
            return WorkoutMapping(statKey: .strength, sessionType: "Strength")
        case .running, .walking, .cycling, .swimming, .rowing, .elliptical, .stairClimbing, .hiking, .mixedCardio, .highIntensityIntervalTraining, .jumpRope:
            return WorkoutMapping(statKey: .cardio, sessionType: "Cardio")
        default:
            return nil
        }
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
