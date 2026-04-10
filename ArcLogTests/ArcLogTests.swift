import Foundation
@testable import ArcLog
import SwiftData
import Testing

private let testCalendar = WeekMath.calendar(weekStartsOnMonday: true)

private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

@MainActor
private func makeStrengthFixture(
    baseline: Int = 3,
    createdAt: Date? = nil
) throws -> (context: ModelContext, stat: StatDomain, habit: Habit) {
    let container = TrainingStore.makeModelContainer(inMemory: true)
    let context = ModelContext(container)

    try TrainingStore.seedDefaultProfile(
        context: context,
        baselines: [.strength: baseline],
        completeOnboarding: true
    )

    let stat = try #require(try TrainingStore.fetchStats(context: context).first(where: { $0.statKey == .strength }))
    let habit = try #require(TrainingStore.activeHabits(for: stat).first)

    if let createdAt {
        stat.createdAt = createdAt
        try context.save()
    }

    return (context, stat, habit)
}

@MainActor
private func addSessionLogs(
    count: Int,
    habit: Habit,
    weekStart: Date,
    context: ModelContext
) throws {
    for index in 0..<count {
        let dayOffset = min(index, 6)
        let date = testCalendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        context.insert(
            HabitLog(
                date: date,
                numericValue: 1,
                note: "",
                sourceType: .debug,
                createdAt: date,
                habit: habit
            )
        )
    }

    try context.save()
}

struct ArcLogTests {
    @Test func rankTitlesUseCentralConfig() {
        #expect(TrainingArcConfig.rankTitle(for: .strength, level: 1) == "Frail Elder")
        #expect(TrainingArcConfig.rankTitle(for: .strength, level: 10) == "Ascended Martial Titan")
        #expect(TrainingArcConfig.rankTitle(for: .cardio, level: 4) == "Conditioned Human")
        #expect(TrainingArcConfig.defaultHabitTemplates.count == 7)
    }

    @Test func baselineThresholdsMapToExpectedRankLevels() {
        #expect(TrainingArcConfig.minimumBaseline == 0)
        #expect(TrainingArcConfig.rankLevel(for: .strength, weeklyValue: 0) == 1)
        #expect(TrainingArcConfig.rankLevel(for: .strength, weeklyValue: 3) == 4)
        #expect(TrainingArcConfig.rankLevel(for: .strength, weeklyValue: 12) == 10)
        #expect(TrainingArcConfig.rankLevel(for: .focus, weeklyValue: 40) == 5)
    }

    @Test func findYourRankConfigExposesQuestionsAndThresholdPreviews() {
        let creativityOnboarding = TrainingArcConfig.onboardingConfiguration(for: .creativity)
        let intellectOnboarding = TrainingArcConfig.onboardingConfiguration(for: .intellect)

        #expect(creativityOnboarding.question == "How many times a week do you draw, or paint?")
        #expect(intellectOnboarding.question == "How many pages do you read each week?")
        #expect(intellectOnboarding.quickAdjustments == [5, 10, 25])
        #expect(TrainingArcConfig.lowerRankThreshold(for: .strength, level: 4) == 2)
        #expect(TrainingArcConfig.nextRankThreshold(for: .strength, level: 4) == 4)
        #expect(TrainingArcConfig.baselineValueLabel(for: .intellect, value: 25) == "25 pages per week")
    }

    @Test func dashboardChargeDotsMapProgressToFourSteps() {
        #expect(DashboardChargeDots.filledDots(from: -0.5) == 0)
        #expect(DashboardChargeDots.filledDots(from: 0) == 0)
        #expect(DashboardChargeDots.filledDots(from: 0.24) == 0)
        #expect(DashboardChargeDots.filledDots(from: 0.25) == 1)
        #expect(DashboardChargeDots.filledDots(from: 0.5) == 2)
        #expect(DashboardChargeDots.filledDots(from: 0.75) == 3)
        #expect(DashboardChargeDots.filledDots(from: 1.0) == 4)
        #expect(DashboardChargeDots.filledDots(from: 1.6) == 4)
    }

    @Test func dashboardLayoutModeDefaultsToDetailedCards() {
        let settings = AppSettings()
        #expect(settings.dashboardLayoutMode == .detailedCards)
    }

    @Test func strengthRosterUsesUnlockedAndLockedAssetsByLevel() {
        let entries = TrainingArcConfig.characterRosterEntries(for: .strength, currentLevel: 4)

        #expect(entries.count == 10)
        #expect(entries[0].isLocked == false)
        #expect(entries[3].isLocked == false)
        #expect(entries[4].isLocked == true)

        if case .asset(let currentName)? = entries[3].image {
            #expect(currentName == "Strength_Level_4")
        } else {
            Issue.record("Expected unlocked Strength art for level 4.")
        }

        if case .asset(let lockedName)? = entries[4].image {
            #expect(lockedName == "Strength_Level_5_Locked")
        } else {
            Issue.record("Expected locked Strength art for level 5.")
        }
    }

    @Test func nonStrengthRosterFallsBackWithoutInvalidLockedAssets() {
        let entries = TrainingArcConfig.characterRosterEntries(for: .focus, currentLevel: 2)

        #expect(entries.count == 10)
        #expect(entries[1].isLocked == false)
        #expect(entries[2].isLocked == true)
        #expect(entries[2].image == nil)
    }

    @Test @MainActor func progressSnapshotUsesExplicitWeeklyLabels() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let snapshot = TrainingStore.progressSnapshot(for: fixture.stat, settings: nil, now: isoDate("2026-03-30T12:00:00Z"))

        #expect(snapshot.weeklyCounterLabel == "Weekly Sessions")
        #expect(snapshot.weeklyCounterValueLabel == "0 / 3")
        #expect(snapshot.chargeExplanation.contains("Sunday"))
        #expect(snapshot.nextEvaluationLabel.contains("Banks"))
        #expect(snapshot.bankCountdownLabel.contains("Banking in"))
        #expect(snapshot.nextActionLabel.contains("Log"))
        #expect(snapshot.pacingStatus == .behind)
        #expect(snapshot.focusState == .behindTarget)
    }

    @Test @MainActor func recentLogSnapshotsCanFilterToRollingSevenDayWindow() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-09T12:00:00Z")

        fixture.context.insert(
            HabitLog(
                date: isoDate("2026-04-08T09:00:00Z"),
                numericValue: 1,
                note: "Recent",
                sourceType: .manual,
                createdAt: isoDate("2026-04-08T09:00:00Z"),
                habit: fixture.habit
            )
        )

        fixture.context.insert(
            HabitLog(
                date: isoDate("2026-03-30T09:00:00Z"),
                numericValue: 1,
                note: "Old",
                sourceType: .manual,
                createdAt: isoDate("2026-03-30T09:00:00Z"),
                habit: fixture.habit
            )
        )

        try fixture.context.save()

        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now)
        let snapshots = TrainingStore.recentLogSnapshots(for: fixture.stat, since: cutoff)

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.note == "Recent")
        #expect(snapshots.first?.date == isoDate("2026-04-08T09:00:00Z"))
    }

    @Test @MainActor func sessionTypePersistsOnLoggedEntries() throws {
        let fixture = try makeStrengthFixture(baseline: 3)

        _ = try TrainingStore.log(
            habit: fixture.habit,
            value: 1,
            date: isoDate("2026-03-30T18:30:00Z"),
            sessionType: "Upper Body",
            note: "Heavy set",
            source: .manual,
            context: fixture.context
        )

        let logs = try TrainingStore.fetchLogs(context: fixture.context)
        let log = try #require(logs.last)
        #expect(log.sessionType == "Upper Body")
        #expect(log.note == "Heavy set")
    }

    @Test func weeklyProgressionBanksSurplusWithoutInstantLevelUp() {
        let startingState = ProgressionEngine.initialState(for: .strength, startingBaseline: 3)
        let result = ProgressionEngine.evaluateWeek(statKey: .strength, state: startingState, actualTotal: 12)

        #expect(result.levelBefore == 4)
        #expect(result.levelAfter == 4)
        #expect(!result.didLevelUp)
        #expect(!result.didLevelDown)
        #expect(result.expectedTotal == 3)
        #expect(result.weeklyDelta == 9)
        #expect(result.bankedUnitsAfter == 9)
        #expect(result.visibleChargesAfter == 3)
    }

    @Test func twoStrongWeeksProduceSingleRankUpWithCarryover() {
        let weekOne = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: ProgressionEngine.initialState(for: .strength, startingBaseline: 3),
            actualTotal: 12
        )
        let weekTwo = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: weekOne.state,
            actualTotal: 12
        )

        #expect(weekTwo.levelBefore == 4)
        #expect(weekTwo.levelAfter == 5)
        #expect(weekTwo.didLevelUp)
        #expect(!weekTwo.didLevelDown)
        #expect(weekTwo.state.expectedWeeklyTarget == 4)
        #expect(weekTwo.state.bankedProgressUnits == 6)
        #expect(weekTwo.visibleChargesAfter == 1)
    }

    @Test func negativeWeekCreatesDebtAndSingleRankDownPerWeek() {
        let state = WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: -50)
        let result = ProgressionEngine.evaluateWeek(statKey: .strength, state: state, actualTotal: 0)

        #expect(result.levelBefore == 6)
        #expect(result.levelAfter == 5)
        #expect(!result.didLevelUp)
        #expect(result.didLevelDown)
        #expect(result.weeklyDelta == -5)
        #expect(result.bankedUnitsAfter == -35)
        #expect(result.visibleChargesAfter == 0)
    }

    @Test @MainActor func onboardingBaselineAssignsStartingRankAndCurrentBaseline() throws {
        let container = TrainingStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)

        try TrainingStore.seedDefaultProfile(
            context: context,
            baselines: [.strength: 0, .curiosity: 9],
            completeOnboarding: true
        )

        let stats = try TrainingStore.fetchStats(context: context)
        let strength = try #require(stats.first(where: { $0.statKey == .strength }))
        let curiosity = try #require(stats.first(where: { $0.statKey == .curiosity }))

        #expect(strength.rankLevel == 1)
        #expect(strength.currentBaseline == 0)
        #expect(strength.startingBaseline == 0)
        #expect(strength.acknowledgedRankLevel == 1)
        #expect(curiosity.rankLevel == 10)
        #expect(curiosity.currentBaseline == 9)
    }

    @Test @MainActor func completedWeekReplayUpdatesBankedStateFromBackdatedLogs() throws {
        let now = isoDate("2026-03-30T12:00:00Z")
        let completedWeekStart = isoDate("2026-03-23T00:00:00Z")
        let fixture = try makeStrengthFixture(baseline: 3, createdAt: completedWeekStart)

        try TrainingStore.refreshProgress(for: fixture.stat, context: fixture.context, reason: .appRefresh, now: now)
        #expect(fixture.stat.rankLevel == 4)
        #expect(fixture.stat.bankedProgressUnits == -3)

        try addSessionLogs(count: 12, habit: fixture.habit, weekStart: completedWeekStart, context: fixture.context)
        try TrainingStore.refreshProgress(for: fixture.stat, context: fixture.context, reason: .logMutation, now: now)

        #expect(fixture.stat.rankLevel == 4)
        #expect(fixture.stat.currentBaseline == 3)
        #expect(fixture.stat.bankedProgressUnits == 9)
        #expect(fixture.stat.chargeValue == 3)
        #expect(fixture.stat.pendingRankChange == nil)
        #expect(fixture.stat.weeklyResolutions.count == 1)

        let resolution = try #require(fixture.stat.weeklyResolutions.first)
        #expect(resolution.weekStartDate == completedWeekStart)
        #expect(resolution.expectedTotal == 3)
        #expect(resolution.actualCompletedValue == 12)
        #expect(resolution.weeklyDelta == 9)
    }

    @Test @MainActor func currentWeekLogsDoNotInstantlyChangeRank() throws {
        let now = isoDate("2026-03-29T12:00:00Z")
        let currentWeekStart = isoDate("2026-03-23T00:00:00Z")
        let fixture = try makeStrengthFixture(baseline: 3, createdAt: currentWeekStart)

        try addSessionLogs(count: 12, habit: fixture.habit, weekStart: currentWeekStart, context: fixture.context)
        try TrainingStore.refreshProgress(for: fixture.stat, context: fixture.context, reason: .logMutation, now: now)

        #expect(fixture.stat.rankLevel == 4)
        #expect(fixture.stat.currentBaseline == 3)
        #expect(fixture.stat.bankedProgressUnits == 0)
        #expect(fixture.stat.chargeValue == 0)
        #expect(fixture.stat.pendingRankChange == nil)
        #expect(fixture.stat.weeklyResolutions.isEmpty)
        #expect(TrainingStore.currentWeekTotal(for: fixture.stat, settings: nil, now: now) == 12)
    }

    @Test @MainActor func completedStrongWeeksCreatePendingRankChangeUntilAcknowledged() throws {
        let now = isoDate("2026-03-30T12:00:00Z")
        let firstWeekStart = isoDate("2026-03-16T00:00:00Z")
        let secondWeekStart = isoDate("2026-03-23T00:00:00Z")
        let fixture = try makeStrengthFixture(baseline: 3, createdAt: firstWeekStart)

        try addSessionLogs(count: 12, habit: fixture.habit, weekStart: firstWeekStart, context: fixture.context)
        try addSessionLogs(count: 12, habit: fixture.habit, weekStart: secondWeekStart, context: fixture.context)
        try TrainingStore.refreshProgress(for: fixture.stat, context: fixture.context, reason: .appRefresh, now: now)

        let pending = try #require(fixture.stat.pendingRankChange)
        #expect(fixture.stat.rankLevel == 5)
        #expect(fixture.stat.currentBaseline == 4)
        #expect(fixture.stat.bankedProgressUnits == 6)
        #expect(fixture.stat.chargeValue == 1)
        #expect(pending.direction == .up)
        #expect(pending.fromLevel == 4)
        #expect(pending.toLevel == 5)

        try TrainingStore.acknowledgePendingRankChange(for: fixture.stat, context: fixture.context)
        #expect(fixture.stat.pendingRankChange == nil)
        #expect(fixture.stat.acknowledgedRankLevel == 5)
    }

    @Test @MainActor func localInsightHelpersReturnUsefulContent() throws {
        let now = isoDate("2026-03-30T12:00:00Z")
        let previousWeekStart = isoDate("2026-03-23T00:00:00Z")
        let fixture = try makeStrengthFixture(baseline: 3, createdAt: previousWeekStart)

        try addSessionLogs(count: 8, habit: fixture.habit, weekStart: previousWeekStart, context: fixture.context)
        try TrainingStore.refreshProgress(for: fixture.stat, context: fixture.context, reason: .appRefresh, now: now)

        let work = try TrainingStore.workFocusAnalysis(context: fixture.context, settings: nil, now: now)
        let month = try TrainingStore.monthlyImprovementAnalysis(context: fixture.context, settings: nil, now: now)
        let routine = try TrainingStore.standardDayAnalysis(context: fixture.context, settings: nil, now: now)

        #expect(work.focusSkillName.isEmpty == false)
        #expect(work.recommendations.isEmpty == false)
        #expect(month.headline.isEmpty == false)
        #expect(month.improvedSkills.isEmpty == false)
        #expect(routine.headline.isEmpty == false)
        #expect(routine.suggestions.isEmpty == false)
    }

    @Test func streakCalculationHandlesDailyCadence() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_711_843_200))
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
        let date = isoDate("2026-03-26T12:00:00Z")
        let start = WeekMath.startOfWeek(for: date, weekStartsOnMonday: true)
        let range = WeekMath.lastCompletedWeek(before: date, weekStartsOnMonday: true)

        #expect(ISO8601DateFormatter().string(from: start).hasPrefix("2026-03-23"))
        #expect(ISO8601DateFormatter().string(from: range.start).hasPrefix("2026-03-16"))
        #expect(ISO8601DateFormatter().string(from: range.end).hasPrefix("2026-03-22"))
    }
}
