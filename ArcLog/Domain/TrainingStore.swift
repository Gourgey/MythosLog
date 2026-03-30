import Foundation
import SwiftData

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
        AppSettings.self
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
        let descriptor = FetchDescriptor<StatDomain>(sortBy: [SortDescriptor(\.name)])
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
        for template in TrainingArcConfig.statTemplates {
            let baseline = max(TrainingArcConfig.minimumBaseline, baselines[template.key] ?? template.defaultBaseline)
            let startingLevel = TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(baseline))
            let stat = StatDomain(
                key: template.key.rawValue,
                name: template.key.displayName,
                iconName: template.iconName,
                colorToken: template.colorToken,
                descriptor: TrainingArcConfig.overview(for: template.key),
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
        for item in try fetchLogs(context: context) { context.delete(item) }
        for item in try fetchResolutions(context: context) { context.delete(item) }
        for item in try fetchHabits(context: context) { context.delete(item) }
        for item in try fetchStats(context: context) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<AppSettings>()) { context.delete(item) }
        try context.save()
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
        stat.chargeValue = max(0, stat.chargeValue)
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

            let stat = StatDomain(
                key: template.key.rawValue,
                name: template.key.displayName,
                iconName: template.iconName,
                colorToken: template.colorToken,
                descriptor: TrainingArcConfig.overview(for: template.key),
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

    static func recentLogSnapshots(for stat: StatDomain, limit: Int? = nil) -> [SkillLogEntrySnapshot] {
        let logs = recentLogs(for: stat)
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
        chargeMaximum: Int,
        nextRank: RankLevelDefinition?,
        now: Date = .now
    ) -> String {
        let counter = weeklyCounterLabel(for: stat)
        if let nextRank {
            return "\(counter) builds through the week. At Sunday midnight your surplus is banked into charge. You currently have \(chargeValue) of \(chargeMaximum) charges toward \(nextRank.title)."
        }
        return "\(counter) still banks on Sunday night, but this skill is already at the current maximum rank."
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
        chargeMaximum: Int,
        nextRank: RankLevelDefinition?
    ) -> String {
        guard let nextRank else { return "You have reached the current maximum rank." }
        let remaining = max(chargeMaximum - chargeValue, 0)
        if remaining == 0 {
            return "The next banked check can promote you to \(nextRank.title)."
        }
        let unit = remaining == 1 ? "charge" : "charges"
        return "\(remaining) more \(unit) will unlock \(nextRank.title)."
    }

    static func nextActionLabel(
        for stat: StatDomain,
        settings: AppSettings?,
        nextRank: RankLevelDefinition?,
        chargeValue: Int,
        chargeMaximum: Int,
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
            return "Keep banking strong weeks to defend this max rank."
        }

        let remainingCharges = max(chargeMaximum - chargeValue, 0)
        if remainingCharges == 0 {
            return "Hold this pace through Sunday night to convert the next rank."
        }
        if remainingCharges == 1 {
            return "One more strong week will socket the final charge."
        }

        let pacing = pacingStatus(for: stat, settings: settings, now: now)
        if pacing == .ahead {
            return "You are ahead of pace. Keep stacking surplus for the next bank."
        }

        return "\(remainingCharges) more charges stand between you and \(nextRank?.title ?? "the next rank")."
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
        let chargeMaximum = nextRank.map { _ in
            TrainingArcConfig.nextRankChargeRequirement(for: definition.key, level: currentLevel) ?? max(chargeValue, 1)
        } ?? max(chargeValue, 1)
        let focusState = focusState(for: stat, settings: settings, chargeProgress: chargeProgress, now: now)

        return SkillProgressSnapshot(
            rank: RankSnapshot(
                level: currentLevel,
                maximumLevel: TrainingArcConfig.maximumRankLevel,
                title: currentRank.title,
                nextTitle: nextRank?.title,
                progressValue: Double(chargeValue),
                progressValueLabel: "\(chargeValue) charges",
                progressRequiredLabel: nextRank == nil ? "Maximum" : "\(chargeMaximum) charges",
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
                chargeMaximum: chargeMaximum,
                nextRank: nextRank,
                now: now
            ),
            nextEvaluationLabel: nextEvaluationLabel(now: now),
            nextRankImage: nextRank?.image,
            bankedChargeLabel: nextRank == nil ? "Maximum rank reached" : "\(chargeValue) / \(chargeMaximum) charges banked",
            nextRankStatusLabel: nextRankStatusLabel(
                for: stat,
                chargeValue: chargeValue,
                chargeMaximum: chargeMaximum,
                nextRank: nextRank
            ),
            focusState: focusState,
            nextActionLabel: nextActionLabel(
                for: stat,
                settings: settings,
                nextRank: nextRank,
                chargeValue: chargeValue,
                chargeMaximum: chargeMaximum,
                now: now
            ),
            pacingStatus: pacing,
            bankCountdownLabel: bankCountdownLabel(now: now)
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
                chargesEarned: max(0, Int(floor(result.weeklyDelta / Double(max(state.expectedWeeklyTarget, 1))))),
                chargesSpentOnLevelUp: result.didLevelUp ? (TrainingArcConfig.nextRankChargeRequirement(for: statKey, level: result.levelBefore) ?? 0) : 0,
                bankedUnitsBefore: result.bankedUnitsBefore,
                bankedUnitsAfter: result.bankedUnitsAfter,
                levelBefore: result.levelBefore,
                levelAfter: result.levelAfter,
                storedChargesAfter: result.visibleChargesAfter,
                didDecay: result.didLevelDown,
                didLevelUp: result.didLevelUp,
                didStagnate: result.weeklyDelta < 0,
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
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) advanced \(stat.name) to Level \(result.levelAfter)."
        }
        if result.didLevelDown {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) dropped \(stat.name) to Level \(result.levelAfter)."
        }
        if result.weeklyDelta >= 0 {
            return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) banked extra charge for the next rank check."
        }
        return "Week of \(week.displayTitle): \(actualLabel) against \(expectedLabel) created charge debt that can pull the rank down later."
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
            return MomentumStatus(title: "Momentum Rising", subtitle: "You are pushing beyond baseline and banking pressure.", score: score)
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

        let snapshot = TrainingWidgetSnapshot(
            generatedAt: now,
            appName: AppIdentity.displayName,
            momentumTitle: momentum.title,
            momentumSubtitle: momentum.subtitle,
            characterSummary: selfSummary(from: stats),
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
            themePreference: ThemePreference(rawValue: bundle.settings.themePreferenceRaw) ?? .dark,
            dashboardLayoutMode: DashboardLayoutMode(rawValue: bundle.settings.dashboardLayoutModeRaw) ?? .detailedCards
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
