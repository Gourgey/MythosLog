import Foundation
import SwiftData

// JSON backup/restore (export/import bundle) and debug sample-data seeding.

extension TrainingStore {
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
}
