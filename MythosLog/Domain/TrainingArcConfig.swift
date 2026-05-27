import Foundation
import SwiftUI

enum RankImageReference: Hashable, Sendable {
    case asset(name: String)
}

struct ChargeConfiguration: Sendable {
    let maximumValue: Int
    let label: String
}

struct BaselineOnboardingConfiguration: Sendable {
    let question: String
    let valueLabelSingular: String
    let valueLabelPlural: String
    let minimumValue: Int
    let maximumValue: Int
    let quickAdjustments: [Int]
    let manualEntryLabel: String
}

struct RankProgressionConfiguration: Sendable {
    let rollingWindowWeeks: Int
    let levelThresholds: [Int]
}

struct RankLevelDefinition: Identifiable, Sendable {
    let level: Int
    let title: String
    let image: RankImageReference?
    let description: String?

    var id: Int { level }
}

struct CharacterRosterEntry: Identifiable, Sendable {
    let level: Int
    let title: String
    let image: RankImageReference?
    let isLocked: Bool

    var id: Int { level }
}

struct StatTemplate: Identifiable, Sendable {
    let key: StatKey
    let iconName: String
    let colorToken: String
    let defaultBaseline: Int
    let isCore: Bool
    let parentKey: StatKey?

    var id: StatKey { key }
}

struct HabitTemplate: Identifiable, Sendable {
    let id: String
    let systemKey: String
    let name: String
    let statKey: StatKey
    let measurementType: MeasurementType
    let scheduleType: ScheduleType
    let unitLabel: String
    let targetPerPeriod: Double
    let notes: String
}

struct HabitProgressionDefinition: Identifiable, Sendable {
    let key: StatKey
    let displayName: String
    let iconName: String
    let colorToken: String
    let overview: String
    let defaultBaseline: Int
    let starterHabit: HabitTemplate
    let charge: ChargeConfiguration
    let onboarding: BaselineOnboardingConfiguration
    let progression: RankProgressionConfiguration
    let ranks: [RankLevelDefinition]

    var id: StatKey { key }
}

enum TrainingArcConfig {
    static let minimumBaseline = 0
    static let minimumRankLevel = 1
    static let maximumRankLevel = 10
    static let defaultRollingWindowWeeks = 4
    static let defaultChargeMaximum = 4
    static let defaultRankThresholds = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    static let focusRankThresholds = [0, 10, 20, 30, 40, 60, 80, 100, 120, 150]
    static let intellectRankThresholds = [0, 10, 20, 30, 45, 60, 80, 100, 130, 170]
    static let cardioRankThresholds = [0, 15, 30, 45, 60, 90, 120, 150, 180, 240]
    static let readingRankThresholds = [0, 30, 60, 90, 120, 180, 240, 300, 360, 480]
    private static let strengthSourceLockedLevels: Set<Int> = Set(2...10)
    private static let creativitySourceLockedLevels: Set<Int> = Set(2...10)

    static let habitDefinitions: [HabitProgressionDefinition] = [
        HabitProgressionDefinition(
            key: .creativity,
            displayName: "Creativity",
            iconName: "paintbrush.pointed.fill",
            colorToken: "creativity",
            overview: "Making, designing, writing, drawing, and creative output.",
            defaultBaseline: 3,
            starterHabit: HabitTemplate(
                id: "drawing",
                systemKey: "habit.drawing",
                name: "Drawing Sessions",
                statKey: .creativity,
                measurementType: .booleanSession,
                scheduleType: .weekly,
                unitLabel: "session",
                targetPerPeriod: 3,
                notes: "Sketching, design work, or creative practice."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many times a week do you draw, or paint?",
                valueLabelSingular: "time per week",
                valueLabelPlural: "times per week",
                minimumValue: minimumBaseline,
                maximumValue: 30,
                quickAdjustments: [1, 2, 3],
                manualEntryLabel: "Custom number"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: defaultRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Untrained", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Beginner", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Practicing", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Active Maker", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Skilled Maker", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Strong Voice", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Distinctive Creator", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Mature Artist", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Master Creator", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Defining Artist", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .curiosity,
            displayName: "Curiosity",
            iconName: "sparkles.rectangle.stack.fill",
            colorToken: "curiosity",
            overview: "Open-ended exploration, research sessions, and questions investigated — distinct from structured study.",
            defaultBaseline: 2,
            starterHabit: HabitTemplate(
                id: "curiosity",
                systemKey: "habit.curiosity",
                name: "Curiosity Research Sessions",
                statKey: .curiosity,
                measurementType: .booleanSession,
                scheduleType: .weekly,
                unitLabel: "session",
                targetPerPeriod: 2,
                notes: "Deep dives into topics that expand your range and perspective."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many research sessions do you do each week?",
                valueLabelSingular: "session per week",
                valueLabelPlural: "sessions per week",
                minimumValue: minimumBaseline,
                maximumValue: 30,
                quickAdjustments: [1, 2, 3],
                manualEntryLabel: "Custom number"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: defaultRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Closed Off", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Browsing", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Exploring", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Active Learner", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Wide Reader", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Pattern Hunter", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Deep Investigator", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Polymath", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Boundary Pusher", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Master Explorer", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .emotional,
            displayName: "Emotional",
            iconName: "heart.text.square.fill",
            colorToken: "emotional",
            overview: "Journaling, reflection, regulation, and therapy-style exercises.",
            defaultBaseline: 4,
            starterHabit: HabitTemplate(
                id: "journal",
                systemKey: "habit.journal",
                name: "Journal Sessions",
                statKey: .emotional,
                measurementType: .booleanSession,
                scheduleType: .weekly,
                unitLabel: "session",
                targetPerPeriod: 4,
                notes: "Reflection, emotional processing, or personal writing."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many times a week do you journal, reflect, or reset?",
                valueLabelSingular: "time per week",
                valueLabelPlural: "times per week",
                minimumValue: minimumBaseline,
                maximumValue: 30,
                quickAdjustments: [1, 2, 3],
                manualEntryLabel: "Custom number"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: defaultRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Untended", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Guarded", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Reflecting", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Grounded", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Steady", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Self-Aware", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Resilient", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Anchored", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Deeply Grounded", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Master of Self", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .focus,
            displayName: "Focus",
            iconName: "scope",
            colorToken: "focus",
            overview: "Meditation, breathwork, yoga, and attention control.",
            defaultBaseline: 40,
            starterHabit: HabitTemplate(
                id: "meditation",
                systemKey: "habit.meditation",
                name: "Meditation Minutes",
                statKey: .focus,
                measurementType: .minutes,
                scheduleType: .weekly,
                unitLabel: "min",
                targetPerPeriod: 40,
                notes: "Meditation, breathwork, or concentration training."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many minutes a week do you spend meditating or training focus?",
                valueLabelSingular: "minute per week",
                valueLabelPlural: "minutes per week",
                minimumValue: minimumBaseline,
                maximumValue: 600,
                quickAdjustments: [5, 10, 20],
                manualEntryLabel: "Custom minutes"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: focusRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Scattered", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Distracted", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Practicing Focus", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Steady", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Focused", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Deep Worker", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Disciplined", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Flow Capable", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Iron Concentration", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Master of Focus", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .intellect,
            displayName: "Intellect",
            iconName: "book.pages.fill",
            colorToken: "intellect",
            overview: "Structured learning, reading, study, and deliberate knowledge-building.",
            defaultBaseline: 30,
            starterHabit: HabitTemplate(
                id: "reading",
                systemKey: "habit.reading",
                name: "Reading Pages",
                statKey: .intellect,
                measurementType: .pages,
                scheduleType: .weekly,
                unitLabel: "pages",
                targetPerPeriod: 30,
                notes: "Non-fiction, study material, or deliberate learning."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many pages do you read each week?",
                valueLabelSingular: "page per week",
                valueLabelPlural: "pages per week",
                minimumValue: minimumBaseline,
                maximumValue: 1_000,
                quickAdjustments: [5, 10, 25],
                manualEntryLabel: "Custom pages"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: intellectRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Untrained Mind", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Beginning Learner", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Student", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Thoughtful Reader", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Sharp Thinker", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Analytical", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Well-Read", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Scholar", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Deep Thinker", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Master Intellect", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .strength,
            displayName: "Strength",
            iconName: "figure.strengthtraining.traditional",
            colorToken: "strength",
            overview: "Resistance training and muscular strength.",
            defaultBaseline: 3,
            starterHabit: HabitTemplate(
                id: "gym",
                systemKey: "habit.gym",
                name: "Gym Sessions",
                statKey: .strength,
                measurementType: .booleanSession,
                scheduleType: .weekly,
                unitLabel: "session",
                targetPerPeriod: 3,
                notes: "Strength training, sports, or any session that builds physical capacity."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many gym or strength sessions do you do each week?",
                valueLabelSingular: "session per week",
                valueLabelPlural: "sessions per week",
                minimumValue: minimumBaseline,
                maximumValue: 30,
                quickAdjustments: [1, 2, 3],
                manualEntryLabel: "Custom number"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: defaultRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Untrained", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Beginning Lifter", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Novice", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Steady Trainee", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Strong", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Powerful", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Hardened", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Highly Trained", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Elite Strength", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Master of Strength", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .cardio,
            displayName: "Cardio",
            iconName: "figure.run",
            colorToken: "cardio",
            overview: "Endurance, conditioning, and sport movement.",
            defaultBaseline: 60,
            starterHabit: HabitTemplate(
                id: "cardio",
                systemKey: "habit.cardio",
                name: "Cardio Minutes",
                statKey: .cardio,
                measurementType: .minutes,
                scheduleType: .weekly,
                unitLabel: "min",
                targetPerPeriod: 60,
                notes: "Running, cycling, rowing, or sustained conditioning work."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many minutes of cardio do you do each week?",
                valueLabelSingular: "minute per week",
                valueLabelPlural: "minutes per week",
                minimumValue: minimumBaseline,
                maximumValue: 1_000,
                quickAdjustments: [5, 10, 25],
                manualEntryLabel: "Custom minutes"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: cardioRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Sedentary", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Casual Mover", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Building Pace", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Conditioned", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Enduring", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Strong Engine", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Distance Capable", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "High Endurance", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Elite Endurance", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Master of Endurance", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .cooking,
            displayName: "Cooking",
            iconName: "fork.knife",
            colorToken: "cooking",
            overview: "Meals cooked from scratch and practical food skill.",
            defaultBaseline: 3,
            starterHabit: HabitTemplate(
                id: "cooking",
                systemKey: "habit.cooking",
                name: "Cooked Meals",
                statKey: .cooking,
                measurementType: .count,
                scheduleType: .weekly,
                unitLabel: "meals",
                targetPerPeriod: 3,
                notes: "Meals prepared from scratch at home."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many meals do you cook from scratch each week?",
                valueLabelSingular: "meal per week",
                valueLabelPlural: "meals per week",
                minimumValue: minimumBaseline,
                maximumValue: 30,
                quickAdjustments: [1, 2, 3],
                manualEntryLabel: "Custom number"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: defaultRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Untrained Cook", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Beginning Cook", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Recipe Follower", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Home Cook", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Capable Cook", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Confident Cook", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Skilled Cook", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Strong Cook", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Expert Cook", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Master Cook", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .reading,
            displayName: "Reading",
            iconName: "book.fill",
            colorToken: "reading",
            overview: "Standalone reading volume — narrative immersion and longer-form work.",
            defaultBaseline: 90,
            starterHabit: HabitTemplate(
                id: "reading.session",
                systemKey: "habit.reading.session",
                name: "Reading Minutes",
                statKey: .reading,
                measurementType: .minutes,
                scheduleType: .weekly,
                unitLabel: "min",
                targetPerPeriod: 90,
                notes: "Fiction, narrative non-fiction, or any long-form reading."
            ),
            charge: ChargeConfiguration(maximumValue: defaultChargeMaximum, label: "Charge"),
            onboarding: BaselineOnboardingConfiguration(
                question: "How many minutes a week do you read for pleasure?",
                valueLabelSingular: "minute per week",
                valueLabelPlural: "minutes per week",
                minimumValue: minimumBaseline,
                maximumValue: 1_000,
                quickAdjustments: [10, 30, 60],
                manualEntryLabel: "Custom minutes"
            ),
            progression: RankProgressionConfiguration(
                rollingWindowWeeks: defaultRollingWindowWeeks,
                levelThresholds: readingRankThresholds
            ),
            ranks: [
                RankLevelDefinition(level: 1, title: "Non-Reader", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Occasional Reader", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Light Reader", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Steady Reader", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Regular Reader", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Deep Reader", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Voracious Reader", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Scholar of Books", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Master Reader", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Lifelong Reader", image: nil, description: nil)
            ]
        )
    ]

    // MARK: - Skill taxonomy / activation

    /// The lean default skill set every new profile starts with.
    static let coreSkillKeys: Set<StatKey> = [
        .strength, .cardio, .focus, .intellect, .creativity, .emotional, .cooking
    ]

    /// Optional skills that are available but archived by default. Reading is
    /// normally covered by the Reading Pages habit under Intellect; Curiosity is a
    /// distinct open-ended exploration workflow.
    static let optionalSkillKeys: [StatKey] = [.reading, .curiosity]

    static func isCoreSkill(_ key: StatKey) -> Bool {
        coreSkillKeys.contains(key)
    }

    /// Sensible active parent to fall back to when an optional skill is archived.
    static func parentSkillKey(for key: StatKey) -> StatKey? {
        switch key {
        case .reading: return .intellect
        default: return nil
        }
    }

    static var statTemplates: [StatTemplate] {
        habitDefinitions.map {
            StatTemplate(
                key: $0.key,
                iconName: $0.iconName,
                colorToken: $0.colorToken,
                defaultBaseline: $0.defaultBaseline,
                isCore: isCoreSkill($0.key),
                parentKey: parentSkillKey(for: $0.key)
            )
        }
    }

    static var defaultHabitTemplates: [HabitTemplate] {
        habitDefinitions.map(\.starterHabit)
    }

    static func definition(for key: StatKey) -> HabitProgressionDefinition {
        habitDefinitions.first(where: { $0.key == key }) ?? habitDefinitions[0]
    }

    static func clampedRankLevel(_ level: Int) -> Int {
        min(max(level, minimumRankLevel), maximumRankLevel)
    }

    static func rankDefinition(for statKey: StatKey, level: Int) -> RankLevelDefinition {
        let definition = definition(for: statKey)
        let clampedLevel = clampedRankLevel(level)
        let rank = definition.ranks.first(where: { $0.level == clampedLevel }) ?? definition.ranks[0]

        guard rank.image == nil, let displayImage = rankArtworkImage(for: statKey, level: clampedLevel) else {
            return rank
        }

        return RankLevelDefinition(
            level: rank.level,
            title: rank.title,
            image: displayImage,
            description: rank.description
        )
    }

    static func nextRankDefinition(for statKey: StatKey, level: Int) -> RankLevelDefinition? {
        let currentLevel = clampedRankLevel(level)
        guard currentLevel < maximumRankLevel else { return nil }
        return rankDefinition(for: statKey, level: currentLevel + 1)
    }

    static func rankTitle(for statKey: StatKey, level: Int) -> String {
        rankDefinition(for: statKey, level: level).title
    }

    static func overview(for statKey: StatKey) -> String {
        definition(for: statKey).overview
    }

    static func chargeConfiguration(for statKey: StatKey) -> ChargeConfiguration {
        definition(for: statKey).charge
    }

    static func onboardingConfiguration(for statKey: StatKey) -> BaselineOnboardingConfiguration {
        definition(for: statKey).onboarding
    }

    static func progressionConfiguration(for statKey: StatKey) -> RankProgressionConfiguration {
        definition(for: statKey).progression
    }

    static func rollingWindowWeeks(for statKey: StatKey) -> Int {
        progressionConfiguration(for: statKey).rollingWindowWeeks
    }

    static func rankThresholds(for statKey: StatKey) -> [Int] {
        progressionConfiguration(for: statKey).levelThresholds
    }

    static func requiredWeeklyValue(for statKey: StatKey, level: Int) -> Int {
        let thresholds = rankThresholds(for: statKey)
        let clampedLevel = clampedRankLevel(level)
        let index = min(max(clampedLevel - 1, 0), thresholds.count - 1)
        return thresholds[index]
    }

    static func characterRosterEntries(for statKey: StatKey, currentLevel: Int) -> [CharacterRosterEntry] {
        let clampedCurrentLevel = clampedRankLevel(currentLevel)

        return (minimumRankLevel...maximumRankLevel).map { level in
            CharacterRosterEntry(
                level: level,
                title: rankTitle(for: statKey, level: level),
                image: progressionImage(for: statKey, level: level, currentLevel: clampedCurrentLevel),
                isLocked: level > clampedCurrentLevel
            )
        }
    }

    static func progressionImage(for statKey: StatKey, level: Int, currentLevel: Int) -> RankImageReference? {
        let clampedLevel = clampedRankLevel(level)
        let clampedCurrentLevel = clampedRankLevel(currentLevel)
        let isLocked = clampedLevel > clampedCurrentLevel

        if let bundledImage = bundledProgressionImage(for: statKey, level: clampedLevel, isLocked: isLocked) {
            return bundledImage
        }

        guard !isLocked else { return nil }
        return rankArtworkImage(for: statKey, level: clampedLevel)
    }

    static func rankArtworkImage(for statKey: StatKey, level: Int) -> RankImageReference? {
        let clampedLevel = clampedRankLevel(level)

        if let bundledImage = bundledProgressionImage(for: statKey, level: clampedLevel, isLocked: false) {
            return bundledImage
        }

        return prototypeRankImage(for: statKey, level: clampedLevel)
    }

    // Temporary art mapping so prototype character images can be previewed
    // until full roster assets exist for every skill.
    private static func prototypeRankImage(for statKey: StatKey, level: Int) -> RankImageReference? {
        switch (statKey, level) {
        case (.strength, 1):
            return .asset(name: "StrengthFrailElderPrototype")
        case (.strength, 4):
            return .asset(name: "StrengthStrongHumanPrototype")
        case (.focus, 2):
            return .asset(name: "StrengthFrailElderPrototype")
        default:
            return nil
        }
    }

    private static func bundledProgressionImage(for statKey: StatKey, level: Int, isLocked: Bool) -> RankImageReference? {
        guard let assetName = bundledProgressionAssetName(for: statKey, level: level, isLocked: isLocked) else {
            return nil
        }

        return .asset(name: assetName)
    }

    private static func bundledProgressionAssetName(for statKey: StatKey, level: Int, isLocked: Bool) -> String? {
        switch statKey {
        case .strength:
            let unlockedName = "Strength_Level_\(level)"

            if isLocked {
                guard level != minimumRankLevel else { return nil }
                if strengthSourceLockedLevels.contains(level) {
                    return "Strength_Level_\(level)_Locked"
                }
                return unlockedName
            }

            return unlockedName
        case .creativity:
            let unlockedName = "Creativity_Level_\(level)"

            if isLocked {
                guard level != minimumRankLevel else { return nil }
                if creativitySourceLockedLevels.contains(level) {
                    return "Creativity_Level_\(level)_Locked"
                }
                return unlockedName
            }

            return unlockedName
        case .intellect, .emotional, .focus, .curiosity, .cardio, .cooking, .reading:
            return nil
        }
    }

    static func lowerRankThreshold(for statKey: StatKey, level: Int) -> Int? {
        let clampedLevel = clampedRankLevel(level)
        guard clampedLevel > minimumRankLevel else { return nil }
        return requiredWeeklyValue(for: statKey, level: clampedLevel - 1)
    }

    static func nextRankThreshold(for statKey: StatKey, level: Int) -> Int? {
        let clampedLevel = clampedRankLevel(level)
        guard clampedLevel < maximumRankLevel else { return nil }
        return requiredWeeklyValue(for: statKey, level: clampedLevel + 1)
    }

    static func rankLevel(for statKey: StatKey, weeklyValue: Double) -> Int {
        let thresholds = rankThresholds(for: statKey)
        let flooredValue = Int(max(0, weeklyValue).rounded(.down))

        for (index, threshold) in thresholds.enumerated().reversed() where flooredValue >= threshold {
            return clampedRankLevel(index + 1)
        }

        return minimumRankLevel
    }

    static func suggestedTargetValue(for statKey: StatKey, baseline: Int) -> Int {
        let onboarding = onboardingConfiguration(for: statKey)
        let stepUp = max(positiveChargeStep(for: statKey, level: rankLevel(for: statKey, weeklyValue: Double(baseline))) ?? 1, 1)
        let suggested = baseline + stepUp
        return min(max(suggested, onboarding.minimumValue), onboarding.maximumValue)
    }

    static func suggestedPersonalMaxValue(for statKey: StatKey, baseline: Int, target: Int? = nil) -> Int {
        let onboarding = onboardingConfiguration(for: statKey)
        let basis = max(target ?? baseline, baseline)
        let suggested = max(basis * 2, basis + 2)
        return min(max(suggested, basis), onboarding.maximumValue)
    }

    static func clampCalibration(baseline: Int, target: Int?, personalMax: Int?, maintenance: Int?) -> (target: Int?, max: Int?, maintenance: Int?) {
        var resolvedTarget = target
        if let t = resolvedTarget, t < baseline {
            resolvedTarget = baseline
        }
        var resolvedMax = personalMax
        if let m = resolvedMax {
            let floor = resolvedTarget ?? baseline
            if m < floor {
                resolvedMax = floor
            }
        }
        var resolvedMaintenance = maintenance
        if let f = resolvedMaintenance {
            resolvedMaintenance = max(0, min(f, baseline))
        }
        return (resolvedTarget, resolvedMax, resolvedMaintenance)
    }

    static func baselineValueLabel(for statKey: StatKey, value: Int) -> String {
        let onboarding = onboardingConfiguration(for: statKey)
        let label = value == 1 ? onboarding.valueLabelSingular : onboarding.valueLabelPlural
        return "\(value) \(label)"
    }

    static func effectiveWeeklyTarget(for statKey: StatKey, level: Int) -> Int {
        max(requiredWeeklyValue(for: statKey, level: level), 1)
    }

    static func nextRankChargeRequirement(for statKey: StatKey, level: Int) -> Int? {
        let clampedLevel = clampedRankLevel(level)
        guard clampedLevel < maximumRankLevel else { return nil }
        return effectiveWeeklyTarget(for: statKey, level: clampedLevel + 1)
    }

    static func previousRankChargeRequirement(for statKey: StatKey, level: Int) -> Int? {
        let clampedLevel = clampedRankLevel(level)
        guard clampedLevel > minimumRankLevel else { return nil }
        return effectiveWeeklyTarget(for: statKey, level: clampedLevel - 1)
    }

    static func positiveChargeStep(for statKey: StatKey, level: Int) -> Int? {
        let clampedLevel = clampedRankLevel(level)
        guard let nextTarget = nextRankChargeRequirement(for: statKey, level: clampedLevel) else { return nil }
        let currentTarget = effectiveWeeklyTarget(for: statKey, level: clampedLevel)
        return max(nextTarget - currentTarget, 1)
    }

    static func negativeChargeStep(for statKey: StatKey, level: Int) -> Int? {
        let clampedLevel = clampedRankLevel(level)
        guard let lowerTarget = previousRankChargeRequirement(for: statKey, level: clampedLevel) else { return nil }
        let currentTarget = effectiveWeeklyTarget(for: statKey, level: clampedLevel)
        return max(currentTarget - lowerTarget, 1)
    }

    static func progressionBridgeUnits(for statKey: StatKey, fromLevel: Int, toLevel: Int) -> Double {
        let fromTarget = effectiveWeeklyTarget(for: statKey, level: fromLevel)
        let toTarget = effectiveWeeklyTarget(for: statKey, level: toLevel)
        return Double(fromTarget * toTarget)
    }

    static func displayedCharge(for statKey: StatKey, bankedUnits: Double, level: Int) -> Int {
        DashboardChargeDots.clampedCharge(Int(bankedUnits.rounded(.towardZero)))
    }

    static func chargeProgress(for statKey: StatKey, bankedUnits: Double, level: Int) -> Double {
        let clampedLevel = clampedRankLevel(level)
        guard nextRankChargeRequirement(for: statKey, level: clampedLevel) != nil, clampedLevel < maximumRankLevel else {
            return 1
        }
        let visibleCharge = max(displayedCharge(for: statKey, bankedUnits: bankedUnits, level: clampedLevel), 0)
        return min(max(Double(visibleCharge) / Double(defaultChargeMaximum), 0), 1)
    }

    static func color(for token: String) -> Color {
        switch token {
        case "strength": Color(red: 0.87, green: 0.43, blue: 0.34)
        case "intellect": Color(red: 0.39, green: 0.60, blue: 0.89)
        case "creativity": Color(red: 0.90, green: 0.58, blue: 0.31)
        case "emotional": Color(red: 0.84, green: 0.41, blue: 0.56)
        case "focus": Color(red: 0.34, green: 0.72, blue: 0.61)
        case "curiosity": Color(red: 0.63, green: 0.56, blue: 0.88)
        case "cardio": Color(red: 0.30, green: 0.72, blue: 0.88)
        case "cooking": Color(red: 0.92, green: 0.50, blue: 0.30)
        case "reading": Color(red: 0.45, green: 0.50, blue: 0.74)
        default: TrainingTheme.textSecondary
        }
    }
}
