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

    /// Replays one completed week of activity through the charge meter.
    ///
    /// `decayEnabled` mirrors `AppSettings.enableDecay`: when the user turns
    /// decay off, an idle week no longer bleeds charge back toward zero. The
    /// parameter defaults to `true` so the historical behaviour (and every
    /// existing unit test) is preserved for callers that don't pass settings.
    ///
    /// `decaySensitivity` mirrors `AppSettings.decaySensitivity`
    /// (Forgiving 0.7 / Balanced 1.0 / Strict 1.3) and scales how far charge
    /// bleeds toward zero on a completed week — see `decayCharge`. It defaults
    /// to `1.0` (Balanced), the historical behaviour.
    static func evaluateWeek(
        statKey: StatKey,
        state: WeeklyProgressionState,
        actualTotal: Double,
        activeGoalTarget: Int? = nil,
        isRecoveryGoal: Bool = false,
        allowRankDown: Bool = true,
        decayEnabled: Bool = true,
        decaySensitivity: Double = 1.0
    ) -> WeeklyProgressionResult {
        let levelBefore = TrainingArcConfig.clampedRankLevel(state.level)
        let expectedTargetBefore = max(state.expectedWeeklyTarget, TrainingArcConfig.minimumBaseline)
        let expectedTotal = Double(expectedTargetBefore)
        let weeklyDelta = actualTotal - expectedTotal
        let bankedUnitsBefore = state.bankedProgressUnits
        let chargeBeforeDecay = TrainingArcConfig.displayedCharge(for: statKey, bankedUnits: bankedUnitsBefore, level: levelBefore)
        let chargeAfterDecay = decayEnabled ? decayCharge(chargeBeforeDecay, sensitivity: decaySensitivity) : chargeBeforeDecay
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

    /// Bleeds the signed charge meter toward zero for one completed week, with
    /// the step size chosen by progression strictness (`decaySensitivity`).
    /// The rule is deliberately discrete so charge stays an integer — no
    /// fractional accumulator to persist:
    ///
    /// - **Strict** (`>= 1.15`): two steps toward zero. Earned charge and debt
    ///   both bleed off twice as fast when a week goes unworked.
    /// - **Balanced** (`~1.0`): one step toward zero — the original behaviour.
    /// - **Forgiving** (`< 0.85`): one step, but only once charge is at least
    ///   two away from zero. The point nearest zero is "sticky", so a single
    ///   idle week never erases your last foothold of progress (or your last
    ///   unit of debt).
    ///
    /// Decay never crosses zero: a positive charge floors at 0 and a negative
    /// charge ceilings at 0.
    private static func decayCharge(_ charge: Int, sensitivity: Double) -> Int {
        guard charge != 0 else { return 0 }

        let magnitude: Int
        if sensitivity >= 1.15 {
            magnitude = 2
        } else if sensitivity < 0.85 {
            magnitude = abs(charge) >= 2 ? 1 : 0
        } else {
            magnitude = 1
        }

        if charge > 0 {
            return max(0, charge - magnitude)
        } else {
            return min(0, charge + magnitude)
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
