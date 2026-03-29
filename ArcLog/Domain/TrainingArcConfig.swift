import Foundation
import SwiftUI

enum RankImageReference: Hashable, Sendable {
    case asset(name: String)
}

struct ChargeConfiguration: Sendable {
    let maximumValue: Int
    let fullChargeBaselineRatio: Double
    let label: String
}

struct RankLevelDefinition: Identifiable, Sendable {
    let level: Int
    let title: String
    let image: RankImageReference?
    let description: String?

    var id: Int { level }
}

struct StatTemplate: Identifiable, Sendable {
    let key: StatKey
    let iconName: String
    let colorToken: String
    let defaultBaseline: Int

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
    let ranks: [RankLevelDefinition]

    var id: StatKey { key }
}

enum TrainingArcConfig {
    static let minimumBaseline = 1
    static let minimumRankLevel = 1
    static let maximumRankLevel = 10
    static let requiredRankProgressToLevelUp = 4

    static let habitDefinitions: [HabitProgressionDefinition] = [
        HabitProgressionDefinition(
            key: .creativity,
            displayName: "Creativity",
            iconName: "paintbrush.pointed.fill",
            colorToken: "creativity",
            overview: "Creative output, design work, and making something from nothing.",
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
            charge: ChargeConfiguration(maximumValue: 4, fullChargeBaselineRatio: 1.0, label: "Charge"),
            ranks: [
                RankLevelDefinition(level: 1, title: "Idle Maker", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Casual Doodler", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Rookie Creator", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Active Maker", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Skilled Creator", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Vision Builder", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Signature Artist", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Master Creator", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Cultural Maker", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "World-Shaping Visionary", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .curiosity,
            displayName: "Curiosity",
            iconName: "sparkles.rectangle.stack.fill",
            colorToken: "curiosity",
            overview: "Research, exploration, and following questions farther than comfort.",
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
            charge: ChargeConfiguration(maximumValue: 4, fullChargeBaselineRatio: 1.0, label: "Charge"),
            ranks: [
                RankLevelDefinition(level: 1, title: "Closed Observer", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Casual Browser", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Rookie Researcher", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Active Learner", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Wide Explorer", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Insight Hunter", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Field Scholar", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Relentless Seeker", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Boundary Breaker", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "World-Class Explorer", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .emotional,
            displayName: "Emotional",
            iconName: "heart.text.square.fill",
            colorToken: "emotional",
            overview: "Reflection, regulation, and keeping your inner state in working order.",
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
            charge: ChargeConfiguration(maximumValue: 4, fullChargeBaselineRatio: 1.0, label: "Charge"),
            ranks: [
                RankLevelDefinition(level: 1, title: "Untended Self", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Guarded Civilian", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Honest Beginner", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Grounded Human", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Steady Heart", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Centered Presence", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Resilient Guide", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Emotional Anchor", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Pillar of Calm", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Master of Self", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .focus,
            displayName: "Focus",
            iconName: "scope",
            colorToken: "focus",
            overview: "Attention control, deep work, and finishing what you start.",
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
            charge: ChargeConfiguration(maximumValue: 4, fullChargeBaselineRatio: 1.0, label: "Charge"),
            ranks: [
                RankLevelDefinition(level: 1, title: "Scattered Starter", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Distracted Worker", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Attention Trainee", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Steady Operator", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Deep Worker", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Calm Executor", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Precision Specialist", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Flow State Adept", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Iron Discipline", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Absolute Concentration", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .intellect,
            displayName: "Intellect",
            iconName: "book.pages.fill",
            colorToken: "intellect",
            overview: "Learning, analysis, and building a sharper mind over time.",
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
            charge: ChargeConfiguration(maximumValue: 4, fullChargeBaselineRatio: 1.0, label: "Charge"),
            ranks: [
                RankLevelDefinition(level: 1, title: "Dormant Student", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Casual Learner", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Rookie Scholar", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Thoughtful Reader", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Sharp Thinker", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Skilled Analyst", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Learned Strategist", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Master Scholar", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Towering Mind", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Apex Intellectual", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .strength,
            displayName: "Strength",
            iconName: "figure.strengthtraining.traditional",
            colorToken: "strength",
            overview: "Physical force, durability, and the ability to impose effort on the world.",
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
            charge: ChargeConfiguration(maximumValue: 4, fullChargeBaselineRatio: 1.0, label: "Charge"),
            ranks: [
                RankLevelDefinition(level: 1, title: "Frail Elder", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Soft Civilian", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Rookie Trainee", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Strong Human", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Peak Human", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Iron Colossus", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Monster Hero", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Polished Titan", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Symbol of Strength", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Ascended Martial Titan", image: nil, description: nil)
            ]
        ),
        HabitProgressionDefinition(
            key: .cardio,
            displayName: "Cardio",
            iconName: "figure.run",
            colorToken: "cardio",
            overview: "Endurance, conditioning, and the ability to keep moving under load.",
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
            charge: ChargeConfiguration(maximumValue: 4, fullChargeBaselineRatio: 1.0, label: "Charge"),
            ranks: [
                RankLevelDefinition(level: 1, title: "Winded Walker", image: nil, description: nil),
                RankLevelDefinition(level: 2, title: "Casual Mover", image: nil, description: nil),
                RankLevelDefinition(level: 3, title: "Rookie Runner", image: nil, description: nil),
                RankLevelDefinition(level: 4, title: "Conditioned Human", image: nil, description: nil),
                RankLevelDefinition(level: 5, title: "Enduring Athlete", image: nil, description: nil),
                RankLevelDefinition(level: 6, title: "Distance Machine", image: nil, description: nil),
                RankLevelDefinition(level: 7, title: "Iron-Lung Competitor", image: nil, description: nil),
                RankLevelDefinition(level: 8, title: "Elite Endurance", image: nil, description: nil),
                RankLevelDefinition(level: 9, title: "Symbol of Endurance", image: nil, description: nil),
                RankLevelDefinition(level: 10, title: "Ascended Endurance", image: nil, description: nil)
            ]
        )
    ]

    static var statTemplates: [StatTemplate] {
        habitDefinitions.map {
            StatTemplate(
                key: $0.key,
                iconName: $0.iconName,
                colorToken: $0.colorToken,
                defaultBaseline: $0.defaultBaseline
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
        return definition.ranks.first(where: { $0.level == clampedLevel }) ?? definition.ranks[0]
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

    static func currentCharge(for statKey: StatKey, actual: Double, baseline: Int) -> Int {
        let config = chargeConfiguration(for: statKey)
        let safeBaseline = max(Double(baseline), 1)
        let ratio = max(0, actual) / safeBaseline
        let normalized = min(ratio / max(config.fullChargeBaselineRatio, 0.25), 1)
        let rawValue = Int((normalized * Double(config.maximumValue)).rounded(.down))

        if actual > 0 {
            return min(config.maximumValue, max(1, rawValue))
        }

        return 0
    }

    static func chargeProgress(for statKey: StatKey, actual: Double, baseline: Int) -> Double {
        let config = chargeConfiguration(for: statKey)
        let safeBaseline = max(Double(baseline), 1)
        let ratio = max(0, actual) / safeBaseline
        return min(ratio / max(config.fullChargeBaselineRatio, 0.25), 1)
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
        default: TrainingTheme.textSecondary
        }
    }
}
