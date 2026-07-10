import Foundation
import SwiftData
import SwiftUI

enum StatKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength
    case intellect
    case creativity
    case emotional
    case focus
    case curiosity
    case cardio
    case cooking
    case reading

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: "Strength"
        case .intellect: "Intellect"
        case .creativity: "Creativity"
        case .emotional: "Emotional"
        case .focus: "Focus"
        case .curiosity: "Curiosity"
        case .cardio: "Cardio"
        case .cooking: "Cooking"
        case .reading: "Reading"
        }
    }
}

enum MeasurementType: String, Codable, CaseIterable, Identifiable, Sendable {
    case booleanSession
    case count
    case pages
    case minutes
    case customNumber

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .booleanSession: "Session"
        case .count: "Count"
        case .pages: "Pages"
        case .minutes: "Minutes"
        case .customNumber: "Custom"
        }
    }

    var defaultUnitLabel: String {
        switch self {
        case .booleanSession: "session"
        case .count: "count"
        case .pages: "pages"
        case .minutes: "min"
        case .customNumber: "points"
        }
    }

    var defaultIncrement: Double {
        switch self {
        case .booleanSession: 1
        case .count: 1
        case .pages: 10
        case .minutes: 10
        case .customNumber: 1
        }
    }

    var quickStepValues: [Double] {
        switch self {
        case .booleanSession:
            [1]
        case .count:
            [1, 5, 10]
        case .pages:
            [10, 25, 50, 100]
        case .minutes:
            [5, 10, 20, 30]
        case .customNumber:
            [1, 3, 5]
        }
    }

    /// Quick-log increments scaled to a skill's weekly baseline so the tap
    /// options are proportional to typical effort. A 120 min/week cardio skill
    /// yields ~+20/+40/+60; a 10/week cooking skill yields ~+1/+2/+3. Falls back
    /// to the static `quickStepValues` when no baseline is known.
    func quickStepValues(weeklyBaseline: Int) -> [Double] {
        if self == .booleanSession { return [1] }
        guard weeklyBaseline > 0 else { return quickStepValues }
        let unit = MeasurementType.niceStep(Double(weeklyBaseline) / 6)
        return [unit, unit * 2, unit * 3]
    }

    /// Rounds a raw increment to a tidy, human-friendly number.
    static func niceStep(_ value: Double) -> Double {
        guard value > 1 else { return 1 }
        if value >= 15 { return (value / 10).rounded() * 10 } // nearest 10
        if value >= 7 { return (value / 5).rounded() * 5 }    // nearest 5
        return value.rounded(.down)                            // nearest whole
    }

    var prefersIntegerValue: Bool {
        true
    }
}

enum ScheduleType: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

enum LogSourceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case shortcut
    case widget
    case health
    case integration
    case debug

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .shortcut: "Shortcut"
        case .widget: "Widget"
        case .health: "Apple Health"
        case .integration: "Integration"
        case .debug: "Debug"
        }
    }
}

enum ProgressionStrictness: String, Codable, CaseIterable, Identifiable, Sendable {
    case forgiving
    case balanced
    case strict

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forgiving: "Forgiving"
        case .balanced: "Balanced"
        case .strict: "Strict"
        }
    }

    var decaySensitivity: Double {
        switch self {
        case .forgiving: 0.7
        case .balanced: 1.0
        case .strict: 1.3
        }
    }

    var detail: String {
        switch self {
        case .forgiving: "Slower decay. Missing baseline costs less charge."
        case .balanced: "Default behavior. One step toward zero each completed week."
        case .strict: "Faster decay. Missing baseline costs more charge."
        }
    }
}

enum RegressionBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case noRankLoss

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .noRankLoss: "No rank loss"
        }
    }

    var detail: String {
        switch self {
        case .standard: "Skills can drop a rank after a sustained stretch below baseline."
        case .noRankLoss: "Charge can fall but ranks never drop. Progress only moves forward."
        }
    }

    /// When false, the engine holds the current rank even at minimum charge.
    var allowsRankDown: Bool { self == .standard }
}

enum DashboardLayoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case detailedCards
    case compactGrid
    case gameGrid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .detailedCards:
            return "Detailed Cards"
        case .compactGrid:
            return "Compact Grid"
        case .gameGrid:
            return "Game Grid"
        }
    }
}

enum RankChangeDirection: String, Codable, Sendable {
    case up
    case down
}

enum RankChangeReason: String, Codable, Sendable {
    case onboarding
    case logMutation
    case deleteMutation
    case appRefresh
    case skillOpen
}

@Model
final class StatDomain {
    var id: UUID = UUID()
    var key: String = ""
    var name: String = ""
    var iconName: String = ""
    var colorToken: String = ""
    var descriptor: String = ""
    var sortOrder: Int = 0
    var currentLevel: Int = 1
    var currentTierName: String = ""
    var startingBaseline: Int = 0
    var currentBaseline: Int = 0
    var targetValue: Int?
    var personalMaxValue: Int?
    var maintenanceFloor: Int?
    var storedCharges: Int = 0
    var bankedProgressUnits: Double = 0
    var lastResolvedWeekStart: Date?
    var lastAcknowledgedLevel: Int = 1
    var pendingRankChangeDirectionRaw: String?
    var pendingRankChangeFromLevel: Int?
    var pendingRankChangeToLevel: Int?
    var pendingRankChangeRecordedAt: Date?
    var pendingRankChangeReasonRaw: String?
    var pendingRankChangeViewedAt: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isArchived: Bool = false
    // Skill activation model. All default so existing rows migrate cleanly and
    // CloudKit can mirror them.
    var isCore: Bool = false
    var isEnabled: Bool = true
    var isCustom: Bool = false
    var parentSkillKeyRaw: String?
    @Relationship(deleteRule: .cascade, inverse: \Habit.statDomain) var habits: [Habit]? = []
    @Relationship(deleteRule: .cascade, inverse: \WeeklyResolution.statDomain) var weeklyResolutions: [WeeklyResolution]? = []

    init(
        id: UUID = UUID(),
        key: String,
        name: String,
        iconName: String,
        colorToken: String,
        descriptor: String,
        sortOrder: Int = 0,
        currentLevel: Int = 1,
        currentTierName: String,
        startingBaseline: Int,
        currentBaseline: Int,
        targetValue: Int? = nil,
        personalMaxValue: Int? = nil,
        maintenanceFloor: Int? = nil,
        storedCharges: Int = 0,
        bankedProgressUnits: Double = 0,
        lastResolvedWeekStart: Date? = nil,
        lastAcknowledgedLevel: Int = 1,
        pendingRankChangeDirectionRaw: String? = nil,
        pendingRankChangeFromLevel: Int? = nil,
        pendingRankChangeToLevel: Int? = nil,
        pendingRankChangeRecordedAt: Date? = nil,
        pendingRankChangeReasonRaw: String? = nil,
        pendingRankChangeViewedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isArchived: Bool = false,
        isCore: Bool = false,
        isEnabled: Bool = true,
        isCustom: Bool = false,
        parentSkillKeyRaw: String? = nil
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.iconName = iconName
        self.colorToken = colorToken
        self.descriptor = descriptor
        self.sortOrder = sortOrder
        self.currentLevel = currentLevel
        self.currentTierName = currentTierName
        self.startingBaseline = startingBaseline
        self.currentBaseline = currentBaseline
        self.targetValue = targetValue
        self.personalMaxValue = personalMaxValue
        self.maintenanceFloor = maintenanceFloor
        self.storedCharges = storedCharges
        self.bankedProgressUnits = bankedProgressUnits
        self.lastResolvedWeekStart = lastResolvedWeekStart
        self.lastAcknowledgedLevel = lastAcknowledgedLevel
        self.pendingRankChangeDirectionRaw = pendingRankChangeDirectionRaw
        self.pendingRankChangeFromLevel = pendingRankChangeFromLevel
        self.pendingRankChangeToLevel = pendingRankChangeToLevel
        self.pendingRankChangeRecordedAt = pendingRankChangeRecordedAt
        self.pendingRankChangeReasonRaw = pendingRankChangeReasonRaw
        self.pendingRankChangeViewedAt = pendingRankChangeViewedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.isCore = isCore
        self.isEnabled = isEnabled
        self.isCustom = isCustom
        self.parentSkillKeyRaw = parentSkillKeyRaw
    }

    var statKey: StatKey? {
        StatKey(rawValue: key)
    }

    var parentSkillKey: StatKey? {
        get { parentSkillKeyRaw.flatMap(StatKey.init(rawValue:)) }
        set { parentSkillKeyRaw = newValue?.rawValue }
    }

    /// Visible in the main experience: enabled and not archived.
    var isActive: Bool {
        isEnabled && !isArchived
    }
}

extension StatDomain {
    var rankLevel: Int {
        get { TrainingArcConfig.clampedRankLevel(currentLevel) }
        set { currentLevel = TrainingArcConfig.clampedRankLevel(newValue) }
    }

    var rankTitle: String {
        get { currentTierName }
        set { currentTierName = newValue }
    }

    var chargeValue: Int {
        get { storedCharges }
        set { storedCharges = DashboardChargeDots.clampedCharge(newValue) }
    }

    var acknowledgedRankLevel: Int {
        get { TrainingArcConfig.clampedRankLevel(lastAcknowledgedLevel) }
        set { lastAcknowledgedLevel = TrainingArcConfig.clampedRankLevel(newValue) }
    }

    var pendingRankChangeDirection: RankChangeDirection? {
        get { pendingRankChangeDirectionRaw.flatMap(RankChangeDirection.init(rawValue:)) }
        set { pendingRankChangeDirectionRaw = newValue?.rawValue }
    }

    var pendingRankChangeReason: RankChangeReason? {
        get { pendingRankChangeReasonRaw.flatMap(RankChangeReason.init(rawValue:)) }
        set { pendingRankChangeReasonRaw = newValue?.rawValue }
    }

    var pendingRankChange: PendingRankChange? {
        guard
            let direction = pendingRankChangeDirection,
            let statKey,
            let fromLevel = pendingRankChangeFromLevel,
            let toLevel = pendingRankChangeToLevel,
            let recordedAt = pendingRankChangeRecordedAt
        else {
            return nil
        }

        return PendingRankChange(
            direction: direction,
            fromLevel: TrainingArcConfig.clampedRankLevel(fromLevel),
            toLevel: TrainingArcConfig.clampedRankLevel(toLevel),
            fromTitle: TrainingArcConfig.rankTitle(for: statKey, level: fromLevel),
            toTitle: TrainingArcConfig.rankTitle(for: statKey, level: toLevel),
            recordedAt: recordedAt,
            reason: pendingRankChangeReason
        )
    }

    func setPendingRankChange(from fromLevel: Int, to toLevel: Int, direction: RankChangeDirection, reason: RankChangeReason, recordedAt: Date) {
        let isNewChange =
            pendingRankChangeRecordedAt != recordedAt ||
            pendingRankChangeFromLevel != TrainingArcConfig.clampedRankLevel(fromLevel) ||
            pendingRankChangeToLevel != TrainingArcConfig.clampedRankLevel(toLevel) ||
            pendingRankChangeDirection != direction

        pendingRankChangeFromLevel = TrainingArcConfig.clampedRankLevel(fromLevel)
        pendingRankChangeToLevel = TrainingArcConfig.clampedRankLevel(toLevel)
        pendingRankChangeDirection = direction
        pendingRankChangeReason = reason
        pendingRankChangeRecordedAt = recordedAt
        if isNewChange {
            pendingRankChangeViewedAt = nil
        }
    }

    func clearPendingRankChange() {
        pendingRankChangeFromLevel = nil
        pendingRankChangeToLevel = nil
        pendingRankChangeDirection = nil
        pendingRankChangeReason = nil
        pendingRankChangeRecordedAt = nil
        pendingRankChangeViewedAt = nil
    }
}

@Model
final class Habit {
    var id: UUID = UUID()
    var systemKey: String?
    var name: String = ""
    var notes: String = ""
    var measurementTypeRaw: String = MeasurementType.booleanSession.rawValue
    var unitLabel: String = ""
    var scheduleTypeRaw: String = ScheduleType.weekly.rawValue
    var targetPerPeriod: Double = 0
    var active: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    @Relationship(deleteRule: .nullify) var statDomain: StatDomain?
    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit) var logs: [HabitLog]? = []

    init(
        id: UUID = UUID(),
        systemKey: String? = nil,
        name: String,
        notes: String = "",
        measurementType: MeasurementType,
        unitLabel: String,
        scheduleType: ScheduleType,
        targetPerPeriod: Double,
        active: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        statDomain: StatDomain? = nil
    ) {
        self.id = id
        self.systemKey = systemKey
        self.name = name
        self.notes = notes
        self.measurementTypeRaw = measurementType.rawValue
        self.unitLabel = unitLabel
        self.scheduleTypeRaw = scheduleType.rawValue
        self.targetPerPeriod = targetPerPeriod
        self.active = active
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.statDomain = statDomain
    }

    var measurementType: MeasurementType {
        get { MeasurementType(rawValue: measurementTypeRaw) ?? .booleanSession }
        set { measurementTypeRaw = newValue.rawValue }
    }

    var scheduleType: ScheduleType {
        get { ScheduleType(rawValue: scheduleTypeRaw) ?? .weekly }
        set { scheduleTypeRaw = newValue.rawValue }
    }
}

@Model
final class HabitLog {
    var id: UUID = UUID()
    var date: Date = Date.now
    var numericValue: Double = 0
    var sessionType: String?
    var note: String = ""
    var sourceTypeRaw: String = LogSourceType.manual.rawValue
    var healthWorkoutUUID: String?
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify) var habit: Habit?

    init(
        id: UUID = UUID(),
        date: Date,
        numericValue: Double,
        sessionType: String? = nil,
        note: String = "",
        sourceType: LogSourceType = .manual,
        healthWorkoutUUID: String? = nil,
        createdAt: Date = .now,
        habit: Habit? = nil
    ) {
        self.id = id
        self.date = date
        self.numericValue = numericValue
        self.sessionType = sessionType
        self.note = note
        self.sourceTypeRaw = sourceType.rawValue
        self.healthWorkoutUUID = healthWorkoutUUID
        self.createdAt = createdAt
        self.habit = habit
    }

    var sourceType: LogSourceType {
        get { LogSourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }
}

@Model
final class WeeklyResolution {
    var id: UUID = UUID()
    var statKey: String = ""
    var statName: String = ""
    var weekStartDate: Date = Date.now
    var weekEndDate: Date = Date.now
    var baselineAtStart: Int = 0
    var expectedTotal: Double = 0
    var actualCompletedValue: Double = 0
    var weeklyDelta: Double = 0
    var excessValue: Double = 0
    var chargesEarned: Int = 0
    var chargesSpentOnLevelUp: Int = 0
    var bankedUnitsBefore: Double = 0
    var bankedUnitsAfter: Double = 0
    var levelBefore: Int = 1
    var levelAfter: Int = 1
    var storedChargesAfter: Int = 0
    var didDecay: Bool = false
    var didLevelUp: Bool = false
    var didStagnate: Bool = false
    var didRegress: Bool = false
    var summaryText: String = ""
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify) var statDomain: StatDomain?

    init(
        id: UUID = UUID(),
        statKey: String,
        statName: String,
        weekStartDate: Date,
        weekEndDate: Date,
        baselineAtStart: Int,
        expectedTotal: Double,
        actualCompletedValue: Double,
        weeklyDelta: Double,
        excessValue: Double,
        chargesEarned: Int,
        chargesSpentOnLevelUp: Int,
        bankedUnitsBefore: Double,
        bankedUnitsAfter: Double,
        levelBefore: Int,
        levelAfter: Int,
        storedChargesAfter: Int,
        didDecay: Bool,
        didLevelUp: Bool,
        didStagnate: Bool,
        didRegress: Bool,
        summaryText: String,
        createdAt: Date = .now,
        statDomain: StatDomain? = nil
    ) {
        self.id = id
        self.statKey = statKey
        self.statName = statName
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.baselineAtStart = baselineAtStart
        self.expectedTotal = expectedTotal
        self.actualCompletedValue = actualCompletedValue
        self.weeklyDelta = weeklyDelta
        self.excessValue = excessValue
        self.chargesEarned = chargesEarned
        self.chargesSpentOnLevelUp = chargesSpentOnLevelUp
        self.bankedUnitsBefore = bankedUnitsBefore
        self.bankedUnitsAfter = bankedUnitsAfter
        self.levelBefore = levelBefore
        self.levelAfter = levelAfter
        self.storedChargesAfter = storedChargesAfter
        self.didDecay = didDecay
        self.didLevelUp = didLevelUp
        self.didStagnate = didStagnate
        self.didRegress = didRegress
        self.summaryText = summaryText
        self.createdAt = createdAt
        self.statDomain = statDomain
    }
}

@Model
final class AppSettings {
    var id: String = "app-settings"
    var hasCompletedOnboarding: Bool = false
    var enableDecay: Bool = true
    var decaySensitivity: Double = 1.0
    var dailyReminderEnabled: Bool = false
    var eveningReminderEnabled: Bool = true
    var weeklyReviewReminderEnabled: Bool = true
    var weekStartsOnMonday: Bool = true
    var hapticsEnabled: Bool = true
    var lockInWeeklyReview: Bool = true
    var healthAutoImportEnabled: Bool = true
    var lastHealthSyncAt: Date?
    var themePreferenceRaw: String = "light"
    var dashboardLayoutModeRaw: String = DashboardLayoutMode.gameGrid.rawValue
    var disabledHealthWorkoutTypeKeysRaw: String = ""
    var progressionStrictnessRaw: String = ProgressionStrictness.balanced.rawValue
    var goalsCanAffectProgression: Bool = false
    var showPersonalMaxInUI: Bool = true
    var goalAtRiskReminderEnabled: Bool = false
    var regressionBehaviorRaw: String = RegressionBehavior.standard.rawValue
    var skillBehindPaceReminderEnabled: Bool = false
    var goalsAffectPacing: Bool = true
    var lastReadingBookTitle: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: String = "app-settings",
        hasCompletedOnboarding: Bool = false,
        enableDecay: Bool = true,
        decaySensitivity: Double = 1.0,
        dailyReminderEnabled: Bool = false,
        eveningReminderEnabled: Bool = true,
        weeklyReviewReminderEnabled: Bool = true,
        weekStartsOnMonday: Bool = true,
        hapticsEnabled: Bool = true,
        lockInWeeklyReview: Bool = true,
        healthAutoImportEnabled: Bool = true,
        lastHealthSyncAt: Date? = nil,
        dashboardLayoutMode: DashboardLayoutMode = .gameGrid,
        disabledHealthWorkoutTypeKeys: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.enableDecay = enableDecay
        self.decaySensitivity = decaySensitivity
        self.dailyReminderEnabled = dailyReminderEnabled
        self.eveningReminderEnabled = eveningReminderEnabled
        self.weeklyReviewReminderEnabled = weeklyReviewReminderEnabled
        self.weekStartsOnMonday = weekStartsOnMonday
        self.hapticsEnabled = hapticsEnabled
        self.lockInWeeklyReview = lockInWeeklyReview
        self.healthAutoImportEnabled = healthAutoImportEnabled
        self.lastHealthSyncAt = lastHealthSyncAt
        self.themePreferenceRaw = "light"
        self.dashboardLayoutModeRaw = dashboardLayoutMode.rawValue
        self.disabledHealthWorkoutTypeKeysRaw = AppSettings.encodeWorkoutTypeKeys(disabledHealthWorkoutTypeKeys)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var dashboardLayoutMode: DashboardLayoutMode {
        get { DashboardLayoutMode(rawValue: dashboardLayoutModeRaw) ?? .gameGrid }
        set { dashboardLayoutModeRaw = newValue.rawValue }
    }

    var progressionStrictness: ProgressionStrictness {
        get { ProgressionStrictness(rawValue: progressionStrictnessRaw) ?? .balanced }
        set {
            progressionStrictnessRaw = newValue.rawValue
            decaySensitivity = newValue.decaySensitivity
        }
    }

    var regressionBehavior: RegressionBehavior {
        get { RegressionBehavior(rawValue: regressionBehaviorRaw) ?? .standard }
        set { regressionBehaviorRaw = newValue.rawValue }
    }

    var disabledHealthWorkoutTypeKeys: Set<String> {
        get {
            Set(disabledHealthWorkoutTypeKeysRaw
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0) })
        }
        set { disabledHealthWorkoutTypeKeysRaw = AppSettings.encodeWorkoutTypeKeys(Array(newValue)) }
    }

    fileprivate static func encodeWorkoutTypeKeys(_ keys: [String]) -> String {
        keys.filter { !$0.isEmpty }.sorted().joined(separator: ",")
    }
}

@Model
final class HealthImportedWorkout {
    var workoutUUID: String = ""
    var statKeyRaw: String = ""
    var habitSystemKey: String?
    var sourceName: String?
    var sourceBundleIdentifier: String?
    var activityTypeRaw: Int = 0
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var durationMinutes: Double = 0
    var wasImported: Bool = true
    var isDuplicate: Bool = false
    var overlapsImportedWorkout: Bool = false
    var relatedWorkoutUUID: String?
    var awaitingHabitAssignment: Bool = false
    var createdAt: Date = Date.now

    init(
        workoutUUID: String,
        statKeyRaw: String,
        habitSystemKey: String?,
        sourceName: String? = nil,
        sourceBundleIdentifier: String?,
        activityTypeRaw: Int,
        startDate: Date,
        endDate: Date,
        durationMinutes: Double,
        wasImported: Bool = true,
        isDuplicate: Bool = false,
        overlapsImportedWorkout: Bool = false,
        relatedWorkoutUUID: String? = nil,
        awaitingHabitAssignment: Bool = false,
        createdAt: Date = .now
    ) {
        self.workoutUUID = workoutUUID
        self.statKeyRaw = statKeyRaw
        self.habitSystemKey = habitSystemKey
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.activityTypeRaw = activityTypeRaw
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = durationMinutes
        self.wasImported = wasImported
        self.isDuplicate = isDuplicate
        self.overlapsImportedWorkout = overlapsImportedWorkout
        self.relatedWorkoutUUID = relatedWorkoutUUID
        self.awaitingHabitAssignment = awaitingHabitAssignment
        self.createdAt = createdAt
    }
}

enum GoalScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case skill
    case overall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skill: "Skill"
        case .overall: "Overall"
        }
    }
}

enum GoalType: String, Codable, CaseIterable, Identifiable, Sendable {
    case weeklyTarget
    case monthlyTotal
    case consistency
    case reachLevel
    case reachRank
    case maintainBaseline
    case improveBalance
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weeklyTarget: "Weekly target"
        case .monthlyTotal: "Monthly total"
        case .consistency: "Consistency"
        case .reachLevel: "Reach level"
        case .reachRank: "Reach rank"
        case .maintainBaseline: "Maintain baseline"
        case .improveBalance: "Improve balance"
        case .custom: "Custom"
        }
    }
}

enum GoalStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case completed
    case paused
    case failed
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: "Active"
        case .completed: "Completed"
        case .paused: "Paused"
        case .failed: "Failed"
        case .archived: "Archived"
        }
    }
}

enum GoalPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

@Model
final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var goalScopeRaw: String = GoalScope.skill.rawValue
    var linkedStatKeyRaw: String?
    var linkedHabitIDRaw: String?
    var goalTypeRaw: String = GoalType.weeklyTarget.rawValue
    var measurementTypeRaw: String = MeasurementType.count.rawValue
    var targetValue: Double = 0
    var startDate: Date = Date.now
    var endDate: Date?
    var statusRaw: String = GoalStatus.active.rawValue
    var priorityRaw: String = GoalPriority.normal.rawValue
    var affectsMetrics: Bool = false
    var affectsProgression: Bool = false
    var isRecoveryMode: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        scope: GoalScope = .skill,
        linkedStatKey: StatKey? = nil,
        linkedHabitID: UUID? = nil,
        type: GoalType = .weeklyTarget,
        measurementType: MeasurementType = .count,
        targetValue: Double = 0,
        startDate: Date = .now,
        endDate: Date? = nil,
        status: GoalStatus = .active,
        priority: GoalPriority = .normal,
        affectsMetrics: Bool = false,
        affectsProgression: Bool = false,
        isRecoveryMode: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.goalScopeRaw = scope.rawValue
        self.linkedStatKeyRaw = linkedStatKey?.rawValue
        self.linkedHabitIDRaw = linkedHabitID?.uuidString
        self.goalTypeRaw = type.rawValue
        self.measurementTypeRaw = measurementType.rawValue
        self.targetValue = targetValue
        self.startDate = startDate
        self.endDate = endDate
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.affectsMetrics = affectsMetrics
        self.affectsProgression = affectsProgression
        self.isRecoveryMode = isRecoveryMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    var scope: GoalScope {
        get { GoalScope(rawValue: goalScopeRaw) ?? .skill }
        set { goalScopeRaw = newValue.rawValue }
    }

    var type: GoalType {
        get { GoalType(rawValue: goalTypeRaw) ?? .weeklyTarget }
        set { goalTypeRaw = newValue.rawValue }
    }

    var measurementType: MeasurementType {
        get { MeasurementType(rawValue: measurementTypeRaw) ?? .count }
        set { measurementTypeRaw = newValue.rawValue }
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var priority: GoalPriority {
        get { GoalPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var linkedStatKey: StatKey? {
        get { linkedStatKeyRaw.flatMap(StatKey.init(rawValue:)) }
        set { linkedStatKeyRaw = newValue?.rawValue }
    }

    var linkedHabitID: UUID? {
        get { linkedHabitIDRaw.flatMap(UUID.init(uuidString:)) }
        set { linkedHabitIDRaw = newValue?.uuidString }
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? autoDerivedTitle : trimmed
    }

    var autoDerivedTitle: String {
        Goal.autoDerivedTitle(
            type: type,
            measurementType: measurementType,
            targetValue: targetValue,
            linkedStatKey: linkedStatKey
        )
    }

    static func autoDerivedTitle(
        type: GoalType,
        measurementType: MeasurementType,
        targetValue: Double,
        linkedStatKey: StatKey?
    ) -> String {
        let prefix = linkedStatKey?.displayName
        let target = formatTarget(targetValue, measurementType: measurementType)
        let unit = measurementType.defaultUnitLabel
        let suffix: String

        switch type {
        case .weeklyTarget:
            suffix = "\(target) \(unit) this week"
        case .monthlyTotal:
            suffix = "\(target) \(unit) this month"
        case .consistency:
            suffix = "Consistency \(target) \(unit)"
        case .reachLevel:
            suffix = "Reach level \(target)"
        case .reachRank:
            suffix = "Reach rank \(target)"
        case .maintainBaseline:
            suffix = "Maintain baseline"
        case .improveBalance:
            suffix = "Improve balance"
        case .custom:
            suffix = "Custom goal"
        }

        if let prefix {
            return "\(prefix): \(suffix)"
        }
        return suffix
    }

    private static func formatTarget(_ value: Double, measurementType: MeasurementType) -> String {
        if measurementType.prefersIntegerValue, value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

struct LogEntryDraft: Identifiable {
    let id = UUID()
    var habit: Habit
    var value: Double
    var date: Date
    var sessionType: String
    var note: String
    var sourceType: LogSourceType

    init(
        habit: Habit,
        value: Double? = nil,
        date: Date = .now,
        sessionType: String = "",
        note: String = "",
        sourceType: LogSourceType = .manual
    ) {
        self.habit = habit
        self.value = value ?? habit.measurementType.defaultIncrement
        self.date = date
        self.sessionType = sessionType
        self.note = note
        self.sourceType = sourceType
    }
}

struct HabitStreakSummary: Sendable {
    var current: Int
    var longest: Int
    var lastLoggedDate: Date?
}

struct WeeklyReviewBatch: Identifiable, Sendable {
    var id: Date { week.start }
    var week: WeekRange
    var resolutions: [WeeklyResolution]
}

struct StatProgressSnapshot: Identifiable, Sendable {
    var id: UUID
    var stat: StatDomain
    var currentWeekActual: Double
    var progressToNextLevel: Double
    var recentTrend: Double
    var weeklyStreak: HabitStreakSummary
}

struct MomentumStatus: Sendable {
    var title: String
    var subtitle: String
    var score: Double
}

enum SkillEngagementState: String, Sendable {
    case neutral
    case nearCharge
    case aheadOfTarget
    case behindTarget
    case pendingRankChange
}

enum SkillPacingStatus: String, Sendable {
    case behind
    case onPace
    case ahead

    var label: String {
        switch self {
        case .behind:
            return "Behind Pace"
        case .onPace:
            return "On Pace"
        case .ahead:
            return "Ahead of Pace"
        }
    }
}

struct ChargeSnapshot: Sendable {
    var current: Int
    var maximum: Int
    var progress: Double
    var label: String
}

struct SkillLogEntrySnapshot: Identifiable, Sendable {
    var id: UUID
    var habitName: String
    var valueLabel: String
    var date: Date
    var note: String
    var sessionType: String?
    var sourceType: LogSourceType = .manual
    var healthAttribution: HealthLogAttribution?
}

/// Per-log transparency for entries imported from Apple Health. Lets the UI
/// honestly show where a log came from, which skill/goal it touched, and whether
/// it actually counted toward weekly progress.
struct HealthLogAttribution: Sendable, Equatable {
    /// Name of the originating app/device (e.g. "Apple Watch", "Strava"). Nil when unknown.
    var sourceAppName: String?
    /// Display name of the skill this workout was mapped to.
    var mappedSkillName: String
    /// Color token for the mapped skill, for tinting the badge.
    var mappedSkillColorToken: String
    /// The session type recorded on the log (e.g. "Cardio").
    var sessionType: String?
    /// Recorded workout duration in minutes (0 when unknown).
    var durationMinutes: Double
    /// True when this log counted toward the week's progress total.
    var countedTowardWeeklyProgress: Bool
    /// True when Apple Health flagged this as a duplicate and it was ignored.
    var ignoredAsDuplicate: Bool
    /// True when this workout overlaps another imported workout in time.
    var needsReview: Bool
    /// True when this log contributes to at least one active goal's progress.
    var affectedGoal: Bool

    var sourceDisplayName: String {
        if let sourceAppName, !sourceAppName.isEmpty {
            return "Apple Health · \(sourceAppName)"
        }
        return "Apple Health"
    }
}

struct DayLogSummary: Identifiable, Sendable {
    var id: Date { date }
    var date: Date
    var totalValue: Double
    var logCount: Int
    var totalLabel: String
    var isToday: Bool
}

struct SkillWeekSnapshot: Identifiable, Sendable {
    var id: Date { week.start }
    var week: WeekRange
    var daySummaries: [DayLogSummary]
    var totalValue: Double
    var totalLabel: String
    var logEntries: [SkillLogEntrySnapshot]
}

struct PendingRankChange: Sendable, Equatable {
    var direction: RankChangeDirection
    var fromLevel: Int
    var toLevel: Int
    var fromTitle: String
    var toTitle: String
    var recordedAt: Date
    var reason: RankChangeReason?
}

struct RankSnapshot: Sendable {
    var level: Int
    var maximumLevel: Int
    var title: String
    var nextTitle: String?
    var progressValue: Double
    var progressValueLabel: String
    var progressRequiredLabel: String
    var progressToNextLevel: Double
    var isAtMaximumRank: Bool
    var image: RankImageReference?
}

struct SkillProgressSnapshot: Sendable {
    var rank: RankSnapshot
    var charge: ChargeSnapshot
    var overview: String
    var currentWeekActual: Double
    var baseline: Int
    var bankedProgressUnits: Double
    var nextEvaluationDate: Date
    var pendingRankChange: PendingRankChange?
    var rankChangeIndicatorVisible: Bool
    var weeklyTargetProgress: Double
    var weeklyCounterLabel: String
    var weeklyCounterValueLabel: String
    var chargeExplanation: String
    var nextEvaluationLabel: String
    var nextRankImage: RankImageReference?
    var bankedChargeLabel: String
    var nextRankStatusLabel: String
    var focusState: SkillEngagementState
    var nextActionLabel: String
    var pacingStatus: SkillPacingStatus
    var bankCountdownLabel: String
}

extension SkillProgressSnapshot {
    var weeklyTargetFractionLabel: String {
        "\(MetricFormatting.shortMetric(currentWeekActual))/\(MetricFormatting.shortMetric(Double(baseline)))"
    }
}

struct DashboardCardPreview: Sendable {
    var rankSummary: String
    var bankedChargeSummary: String
    var stayOnTargetSummary: String
    var weeklyTargetSummary: String
    var levelUpSummary: String
}

enum DashboardInsightOption: String, CaseIterable, Identifiable, Sendable {
    case whatToWorkOn
    case whatImproved
    case standardDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whatToWorkOn:
            return "What To Work On"
        case .whatImproved:
            return "What Improved"
        case .standardDay:
            return "Standard Day"
        }
    }

    var systemImage: String {
        switch self {
        case .whatToWorkOn:
            return "target"
        case .whatImproved:
            return "chart.line.uptrend.xyaxis"
        case .standardDay:
            return "sun.max"
        }
    }
}

enum GoalPaceStatus: String, Sendable {
    case onPace
    case ahead
    case atRisk
    case behind
    case complete

    var label: String {
        switch self {
        case .onPace: "On pace"
        case .ahead: "Ahead"
        case .atRisk: "At risk"
        case .behind: "Behind"
        case .complete: "Complete"
        }
    }
}

enum TrainTodayReason: String, Sendable {
    case behindBaseline
    case noLogsThisWeek
    case lowCharge
    case goalAtRisk
    case reviewReady
    case nearRankUp
    case staleSkill
}

struct TrainTodayRecommendation: Identifiable, Sendable {
    var id: String
    var statKeyRaw: String?
    var statName: String
    var colorToken: String
    var iconName: String
    var headline: String
    var detail: String
    var reason: TrainTodayReason
    var priority: Int
    var hasReviewReady: Bool
}

struct GoalProgressSnapshot: Identifiable, Sendable {
    var id: UUID
    var goal: Goal
    var currentValue: Double
    var targetValue: Double
    var progressRatio: Double
    var remainingValue: Double
    var paceStatus: GoalPaceStatus
    var timeRemainingLabel: String
    var statusLabel: String
}

/// Aggregated dashboard sections (Phase 7): an at-a-glance read on the week,
/// rank/charge movement, and goal health. Pure value types so they can be built
/// once and handed to the view.
struct DashboardSections: Sendable {
    var weeklyStatus: DashboardWeeklyStatus
    var highlights: [DashboardHighlight]
    var goals: DashboardGoalsSummary
}

struct DashboardWeeklyStatus: Sendable {
    enum Kind: String, Sendable {
        case reviewReady
        case ahead
        case onPace
        case atRisk
        case noActivity
    }

    var kind: Kind
    var aheadCount: Int
    var onPaceCount: Int
    var behindCount: Int
    var headline: String
    var detail: String
}

struct DashboardHighlight: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case rankedUp
        case nearRankUp
        case losingMomentum

        /// Lower sorts first (most positive/urgent surfaced at the top).
        var order: Int {
            switch self {
            case .rankedUp: 0
            case .nearRankUp: 1
            case .losingMomentum: 2
            }
        }
    }

    var id: String
    var statKeyRaw: String?
    var statName: String
    var colorToken: String
    var kind: Kind
    var text: String
}

struct DashboardGoalsSummary: Sendable {
    var activeCount: Int
    var atRiskCount: Int
    var completedThisWeekCount: Int
    var closeToCompletionCount: Int
    var totalCount: Int

    var hasAnyGoals: Bool { totalCount > 0 }
}

/// Aggregate recap of a single resolved week (Phase 8): what moved, what slipped,
/// and how goals fared. Built from that week's WeeklyResolutions plus current goals.
struct WeeklyRecap: Sendable {
    var bestSkillName: String?
    var bestSkillDetail: String?
    var neglectedSkillName: String?
    var neglectedSkillDetail: String?
    var gainedChargeSkills: [String]
    var lostChargeSkills: [String]
    var goalsCompleted: [String]
    var goalsProgressedCount: Int
    var goalsAtRiskCount: Int

    var hasContent: Bool {
        bestSkillName != nil
            || neglectedSkillName != nil
            || !gainedChargeSkills.isEmpty
            || !lostChargeSkills.isEmpty
            || !goalsCompleted.isEmpty
            || goalsProgressedCount > 0
            || goalsAtRiskCount > 0
    }
}

struct WorkFocusAnalysis: Sendable {
    var headline: String
    var focusSkillName: String
    var recommendations: [String]
}

struct MonthlyImprovementAnalysis: Sendable {
    var headline: String
    var summary: String
    var improvedSkills: [String]
}

struct StandardDayAnalysis: Sendable {
    var headline: String
    var rhythmSummary: String
    var suggestions: [String]
}

nonisolated struct TrainingExportBundle: Codable, Sendable {
    var exportedAt: Date
    var stats: [StatExport]
    var habits: [HabitExport]
    var logs: [HabitLogExport]
    var resolutions: [WeeklyResolutionExport]
    var settings: SettingsExport
    var goals: [GoalExport]?

    enum CodingKeys: String, CodingKey {
        case exportedAt, stats, habits, logs, resolutions, settings, goals
    }

    init(
        exportedAt: Date,
        stats: [StatExport],
        habits: [HabitExport],
        logs: [HabitLogExport],
        resolutions: [WeeklyResolutionExport],
        settings: SettingsExport,
        goals: [GoalExport]? = nil
    ) {
        self.exportedAt = exportedAt
        self.stats = stats
        self.habits = habits
        self.logs = logs
        self.resolutions = resolutions
        self.settings = settings
        self.goals = goals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        stats = try container.decode([StatExport].self, forKey: .stats)
        habits = try container.decode([HabitExport].self, forKey: .habits)
        logs = try container.decode([HabitLogExport].self, forKey: .logs)
        resolutions = try container.decode([WeeklyResolutionExport].self, forKey: .resolutions)
        settings = try container.decode(SettingsExport.self, forKey: .settings)
        goals = try container.decodeIfPresent([GoalExport].self, forKey: .goals)
    }

    static let empty = TrainingExportBundle(
        exportedAt: .now,
        stats: [],
        habits: [],
        logs: [],
        resolutions: [],
        settings: SettingsExport(
            hasCompletedOnboarding: false,
            enableDecay: true,
            decaySensitivity: 1,
            dailyReminderEnabled: false,
            eveningReminderEnabled: true,
            weeklyReviewReminderEnabled: true,
            weekStartsOnMonday: true,
            hapticsEnabled: true,
            lockInWeeklyReview: true,
            healthAutoImportEnabled: true,
            lastHealthSyncAt: nil,
            themePreferenceRaw: "light",
            dashboardLayoutModeRaw: DashboardLayoutMode.gameGrid.rawValue,
            disabledHealthWorkoutTypeKeysRaw: ""
        )
    )
}

enum SampleProfile: String, CaseIterable, Identifiable, Sendable {
    case newUser
    case streaking
    case stagnating
    case levelUpWeek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newUser: "New User"
        case .streaking: "Streaking"
        case .stagnating: "Stagnating"
        case .levelUpWeek: "Level-Up Week"
        }
    }
}

nonisolated struct StatExport: Codable, Sendable {
    var id: UUID
    var key: String
    var name: String
    var iconName: String
    var colorToken: String
    var descriptor: String
    var sortOrder: Int
    var currentLevel: Int
    var currentTierName: String
    var startingBaseline: Int
    var currentBaseline: Int
    var targetValue: Int?
    var personalMaxValue: Int?
    var maintenanceFloor: Int?
    var storedCharges: Int
    var bankedProgressUnits: Double
    var lastResolvedWeekStart: Date?
    var lastAcknowledgedLevel: Int
    var pendingRankChangeDirectionRaw: String?
    var pendingRankChangeFromLevel: Int?
    var pendingRankChangeToLevel: Int?
    var pendingRankChangeRecordedAt: Date?
    var pendingRankChangeReasonRaw: String?
    var pendingRankChangeViewedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var isCore: Bool?
    var isEnabled: Bool?
    var isCustom: Bool?
    var parentSkillKeyRaw: String?

    enum CodingKeys: String, CodingKey {
        case id, key, name, iconName, colorToken, descriptor, sortOrder,
             currentLevel, currentTierName, startingBaseline, currentBaseline,
             targetValue, personalMaxValue, maintenanceFloor,
             storedCharges, bankedProgressUnits, lastResolvedWeekStart, lastAcknowledgedLevel,
             pendingRankChangeDirectionRaw, pendingRankChangeFromLevel, pendingRankChangeToLevel,
             pendingRankChangeRecordedAt, pendingRankChangeReasonRaw, pendingRankChangeViewedAt,
             createdAt, updatedAt, isArchived,
             isCore, isEnabled, isCustom, parentSkillKeyRaw
    }

    init(
        id: UUID,
        key: String,
        name: String,
        iconName: String,
        colorToken: String,
        descriptor: String,
        sortOrder: Int,
        currentLevel: Int,
        currentTierName: String,
        startingBaseline: Int,
        currentBaseline: Int,
        targetValue: Int? = nil,
        personalMaxValue: Int? = nil,
        maintenanceFloor: Int? = nil,
        storedCharges: Int,
        bankedProgressUnits: Double,
        lastResolvedWeekStart: Date?,
        lastAcknowledgedLevel: Int,
        pendingRankChangeDirectionRaw: String?,
        pendingRankChangeFromLevel: Int?,
        pendingRankChangeToLevel: Int?,
        pendingRankChangeRecordedAt: Date?,
        pendingRankChangeReasonRaw: String?,
        pendingRankChangeViewedAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        isArchived: Bool,
        isCore: Bool? = nil,
        isEnabled: Bool? = nil,
        isCustom: Bool? = nil,
        parentSkillKeyRaw: String? = nil
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.iconName = iconName
        self.colorToken = colorToken
        self.descriptor = descriptor
        self.sortOrder = sortOrder
        self.currentLevel = currentLevel
        self.currentTierName = currentTierName
        self.startingBaseline = startingBaseline
        self.currentBaseline = currentBaseline
        self.targetValue = targetValue
        self.personalMaxValue = personalMaxValue
        self.maintenanceFloor = maintenanceFloor
        self.storedCharges = storedCharges
        self.bankedProgressUnits = bankedProgressUnits
        self.lastResolvedWeekStart = lastResolvedWeekStart
        self.lastAcknowledgedLevel = lastAcknowledgedLevel
        self.pendingRankChangeDirectionRaw = pendingRankChangeDirectionRaw
        self.pendingRankChangeFromLevel = pendingRankChangeFromLevel
        self.pendingRankChangeToLevel = pendingRankChangeToLevel
        self.pendingRankChangeRecordedAt = pendingRankChangeRecordedAt
        self.pendingRankChangeReasonRaw = pendingRankChangeReasonRaw
        self.pendingRankChangeViewedAt = pendingRankChangeViewedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.isCore = isCore
        self.isEnabled = isEnabled
        self.isCustom = isCustom
        self.parentSkillKeyRaw = parentSkillKeyRaw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        iconName = try c.decode(String.self, forKey: .iconName)
        colorToken = try c.decode(String.self, forKey: .colorToken)
        descriptor = try c.decode(String.self, forKey: .descriptor)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        currentLevel = try c.decode(Int.self, forKey: .currentLevel)
        currentTierName = try c.decode(String.self, forKey: .currentTierName)
        startingBaseline = try c.decode(Int.self, forKey: .startingBaseline)
        currentBaseline = try c.decode(Int.self, forKey: .currentBaseline)
        targetValue = try c.decodeIfPresent(Int.self, forKey: .targetValue)
        personalMaxValue = try c.decodeIfPresent(Int.self, forKey: .personalMaxValue)
        maintenanceFloor = try c.decodeIfPresent(Int.self, forKey: .maintenanceFloor)
        storedCharges = try c.decode(Int.self, forKey: .storedCharges)
        bankedProgressUnits = try c.decode(Double.self, forKey: .bankedProgressUnits)
        lastResolvedWeekStart = try c.decodeIfPresent(Date.self, forKey: .lastResolvedWeekStart)
        lastAcknowledgedLevel = try c.decode(Int.self, forKey: .lastAcknowledgedLevel)
        pendingRankChangeDirectionRaw = try c.decodeIfPresent(String.self, forKey: .pendingRankChangeDirectionRaw)
        pendingRankChangeFromLevel = try c.decodeIfPresent(Int.self, forKey: .pendingRankChangeFromLevel)
        pendingRankChangeToLevel = try c.decodeIfPresent(Int.self, forKey: .pendingRankChangeToLevel)
        pendingRankChangeRecordedAt = try c.decodeIfPresent(Date.self, forKey: .pendingRankChangeRecordedAt)
        pendingRankChangeReasonRaw = try c.decodeIfPresent(String.self, forKey: .pendingRankChangeReasonRaw)
        pendingRankChangeViewedAt = try c.decodeIfPresent(Date.self, forKey: .pendingRankChangeViewedAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isArchived = try c.decode(Bool.self, forKey: .isArchived)
        isCore = try c.decodeIfPresent(Bool.self, forKey: .isCore)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled)
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom)
        parentSkillKeyRaw = try c.decodeIfPresent(String.self, forKey: .parentSkillKeyRaw)
    }
}

nonisolated struct GoalExport: Codable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var goalScopeRaw: String
    var linkedStatKeyRaw: String?
    var linkedHabitIDRaw: String?
    var goalTypeRaw: String
    var measurementTypeRaw: String
    var targetValue: Double
    var startDate: Date
    var endDate: Date?
    var statusRaw: String
    var priorityRaw: String
    var affectsMetrics: Bool
    var affectsProgression: Bool
    var isRecoveryMode: Bool?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
}

nonisolated struct HabitExport: Codable, Sendable {
    var id: UUID
    var systemKey: String?
    var name: String
    var notes: String
    var measurementTypeRaw: String
    var unitLabel: String
    var scheduleTypeRaw: String
    var targetPerPeriod: Double
    var active: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var statID: UUID?
}

nonisolated struct HabitLogExport: Codable, Sendable {
    var id: UUID
    var habitID: UUID?
    var date: Date
    var numericValue: Double
    var sessionType: String?
    var note: String
    var sourceTypeRaw: String
    var healthWorkoutUUID: String?
    var createdAt: Date
}

nonisolated struct WeeklyResolutionExport: Codable, Sendable {
    var id: UUID
    var statID: UUID?
    var statKey: String
    var statName: String
    var weekStartDate: Date
    var weekEndDate: Date
    var baselineAtStart: Int
    var expectedTotal: Double
    var actualCompletedValue: Double
    var weeklyDelta: Double
    var excessValue: Double
    var chargesEarned: Int
    var chargesSpentOnLevelUp: Int
    var bankedUnitsBefore: Double
    var bankedUnitsAfter: Double
    var levelBefore: Int
    var levelAfter: Int
    var storedChargesAfter: Int
    var didDecay: Bool
    var didLevelUp: Bool
    var didStagnate: Bool
    var didRegress: Bool
    var summaryText: String
    var createdAt: Date
}

nonisolated struct SettingsExport: Codable, Sendable {
    var hasCompletedOnboarding: Bool
    var enableDecay: Bool
    var decaySensitivity: Double
    var dailyReminderEnabled: Bool
    var eveningReminderEnabled: Bool
    var weeklyReviewReminderEnabled: Bool
    var weekStartsOnMonday: Bool
    var hapticsEnabled: Bool
    var lockInWeeklyReview: Bool
    var healthAutoImportEnabled: Bool?
    var lastHealthSyncAt: Date?
    var themePreferenceRaw: String
    var dashboardLayoutModeRaw: String
    var disabledHealthWorkoutTypeKeysRaw: String?
    var progressionStrictnessRaw: String? = nil
    var goalsCanAffectProgression: Bool? = nil
    var showPersonalMaxInUI: Bool? = nil
    var goalAtRiskReminderEnabled: Bool? = nil
    var regressionBehaviorRaw: String? = nil
    var skillBehindPaceReminderEnabled: Bool? = nil
    var goalsAffectPacing: Bool? = nil
}
