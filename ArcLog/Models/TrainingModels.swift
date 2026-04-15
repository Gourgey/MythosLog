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
            [5, 10, 25]
        case .minutes:
            [5, 10, 20]
        case .customNumber:
            [1, 3, 5]
        }
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

enum ThemePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
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
    @Attribute(.unique) var id: UUID
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
    var storedCharges: Int
    var bankedProgressUnits: Double
    var lastResolvedWeekStart: Date?
    var lastAcknowledgedLevel: Int
    var pendingRankChangeDirectionRaw: String?
    var pendingRankChangeFromLevel: Int?
    var pendingRankChangeToLevel: Int?
    var pendingRankChangeRecordedAt: Date?
    var pendingRankChangeReasonRaw: String?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    @Relationship(deleteRule: .cascade, inverse: \Habit.statDomain) var habits: [Habit] = []
    @Relationship(deleteRule: .cascade, inverse: \WeeklyResolution.statDomain) var weeklyResolutions: [WeeklyResolution] = []

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
        storedCharges: Int = 0,
        bankedProgressUnits: Double = 0,
        lastResolvedWeekStart: Date? = nil,
        lastAcknowledgedLevel: Int = 1,
        pendingRankChangeDirectionRaw: String? = nil,
        pendingRankChangeFromLevel: Int? = nil,
        pendingRankChangeToLevel: Int? = nil,
        pendingRankChangeRecordedAt: Date? = nil,
        pendingRankChangeReasonRaw: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isArchived: Bool = false
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
        self.storedCharges = storedCharges
        self.bankedProgressUnits = bankedProgressUnits
        self.lastResolvedWeekStart = lastResolvedWeekStart
        self.lastAcknowledgedLevel = lastAcknowledgedLevel
        self.pendingRankChangeDirectionRaw = pendingRankChangeDirectionRaw
        self.pendingRankChangeFromLevel = pendingRankChangeFromLevel
        self.pendingRankChangeToLevel = pendingRankChangeToLevel
        self.pendingRankChangeRecordedAt = pendingRankChangeRecordedAt
        self.pendingRankChangeReasonRaw = pendingRankChangeReasonRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    var statKey: StatKey? {
        StatKey(rawValue: key)
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
        pendingRankChangeFromLevel = TrainingArcConfig.clampedRankLevel(fromLevel)
        pendingRankChangeToLevel = TrainingArcConfig.clampedRankLevel(toLevel)
        pendingRankChangeDirection = direction
        pendingRankChangeReason = reason
        pendingRankChangeRecordedAt = recordedAt
    }

    func clearPendingRankChange() {
        pendingRankChangeFromLevel = nil
        pendingRankChangeToLevel = nil
        pendingRankChangeDirection = nil
        pendingRankChangeReason = nil
        pendingRankChangeRecordedAt = nil
    }
}

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
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
    @Relationship(deleteRule: .nullify) var statDomain: StatDomain?
    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit) var logs: [HabitLog] = []

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
    @Attribute(.unique) var id: UUID
    var date: Date
    var numericValue: Double
    var sessionType: String?
    var note: String
    var sourceTypeRaw: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify) var habit: Habit?

    init(
        id: UUID = UUID(),
        date: Date,
        numericValue: Double,
        sessionType: String? = nil,
        note: String = "",
        sourceType: LogSourceType = .manual,
        createdAt: Date = .now,
        habit: Habit? = nil
    ) {
        self.id = id
        self.date = date
        self.numericValue = numericValue
        self.sessionType = sessionType
        self.note = note
        self.sourceTypeRaw = sourceType.rawValue
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
    @Attribute(.unique) var id: UUID
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
    @Attribute(.unique) var id: String
    var hasCompletedOnboarding: Bool
    var enableDecay: Bool
    var decaySensitivity: Double
    var dailyReminderEnabled: Bool
    var eveningReminderEnabled: Bool
    var weeklyReviewReminderEnabled: Bool
    var weekStartsOnMonday: Bool
    var hapticsEnabled: Bool
    var lockInWeeklyReview: Bool
    var healthAutoImportEnabled: Bool
    var lastHealthSyncAt: Date?
    var themePreferenceRaw: String
    var dashboardLayoutModeRaw: String
    var createdAt: Date
    var updatedAt: Date

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
        themePreference: ThemePreference = .light,
        dashboardLayoutMode: DashboardLayoutMode = .compactGrid,
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
        self.themePreferenceRaw = themePreference.rawValue
        self.dashboardLayoutModeRaw = dashboardLayoutMode.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .dark }
        set { themePreferenceRaw = newValue.rawValue }
    }

    var dashboardLayoutMode: DashboardLayoutMode {
        get { DashboardLayoutMode(rawValue: dashboardLayoutModeRaw) ?? .compactGrid }
        set { dashboardLayoutModeRaw = newValue.rawValue }
    }
}

@Model
final class HealthImportedWorkout {
    @Attribute(.unique) var workoutUUID: String
    var statKeyRaw: String
    var habitSystemKey: String?
    var sourceBundleIdentifier: String?
    var activityTypeRaw: Int
    var startDate: Date
    var endDate: Date
    var durationMinutes: Double
    var createdAt: Date

    init(
        workoutUUID: String,
        statKeyRaw: String,
        habitSystemKey: String?,
        sourceBundleIdentifier: String?,
        activityTypeRaw: Int,
        startDate: Date,
        endDate: Date,
        durationMinutes: Double,
        createdAt: Date = .now
    ) {
        self.workoutUUID = workoutUUID
        self.statKeyRaw = statKeyRaw
        self.habitSystemKey = habitSystemKey
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.activityTypeRaw = activityTypeRaw
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = durationMinutes
        self.createdAt = createdAt
    }
}

struct LogEntryDraft: Identifiable {
    let id = UUID()
    let habit: Habit
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
            themePreferenceRaw: ThemePreference.dark.rawValue,
            dashboardLayoutModeRaw: DashboardLayoutMode.compactGrid.rawValue
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
    var storedCharges: Int
    var bankedProgressUnits: Double
    var lastResolvedWeekStart: Date?
    var lastAcknowledgedLevel: Int
    var pendingRankChangeDirectionRaw: String?
    var pendingRankChangeFromLevel: Int?
    var pendingRankChangeToLevel: Int?
    var pendingRankChangeRecordedAt: Date?
    var pendingRankChangeReasonRaw: String?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
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
}
