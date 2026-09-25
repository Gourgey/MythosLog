import Foundation
import SwiftData

// Goal CRUD, automatic status transitions, and goal progress/pace computation.

extension TrainingStore {
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
        goal.attentionViewedAt = nil
        goal.updatedAt = .now
        try context.save()
        recordLocalWrite(reason: "updated goal")
    }

    static func setGoalStatus(_ goal: Goal, status: GoalStatus, context: ModelContext) throws {
        let previous = goal.status
        goal.status = status
        if status != previous {
            goal.attentionViewedAt = nil
        }
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
        var inputs: GoalProgressInputs?

        for goal in activeGoals {
            guard let endDate = goal.endDate, endDate < now else { continue }

            let newStatus: GoalStatus
            if recurringGoalTypes.contains(goal.type) {
                newStatus = .archived
            } else {
                let resolvedInputs = inputs ?? goalProgressInputs(context: context)
                inputs = resolvedInputs
                let progress = goalProgress(for: goal, inputs: resolvedInputs, now: now)
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

    /// Everything goal-progress math reads, fetched once per batch instead of
    /// once per goal (the full log table is the expensive fetch).
    struct GoalProgressInputs {
        var logs: [HabitLog]
        var statsByKey: [String: StatDomain]
    }

    static func goalProgressInputs(context: ModelContext) -> GoalProgressInputs {
        let logs = (try? fetchLogs(context: context)) ?? []
        let stats = (try? fetchStats(context: context)) ?? []
        let statsByKey = Dictionary(stats.compactMap { stat -> (String, StatDomain)? in
            guard let key = stat.statKey?.rawValue else { return nil }
            return (key, stat)
        }) { lhs, _ in lhs }
        return GoalProgressInputs(logs: logs, statsByKey: statsByKey)
    }

    static func goalProgress(for goal: Goal, context: ModelContext, now: Date = .now) -> GoalProgressSnapshot {
        goalProgress(for: goal, inputs: goalProgressInputs(context: context), now: now)
    }

    static func goalProgress(for goal: Goal, inputs: GoalProgressInputs, now: Date = .now) -> GoalProgressSnapshot {
        let currentValue = computeGoalCurrentValue(for: goal, inputs: inputs, now: now)
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
        let inputs = goalProgressInputs(context: context)
        return try fetchGoals(context: context).map { goal in
            goalProgress(for: goal, inputs: inputs, now: now)
        }
    }

    static func goalNeedsAttention(_ progress: GoalProgressSnapshot) -> Bool {
        progress.goal.status == .active && (progress.paceStatus == .atRisk || progress.paceStatus == .behind)
    }

    /// An acknowledgement silences the tab badge for the current week. Editing
    /// the goal or reaching a new week makes a still-struggling goal visible
    /// again, so "viewed" never hides future attention indefinitely.
    static func goalAttentionIsViewed(
        for goal: Goal,
        progress: GoalProgressSnapshot,
        now: Date = .now,
        weekStartsOnMonday: Bool
    ) -> Bool {
        guard goalNeedsAttention(progress), let viewedAt = goal.attentionViewedAt else { return false }
        let weekStart = WeekMath.startOfWeek(for: now, weekStartsOnMonday: weekStartsOnMonday)
        return viewedAt >= weekStart && viewedAt >= goal.updatedAt
    }

    static func goalHasUnviewedAttention(
        _ goal: Goal,
        progress: GoalProgressSnapshot,
        now: Date = .now,
        weekStartsOnMonday: Bool
    ) -> Bool {
        goalNeedsAttention(progress) && !goalAttentionIsViewed(
            for: goal,
            progress: progress,
            now: now,
            weekStartsOnMonday: weekStartsOnMonday
        )
    }

    static func markGoalAttentionViewed(_ goal: Goal, context: ModelContext, now: Date = .now) throws {
        goal.attentionViewedAt = now
        try context.save()
        recordLocalWrite(reason: "viewed goal attention")
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

    private static func computeGoalCurrentValue(for goal: Goal, inputs: GoalProgressInputs, now: Date) -> Double {
        switch goal.type {
        case .reachLevel, .reachRank:
            guard
                let statKey = goal.linkedStatKey,
                let stat = inputs.statsByKey[statKey.rawValue]
            else {
                return 0
            }
            return Double(stat.rankLevel)
        case .weeklyTarget:
            return totalForGoal(
                goal,
                in: boundedPeriodInterval(progressionWeekInterval(containing: now), for: goal),
                logs: inputs.logs
            )
        case .monthlyTotal:
            return totalForGoal(
                goal,
                in: boundedPeriodInterval(monthInterval(containing: now), for: goal),
                logs: inputs.logs
            )
        case .consistency, .maintainBaseline, .improveBalance, .custom:
            let interval = goalDateInterval(for: goal, now: now)
            return totalForGoal(goal, in: interval, logs: inputs.logs)
        }
    }

    private static func totalForGoal(_ goal: Goal, in interval: DateInterval, logs: [HabitLog]) -> Double {
        let filtered = logs.filter { log in
            guard interval.contains(log.date) else { return false }
            if let habitID = goal.linkedHabitID {
                return log.habit?.id == habitID
            }
            if let statKey = goal.linkedStatKey {
                return log.habit?.statDomain?.statKey == statKey
            }
            return true
        }
        // A session/count goal spanning several habits (e.g. "Log 20 sessions
        // this month") counts a minutes or pages log as one session rather
        // than adding its minutes or pages to the total.
        let countsSessions = goal.measurementType == .booleanSession || goal.measurementType == .count
        return filtered.reduce(0) { total, log in
            guard countsSessions, let habitType = log.habit?.measurementType,
                  habitType != .booleanSession, habitType != .count else {
                return total + log.numericValue
            }
            return total + 1
        }
    }

    private static func goalDateInterval(for goal: Goal, now: Date) -> DateInterval {
        let start = goal.startDate
        let end = goal.endDate ?? now
        if end <= start {
            return DateInterval(start: start, end: max(now, start))
        }
        return DateInterval(start: start, end: end)
    }

    /// Clips a recurring goal's current week/month to the goal's end date. The
    /// start is deliberately not clipped: a weekly goal created mid-week counts
    /// sessions already logged that week. Both the logged total and the pacing
    /// clock use this same period.
    private static func boundedPeriodInterval(_ period: DateInterval, for goal: Goal) -> DateInterval {
        let start = period.start
        let proposedEnd = min(period.end, goal.endDate ?? period.end)
        return DateInterval(start: start, end: max(proposedEnd, start))
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

        let interval: DateInterval
        switch goal.type {
        case .weeklyTarget:
            interval = boundedPeriodInterval(progressionWeekInterval(containing: now), for: goal)
        case .monthlyTotal:
            interval = boundedPeriodInterval(monthInterval(containing: now), for: goal)
        case .reachLevel, .reachRank, .consistency, .maintainBaseline, .improveBalance, .custom:
            // Without a deadline there is no honest expected pace to compare
            // against, so an open-ended goal should not create a permanent
            // warning badge merely because it is unfinished.
            guard goal.endDate != nil else { return .onPace }
            interval = goalDateInterval(for: goal, now: now)
        }
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

    /// Goal types whose progress is derived by summing logs (so a fresh log can
    /// "affect" them). Level/rank goals read the stat directly, not the logs.
    static let logDerivedGoalTypes: Set<GoalType> = [
        .weeklyTarget, .monthlyTotal, .consistency, .maintainBaseline, .improveBalance, .custom
    ]
}
