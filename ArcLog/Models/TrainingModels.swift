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
    case integration
    case debug

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .shortcut: "Shortcut"
        case .widget: "Widget"
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

@Model
final class StatDomain {
    @Attribute(.unique) var id: UUID
    var key: String
    var name: String
    var iconName: String
    var colorToken: String
    var descriptor: String
    var currentLevel: Int
    var currentTierName: String
    var currentBaseline: Int
    var storedCharges: Int
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
        currentLevel: Int = 1,
        currentTierName: String,
        currentBaseline: Int,
        storedCharges: Int = 0,
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
        self.currentLevel = currentLevel
        self.currentTierName = currentTierName
        self.currentBaseline = currentBaseline
        self.storedCharges = storedCharges
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

    var rankProgress: Int {
        get { storedCharges }
        set { storedCharges = max(0, newValue) }
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
    var note: String
    var sourceTypeRaw: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify) var habit: Habit?

    init(
        id: UUID = UUID(),
        date: Date,
        numericValue: Double,
        note: String = "",
        sourceType: LogSourceType = .manual,
        createdAt: Date = .now,
        habit: Habit? = nil
    ) {
        self.id = id
        self.date = date
        self.numericValue = numericValue
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
    var actualCompletedValue: Double
    var excessValue: Double
    var chargesEarned: Int
    var chargesSpentOnLevelUp: Int
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
        actualCompletedValue: Double,
        excessValue: Double,
        chargesEarned: Int,
        chargesSpentOnLevelUp: Int,
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
        self.actualCompletedValue = actualCompletedValue
        self.excessValue = excessValue
        self.chargesEarned = chargesEarned
        self.chargesSpentOnLevelUp = chargesSpentOnLevelUp
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
    var themePreferenceRaw: String
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
        themePreference: ThemePreference = .light,
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
        self.themePreferenceRaw = themePreference.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .dark }
        set { themePreferenceRaw = newValue.rawValue }
    }
}

struct HabitLogDraft: Sendable {
    var value: Double
    var date: Date
    var note: String
    var sourceType: LogSourceType

    static let `default` = HabitLogDraft(value: 1, date: .now, note: "", sourceType: .manual)
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

struct ChargeSnapshot: Sendable {
    var current: Int
    var maximum: Int
    var progress: Double
    var label: String
}

struct RankSnapshot: Sendable {
    var level: Int
    var maximumLevel: Int
    var title: String
    var nextTitle: String?
    var progressUnits: Int
    var progressRequired: Int
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
    var earnedRankProgressThisWeek: Int
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
            themePreferenceRaw: ThemePreference.dark.rawValue
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
    var currentLevel: Int
    var currentTierName: String
    var currentBaseline: Int
    var storedCharges: Int
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
    var actualCompletedValue: Double
    var excessValue: Double
    var chargesEarned: Int
    var chargesSpentOnLevelUp: Int
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
    var themePreferenceRaw: String
}
