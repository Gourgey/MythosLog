import Foundation

struct WeeklyProgressionState: Sendable {
    var level: Int
    var expectedWeeklyTarget: Int
    var bankedProgressUnits: Double
}

struct WeeklyProgressionResult: Sendable {
    var state: WeeklyProgressionState
    var expectedTotal: Double
    var actualTotal: Double
    var weeklyDelta: Double
    var bankedUnitsBefore: Double
    var bankedUnitsAfter: Double
    var levelBefore: Int
    var levelAfter: Int
    var didLevelUp: Bool
    var didLevelDown: Bool
    var visibleChargesAfter: Int
}

enum ProgressionEngine {
    static func initialState(for statKey: StatKey, startingBaseline: Int) -> WeeklyProgressionState {
        let openingLevel = TrainingArcConfig.rankLevel(for: statKey, weeklyValue: Double(startingBaseline))
        return WeeklyProgressionState(
            level: openingLevel,
            expectedWeeklyTarget: startingBaseline,
            bankedProgressUnits: 0
        )
    }

    static func evaluateWeek(
        statKey: StatKey,
        state: WeeklyProgressionState,
        actualTotal: Double
    ) -> WeeklyProgressionResult {
        let levelBefore = TrainingArcConfig.clampedRankLevel(state.level)
        let expectedTargetBefore = max(state.expectedWeeklyTarget, TrainingArcConfig.minimumBaseline)
        let expectedTotal = Double(expectedTargetBefore)
        let weeklyDelta = actualTotal - expectedTotal
        let bankedUnitsBefore = state.bankedProgressUnits
        var bankedUnitsAfter = bankedUnitsBefore + weeklyDelta
        var levelAfter = levelBefore
        var expectedTargetAfter = expectedTargetBefore
        var didLevelUp = false
        var didLevelDown = false

        if levelBefore < TrainingArcConfig.maximumRankLevel {
            let nextLevel = levelBefore + 1
            let bridgeUnits = TrainingArcConfig.progressionBridgeUnits(for: statKey, fromLevel: levelBefore, toLevel: nextLevel)
            if bankedUnitsAfter >= bridgeUnits {
                levelAfter = nextLevel
                expectedTargetAfter = TrainingArcConfig.requiredWeeklyValue(for: statKey, level: nextLevel)
                bankedUnitsAfter -= bridgeUnits
                didLevelUp = true
            }
        }

        if !didLevelUp, levelBefore > TrainingArcConfig.minimumRankLevel {
            let previousLevel = levelBefore - 1
            let bridgeUnits = TrainingArcConfig.progressionBridgeUnits(for: statKey, fromLevel: levelBefore, toLevel: previousLevel)
            if bankedUnitsAfter <= -bridgeUnits {
                levelAfter = previousLevel
                expectedTargetAfter = TrainingArcConfig.requiredWeeklyValue(for: statKey, level: previousLevel)
                bankedUnitsAfter += bridgeUnits
                didLevelDown = true
            }
        }

        let finalState = WeeklyProgressionState(
            level: levelAfter,
            expectedWeeklyTarget: expectedTargetAfter,
            bankedProgressUnits: bankedUnitsAfter
        )

        return WeeklyProgressionResult(
            state: finalState,
            expectedTotal: expectedTotal,
            actualTotal: actualTotal,
            weeklyDelta: weeklyDelta,
            bankedUnitsBefore: bankedUnitsBefore,
            bankedUnitsAfter: bankedUnitsAfter,
            levelBefore: levelBefore,
            levelAfter: levelAfter,
            didLevelUp: didLevelUp,
            didLevelDown: didLevelDown,
            visibleChargesAfter: TrainingArcConfig.displayedCharge(
                for: statKey,
                bankedUnits: bankedUnitsAfter,
                level: levelAfter
            )
        )
    }

    static func progressToNextRank(statKey: StatKey, state: WeeklyProgressionState) -> Double {
        guard state.level < TrainingArcConfig.maximumRankLevel else { return 1 }
        return TrainingArcConfig.chargeProgress(
            for: statKey,
            bankedUnits: state.bankedProgressUnits,
            level: state.level
        )
    }

    static func visibleCharge(statKey: StatKey, state: WeeklyProgressionState) -> Int {
        TrainingArcConfig.displayedCharge(
            for: statKey,
            bankedUnits: state.bankedProgressUnits,
            level: state.level
        )
    }
}
