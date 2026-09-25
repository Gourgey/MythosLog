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
    static func initialState(for statKey: StatKey, startingBaseline: Int, personalMax: Int? = nil) -> WeeklyProgressionState {
        let openingLevel = TrainingArcConfig.rankLevel(
            for: statKey,
            weeklyValue: Double(startingBaseline),
            personalMax: personalMax
        )
        return WeeklyProgressionState(
            level: openingLevel,
            expectedWeeklyTarget: startingBaseline,
            bankedProgressUnits: 0
        )
    }

    /// Replays one completed week of activity through the charge meter.
    ///
    /// Charge rules for a completed week:
    ///
    /// - A week at or above target keeps every charge it already had and adds
    ///   what it earned. Decay never touches a week that met its target.
    /// - A week below target decays *earned* (positive) charge toward zero
    ///   (see `decayCharge`) and adds shortfall debt. Debt itself never decays;
    ///   it is only paid back by training.
    /// - A below-target week that starts with no positive charge always costs
    ///   at least one charge, so small misses and idle weeks accumulate toward
    ///   a rank-down. Meeting an active goal waives that minimum, and Level 1
    ///   takes no debt because there is no lower rank.
    ///
    /// `decayEnabled` mirrors `AppSettings.enableDecay`: when off, earned
    /// charge is kept through a missed week. Shortfall debt still applies.
    ///
    /// `decaySensitivity` mirrors `AppSettings.decaySensitivity`
    /// (Forgiving 0.7 / Balanced 1.0 / Strict 1.3) and scales how much earned
    /// charge a missed week costs. It defaults to `1.0` (Balanced).
    static func evaluateWeek(
        statKey: StatKey,
        state: WeeklyProgressionState,
        actualTotal: Double,
        activeGoalTarget: Int? = nil,
        isRecoveryGoal: Bool = false,
        allowRankDown: Bool = true,
        decayEnabled: Bool = true,
        decaySensitivity: Double = 1.0,
        personalMax: Int? = nil
    ) -> WeeklyProgressionResult {
        let levelBefore = TrainingArcConfig.clampedRankLevel(state.level)
        let expectedTargetBefore = max(state.expectedWeeklyTarget, TrainingArcConfig.minimumBaseline)
        let expectedTotal = Double(expectedTargetBefore)
        let weeklyDelta = actualTotal - expectedTotal
        let bankedUnitsBefore = state.bankedProgressUnits
        let chargeBeforeDecay = TrainingArcConfig.displayedCharge(for: statKey, bankedUnits: bankedUnitsBefore, level: levelBefore)
        let missedTarget = actualTotal < expectedTotal
        let chargeAfterDecay = (decayEnabled && missedTarget)
            ? decayCharge(chargeBeforeDecay, sensitivity: decaySensitivity)
            : chargeBeforeDecay

        let goalTargetMet: Bool = {
            guard let goalTarget = activeGoalTarget, goalTarget > 0 else { return false }
            return actualTotal >= Double(goalTarget)
        }()

        var baselineChargeDelta = chargeDelta(
            statKey: statKey,
            level: levelBefore,
            expectedTarget: expectedTargetBefore,
            actualTotal: actualTotal,
            personalMax: personalMax
        )
        if missedTarget,
           chargeBeforeDecay <= 0,
           !goalTargetMet,
           baselineChargeDelta == 0,
           TrainingArcConfig.negativeChargeStep(for: statKey, level: levelBefore, personalMax: personalMax) != nil {
            baselineChargeDelta = -1
        }
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
            expectedTargetAfter = TrainingArcConfig.requiredWeeklyValue(for: statKey, level: levelAfter, personalMax: personalMax)
            resolvedCharge = 0
            didLevelUp = true
        }

        if allowRankDown, !didLevelUp, resolvedCharge <= -ChargeMath.slotsPerSide, levelBefore > TrainingArcConfig.minimumRankLevel {
            levelAfter = levelBefore - 1
            expectedTargetAfter = TrainingArcConfig.requiredWeeklyValue(for: statKey, level: levelAfter, personalMax: personalMax)
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

    /// Bleeds earned (positive) charge toward zero for one missed week, with
    /// the step size chosen by progression strictness (`decaySensitivity`).
    /// The rule is deliberately discrete so charge stays an integer — no
    /// fractional accumulator to persist:
    ///
    /// - **Strict** (`>= 1.15`): two steps toward zero.
    /// - **Balanced** (`~1.0`): one step toward zero.
    /// - **Forgiving** (`< 0.85`): one step, but only once charge is at least
    ///   two. The last point is "sticky", so a single missed week never
    ///   erases your last foothold of progress.
    ///
    /// Decay never crosses zero, and debt (negative charge) is returned
    /// unchanged: missing a week must never shrink what you owe.
    private static func decayCharge(_ charge: Int, sensitivity: Double) -> Int {
        guard charge > 0 else { return charge }

        let magnitude: Int
        if sensitivity >= 1.15 {
            magnitude = 2
        } else if sensitivity < 0.85 {
            magnitude = charge >= 2 ? 1 : 0
        } else {
            magnitude = 1
        }

        return max(0, charge - magnitude)
    }

    private static func chargeDelta(
        statKey: StatKey,
        level: Int,
        expectedTarget: Int,
        actualTotal: Double,
        personalMax: Int?
    ) -> Int {
        let currentTarget = Double(expectedTarget)

        if actualTotal > currentTarget, let positiveStep = TrainingArcConfig.positiveChargeStep(for: statKey, level: level, personalMax: personalMax) {
            return Int(floor((actualTotal - currentTarget) / Double(positiveStep)))
        }

        if actualTotal < currentTarget, let negativeStep = TrainingArcConfig.negativeChargeStep(for: statKey, level: level, personalMax: personalMax) {
            return -Int(floor((currentTarget - actualTotal) / Double(negativeStep)))
        }

        return 0
    }
}
