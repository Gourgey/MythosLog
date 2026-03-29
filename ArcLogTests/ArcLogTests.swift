import Foundation
@testable import ArcLog
import Testing

struct ArcLogTests {
    @Test func weeklyRankProgressUsesOnlyExcess() {
        let result = ProgressionEngine.resolve(
            state: ProgressionState(baseline: 3, storedRankProgress: 0, level: 1),
            actual: 5,
            history: [],
            decaySettings: DecaySettings(isEnabled: true, sensitivity: 1, minimumBaseline: 1)
        )

        #expect(result.rankProgressEarned == 2)
        #expect(result.storedRankProgressAfter == 2)
        #expect(result.levelAfter == 1)
        #expect(result.baselineAfter == 3)
    }

    @Test func rankUpSpendsProgressAndRaisesBaseline() {
        let result = ProgressionEngine.resolve(
            state: ProgressionState(baseline: 3, storedRankProgress: 3, level: 1),
            actual: 4,
            history: [],
            decaySettings: DecaySettings(isEnabled: true, sensitivity: 1, minimumBaseline: 1)
        )

        #expect(result.rankProgressEarned == 1)
        #expect(result.rankProgressSpentOnLevelUp == 4)
        #expect(result.storedRankProgressAfter == 0)
        #expect(result.levelAfter == 2)
        #expect(result.baselineAfter == 4)
        #expect(result.flags.contains(.rankUp))
    }

    @Test func decayRemovesStoredRankProgressAfterTwoZeroWeeks() {
        let result = ProgressionEngine.resolve(
            state: ProgressionState(baseline: 3, storedRankProgress: 3, level: 2),
            actual: 0,
            history: [HistoricWeeklyPerformance(actual: 0, baseline: 3)],
            decaySettings: DecaySettings(isEnabled: true, sensitivity: 1, minimumBaseline: 1)
        )

        #expect(result.storedRankProgressAfter == 2)
        #expect(result.didDecay)
        #expect(result.flags.contains(.rankProgressDecay))
    }

    @Test func regressionTriggersAfterFourBelowBaselineWeeks() {
        let history = [
            HistoricWeeklyPerformance(actual: 1, baseline: 3),
            HistoricWeeklyPerformance(actual: 2, baseline: 3),
            HistoricWeeklyPerformance(actual: 1, baseline: 3)
        ]

        let result = ProgressionEngine.resolve(
            state: ProgressionState(baseline: 3, storedRankProgress: 0, level: 3),
            actual: 1,
            history: history,
            decaySettings: DecaySettings(isEnabled: true, sensitivity: 1, minimumBaseline: 1)
        )

        #expect(result.baselineAfter == 2)
        #expect(result.levelAfter == 2)
        #expect(result.flags.contains(.baselineRegression))
        #expect(result.flags.contains(.stagnationWarning))
    }

    @Test func rankTitlesUseCentralConfig() {
        #expect(TrainingArcConfig.rankTitle(for: .strength, level: 1) == "Frail Elder")
        #expect(TrainingArcConfig.rankTitle(for: .strength, level: 10) == "Ascended Martial Titan")
        #expect(TrainingArcConfig.rankTitle(for: .cardio, level: 4) == "Conditioned Human")
        #expect(TrainingArcConfig.defaultHabitTemplates.count == 7)
    }

    @Test func chargeUsesCurrentMomentumRatio() {
        #expect(TrainingArcConfig.currentCharge(for: .focus, actual: 0, baseline: 40) == 0)
        #expect(TrainingArcConfig.currentCharge(for: .focus, actual: 10, baseline: 40) == 1)
        #expect(TrainingArcConfig.currentCharge(for: .focus, actual: 40, baseline: 40) == 4)
    }

    @Test func streakCalculationHandlesDailyCadence() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_711_843_200)) // Mar 31 2024
        let dates = [
            today,
            calendar.date(byAdding: .day, value: -1, to: today)!,
            calendar.date(byAdding: .day, value: -2, to: today)!,
            calendar.date(byAdding: .day, value: -4, to: today)!
        ]

        let streak = StreakService.summary(for: dates, cadence: .daily, referenceDate: today)
        #expect(streak.current == 3)
        #expect(streak.longest == 3)
    }

    @Test func weekMathResolvesMondayWeekBoundaries() {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: "2026-03-26T12:00:00Z")!

        let start = WeekMath.startOfWeek(for: date, weekStartsOnMonday: true)
        let range = WeekMath.lastCompletedWeek(before: date, weekStartsOnMonday: true)

        #expect(formatter.string(from: start).hasPrefix("2026-03-23"))
        #expect(formatter.string(from: range.start).hasPrefix("2026-03-16"))
        #expect(formatter.string(from: range.end).hasPrefix("2026-03-22"))
    }
}
