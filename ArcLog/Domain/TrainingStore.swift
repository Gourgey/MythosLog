import Foundation
import SwiftData

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
enum TrainingStore {
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

        let configurations: [ModelConfiguration] = [
            makeConfiguration(inMemory: inMemory, useAppGroup: canUseAppGroup),
            makeConfiguration(inMemory: inMemory, useAppGroup: false)
        ]

        for configuration in configurations {
            do {
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                continue
            }
        }

        fatalError("Unable to create ModelContainer.")
    }

    private static func makeConfiguration(inMemory: Bool, useAppGroup: Bool) -> ModelConfiguration {
        if useAppGroup {
            return ModelConfiguration(
                AppIdentity.displayName,
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                groupContainer: .identifier(AppIdentity.appGroupIdentifier),
                cloudKitDatabase: .none
            )
        }

        return ModelConfiguration(
            AppIdentity.displayName,
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
    }

    static func refreshAppState() {
        let context = ModelContext(sharedModelContainer)
        try? synchronizeCatalog(context: context)
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
            let stat = StatDomain(
                key: template.key.rawValue,
                name: template.key.displayName,
                iconName: template.iconName,
                colorToken: template.colorToken,
                descriptor: TrainingArcConfig.overview(for: template.key),
                currentLevel: TrainingArcConfig.minimumRankLevel,
                currentTierName: TrainingArcConfig.rankTitle(for: template.key, level: TrainingArcConfig.minimumRankLevel),
                currentBaseline: baseline
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
        stat.rankLevel = stat.currentLevel
        stat.rankTitle = TrainingArcConfig.rankTitle(for: key, level: stat.rankLevel)
        stat.descriptor = TrainingArcConfig.overview(for: key)
        stat.updatedAt = .now
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
                existing.name = template.key.displayName
                existing.iconName = template.iconName
                existing.colorToken = template.colorToken
                updateDerivedFields(for: existing)
                didMutate = true
                continue
            }

            let stat = StatDomain(
                key: template.key.rawValue,
                name: template.key.displayName,
                iconName: template.iconName,
                colorToken: template.colorToken,
                descriptor: TrainingArcConfig.overview(for: template.key),
                currentLevel: TrainingArcConfig.minimumRankLevel,
                currentTierName: TrainingArcConfig.rankTitle(for: template.key, level: TrainingArcConfig.minimumRankLevel),
                currentBaseline: template.defaultBaseline
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
        }
    }

    @discardableResult
    static func log(
        habit: Habit,
        value: Double,
        date: Date,
        note: String,
        source: LogSourceType,
        context: ModelContext
    ) throws -> HabitLog {
        let numericValue = habit.measurementType == .booleanSession ? 1 : max(0, value)
        let log = HabitLog(date: date, numericValue: numericValue, note: note, sourceType: source, habit: habit)
        habit.updatedAt = .now
        context.insert(log)
        try context.save()
        try refreshWidgetSnapshot(context: context)
        return log
    }

    static func delete(_ log: HabitLog, context: ModelContext) throws {
        context.delete(log)
        try context.save()
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

    static func currentWeekInterval(settings: AppSettings?, now: Date = .now) -> DateInterval {
        let weekStartsOnMonday = settings?.weekStartsOnMonday ?? true
        let week = WeekMath.weekRange(containing: now, weekStartsOnMonday: weekStartsOnMonday)
        return WeekMath.dateInterval(
            for: week,
            calendar: WeekMath.calendar(weekStartsOnMonday: weekStartsOnMonday)
        )
    }

    static func currentWeekTotal(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Double {
        total(for: stat, in: currentWeekInterval(settings: settings, now: now))
    }

    static func currentWeekEarnedRankProgress(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Int {
        let actual = Int(currentWeekTotal(for: stat, settings: settings, now: now).rounded(.down))
        return max(0, actual - stat.currentBaseline)
    }

    static func projectedStoredRankProgress(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Int {
        stat.rankProgress + currentWeekEarnedRankProgress(for: stat, settings: settings, now: now)
    }

    static func rankProgressToNextLevel(for stat: StatDomain) -> Double {
        Double(stat.rankProgress) / Double(TrainingArcConfig.requiredRankProgressToLevelUp)
    }

    static func projectedRankProgressToNextLevel(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Double {
        min(
            Double(projectedStoredRankProgress(for: stat, settings: settings, now: now))
                / Double(TrainingArcConfig.requiredRankProgressToLevelUp),
            1
        )
    }

    static func currentCharge(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Int {
        guard let key = stat.statKey else { return 0 }
        return TrainingArcConfig.currentCharge(
            for: key,
            actual: currentWeekTotal(for: stat, settings: settings, now: now),
            baseline: stat.currentBaseline
        )
    }

    static func currentChargeProgress(for stat: StatDomain, settings: AppSettings?, now: Date = .now) -> Double {
        guard let key = stat.statKey else { return 0 }
        return TrainingArcConfig.chargeProgress(
            for: key,
            actual: currentWeekTotal(for: stat, settings: settings, now: now),
            baseline: stat.currentBaseline
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
        let projectedRankProgress = projectedStoredRankProgress(for: stat, settings: settings, now: now)

        return SkillProgressSnapshot(
            rank: RankSnapshot(
                level: currentLevel,
                maximumLevel: TrainingArcConfig.maximumRankLevel,
                title: currentRank.title,
                nextTitle: nextRank?.title,
                progressUnits: projectedRankProgress,
                progressRequired: TrainingArcConfig.requiredRankProgressToLevelUp,
                progressToNextLevel: projectedRankProgressToNextLevel(for: stat, settings: settings, now: now),
                isAtMaximumRank: currentLevel >= TrainingArcConfig.maximumRankLevel,
                image: currentRank.image
            ),
            charge: ChargeSnapshot(
                current: chargeValue,
                maximum: definition.charge.maximumValue,
                progress: chargeProgress,
                label: definition.charge.label
            ),
            overview: definition.overview,
            currentWeekActual: currentWeekActual,
            baseline: stat.currentBaseline,
            earnedRankProgressThisWeek: currentWeekEarnedRankProgress(for: stat, settings: settings, now: now)
        )
    }

    static func pendingWeek(context: ModelContext, now: Date = .now) throws -> WeekRange? {
        let settings = try fetchSettings(context: context)
        let week = WeekMath.lastCompletedWeek(before: now, weekStartsOnMonday: settings.weekStartsOnMonday)
        let stats = try fetchActiveStats(context: context)
        guard !stats.isEmpty else { return nil }

        let existing = try fetchResolutions(context: context).filter {
            WeekMath.isSameWeek($0.weekStartDate, week.start, weekStartsOnMonday: settings.weekStartsOnMonday)
        }

        let resolvedKeys = Set(existing.map(\.statKey))
        let activeKeys = Set(stats.map(\.key))
        return resolvedKeys == activeKeys ? nil : week
    }

    static func latestResolvedWeek(context: ModelContext) throws -> WeekRange? {
        guard let latest = try fetchResolutions(context: context).last else { return nil }
        return WeekRange(start: latest.weekStartDate, end: latest.weekEndDate)
    }

    @discardableResult
    static func resolvePendingWeek(context: ModelContext, now: Date = .now) throws -> WeeklyReviewBatch? {
        let settings = try fetchSettings(context: context)
        let week = WeekMath.lastCompletedWeek(before: now, weekStartsOnMonday: settings.weekStartsOnMonday)
        let stats = try fetchActiveStats(context: context)
        guard !stats.isEmpty else { return nil }

        let existing = try fetchResolutions(context: context).filter {
            WeekMath.isSameWeek($0.weekStartDate, week.start, weekStartsOnMonday: settings.weekStartsOnMonday)
        }

        var resolutions = existing
        let resolvedKeys = Set(existing.map(\.statKey))
        let interval = WeekMath.dateInterval(for: week, calendar: WeekMath.calendar(weekStartsOnMonday: settings.weekStartsOnMonday))

        for stat in stats where !resolvedKeys.contains(stat.key) {
            let history = stat.weeklyResolutions
                .sorted { $0.weekStartDate < $1.weekStartDate }
                .map { HistoricWeeklyPerformance(actual: $0.actualCompletedValue, baseline: $0.baselineAtStart) }

            let actual = total(for: stat, in: interval)
            let result = ProgressionEngine.resolve(
                state: ProgressionState(
                    baseline: stat.currentBaseline,
                    storedRankProgress: stat.rankProgress,
                    level: stat.rankLevel
                ),
                actual: actual,
                history: history,
                decaySettings: DecaySettings(
                    isEnabled: settings.enableDecay,
                    sensitivity: settings.decaySensitivity,
                    minimumBaseline: TrainingArcConfig.minimumBaseline
                )
            )

            stat.currentBaseline = result.baselineAfter
            stat.rankLevel = result.levelAfter
            stat.rankProgress = result.storedRankProgressAfter
            updateDerivedFields(for: stat)

            let resolution = WeeklyResolution(
                statKey: stat.key,
                statName: stat.name,
                weekStartDate: week.start,
                weekEndDate: week.end,
                baselineAtStart: result.baselineBefore,
                actualCompletedValue: result.actual,
                excessValue: result.excessValue,
                chargesEarned: result.rankProgressEarned,
                chargesSpentOnLevelUp: result.rankProgressSpentOnLevelUp,
                levelBefore: result.levelBefore,
                levelAfter: result.levelAfter,
                storedChargesAfter: result.storedRankProgressAfter,
                didDecay: result.didDecay,
                didLevelUp: result.flags.contains(.rankUp),
                didStagnate: result.flags.contains(.stagnationWarning),
                didRegress: result.flags.contains(.baselineRegression),
                summaryText: result.summary,
                statDomain: stat
            )

            context.insert(resolution)
            resolutions.append(resolution)
        }

        guard !resolutions.isEmpty else { return nil }

        try context.save()
        try refreshWidgetSnapshot(context: context)
        return WeeklyReviewBatch(week: week, resolutions: resolutions.sorted { $0.statName < $1.statName })
    }

    static func momentum(context: ModelContext, now: Date = .now) throws -> MomentumStatus {
        let settings = try fetchSettings(context: context)
        let week = WeekMath.weekRange(containing: now, weekStartsOnMonday: settings.weekStartsOnMonday)
        let interval = WeekMath.dateInterval(for: week, calendar: WeekMath.calendar(weekStartsOnMonday: settings.weekStartsOnMonday))
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
            return MomentumStatus(title: "Slipping", subtitle: "A few core stats are under baseline.", score: score)
        case ..<1.05:
            return MomentumStatus(title: "Holding", subtitle: "You are maintaining current form.", score: score)
        default:
            return MomentumStatus(title: "Rising", subtitle: "You are pushing beyond the current build.", score: score)
        }
    }

    static func weakestStat(context: ModelContext, now: Date = .now) throws -> StatDomain? {
        let settings = try fetchSettings(context: context)
        let week = WeekMath.weekRange(containing: now, weekStartsOnMonday: settings.weekStartsOnMonday)
        let interval = WeekMath.dateInterval(for: week, calendar: WeekMath.calendar(weekStartsOnMonday: settings.weekStartsOnMonday))
        return try fetchActiveStats(context: context).min { lhs, rhs in
            let lhsRatio = total(for: lhs, in: interval) / max(Double(lhs.currentBaseline), 1)
            let rhsRatio = total(for: rhs, in: interval) / max(Double(rhs.currentBaseline), 1)
            return lhsRatio < rhsRatio
        }
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
        let settings = try fetchSettings(context: context)
        let week = WeekMath.weekRange(containing: now, weekStartsOnMonday: settings.weekStartsOnMonday)
        let interval = WeekMath.dateInterval(for: week, calendar: WeekMath.calendar(weekStartsOnMonday: settings.weekStartsOnMonday))
        let stats = try fetchActiveStats(context: context)
        let habits = try fetchActiveHabits(context: context)
        let momentum = try momentum(context: context, now: now)
        let weakest = try weakestStat(context: context, now: now)
        let pending = try pendingWeek(context: context, now: now) != nil

        let statSnapshots = stats.map { stat in
            let progress = Double(stat.rankProgress) / Double(TrainingArcConfig.requiredRankProgressToLevelUp)
            return TrainingWidgetStat(
                id: stat.id,
                name: stat.name,
                descriptor: stat.rankTitle,
                level: stat.rankLevel,
                baseline: stat.currentBaseline,
                storedCharges: stat.rankProgress,
                weekActual: total(for: stat, in: interval),
                progressToNextLevel: min(progress, 1),
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
                    currentBaseline: $0.currentBaseline,
                    storedCharges: $0.storedCharges,
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
                    actualCompletedValue: $0.actualCompletedValue,
                    excessValue: $0.excessValue,
                    chargesEarned: $0.chargesEarned,
                    chargesSpentOnLevelUp: $0.chargesSpentOnLevelUp,
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
                themePreferenceRaw: settings.themePreferenceRaw
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
                currentBaseline: exported.currentBaseline,
                storedCharges: exported.storedCharges,
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
                actualCompletedValue: exported.actualCompletedValue,
                excessValue: exported.excessValue,
                chargesEarned: exported.chargesEarned,
                chargesSpentOnLevelUp: exported.chargesSpentOnLevelUp,
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
            themePreference: ThemePreference(rawValue: bundle.settings.themePreferenceRaw) ?? .dark
        )
        context.insert(settings)

        try context.save()
        try synchronizeCatalog(context: context)
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
        let settings = try fetchSettings(context: context)
        let currentWeekStart = WeekMath.startOfWeek(for: now, weekStartsOnMonday: settings.weekStartsOnMonday)
        let calendar = WeekMath.calendar(weekStartsOnMonday: settings.weekStartsOnMonday)
        let habits = try fetchActiveHabits(context: context)

        func createWeek(at offset: Int, multiplier: Double) throws {
            guard let weekStart = calendar.date(byAdding: .day, value: -(offset * 7), to: currentWeekStart) else { return }
            for habit in habits {
                try addSeededLogs(for: habit, weekStart: weekStart, total: habit.targetPerPeriod * multiplier, context: context)
            }
            let triggerDate = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
            _ = try resolvePendingWeek(context: context, now: triggerDate)
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
            for stat in try fetchActiveStats(context: context) {
                stat.rankProgress = TrainingArcConfig.requiredRankProgressToLevelUp - 1
                stat.updatedAt = .now
            }
            for habit in habits {
                try addSeededLogs(for: habit, weekStart: calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart, total: habit.targetPerPeriod + 1, context: context)
            }
        }

        try context.save()
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
}
