import Foundation
@testable import MythosLog
import SwiftData
import Testing
#if canImport(HealthKit)
import HealthKit
#endif

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

struct MythosLogTests {
    @Test func rankTitlesUseCentralConfig() {
        #expect(TrainingArcConfig.rankTitle(for: .strength, level: 1) == "Untrained")
        #expect(TrainingArcConfig.rankTitle(for: .strength, level: 10) == "Master of Strength")
        #expect(TrainingArcConfig.rankTitle(for: .cardio, level: 4) == "Conditioned")
        #expect(TrainingArcConfig.defaultHabitTemplates.count == 9)
        #expect(TrainingArcConfig.rankTitle(for: .cooking, level: 1) == "Untrained Cook")
        #expect(TrainingArcConfig.rankTitle(for: .reading, level: 10) == "Lifelong Reader")
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

    @Test func dashboardChargeDotsClampSignedChargeIntoLeftAndRightSlots() {
        #expect(DashboardChargeDots.positiveDots(from: -3) == 0)
        #expect(DashboardChargeDots.negativeDots(from: -3) == 3)
        #expect(DashboardChargeDots.positiveDots(from: 0) == 0)
        #expect(DashboardChargeDots.negativeDots(from: 0) == 0)
        #expect(DashboardChargeDots.positiveDots(from: 2) == 2)
        #expect(DashboardChargeDots.negativeDots(from: 2) == 0)
        #expect(DashboardChargeDots.positiveDots(from: 7) == 4)
        #expect(DashboardChargeDots.negativeDots(from: -9) == 4)
    }

    @Test func dashboardLayoutModeDefaultsToGameGrid() {
        let settings = AppSettings()
        #expect(settings.dashboardLayoutMode == .gameGrid)
    }

    @Test @MainActor func reconcileSyncedDataKeepsNewestSettingsRecord() throws {
        let container = TrainingStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let older = AppSettings(
            hasCompletedOnboarding: false,
            createdAt: isoDate("2026-01-01T09:00:00Z"),
            updatedAt: isoDate("2026-01-01T09:00:00Z")
        )
        let newer = AppSettings(
            hasCompletedOnboarding: true,
            createdAt: isoDate("2026-01-02T09:00:00Z"),
            updatedAt: isoDate("2026-01-02T09:00:00Z")
        )

        context.insert(older)
        context.insert(newer)
        try context.save()

        try TrainingStore.reconcileSyncedData(context: context)

        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(settings.count == 1)
        #expect(settings.first?.hasCompletedOnboarding == true)
    }

    @Test @MainActor func reconcileSyncedDataMergesDuplicateStatsByKey() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let duplicateStat = StatDomain(
            key: StatKey.strength.rawValue,
            name: "Duplicate Strength",
            iconName: "bolt.fill",
            colorToken: "strength",
            descriptor: "Duplicate",
            currentTierName: "Duplicate",
            startingBaseline: 1,
            currentBaseline: 1,
            createdAt: isoDate("2026-01-01T09:00:00Z"),
            updatedAt: isoDate("2026-01-01T09:00:00Z")
        )
        let duplicateHabit = Habit(
            name: "Duplicate Lift",
            measurementType: .booleanSession,
            unitLabel: "session",
            scheduleType: .weekly,
            targetPerPeriod: 1,
            statDomain: duplicateStat
        )

        fixture.context.insert(duplicateStat)
        fixture.context.insert(duplicateHabit)
        try fixture.context.save()

        try TrainingStore.reconcileSyncedData(context: fixture.context)

        let strengthStats = try TrainingStore.fetchStats(context: fixture.context).filter { $0.key == StatKey.strength.rawValue }
        let duplicateHabitAfterMerge = try #require(try TrainingStore.fetchHabits(context: fixture.context).first { $0.name == "Duplicate Lift" })
        #expect(strengthStats.count == 1)
        #expect(duplicateHabitAfterMerge.statDomain?.id == strengthStats.first?.id)
    }

    @Test @MainActor func reconcileSyncedDataDeduplicatesHealthImportedWorkouts() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let workoutID = UUID().uuidString
        let workoutEnd = isoDate("2026-03-24T18:00:00Z")
        let importedRecord = HealthImportedWorkout(
            workoutUUID: workoutID,
            statKeyRaw: StatKey.strength.rawValue,
            habitSystemKey: fixture.habit.systemKey,
            sourceBundleIdentifier: "com.apple.Health",
            activityTypeRaw: 50,
            startDate: isoDate("2026-03-24T17:00:00Z"),
            endDate: workoutEnd,
            durationMinutes: 60,
            wasImported: true,
            isDuplicate: false,
            createdAt: isoDate("2026-03-24T18:01:00Z")
        )
        let duplicateRecord = HealthImportedWorkout(
            workoutUUID: workoutID,
            statKeyRaw: StatKey.strength.rawValue,
            habitSystemKey: fixture.habit.systemKey,
            sourceBundleIdentifier: "com.apple.Health",
            activityTypeRaw: 50,
            startDate: isoDate("2026-03-24T17:00:00Z"),
            endDate: workoutEnd,
            durationMinutes: 60,
            wasImported: false,
            isDuplicate: true,
            createdAt: isoDate("2026-03-24T18:02:00Z")
        )

        fixture.context.insert(importedRecord)
        fixture.context.insert(duplicateRecord)
        try fixture.context.save()

        try TrainingStore.reconcileSyncedData(context: fixture.context)

        let records = try TrainingStore.fetchImportedHealthWorkouts(context: fixture.context)
        #expect(records.count == 1)
        #expect(records.first?.workoutUUID == workoutID)
        #expect(records.first?.wasImported == true)
    }

    @Test @MainActor func reconcileSyncedDataPreservesDistinctManualLogs() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let loggedAt = isoDate("2026-03-24T18:00:00Z")

        fixture.context.insert(
            HabitLog(
                date: loggedAt,
                numericValue: 1,
                note: "Same visible entry",
                sourceType: .manual,
                createdAt: isoDate("2026-03-24T18:01:00Z"),
                habit: fixture.habit
            )
        )
        fixture.context.insert(
            HabitLog(
                date: loggedAt,
                numericValue: 1,
                note: "Same visible entry",
                sourceType: .manual,
                createdAt: isoDate("2026-03-24T18:02:00Z"),
                habit: fixture.habit
            )
        )
        try fixture.context.save()

        try TrainingStore.reconcileSyncedData(context: fixture.context)

        let manualLogs = try TrainingStore.fetchLogs(context: fixture.context).filter { $0.sourceType == .manual }
        #expect(manualLogs.count == 2)
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

        if case .asset(let fallbackName)? = entries[5].image {
            #expect(fallbackName == "Strength_Level_6_Locked")
        } else {
            Issue.record("Expected future Strength levels to use locked Strength art when it exists.")
        }
    }

    @Test func creativityRosterUsesUnlockedAndLockedAssetsByLevel() {
        let entries = TrainingArcConfig.characterRosterEntries(for: .creativity, currentLevel: 4)

        #expect(entries.count == 10)
        #expect(entries[0].isLocked == false)
        #expect(entries[3].isLocked == false)
        #expect(entries[4].isLocked == true)

        if case .asset(let currentName)? = entries[3].image {
            #expect(currentName == "Creativity_Level_4")
        } else {
            Issue.record("Expected unlocked Creativity art for level 4.")
        }

        if case .asset(let lockedName)? = entries[4].image {
            #expect(lockedName == "Creativity_Level_5_Locked")
        } else {
            Issue.record("Expected locked Creativity art for level 5.")
        }

        if case .asset(let futureName)? = entries[9].image {
            #expect(futureName == "Creativity_Level_10_Locked")
        } else {
            Issue.record("Expected future Creativity levels to use locked Creativity art when it exists.")
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
        #expect(snapshot.chargeExplanation.contains("Level 4"))
        #expect(snapshot.chargeExplanation.contains("+4 ranks you up"))
        #expect(snapshot.nextEvaluationLabel.contains("Resolves"))
        #expect(snapshot.bankCountdownLabel.contains("Resolves in"))
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

    @Test @MainActor func setSkillOrderPersistsCustomDashboardOrder() throws {
        let container = TrainingStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        try TrainingStore.seedDefaultProfile(context: context, completeOnboarding: true)

        let original = try TrainingStore.fetchActiveStats(context: context)
        let reorderedIDs = Array(original.prefix(3).map(\.id).reversed()) + original.dropFirst(3).map(\.id)

        try TrainingStore.setSkillOrder(reorderedIDs, context: context)

        let updated = try TrainingStore.fetchActiveStats(context: context)
        #expect(Array(updated.prefix(3).map(\.id)) == Array(reorderedIDs.prefix(3)))
    }

    @Test @MainActor func synchronizeCatalogPreservesCustomSkillOrder() throws {
        let container = TrainingStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        try TrainingStore.seedDefaultProfile(context: context, completeOnboarding: true)

        let original = try TrainingStore.fetchActiveStats(context: context)
        let reorderedIDs = Array(original.suffix(2).map(\.id)) + original.dropLast(2).map(\.id)

        try TrainingStore.setSkillOrder(reorderedIDs, context: context)
        try TrainingStore.synchronizeCatalog(context: context)

        let updated = try TrainingStore.fetchActiveStats(context: context)
        #expect(updated.map(\.id) == reorderedIDs)
    }

    @Test @MainActor func refreshWidgetSnapshotIncludesMotivationCopy() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-09T12:00:00Z")

        try TrainingStore.refreshWidgetSnapshot(context: fixture.context, now: now)
        let snapshot = WidgetSnapshotStore.load()

        #expect(!snapshot.motivationTitle.isEmpty)
        #expect(!snapshot.motivationMessage.isEmpty)
        #expect(!snapshot.motivationColorToken.isEmpty)
    }

    @Test func strongWeeksCanInstantlyRankUpWhenTheyReachPlusFourCharge() {
        let startingState = ProgressionEngine.initialState(for: .strength, startingBaseline: 3)
        let result = ProgressionEngine.evaluateWeek(statKey: .strength, state: startingState, actualTotal: 12)

        #expect(result.levelBefore == 4)
        #expect(result.levelAfter == 5)
        #expect(result.didLevelUp)
        #expect(!result.didLevelDown)
        #expect(result.expectedTotal == 3)
        #expect(result.weeklyDelta == 9)
        #expect(result.weeklyChargeDelta == 9)
        #expect(result.bankedUnitsAfter == 0)
        #expect(result.visibleChargesAfter == 0)
    }

    @Test func positiveChargeDecaysTowardZeroAcrossBaselineWeeks() {
        let week = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: 3),
            actualTotal: 5
        )

        #expect(week.levelBefore == 6)
        #expect(week.levelAfter == 6)
        #expect(!week.didLevelUp)
        #expect(!week.didLevelDown)
        #expect(week.chargeBeforeDecay == 3)
        #expect(week.chargeAfterDecay == 2)
        #expect(week.weeklyChargeDelta == 0)
        #expect(week.visibleChargesAfter == 2)
    }

    @Test func forgivingStrictnessKeepsChargeNearZeroThroughIdleWeek() {
        // Charge of +1, an idle week (actual == target). Forgiving strictness
        // makes the last point sticky; Balanced bleeds it to zero.
        let state = WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: 1)

        let forgiving = ProgressionEngine.evaluateWeek(
            statKey: .strength, state: state, actualTotal: 5, decaySensitivity: 0.7
        )
        #expect(forgiving.chargeBeforeDecay == 1)
        #expect(forgiving.chargeAfterDecay == 1)
        #expect(forgiving.visibleChargesAfter == 1)

        let balanced = ProgressionEngine.evaluateWeek(
            statKey: .strength, state: state, actualTotal: 5, decaySensitivity: 1.0
        )
        #expect(balanced.chargeAfterDecay == 0)
        #expect(balanced.visibleChargesAfter == 0)
    }

    @Test func strictStrictnessDecaysChargeTwoStepsPerWeek() {
        // Charge of +3, an idle week. Strict removes two steps; the near-zero
        // floor still holds (never crosses zero).
        let state = WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: 3)

        let strict = ProgressionEngine.evaluateWeek(
            statKey: .strength, state: state, actualTotal: 5, decaySensitivity: 1.3
        )
        #expect(strict.chargeBeforeDecay == 3)
        #expect(strict.chargeAfterDecay == 1)
        #expect(strict.visibleChargesAfter == 1)

        let lowCharge = WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: 1)
        let clampedAtZero = ProgressionEngine.evaluateWeek(
            statKey: .strength, state: lowCharge, actualTotal: 5, decaySensitivity: 1.3
        )
        #expect(clampedAtZero.chargeAfterDecay == 0)
    }

    @Test func disablingDecayFreezesChargeRegardlessOfSensitivity() {
        // enableDecay == false must short-circuit decay entirely, so an idle
        // week neither bleeds charge nor honors the strictness step size.
        let state = WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: 3)
        let frozen = ProgressionEngine.evaluateWeek(
            statKey: .strength, state: state, actualTotal: 5, decayEnabled: false, decaySensitivity: 1.3
        )
        #expect(frozen.chargeBeforeDecay == 3)
        #expect(frozen.chargeAfterDecay == 3)
        #expect(frozen.visibleChargesAfter == 3)
    }

    @Test func negativeWeekCreatesDebtAndSingleRankDownPerWeek() {
        let state = WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: -3)
        let result = ProgressionEngine.evaluateWeek(statKey: .strength, state: state, actualTotal: 0)

        #expect(result.levelBefore == 6)
        #expect(result.levelAfter == 5)
        #expect(!result.didLevelUp)
        #expect(result.didLevelDown)
        #expect(result.weeklyDelta == -5)
        #expect(result.weeklyChargeDelta == -5)
        #expect(result.bankedUnitsAfter == 0)
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

        #expect(fixture.stat.rankLevel == 5)
        #expect(fixture.stat.currentBaseline == 4)
        #expect(fixture.stat.bankedProgressUnits == 0)
        #expect(fixture.stat.chargeValue == 0)
        #expect(fixture.stat.pendingRankChange?.direction == .up)
        #expect((fixture.stat.weeklyResolutions ?? []).count == 1)

        let resolution = try #require((fixture.stat.weeklyResolutions ?? []).first)
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
        #expect((fixture.stat.weeklyResolutions ?? []).isEmpty)
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
        #expect(fixture.stat.rankLevel == 6)
        #expect(fixture.stat.currentBaseline == 5)
        #expect(fixture.stat.bankedProgressUnits == 0)
        #expect(fixture.stat.chargeValue == 0)
        #expect(pending.direction == .up)
        #expect(pending.fromLevel == 4)
        #expect(pending.toLevel == 6)

        try TrainingStore.acknowledgePendingRankChange(for: fixture.stat, context: fixture.context)
        #expect(fixture.stat.pendingRankChange == nil)
        #expect(fixture.stat.acknowledgedRankLevel == 6)
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

    // MARK: - Wave A–E coverage

    @Test func calibrationClampingPreservesBaselinePrinciple() {
        let result = TrainingArcConfig.clampCalibration(baseline: 3, target: 2, personalMax: 4, maintenance: 5)
        #expect(result.target == 3, "Target below baseline should be raised to baseline")
        #expect(result.max == 4)
        #expect(result.maintenance == 3, "Maintenance above baseline should be clamped down")

        let strict = TrainingArcConfig.clampCalibration(baseline: 5, target: 7, personalMax: 5, maintenance: nil)
        #expect(strict.target == 7)
        #expect(strict.max == 7, "Personal max below target should be raised to target")
        #expect(strict.maintenance == nil)

        let optional = TrainingArcConfig.clampCalibration(baseline: 3, target: nil, personalMax: nil, maintenance: nil)
        #expect(optional.target == nil)
        #expect(optional.max == nil)
        #expect(optional.maintenance == nil)
    }

    @Test func suggestedTargetAndMaxAreReasonableForStrength() {
        let baseline = 3
        let target = TrainingArcConfig.suggestedTargetValue(for: .strength, baseline: baseline)
        let personalMax = TrainingArcConfig.suggestedPersonalMaxValue(for: .strength, baseline: baseline, target: target)
        #expect(target >= baseline + 1)
        #expect(personalMax >= target)
        #expect(personalMax >= baseline + 2)
    }

    @Test func progressionEngineGrantsBonusWhenGoalMetAboveBaseline() {
        let state = WeeklyProgressionState(level: 4, expectedWeeklyTarget: 3, bankedProgressUnits: 0)
        let baseline = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: state,
            actualTotal: 5,
            activeGoalTarget: nil
        )
        let withGoal = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: state,
            actualTotal: 5,
            activeGoalTarget: 5
        )

        #expect(withGoal.goalTargetMet)
        #expect(withGoal.goalBonusApplied)
        #expect(withGoal.weeklyChargeDelta == baseline.weeklyChargeDelta + 1, "Goal met above baseline should grant +1 bonus charge")
    }

    @Test func progressionEngineWithholdsBonusWhenBelowBaselineAndNotRecovery() {
        let state = WeeklyProgressionState(level: 4, expectedWeeklyTarget: 5, bankedProgressUnits: 0)
        let result = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: state,
            actualTotal: 3,
            activeGoalTarget: 3,
            isRecoveryGoal: false
        )

        #expect(result.goalTargetMet)
        #expect(!result.goalBonusApplied, "Goal met but below baseline should not grant bonus unless recovery mode")
        #expect(result.weeklyChargeDelta < 0, "Below baseline should still penalize charge")
    }

    @Test func progressionEngineGrantsBonusInRecoveryModeEvenBelowBaseline() {
        let state = WeeklyProgressionState(level: 4, expectedWeeklyTarget: 5, bankedProgressUnits: 0)
        let result = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: state,
            actualTotal: 3,
            activeGoalTarget: 3,
            isRecoveryGoal: true
        )

        #expect(result.goalTargetMet)
        #expect(result.goalBonusApplied, "Recovery goal met should grant bonus even below baseline")
        // Baseline penalty was -2, recovery bonus +1, net -1
        #expect(result.weeklyChargeDelta == -1)
    }

    @Test func progressionEngineWithoutGoalBehavesUnchanged() {
        let state = WeeklyProgressionState(level: 4, expectedWeeklyTarget: 3, bankedProgressUnits: 0)
        let result = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: state,
            actualTotal: 3
        )

        #expect(!result.goalTargetMet)
        #expect(!result.goalBonusApplied)
        #expect(result.weeklyChargeDelta == 0)
    }

    @Test func appSettingsDefaultsForNewWaveCFields() {
        let settings = AppSettings()
        #expect(settings.progressionStrictness == .balanced)
        #expect(settings.goalsCanAffectProgression == false)
        #expect(settings.showPersonalMaxInUI == true)
        #expect(settings.goalAtRiskReminderEnabled == false)
    }

    @Test func progressionStrictnessMapsToDecaySensitivity() {
        let settings = AppSettings()
        settings.progressionStrictness = .forgiving
        #expect(settings.decaySensitivity == 0.7)
        settings.progressionStrictness = .strict
        #expect(settings.decaySensitivity == 1.3)
        settings.progressionStrictness = .balanced
        #expect(settings.decaySensitivity == 1.0)
    }

    @Test func deepLinkParsesRouteHostsForBothSchemes() {
        guard case .route(.dashboard)? = DeepLinkRouter.parse(URL(string: "trainingarc://dashboard")!) else {
            Issue.record("Expected dashboard route from trainingarc scheme")
            return
        }
        guard case .route(.goals)? = DeepLinkRouter.parse(URL(string: "mythoslog://goals")!) else {
            Issue.record("Expected goals route from mythoslog scheme")
            return
        }
    }

    @Test func deepLinkRejectsUnknownScheme() {
        #expect(DeepLinkRouter.parse(URL(string: "https://example.com/dashboard")!) == nil)
    }

    @Test func deepLinkParsesSkillDetailWithLogFlag() {
        guard case let .skillDetail(statKey, openLog)? = DeepLinkRouter.parse(URL(string: "mythoslog://skill?key=strength&log=1")!) else {
            Issue.record("Expected skillDetail deep link")
            return
        }
        #expect(statKey == .strength)
        #expect(openLog)
    }

    @Test func deepLinkClampsExternalLogValue() {
        guard case let .externalLog(event)? = DeepLinkRouter.parse(URL(string: "mythoslog://log?stat=strength&value=1e12")!) else {
            Issue.record("Expected externalLog deep link")
            return
        }
        #expect(event.value == 100_000)
        #expect(event.statKey == .strength)
    }

    @Test func deepLinkParsesGoalDetailID() {
        let id = UUID()
        guard case let .goalDetail(goalID)? = DeepLinkRouter.parse(URL(string: "mythoslog://goal?id=\(id.uuidString)")!) else {
            Issue.record("Expected goalDetail deep link")
            return
        }
        #expect(goalID == id)
    }

    #if canImport(HealthKit)
    @Test func healthOverlapDurationComputesIntersection() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        // [0,60] overlapping [30,90] shares 30 seconds.
        #expect(HealthImportService.overlapDuration(
            firstStart: base, firstEnd: base.addingTimeInterval(60),
            secondStart: base.addingTimeInterval(30), secondEnd: base.addingTimeInterval(90)
        ) == 30)
        // Disjoint intervals share nothing.
        #expect(HealthImportService.overlapDuration(
            firstStart: base, firstEnd: base.addingTimeInterval(30),
            secondStart: base.addingTimeInterval(60), secondEnd: base.addingTimeInterval(90)
        ) == 0)
    }

    @Test func healthOverlapRatioIsRelativeToShorterInterval() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        // A 50s window fully inside a 100s window overlaps 100% of the shorter.
        #expect(HealthImportService.overlapRatio(
            firstStart: base, firstEnd: base.addingTimeInterval(100),
            secondStart: base.addingTimeInterval(50), secondEnd: base.addingTimeInterval(100)
        ) == 1.0)
        // A zero-length interval yields a safe 0 rather than dividing by zero.
        #expect(HealthImportService.overlapRatio(
            firstStart: base, firstEnd: base,
            secondStart: base, secondEnd: base.addingTimeInterval(100)
        ) == 0)
    }

    @Test func healthYearBackfillStartDateIsOneGregorianYearBack() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let expected = Calendar(identifier: .gregorian).date(byAdding: .year, value: -1, to: now)!
        #expect(HealthImportService.yearBackfillStartDate(now: now) == expected)
    }

    @Test func healthWorkoutMappingRoutesActivityToStat() {
        #expect(SupportedWorkoutType.mapping(for: .traditionalStrengthTraining)?.statKey == .strength)
        #expect(SupportedWorkoutType.mapping(for: .running)?.statKey == .cardio)
        #expect(SupportedWorkoutType.mapping(for: .tennis)?.statKey == .cardio)
        #expect(SupportedWorkoutType.mapping(for: .yoga)?.statKey == .focus)
        // An activity absent from the catalog is not importable.
        #expect(SupportedWorkoutType.mapping(for: .americanFootball) == nil)
    }
    #endif

    @Test @MainActor func createGoalPersistsAllFields() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let goal = try TrainingStore.createGoal(
            title: "5 gym sessions per week",
            notes: "Building toward marathon strength block.",
            scope: .skill,
            linkedStatKey: .strength,
            linkedHabitID: nil,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 5,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: isoDate("2026-05-01T00:00:00Z"),
            priority: .high,
            affectsMetrics: false,
            affectsProgression: true,
            isRecoveryMode: false,
            context: fixture.context
        )

        let fetched = try #require(try TrainingStore.fetchGoals(context: fixture.context).first { $0.id == goal.id })
        #expect(fetched.title == "5 gym sessions per week")
        #expect(fetched.scope == .skill)
        #expect(fetched.linkedStatKey == .strength)
        #expect(fetched.type == .weeklyTarget)
        #expect(fetched.targetValue == 5)
        #expect(fetched.status == .active)
        #expect(fetched.priority == .high)
        #expect(fetched.affectsProgression == true)
        #expect(fetched.isRecoveryMode == false)
    }

    @Test @MainActor func setGoalStatusTransitionsAndTimestampsCorrectly() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let goal = try TrainingStore.createGoal(
            title: "Test",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 5,
            context: fixture.context
        )

        try TrainingStore.setGoalStatus(goal, status: .completed, context: fixture.context)
        #expect(goal.status == .completed)
        #expect(goal.completedAt != nil)

        try TrainingStore.setGoalStatus(goal, status: .active, context: fixture.context)
        #expect(goal.status == .active)
        #expect(goal.completedAt == nil, "Reactivating should clear completedAt")

        try TrainingStore.setGoalStatus(goal, status: .archived, context: fixture.context)
        #expect(goal.status == .archived)
    }

    @Test @MainActor func goalProgressComputesCurrentValueFromLogs() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let weekStart = TrainingStore.progressionWeek(containing: .now).start

        try addSessionLogs(count: 3, habit: fixture.habit, weekStart: weekStart, context: fixture.context)

        let goal = try TrainingStore.createGoal(
            title: "5 sessions",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 5,
            context: fixture.context
        )

        let snapshot = TrainingStore.goalProgress(for: goal, context: fixture.context)
        #expect(snapshot.currentValue == 3)
        #expect(snapshot.targetValue == 5)
        #expect(snapshot.progressRatio == 0.6)
        #expect(snapshot.remainingValue == 2)
    }

    @Test @MainActor func deleteGoalRemovesItFromStore() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let goal = try TrainingStore.createGoal(
            title: "To delete",
            scope: .overall,
            type: .custom,
            measurementType: .count,
            targetValue: 1,
            context: fixture.context
        )

        try TrainingStore.deleteGoal(goal, context: fixture.context)

        let remaining = try TrainingStore.fetchGoals(context: fixture.context)
        #expect(remaining.allSatisfy { $0.id != goal.id })
    }

    @Test @MainActor func seedSampleGoalsCreatesExpectedSpread() throws {
        let fixture = try makeStrengthFixture(baseline: 3)

        try TrainingStore.seedSampleGoals(context: fixture.context)

        let goals = try TrainingStore.fetchGoals(context: fixture.context)
        #expect(goals.count >= 2, "Should seed at least a Strength weekly + an overall monthly goal")
        #expect(goals.contains { $0.linkedStatKey == .strength })
        #expect(goals.contains { $0.scope == .overall })
    }

    @Test @MainActor func trainTodayRecommendationsSurfaceBaselineGapForUnloggedSkill() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-03-30T12:00:00Z")

        let recommendations = try TrainingStore.trainTodayRecommendations(
            context: fixture.context,
            settings: nil,
            now: now,
            limit: 5
        )

        // With no logs and a baseline, at least one stale-or-no-log recommendation should appear
        #expect(!recommendations.isEmpty)
        #expect(recommendations.allSatisfy { !$0.headline.isEmpty })
    }

    @Test @MainActor func activeWeeklyGoalIsFilteredByDateAndProgressionFlag() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let week = TrainingStore.progressionWeek(containing: isoDate("2026-04-01T12:00:00Z"))

        let trackingOnly = try TrainingStore.createGoal(
            title: "Tracking only",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 4,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: isoDate("2026-05-01T00:00:00Z"),
            affectsProgression: false,
            context: fixture.context
        )
        _ = trackingOnly

        let influencing = try TrainingStore.createGoal(
            title: "Influencing",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 6,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: isoDate("2026-05-01T00:00:00Z"),
            affectsProgression: true,
            context: fixture.context
        )

        let target = TrainingStore.activeWeeklyGoalTarget(for: [trackingOnly, influencing], week: week)
        #expect(target == 6, "Should pick the goal with affectsProgression=true")

        let goal = TrainingStore.activeWeeklyGoal(for: [trackingOnly, influencing], week: week)
        #expect(goal?.id == influencing.id)
    }

    @Test func goalIsRecoveryModeDefaultsToFalse() {
        let goal = Goal(
            title: "Test",
            scope: .skill,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 5
        )
        #expect(goal.isRecoveryMode == false)
        #expect(goal.affectsProgression == false)
        #expect(goal.status == .active)
    }

    @MainActor
    private func insertHealthRecord(
        habit: Habit,
        workoutID: String,
        wasImported: Bool = true,
        isDuplicate: Bool = false,
        overlaps: Bool = false,
        sourceName: String? = "Apple Watch",
        endDate: Date,
        context: ModelContext
    ) {
        context.insert(
            HealthImportedWorkout(
                workoutUUID: workoutID,
                statKeyRaw: StatKey.strength.rawValue,
                habitSystemKey: habit.systemKey,
                sourceName: sourceName,
                sourceBundleIdentifier: "com.apple.Health",
                activityTypeRaw: 50,
                startDate: endDate.addingTimeInterval(-3600),
                endDate: endDate,
                durationMinutes: 45,
                wasImported: wasImported,
                isDuplicate: isDuplicate,
                overlapsImportedWorkout: overlaps
            )
        )
    }

    @Test @MainActor func healthAttributionMatchesByWorkoutUUIDAndCountsTowardWeek() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let workoutID = UUID().uuidString
        let logDate = isoDate("2026-04-02T18:00:00Z")

        insertHealthRecord(habit: fixture.habit, workoutID: workoutID, endDate: logDate, context: fixture.context)
        let log = HabitLog(
            date: logDate,
            numericValue: 1,
            sessionType: "Strength",
            note: "Imported from Apple Health",
            sourceType: .health,
            healthWorkoutUUID: workoutID,
            habit: fixture.habit
        )
        fixture.context.insert(log)
        try fixture.context.save()

        let resolver = TrainingStore.healthAttributionContext(context: fixture.context)
        let attribution = try #require(resolver.attribution(for: log))

        #expect(attribution.mappedSkillName == StatKey.strength.displayName)
        #expect(attribution.countedTowardWeeklyProgress == true)
        #expect(attribution.ignoredAsDuplicate == false)
        #expect(attribution.needsReview == false)
        #expect(attribution.sourceAppName == "Apple Watch")
        #expect(attribution.durationMinutes == 45)
    }

    @Test @MainActor func healthAttributionFlagsDuplicateAsNotCounted() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let workoutID = UUID().uuidString
        let logDate = isoDate("2026-04-02T18:00:00Z")

        insertHealthRecord(
            habit: fixture.habit,
            workoutID: workoutID,
            wasImported: false,
            isDuplicate: true,
            endDate: logDate,
            context: fixture.context
        )
        let log = HabitLog(
            date: logDate,
            numericValue: 1,
            sessionType: "Strength",
            note: "Imported from Apple Health",
            sourceType: .health,
            healthWorkoutUUID: workoutID,
            habit: fixture.habit
        )
        fixture.context.insert(log)
        try fixture.context.save()

        let resolver = TrainingStore.healthAttributionContext(context: fixture.context)
        let attribution = try #require(resolver.attribution(for: log))

        #expect(attribution.ignoredAsDuplicate == true)
        #expect(attribution.countedTowardWeeklyProgress == false)
    }

    @Test @MainActor func healthAttributionIsNilForManualLogs() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let log = HabitLog(
            date: isoDate("2026-04-02T18:00:00Z"),
            numericValue: 1,
            note: "Manual entry",
            sourceType: .manual,
            habit: fixture.habit
        )
        fixture.context.insert(log)
        try fixture.context.save()

        let resolver = TrainingStore.healthAttributionContext(context: fixture.context)
        #expect(resolver.attribution(for: log) == nil)
    }

    @Test @MainActor func healthAttributionDetectsActiveGoalImpact() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let workoutID = UUID().uuidString
        let logDate = isoDate("2026-04-02T18:00:00Z")

        _ = try TrainingStore.createGoal(
            title: "Strength weekly",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 4,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: isoDate("2026-05-01T00:00:00Z"),
            context: fixture.context
        )

        insertHealthRecord(habit: fixture.habit, workoutID: workoutID, endDate: logDate, context: fixture.context)
        let log = HabitLog(
            date: logDate,
            numericValue: 1,
            sessionType: "Strength",
            note: "Imported from Apple Health",
            sourceType: .health,
            healthWorkoutUUID: workoutID,
            habit: fixture.habit
        )
        fixture.context.insert(log)
        try fixture.context.save()

        let resolver = TrainingStore.healthAttributionContext(context: fixture.context)
        let attribution = try #require(resolver.attribution(for: log))
        #expect(attribution.affectedGoal == true)
    }

    @Test @MainActor func dashboardHighlightsClassifyChargeExtremes() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        fixture.stat.chargeValue = 4

        let cardio = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .cardio })
        cardio.chargeValue = -3
        try fixture.context.save()

        let sections = try TrainingStore.dashboardSections(
            context: fixture.context,
            settings: nil,
            now: isoDate("2026-04-03T12:00:00Z")
        )

        #expect(sections.highlights.contains { $0.statKeyRaw == StatKey.strength.rawValue && $0.kind == .nearRankUp })
        #expect(sections.highlights.contains { $0.statKeyRaw == StatKey.cardio.rawValue && $0.kind == .losingMomentum })
    }

    @Test @MainActor func dashboardHighlightSurfacesPendingRankUp() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        fixture.stat.setPendingRankChange(from: 3, to: 4, direction: .up, reason: .logMutation, recordedAt: isoDate("2026-04-01T00:00:00Z"))
        try fixture.context.save()

        let sections = try TrainingStore.dashboardSections(context: fixture.context, settings: nil)
        let highlight = try #require(sections.highlights.first { $0.statKeyRaw == StatKey.strength.rawValue })
        #expect(highlight.kind == .rankedUp)
    }

    @Test @MainActor func weeklyStatusCountsAheadSkillFromProratedPace() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-03T12:00:00Z")
        let week = TrainingStore.progressionWeek(containing: now)
        try addSessionLogs(count: 10, habit: fixture.habit, weekStart: week.start, context: fixture.context)

        let sections = try TrainingStore.dashboardSections(context: fixture.context, settings: nil, now: now)
        #expect(sections.weeklyStatus.aheadCount >= 1)
    }

    @Test @MainActor func weeklyStatusReportsNoActivityWhenNothingLogged() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-03T12:00:00Z")

        let sections = try TrainingStore.dashboardSections(context: fixture.context, settings: nil, now: now)
        #expect(sections.weeklyStatus.kind == .noActivity)
        #expect(sections.weeklyStatus.behindCount >= 1)
    }

    @Test @MainActor func goalsSummaryCountsActiveAndCompletedThisWeek() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-03T12:00:00Z")

        _ = try TrainingStore.createGoal(
            title: "Active strength",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 5,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: isoDate("2026-06-01T00:00:00Z"),
            context: fixture.context
        )

        let completed = try TrainingStore.createGoal(
            title: "Finished overall",
            scope: .overall,
            type: .monthlyTotal,
            measurementType: .count,
            targetValue: 1,
            context: fixture.context
        )
        try TrainingStore.setGoalStatus(completed, status: .completed, context: fixture.context)
        completed.completedAt = now
        try fixture.context.save()

        let sections = try TrainingStore.dashboardSections(context: fixture.context, settings: nil, now: now)
        #expect(sections.goals.activeCount >= 1)
        #expect(sections.goals.completedThisWeekCount >= 1)
        #expect(sections.goals.totalCount >= 2)
    }

    @Test @MainActor func weeklyRecapSummarizesBestNeglectedAndCharge() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-01T12:00:00Z")
        let week = TrainingStore.progressionWeek(containing: now)

        fixture.context.insert(
            WeeklyResolution(
                statKey: StatKey.strength.rawValue,
                statName: "Strength",
                weekStartDate: week.start,
                weekEndDate: week.end,
                baselineAtStart: 3,
                expectedTotal: 3,
                actualCompletedValue: 7,
                weeklyDelta: 4,
                excessValue: 4,
                chargesEarned: 1,
                chargesSpentOnLevelUp: 0,
                bankedUnitsBefore: 0,
                bankedUnitsAfter: 0,
                levelBefore: 4,
                levelAfter: 4,
                storedChargesAfter: 1,
                didDecay: false,
                didLevelUp: false,
                didStagnate: false,
                didRegress: false,
                summaryText: ""
            )
        )
        fixture.context.insert(
            WeeklyResolution(
                statKey: StatKey.reading.rawValue,
                statName: "Reading",
                weekStartDate: week.start,
                weekEndDate: week.end,
                baselineAtStart: 5,
                expectedTotal: 5,
                actualCompletedValue: 2,
                weeklyDelta: -3,
                excessValue: -3,
                chargesEarned: -1,
                chargesSpentOnLevelUp: 0,
                bankedUnitsBefore: 0,
                bankedUnitsAfter: 0,
                levelBefore: 3,
                levelAfter: 3,
                storedChargesAfter: -1,
                didDecay: true,
                didLevelUp: false,
                didStagnate: false,
                didRegress: false,
                summaryText: ""
            )
        )
        try fixture.context.save()

        let recap = try TrainingStore.weeklyRecap(weekStart: week.start, context: fixture.context, settings: nil, now: now)
        #expect(recap.bestSkillName == "Strength")
        #expect(recap.neglectedSkillName == "Reading")
        #expect(recap.gainedChargeSkills.contains("Strength"))
        #expect(recap.lostChargeSkills.contains("Reading"))
        #expect(recap.hasContent)
    }

    @Test @MainActor func weeklyRecapCountsGoalsCompletedInWeek() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-01T12:00:00Z")
        let week = TrainingStore.progressionWeek(containing: now)

        let goal = try TrainingStore.createGoal(
            title: "Done goal",
            scope: .overall,
            type: .monthlyTotal,
            measurementType: .count,
            targetValue: 1,
            context: fixture.context
        )
        try TrainingStore.setGoalStatus(goal, status: .completed, context: fixture.context)
        goal.completedAt = now
        try fixture.context.save()

        let recap = try TrainingStore.weeklyRecap(weekStart: week.start, context: fixture.context, settings: nil, now: now)
        #expect(recap.goalsCompleted.contains("Done goal"))
    }

    @Test func noRankLossBehaviorHoldsRankAtMinimumCharge() {
        let state = WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: -3)
        let result = ProgressionEngine.evaluateWeek(
            statKey: .strength,
            state: state,
            actualTotal: 0,
            allowRankDown: false
        )

        #expect(result.levelBefore == 6)
        #expect(result.levelAfter == 6)
        #expect(!result.didLevelDown)
        #expect(result.bankedUnitsAfter == -4)
    }

    @Test func standardRegressionStillAllowsRankDownByDefault() {
        let state = WeeklyProgressionState(level: 6, expectedWeeklyTarget: 5, bankedProgressUnits: -3)
        let result = ProgressionEngine.evaluateWeek(statKey: .strength, state: state, actualTotal: 0)
        #expect(result.didLevelDown)
        #expect(result.levelAfter == 5)
    }

    @Test func appSettingsDefaultsForRegressionAndPacing() {
        let settings = AppSettings()
        #expect(settings.regressionBehavior == .standard)
        #expect(settings.regressionBehavior.allowsRankDown == true)
        #expect(settings.goalsAffectPacing == true)
        #expect(settings.skillBehindPaceReminderEnabled == false)
    }

    @Test @MainActor func skillsBehindPaceCountFlagsUnloggedSkill() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-03T12:00:00Z")
        let count = TrainingStore.skillsBehindPaceCount(context: fixture.context, settings: nil, now: now)
        #expect(count >= 1)
    }

    @Test @MainActor func goalsAffectPacingOffSuppressesGoalAtRiskRecommendation() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-04-03T12:00:00Z")

        _ = try TrainingStore.createGoal(
            title: "Strength push",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 8,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: isoDate("2026-06-01T00:00:00Z"),
            context: fixture.context
        )

        let settings = try TrainingStore.fetchSettings(context: fixture.context)
        settings.goalsAffectPacing = false
        try fixture.context.save()

        let recommendations = try TrainingStore.trainTodayRecommendations(
            context: fixture.context,
            settings: settings,
            now: now,
            limit: 10
        )
        #expect(!recommendations.contains { $0.reason == .goalAtRisk })
    }

    @Test @MainActor func settingsExportImportRoundTripsRegressionAndPacing() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let settings = try TrainingStore.fetchSettings(context: fixture.context)
        settings.regressionBehavior = .noRankLoss
        settings.goalsAffectPacing = false
        settings.skillBehindPaceReminderEnabled = true
        try fixture.context.save()

        let bundle = try TrainingStore.exportBundle(context: fixture.context)
        #expect(bundle.settings.regressionBehaviorRaw == RegressionBehavior.noRankLoss.rawValue)
        #expect(bundle.settings.goalsAffectPacing == false)
        #expect(bundle.settings.skillBehindPaceReminderEnabled == true)

        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(TrainingExportBundle.self, from: data)
        try TrainingStore.importBundle(decoded, context: fixture.context)

        let imported = try TrainingStore.fetchSettings(context: fixture.context)
        #expect(imported.regressionBehavior == .noRankLoss)
        #expect(imported.goalsAffectPacing == false)
        #expect(imported.skillBehindPaceReminderEnabled == true)
    }

    @Test @MainActor func drainQuickLogQueueCreatesWidgetSourcedLogs() throws {
        let fixture = try makeStrengthFixture(baseline: 3)

        QuickLogQueue.clear()
        QuickLogQueue.enqueue(habitID: fixture.habit.id.uuidString, amount: 2)

        // App group may be unavailable in some environments; only assert when the
        // enqueue actually persisted.
        guard !QuickLogQueue.pending().isEmpty else { return }

        let applied = try TrainingStore.drainQuickLogQueue(context: fixture.context)
        #expect(applied >= 1)
        #expect(QuickLogQueue.pending().isEmpty)

        let widgetLogs = try TrainingStore.fetchLogs(context: fixture.context).filter { $0.sourceType == .widget }
        #expect(!widgetLogs.isEmpty)

        QuickLogQueue.clear()
    }

    @Test @MainActor func drainQuickLogQueueIsNoOpWhenEmpty() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        QuickLogQueue.clear()
        let applied = try TrainingStore.drainQuickLogQueue(context: fixture.context)
        #expect(applied == 0)
    }

    @Test @MainActor func goalLinkedHabitIDPersistsThroughCreate() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let goal = try TrainingStore.createGoal(
            title: "Habit-scoped",
            scope: .skill,
            linkedStatKey: .strength,
            linkedHabitID: fixture.habit.id,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 3,
            context: fixture.context
        )
        #expect(goal.linkedHabitID == fixture.habit.id)
    }

    @Test @MainActor func automaticTransitionFailsUnmetAchievableGoalPastEndDate() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-05-01T12:00:00Z")
        let goal = try TrainingStore.createGoal(
            title: "Custom total",
            scope: .skill,
            linkedStatKey: .strength,
            type: .custom,
            measurementType: .count,
            targetValue: 50,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: isoDate("2026-04-01T00:00:00Z"),
            context: fixture.context
        )

        let count = try TrainingStore.applyAutomaticGoalTransitions(context: fixture.context, now: now)
        #expect(count >= 1)
        #expect(goal.status == .failed)
    }

    @Test @MainActor func automaticTransitionCompletesMetAchievableGoalAtEndDate() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-05-01T12:00:00Z")
        let endDate = isoDate("2026-04-01T00:00:00Z")
        let goal = try TrainingStore.createGoal(
            title: "Reach level",
            scope: .skill,
            linkedStatKey: .strength,
            type: .reachLevel,
            measurementType: .count,
            targetValue: 1,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: endDate,
            context: fixture.context
        )

        _ = try TrainingStore.applyAutomaticGoalTransitions(context: fixture.context, now: now)
        #expect(goal.status == .completed)
        #expect(goal.completedAt == endDate)
    }

    @Test @MainActor func automaticTransitionArchivesRecurringGoalPastEndDate() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-05-01T12:00:00Z")
        let goal = try TrainingStore.createGoal(
            title: "Weekly recurring",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 5,
            startDate: isoDate("2026-03-01T00:00:00Z"),
            endDate: isoDate("2026-04-01T00:00:00Z"),
            context: fixture.context
        )

        _ = try TrainingStore.applyAutomaticGoalTransitions(context: fixture.context, now: now)
        #expect(goal.status == .archived)
    }

    @Test @MainActor func automaticTransitionLeavesFutureAndOpenGoalsActive() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let now = isoDate("2026-05-01T12:00:00Z")
        let future = try TrainingStore.createGoal(
            title: "Future",
            scope: .overall,
            type: .custom,
            measurementType: .count,
            targetValue: 10,
            startDate: isoDate("2026-04-01T00:00:00Z"),
            endDate: isoDate("2026-12-01T00:00:00Z"),
            context: fixture.context
        )
        let open = try TrainingStore.createGoal(
            title: "Open ended",
            scope: .overall,
            type: .custom,
            measurementType: .count,
            targetValue: 10,
            startDate: isoDate("2026-04-01T00:00:00Z"),
            endDate: nil,
            context: fixture.context
        )

        _ = try TrainingStore.applyAutomaticGoalTransitions(context: fixture.context, now: now)
        #expect(future.status == .active)
        #expect(open.status == .active)
    }

    @Test @MainActor func healthWorkoutUUIDRoundTripsThroughExportImport() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let workoutID = UUID().uuidString
        fixture.context.insert(
            HabitLog(
                date: isoDate("2026-04-02T18:00:00Z"),
                numericValue: 1,
                note: "Imported from Apple Health",
                sourceType: .health,
                healthWorkoutUUID: workoutID,
                habit: fixture.habit
            )
        )
        try fixture.context.save()

        let bundle = try TrainingStore.exportBundle(context: fixture.context)
        let exportedLog = try #require(bundle.logs.first { $0.sourceTypeRaw == LogSourceType.health.rawValue })
        #expect(exportedLog.healthWorkoutUUID == workoutID)

        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(TrainingExportBundle.self, from: data)
        let decodedLog = try #require(decoded.logs.first { $0.sourceTypeRaw == LogSourceType.health.rawValue })
        #expect(decodedLog.healthWorkoutUUID == workoutID)
    }

    // MARK: - Skill taxonomy / activation

    @Test @MainActor func onboardingSeedsCoreSkillsActiveAndOptionalArchived() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let active = Set(try TrainingStore.fetchActiveStats(context: fixture.context).compactMap(\.statKey))
        #expect(active == TrainingArcConfig.coreSkillKeys)
        #expect(!active.contains(.reading))
        #expect(!active.contains(.curiosity))

        let reading = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .reading })
        #expect(reading.isArchived)
        #expect(!reading.isCore)
        #expect(reading.parentSkillKey == .intellect)
    }

    @Test @MainActor func intellectKeepsReadingHabitAndReadingSkillStaysOptional() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let intellect = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .intellect })
        #expect(intellect.isActive)
        #expect(TrainingStore.activeHabits(for: intellect).contains { $0.systemKey == "habit.reading" })

        let reading = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .reading })
        #expect(!reading.isActive)
    }

    @Test @MainActor func curiosityIsOptionalAndArchivedByDefault() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let curiosity = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .curiosity })
        #expect(!curiosity.isCore)
        #expect(!curiosity.isActive)
        #expect(curiosity.parentSkillKey == nil)
    }

    @Test @MainActor func archivingSkillPreservesLogsAndExcludesFromActive() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let week = TrainingStore.progressionWeek(containing: isoDate("2026-04-01T12:00:00Z"))
        try addSessionLogs(count: 2, habit: fixture.habit, weekStart: week.start, context: fixture.context)

        try TrainingStore.archiveSkill(fixture.stat, context: fixture.context)
        #expect(fixture.stat.isArchived)
        #expect(!fixture.stat.isActive)

        // Logs preserved; skill still present in the full set, gone from active.
        #expect(try TrainingStore.fetchLogs(context: fixture.context).count >= 2)
        #expect(try TrainingStore.fetchStats(context: fixture.context).contains { $0.statKey == .strength })
        #expect(try TrainingStore.fetchActiveStats(context: fixture.context).allSatisfy { $0.statKey != .strength })
    }

    @Test @MainActor func archivingSkillKeepsLinkedGoal() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let goal = try TrainingStore.createGoal(
            title: "Strength goal",
            scope: .skill,
            linkedStatKey: .strength,
            type: .weeklyTarget,
            measurementType: .booleanSession,
            targetValue: 3,
            context: fixture.context
        )

        try TrainingStore.archiveSkill(fixture.stat, context: fixture.context)
        #expect(try TrainingStore.fetchGoals(context: fixture.context).contains { $0.id == goal.id })
    }

    @Test @MainActor func restoringArchivedOptionalSkillReactivatesWithStarterHabit() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let reading = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .reading })
        #expect(!reading.isActive)

        try TrainingStore.restoreSkill(reading, context: fixture.context)
        #expect(reading.isActive)
        #expect(!TrainingStore.activeHabits(for: reading).isEmpty)

        let active = try TrainingStore.fetchActiveStats(context: fixture.context).compactMap(\.statKey)
        #expect(active.contains(.reading))
    }

    @Test @MainActor func enablingOptionalSkillFromArchivedStateAddsItToActive() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let curiosity = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .curiosity })
        try TrainingStore.enableSkill(curiosity, context: fixture.context)
        #expect(curiosity.isActive)
        #expect(try TrainingStore.fetchActiveStats(context: fixture.context).compactMap(\.statKey).contains(.curiosity))
    }

    @Test @MainActor func widgetSnapshotRefreshHandlesArchivedSkillWithoutCrashing() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        try TrainingStore.archiveSkill(fixture.stat, context: fixture.context)
        // Must not throw; archived skill must be absent from the active set the
        // snapshot is built from.
        try TrainingStore.refreshWidgetSnapshot(context: fixture.context)
        #expect(try TrainingStore.fetchActiveStats(context: fixture.context).allSatisfy { $0.statKey != .strength })
    }

    @Test @MainActor func migrationKeepsOptionalSkillWithLogsAndArchivesEmptyOne() throws {
        let container = TrainingStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        try TrainingStore.seedDefaultProfile(context: context, baselines: [:], completeOnboarding: true)

        // Simulate pre-migration data: optional skills active, reading has a log.
        let reading = try #require(try TrainingStore.fetchStats(context: context).first { $0.statKey == .reading })
        let curiosity = try #require(try TrainingStore.fetchStats(context: context).first { $0.statKey == .curiosity })
        for stat in [reading, curiosity] {
            stat.isArchived = false
            stat.isEnabled = true
            stat.isCore = false
        }
        let readingHabit = Habit(
            systemKey: "habit.reading.session",
            name: "Reading",
            measurementType: .pages,
            unitLabel: "pages",
            scheduleType: .weekly,
            targetPerPeriod: 90,
            statDomain: reading
        )
        context.insert(readingHabit)
        context.insert(HabitLog(date: isoDate("2026-04-01T12:00:00Z"), numericValue: 30, note: "", sourceType: .manual, habit: readingHabit))
        try context.save()

        // Force the one-time migration to run.
        UserDefaults(suiteName: AppIdentity.appGroupIdentifier)?.removeObject(forKey: "training.arc.skillActivationMigrated.v1")
        _ = try TrainingStore.reconcileSyncedData(context: context)

        #expect(reading.isActive)      // has logged history → kept
        #expect(!curiosity.isActive)   // empty optional → archived
        #expect(curiosity.isArchived)
    }

    @Test @MainActor func skillActivationFieldsRoundTripThroughExportImport() throws {
        let fixture = try makeStrengthFixture(baseline: 3)
        let reading = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .reading })
        #expect(!reading.isActive)

        let bundle = try TrainingStore.exportBundle(context: fixture.context)
        let exportedReading = try #require(bundle.stats.first { $0.key == StatKey.reading.rawValue })
        #expect(exportedReading.isCore == false)
        #expect(exportedReading.isEnabled == false)
        #expect(exportedReading.isArchived == true)

        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(TrainingExportBundle.self, from: data)
        try TrainingStore.importBundle(decoded, context: fixture.context)

        let importedReading = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .reading })
        #expect(!importedReading.isActive)
        #expect(!importedReading.isCore)
        let importedStrength = try #require(try TrainingStore.fetchStats(context: fixture.context).first { $0.statKey == .strength })
        #expect(importedStrength.isCore)
        #expect(importedStrength.isActive)
    }
}
