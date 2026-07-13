import Foundation
import SwiftData

// Weekly progression resolution: replays completed weeks through
// ProgressionEngine, maintains WeeklyResolution rows and pending rank changes.

extension TrainingStore {
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

        // Reuse existing WeeklyResolution rows by week start so unchanged
        // weeks produce no writes: identity stays stable for SwiftUI and
        // CloudKit no longer sees a full delete-and-recreate of the history
        // on every log mutation.
        var reusableByWeekStart: [Date: WeeklyResolution] = [:]
        var staleResolutions: [WeeklyResolution] = []
        for resolution in (stat.weeklyResolutions ?? []).sorted(by: { $0.createdAt > $1.createdAt }) {
            if reusableByWeekStart[resolution.weekStartDate] == nil {
                reusableByWeekStart[resolution.weekStartDate] = resolution
            } else {
                staleResolutions.append(resolution)
            }
        }
        var resolutionsChanged = false

        var state = ProgressionEngine.initialState(for: statKey, startingBaseline: stat.startingBaseline)
        let completedWeeks = completedProgressionWeeks(for: stat, now: now)
        let settings = (try? fetchExistingSettings(context: context))
        let influenceEnabled = settings?.goalsCanAffectProgression ?? false
        let goalsForStat: [Goal] = influenceEnabled ? ((try? fetchGoals(for: statKey, context: context)) ?? []) : []
        let allowRankDown = settings?.regressionBehavior.allowsRankDown ?? true
        let decayEnabled = settings?.enableDecay ?? true

        for week in completedWeeks {
            let actual = total(for: stat, in: WeekMath.dateInterval(for: week, calendar: progressionCalendar()))
            let activeGoal = activeWeeklyGoal(for: goalsForStat, week: week)
            let result = ProgressionEngine.evaluateWeek(
                statKey: statKey,
                state: state,
                actualTotal: actual,
                activeGoalTarget: activeGoal.map { Int($0.targetValue.rounded()) },
                isRecoveryGoal: activeGoal?.isRecoveryMode ?? false,
                allowRankDown: allowRankDown,
                decayEnabled: decayEnabled
            )
            let baselineAtStart = state.expectedWeeklyTarget
            let summary = summaryText(for: stat, week: week, result: result)
            if let existing = reusableByWeekStart.removeValue(forKey: week.start) {
                if applyWeekResolution(result, week: week, baselineAtStart: baselineAtStart, summary: summary, stat: stat, to: existing) {
                    resolutionsChanged = true
                }
            } else {
                let resolution = WeeklyResolution(
                    statKey: stat.key,
                    statName: stat.name,
                    weekStartDate: week.start,
                    weekEndDate: week.end,
                    baselineAtStart: baselineAtStart,
                    expectedTotal: result.expectedTotal,
                    actualCompletedValue: result.actualTotal,
                    weeklyDelta: result.weeklyDelta,
                    excessValue: result.weeklyDelta,
                    chargesEarned: result.weeklyChargeDelta,
                    chargesSpentOnLevelUp: (result.didLevelUp || result.didLevelDown) ? ChargeMath.slotsPerSide : 0,
                    bankedUnitsBefore: result.bankedUnitsBefore,
                    bankedUnitsAfter: result.bankedUnitsAfter,
                    levelBefore: result.levelBefore,
                    levelAfter: result.levelAfter,
                    storedChargesAfter: result.visibleChargesAfter,
                    didDecay: result.didDecayTowardZero,
                    didLevelUp: result.didLevelUp,
                    didStagnate: result.weeklyChargeDelta == 0,
                    didRegress: result.didLevelDown,
                    summaryText: summary,
                    statDomain: stat
                )
                context.insert(resolution)
                resolutionsChanged = true
            }
            state = result.state
        }

        staleResolutions.append(contentsOf: reusableByWeekStart.values)
        for stale in staleResolutions {
            context.delete(stale)
            resolutionsChanged = true
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
            resolutionsChanged

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

    /// Writes a recomputed week onto an existing resolution row, assigning
    /// only fields that actually differ. Returns true when anything changed.
    private static func applyWeekResolution(
        _ result: WeeklyProgressionResult,
        week: WeekRange,
        baselineAtStart: Int,
        summary: String,
        stat: StatDomain,
        to resolution: WeeklyResolution
    ) -> Bool {
        var changed = false
        func assign<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<WeeklyResolution, T>, _ value: T) {
            if resolution[keyPath: keyPath] != value {
                resolution[keyPath: keyPath] = value
                changed = true
            }
        }
        assign(\.statKey, stat.key)
        assign(\.statName, stat.name)
        assign(\.weekStartDate, week.start)
        assign(\.weekEndDate, week.end)
        assign(\.baselineAtStart, baselineAtStart)
        assign(\.expectedTotal, result.expectedTotal)
        assign(\.actualCompletedValue, result.actualTotal)
        assign(\.weeklyDelta, result.weeklyDelta)
        assign(\.excessValue, result.weeklyDelta)
        assign(\.chargesEarned, result.weeklyChargeDelta)
        assign(\.chargesSpentOnLevelUp, (result.didLevelUp || result.didLevelDown) ? ChargeMath.slotsPerSide : 0)
        assign(\.bankedUnitsBefore, result.bankedUnitsBefore)
        assign(\.bankedUnitsAfter, result.bankedUnitsAfter)
        assign(\.levelBefore, result.levelBefore)
        assign(\.levelAfter, result.levelAfter)
        assign(\.storedChargesAfter, result.visibleChargesAfter)
        assign(\.didDecay, result.didDecayTowardZero)
        assign(\.didLevelUp, result.didLevelUp)
        assign(\.didStagnate, result.weeklyChargeDelta == 0)
        assign(\.didRegress, result.didLevelDown)
        assign(\.summaryText, summary)
        if resolution.statDomain !== stat {
            resolution.statDomain = stat
            changed = true
        }
        return changed
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
}
