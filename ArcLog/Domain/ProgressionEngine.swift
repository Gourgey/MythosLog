import Foundation

enum WeeklyFlag: String, Codable, Sendable {
    case rankUp
    case stagnationWarning
    case rankProgressDecay
    case baselineRegression
}

struct ProgressionState: Sendable {
    var baseline: Int
    var storedRankProgress: Int
    var level: Int
}

struct HistoricWeeklyPerformance: Sendable {
    var actual: Double
    var baseline: Int
}

struct DecaySettings: Sendable {
    var isEnabled: Bool
    var sensitivity: Double
    var minimumBaseline: Int
}

struct WeeklyResolutionComputation: Sendable {
    var actual: Double
    var excessValue: Double
    var rankProgressEarned: Int
    var rankProgressSpentOnLevelUp: Int
    var levelBefore: Int
    var levelAfter: Int
    var baselineBefore: Int
    var baselineAfter: Int
    var storedRankProgressBefore: Int
    var storedRankProgressAfter: Int
    var didDecay: Bool
    var flags: [WeeklyFlag]
    var summary: String
}

enum ProgressionEngine {
    static func resolve(
        state: ProgressionState,
        actual: Double,
        history: [HistoricWeeklyPerformance],
        requiredRankProgressToLevelUp: Int = TrainingArcConfig.requiredRankProgressToLevelUp,
        maximumRankLevel: Int = TrainingArcConfig.maximumRankLevel,
        decaySettings: DecaySettings
    ) -> WeeklyResolutionComputation {
        let actualRounded = max(0, actual)
        let baselineBefore = state.baseline
        let levelBefore = TrainingArcConfig.clampedRankLevel(state.level)
        let storedBefore = max(0, state.storedRankProgress)

        let actualInt = Int(actualRounded.rounded(.down))
        let excess = max(0, actualInt - baselineBefore)
        let rankProgressEarned = excess

        var levelAfter = levelBefore
        var baselineAfter = baselineBefore
        var storedRankProgressAfter = storedBefore + rankProgressEarned
        var progressSpent = 0
        var flags: [WeeklyFlag] = []
        var didDecay = false

        let metCurrentBaseline = actualInt >= baselineBefore
        let canRankUp = levelBefore < maximumRankLevel
        if metCurrentBaseline && canRankUp && storedRankProgressAfter >= requiredRankProgressToLevelUp {
            progressSpent = requiredRankProgressToLevelUp
            storedRankProgressAfter -= requiredRankProgressToLevelUp
            levelAfter = min(levelBefore + 1, maximumRankLevel)
            baselineAfter += 1
            flags.append(.rankUp)
        }

        if decaySettings.isEnabled {
            let sensitivity = max(0.5, min(decaySettings.sensitivity, 2.0))
            let stagnationThreshold = max(2, Int(ceil(2 / sensitivity)))
            let zeroPenaltyThreshold = max(2, Int(ceil(2 / sensitivity)))
            let regressionThreshold = max(4, Int(ceil(4 / sensitivity)))

            let fullHistory = history + [HistoricWeeklyPerformance(actual: actualRounded, baseline: baselineBefore)]

            let belowBaselineStreak = trailingStreak(in: fullHistory) { week in
                Int(week.actual.rounded(.down)) < week.baseline
            }
            let zeroStreak = trailingStreak(in: fullHistory) { week in
                Int(week.actual.rounded(.down)) == 0
            }

            if belowBaselineStreak >= stagnationThreshold {
                flags.append(.stagnationWarning)
            }

            if zeroStreak >= zeroPenaltyThreshold, zeroStreak.isMultiple(of: zeroPenaltyThreshold) {
                storedRankProgressAfter = max(0, storedRankProgressAfter - 1)
                flags.append(.rankProgressDecay)
                didDecay = true
            }

            if belowBaselineStreak >= regressionThreshold,
               belowBaselineStreak.isMultiple(of: regressionThreshold),
               baselineAfter > decaySettings.minimumBaseline {
                baselineAfter -= 1
                levelAfter = max(TrainingArcConfig.minimumRankLevel, levelAfter - 1)
                flags.append(.baselineRegression)
                didDecay = true
            }
        }

        return WeeklyResolutionComputation(
            actual: actualRounded,
            excessValue: Double(excess),
            rankProgressEarned: rankProgressEarned,
            rankProgressSpentOnLevelUp: progressSpent,
            levelBefore: levelBefore,
            levelAfter: levelAfter,
            baselineBefore: baselineBefore,
            baselineAfter: baselineAfter,
            storedRankProgressBefore: storedBefore,
            storedRankProgressAfter: storedRankProgressAfter,
            didDecay: didDecay,
            flags: flags,
            summary: summary(
                actual: actualRounded,
                baselineBefore: baselineBefore,
                rankProgressEarned: rankProgressEarned,
                flags: flags
            )
        )
    }

    private static func trailingStreak(
        in history: [HistoricWeeklyPerformance],
        matching predicate: (HistoricWeeklyPerformance) -> Bool
    ) -> Int {
        var count = 0
        for item in history.reversed() {
            guard predicate(item) else { break }
            count += 1
        }
        return count
    }

    private static func summary(
        actual: Double,
        baselineBefore: Int,
        rankProgressEarned: Int,
        flags: [WeeklyFlag]
    ) -> String {
        var parts: [String] = []
        parts.append("Completed \(Int(actual.rounded(.down))) against a baseline of \(baselineBefore).")

        if rankProgressEarned > 0 {
            parts.append("+\(rankProgressEarned) rank progress earned.")
        } else {
            parts.append("No rank progress earned this week.")
        }

        if flags.contains(.rankUp) {
            parts.append("Rank advanced.")
        }

        if flags.contains(.stagnationWarning) {
            parts.append("Momentum has stalled for multiple weeks.")
        }

        if flags.contains(.rankProgressDecay) {
            parts.append("One stored rank progress point was lost due to full inactivity.")
        }

        if flags.contains(.baselineRegression) {
            parts.append("Baseline regressed after prolonged underperformance.")
        }

        return parts.joined(separator: " ")
    }
}
