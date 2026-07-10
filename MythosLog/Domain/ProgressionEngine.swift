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
    var weeklyChargeDelta: Int
    var bankedUnitsBefore: Double
    var bankedUnitsAfter: Double
    var levelBefore: Int
    var levelAfter: Int
    var chargeBeforeDecay: Int
    var chargeAfterDecay: Int
    var didLevelUp: Bool
    var didLevelDown: Bool
    var didDecayTowardZero: Bool
    var visibleChargesAfter: Int
    var goalBonusApplied: Bool = false
    var goalTargetMet: Bool = false
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
        actualTotal: Double,
        activeGoalTarget: Int? = nil,
        isRecoveryGoal: Bool = false,
        allowRankDown: Bool = true
    ) -> WeeklyProgressionResult {
        let levelBefore = TrainingArcConfig.clampedRankLevel(state.level)
        let expectedTargetBefore = max(state.expectedWeeklyTarget, TrainingArcConfig.minimumBaseline)
        let expectedTotal = Double(expectedTargetBefore)
        let weeklyDelta = actualTotal - expectedTotal
        let bankedUnitsBefore = state.bankedProgressUnits
        let chargeBeforeDecay = TrainingArcConfig.displayedCharge(for: statKey, bankedUnits: bankedUnitsBefore, level: levelBefore)
        let chargeAfterDecay = decayCharge(chargeBeforeDecay)
        let baselineChargeDelta = chargeDelta(
            statKey: statKey,
            level: levelBefore,
            expectedTarget: expectedTargetBefore,
            actualTotal: actualTotal
        )

        let goalTargetMet: Bool = {
            guard let goalTarget = activeGoalTarget, goalTarget > 0 else { return false }
            return actualTotal >= Double(goalTarget)
        }()
        let goalBonus: Int = {
            guard goalTargetMet else { return 0 }
            if isRecoveryGoal { return 1 }
            return baselineChargeDelta >= 0 ? 1 : 0
        }()
        let weeklyChargeDelta = baselineChargeDelta + goalBonus
        var resolvedCharge = ChargeMath.clampedCharge(chargeAfterDecay + weeklyChargeDelta)
        var levelAfter = levelBefore
        var expectedTargetAfter = expectedTargetBefore
        var didLevelUp = false
        var didLevelDown = false

        if resolvedCharge >= ChargeMath.slotsPerSide, levelBefore < TrainingArcConfig.maximumRankLevel {
            levelAfter = levelBefore + 1
            expectedTargetAfter = TrainingArcConfig.requiredWeeklyValue(for: statKey, level: levelAfter)
            resolvedCharge = 0
            didLevelUp = true
        }

        if allowRankDown, !didLevelUp, resolvedCharge <= -ChargeMath.slotsPerSide, levelBefore > TrainingArcConfig.minimumRankLevel {
            levelAfter = levelBefore - 1
            expectedTargetAfter = TrainingArcConfig.requiredWeeklyValue(for: statKey, level: levelAfter)
            resolvedCharge = 0
            didLevelDown = true
        }

        let bankedUnitsAfter = Double(ChargeMath.clampedCharge(resolvedCharge))

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
            weeklyChargeDelta: weeklyChargeDelta,
            bankedUnitsBefore: bankedUnitsBefore,
            bankedUnitsAfter: bankedUnitsAfter,
            levelBefore: levelBefore,
            levelAfter: levelAfter,
            chargeBeforeDecay: chargeBeforeDecay,
            chargeAfterDecay: chargeAfterDecay,
            didLevelUp: didLevelUp,
            didLevelDown: didLevelDown,
            didDecayTowardZero: chargeBeforeDecay != chargeAfterDecay,
            visibleChargesAfter: TrainingArcConfig.displayedCharge(
                for: statKey,
                bankedUnits: bankedUnitsAfter,
                level: levelAfter
            ),
            goalBonusApplied: goalBonus > 0,
            goalTargetMet: goalTargetMet
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

    private static func decayCharge(_ charge: Int) -> Int {
        switch charge {
        case let value where value > 0:
            return value - 1
        case let value where value < 0:
            return value + 1
        default:
            return 0
        }
    }

    private static func chargeDelta(
        statKey: StatKey,
        level: Int,
        expectedTarget: Int,
        actualTotal: Double
    ) -> Int {
        let currentTarget = Double(expectedTarget)

        if actualTotal > currentTarget, let positiveStep = TrainingArcConfig.positiveChargeStep(for: statKey, level: level) {
            return Int(floor((actualTotal - currentTarget) / Double(positiveStep)))
        }

        if actualTotal < currentTarget, let negativeStep = TrainingArcConfig.negativeChargeStep(for: statKey, level: level) {
            return -Int(floor((currentTarget - actualTotal) / Double(negativeStep)))
        }

        return 0
    }
}
