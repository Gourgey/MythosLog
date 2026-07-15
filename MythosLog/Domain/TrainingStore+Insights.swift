import Foundation
import SwiftData

// Read-only analysis for the dashboard: weekly status, highlights, recaps,
// train-today recommendations, momentum, and the insight analyses.

extension TrainingStore {
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
            headline = "Behind this week"
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
        let chargeMaximum = ChargeMath.slotsPerSide
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
            } else if stat.pendingRankChange?.direction == .down ||
                (charge <= -2 && stat.rankLevel > TrainingArcConfig.minimumRankLevel) {
                // Matches WeeklyReviewView's `reviewUrgency` regression-risk
                // predicate exactly. A pending rank-down already resolves
                // charge back to 0 as part of creating the resolution —
                // before the ceremony is even viewed — so checking `charge
                // <= -2` alone (the old condition) let a skill drop out of
                // this list the moment it dropped rank, while Review (which
                // checks the pending change directly) kept showing it as
                // "Risk" until the user opened and dismissed the ceremony.
                highlights.append(
                    DashboardHighlight(
                        id: "momentum-\(statKey.rawValue)",
                        statKeyRaw: statKey.rawValue,
                        statName: stat.name,
                        colorToken: stat.colorToken,
                        kind: .losingMomentum,
                        text: "At risk — close to ranking down"
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

        let goalInputs = goalProgressInputs(context: context)
        let goalsAtRiskCount = goals.filter { goal in
            guard goal.status == .active else { return false }
            let snapshot = goalProgress(for: goal, inputs: goalInputs, now: now)
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
                        headline: "\(stat.name) is behind",
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
                        headline: "\(stat.name) is at risk",
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
                let unit = weeklyUnitLabel(for: item.stat)
                return "\(item.stat.name): \(deltaLabel) \(unit) compared with the previous month."
            }

        if rankUps.isEmpty == false {
            let gainsBySkill = Dictionary(grouping: rankUps, by: \.statName)
            bullets.append(contentsOf: gainsBySkill.keys.sorted().map { statName in
                let count = gainsBySkill[statName]?.count ?? 0
                return count == 1
                    ? "\(statName) gained a rank."
                    : "\(statName) gained \(count) ranks."
            })
        }

        if bullets.isEmpty {
            bullets = ["Log a few clean weeks to give the monthly analysis more signal."]
        }

        let summary: String
        if rankUps.isEmpty {
            summary = "No monthly rank-up spikes were recorded, so the strongest signal comes from raw activity deltas."
        } else if rankUps.count == 1 {
            summary = "1 weekly rank-up check converted into a level gain this month."
        } else {
            summary = "\(rankUps.count) weekly rank-up checks converted into level gains this month."
        }

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

    private static func formattedHour(_ hour: Int) -> String {
        let safeHour = min(max(hour, 0), 23)
        let components = DateComponents(calendar: Calendar.current, hour: safeHour)
        let date = components.date ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
