import Foundation
import SwiftData

#if canImport(WidgetKit)
import WidgetKit
#endif

// Snapshot/DTO builders for the views and widgets: log entries, week and
// progress snapshots, user-facing label strings, and the widget snapshot.

extension TrainingStore {
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

    static func weeklyCounterLabel(for stat: StatDomain) -> String {
        switch primaryHabit(for: stat)?.measurementType {
        case .booleanSession:
            return "Baseline Sessions"
        case .pages:
            return "Baseline Pages"
        case .minutes:
            return "Baseline Minutes"
        case .count:
            return "Baseline Count"
        case .customNumber:
            return "Baseline Progress"
        case .none:
            return "Baseline Total"
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
            return "times"
        case .customNumber:
            return "points"
        case .none:
            return "logs"
        }
    }

    private static let evaluationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE 'at' HH:mm"
        return formatter
    }()

    static func nextEvaluationLabel(now: Date = .now) -> String {
        "Resolves \(evaluationDateFormatter.string(from: nextWeeklyEvaluationDate(now: now)))"
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
        let chargeLimit = ChargeMath.slotsPerSide

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

        let remainingCharges = max(ChargeMath.slotsPerSide - max(chargeValue, 0), 0)
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
        let chargeMaximum = ChargeMath.slotsPerSide
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
                progressValueLabel: ChargeMath.summaryLabel(for: chargeValue),
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
                : ChargeMath.summaryLabel(for: chargeValue),
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
        let bankedChargeSummary = ChargeMath.summaryLabel(for: snapshot.charge.current)
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

    static func refreshWidgetSnapshot(context: ModelContext, now: Date = .now) throws {
        let settings = try? fetchExistingSettings(context: context)
        let interval = currentWeekInterval(settings: settings, now: now)
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

        let recommendations = (try? trainTodayRecommendations(context: context, settings: settings, now: now, limit: 1)) ?? []
        let topRec = recommendations.first
        let goalSnapshots = (try? goalProgressSnapshots(context: context, now: now)) ?? []
        let goalsAtRiskCount = goalSnapshots.filter {
            $0.goal.status == .active && ($0.paceStatus == .atRisk || $0.paceStatus == .behind)
        }.count

        let snapshot = TrainingWidgetSnapshot(
            generatedAt: now,
            appName: AppIdentity.displayName,
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
            goalsAtRiskCount: goalsAtRiskCount
        )

        WidgetSnapshotStore.save(snapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
