import AppIntents
import SwiftData

private enum IntentSupport {
    @MainActor
    static func context() -> ModelContext {
        ModelContext(TrainingStore.sharedModelContainer)
    }

    @MainActor
    static func logHabit(systemKey: String, value: Double, note: String = "") throws -> String {
        let context = context()
        guard let habit = try TrainingStore.fetchActiveHabits(context: context).first(where: { $0.systemKey == systemKey }) else {
            return "Habit not found."
        }

        _ = try TrainingStore.log(habit: habit, value: value, date: .now, note: note, source: .shortcut, context: context)
        return "Logged \(habit.name)."
    }

    @MainActor
    static func completeHabit(named habitName: String) throws -> String {
        let context = context()
        guard let habit = try TrainingStore.fetchActiveHabits(context: context).first(where: { $0.name == habitName }) else {
            return "Habit not found."
        }

        _ = try TrainingStore.log(habit: habit, value: 1, date: .now, note: "", source: .shortcut, context: context)
        return "Marked \(habit.name) complete."
    }

    @MainActor
    static func orderedActiveStats() throws -> [StatDomain] {
        try TrainingStore.fetchActiveStats(context: context())
    }

    @MainActor
    static func settings() -> AppSettings? {
        try? TrainingStore.fetchSettings(context: context())
    }

    @MainActor
    static func skillEntity(for stat: StatDomain) -> SkillEntity? {
        guard let statKey = stat.statKey else { return nil }
        return SkillEntity(
            id: statKey.rawValue,
            statKeyRaw: statKey.rawValue,
            name: stat.name,
            iconName: stat.iconName
        )
    }

    @MainActor
    static func stat(for skill: SkillEntity) throws -> StatDomain? {
        try orderedActiveStats().first(where: { $0.statKey?.rawValue == skill.statKeyRaw })
    }

    @MainActor
    static func stat(for key: StatKey) throws -> StatDomain? {
        try orderedActiveStats().first(where: { $0.statKey == key })
    }

    @MainActor
    static func openSkill(_ skill: SkillEntity, openLogSheet: Bool = false) -> String {
        guard let statKey = skill.statKey else {
            return "That skill is unavailable right now."
        }

        queueDestination(PendingAppDestination(skillDetail: PendingSkillDestination(statKeyRaw: statKey.rawValue, openLogSheet: openLogSheet)))
        return openLogSheet ? "Opening \(skill.name) and getting the log sheet ready." : "Opening \(skill.name)."
    }

    @MainActor
    static func openSkill(statKey: StatKey, openLogSheet: Bool = false) -> String {
        guard let stat = try? stat(for: statKey) else {
            return "That skill is unavailable right now."
        }

        return openSkill(
            SkillEntity(
                id: statKey.rawValue,
                statKeyRaw: statKey.rawValue,
                name: stat.name,
                iconName: stat.iconName
            ),
            openLogSheet: openLogSheet
        )
    }

    @MainActor
    static func logPrimarySession(for skill: SkillEntity) throws -> String {
        guard let stat = try stat(for: skill) else {
            return "That skill is unavailable right now."
        }

        guard let habit = TrainingStore.primaryHabit(for: stat) else {
            return "No active habit is linked to \(stat.name)."
        }

        guard habit.measurementType == .booleanSession else {
            return "\(stat.name) uses \(habit.unitLabel). Ask Siri to log a specific amount instead."
        }

        _ = try TrainingStore.log(habit: habit, value: 1, date: .now, note: "", source: .shortcut, context: context())
        return "Logged 1 \(habit.unitLabel) for \(stat.name)."
    }

    @MainActor
    static func progressSummary(for skill: SkillEntity) throws -> String {
        guard let stat = try stat(for: skill) else {
            return "That skill is unavailable right now."
        }

        let settings = settings()
        let actual = TrainingStore.currentWeekTotal(for: stat, settings: settings)
        let unit = spokenUnitLabel(for: stat, value: actual)
        let rank = TrainingStore.progressSnapshot(for: stat, settings: settings).rank
        return "You have done \(MetricFormatting.shortMetric(actual)) \(unit) for \(stat.name) this week. You are level \(rank.level), \(rank.title)."
    }

    @MainActor
    static func stayOnPaceSummary(for skill: SkillEntity) throws -> String {
        guard let stat = try stat(for: skill) else {
            return "That skill is unavailable right now."
        }

        return stayOnPaceSummary(for: stat)
    }

    @MainActor
    static func stayOnPaceSummary(for statKey: StatKey) throws -> String {
        guard let stat = try stat(for: statKey) else {
            return "That skill is unavailable right now."
        }

        return stayOnPaceSummary(for: stat)
    }

    @MainActor
    private static func stayOnPaceSummary(for stat: StatDomain) -> String {
        let settings = settings()
        let actual = TrainingStore.currentWeekTotal(for: stat, settings: settings)
        let target = Double(stat.currentBaseline)
        let remaining = max(Double(stat.currentBaseline) - actual, 0)
        let completedUnit = spokenUnitLabel(for: stat, value: max(actual, 1))
        let remainingUnit = spokenUnitLabel(for: stat, value: max(remaining, 1))

        if remaining <= 0 {
            return "Your weekly target for \(stat.name) is \(MetricFormatting.shortMetric(target)) \(spokenUnitLabel(for: stat, value: target)). You have already done \(MetricFormatting.shortMetric(actual)) \(completedUnit), so you have met your weekly target."
        }

        return "Your weekly target for \(stat.name) is \(MetricFormatting.shortMetric(target)) \(spokenUnitLabel(for: stat, value: target)). You have done \(MetricFormatting.shortMetric(actual)) \(completedUnit) so far. You need \(MetricFormatting.shortMetric(remaining)) more \(remainingUnit) this week to meet your weekly target."
    }

    @MainActor
    static func queueNavigation(_ route: TrainingRoute) {
        queueDestination(PendingAppDestination(route: route))
    }

    @MainActor
    static func queueDestination(_ destination: PendingAppDestination) {
        PendingDestinationStore.queue(destination)
    }

    @MainActor
    private static func spokenUnitLabel(for stat: StatDomain, value: Double) -> String {
        guard let habit = TrainingStore.primaryHabit(for: stat) else {
            return value == 1 ? "log" : "logs"
        }

        switch habit.measurementType {
        case .booleanSession:
            return value == 1 ? "session" : "sessions"
        case .pages:
            return value == 1 ? "page" : "pages"
        case .minutes:
            return value == 1 ? "minute" : "minutes"
        case .count:
            return value == 1 ? "count" : "counts"
        case .customNumber:
            return value == 1 ? "point" : "points"
        }
    }
}

struct ActiveHabitOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let context = IntentSupport.context()
        return (try? TrainingStore.fetchActiveHabits(context: context).map(\.name)) ?? []
    }
}

struct SkillEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Skill")
    static var defaultQuery = SkillEntityQuery()

    let id: String
    let statKeyRaw: String
    let name: String
    let iconName: String

    var statKey: StatKey? {
        StatKey(rawValue: statKeyRaw)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SkillEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [SkillEntity.ID]) async throws -> [SkillEntity] {
        try IntentSupport.orderedActiveStats()
            .compactMap(IntentSupport.skillEntity(for:))
            .filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SkillEntity] {
        try IntentSupport.orderedActiveStats().compactMap(IntentSupport.skillEntity(for:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [SkillEntity] {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return try await suggestedEntities()
        }

        return try IntentSupport.orderedActiveStats()
            .compactMap(IntentSupport.skillEntity(for:))
            .filter {
                $0.name.localizedCaseInsensitiveContains(normalized) ||
                $0.statKeyRaw.localizedCaseInsensitiveContains(normalized) ||
                SkillEntityAliases.matches(normalized, skill: $0)
            }
    }
}

private enum SkillEntityAliases {
    private static let aliases: [StatKey: [String]] = [
        .strength: [
            "gym",
            "gym session",
            "gym sessions",
            "gym workout",
            "gym workouts",
            "workout",
            "workouts",
            "lifting",
            "weights",
            "strength training"
        ],
        .cardio: [
            "run",
            "runs",
            "running",
            "cardio workout",
            "cardio workouts"
        ],
        .focus: [
            "meditation",
            "meditate",
            "mindfulness"
        ],
        .intellect: [
            "reading",
            "books",
            "pages"
        ],
        .creativity: [
            "creative practice",
            "creative session",
            "making"
        ],
        .emotional: [
            "journal",
            "journaling",
            "journal entry",
            "journal entries"
        ],
        .curiosity: [
            "research",
            "research session",
            "research sessions"
        ]
    ]

    static func matches(_ query: String, skill: SkillEntity) -> Bool {
        guard let statKey = skill.statKey else { return false }

        let normalizedQuery = query.lowercased()
        return aliases[statKey, default: []].contains { alias in
            normalizedQuery == alias || normalizedQuery.contains(alias)
        }
    }
}

struct LogGymSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Gym Session"
    static let description = IntentDescription("Log a gym session toward Strength.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.logHabit(systemKey: "habit.gym", value: 1)))
    }
}

struct LogJournalSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Journal Session"
    static let description = IntentDescription("Log a journal session toward Emotional.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.logHabit(systemKey: "habit.journal", value: 1)))
    }
}

struct LogCuriositySessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Curiosity Session"
    static let description = IntentDescription("Log a curiosity research session.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.logHabit(systemKey: "habit.curiosity", value: 1)))
    }
}

struct LogReadingPagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Reading Pages"
    static let description = IntentDescription("Log reading pages toward Intellect.")

    @Parameter(title: "Pages", default: 10)
    var pages: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.logHabit(systemKey: "habit.reading", value: Double(pages), note: "Shortcut log")))
    }
}

struct LogMeditationMinutesIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meditation Minutes"
    static let description = IntentDescription("Log meditation minutes toward Focus.")

    @Parameter(title: "Minutes", default: 10)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.logHabit(systemKey: "habit.meditation", value: Double(minutes), note: "Shortcut log")))
    }
}

struct MarkHabitCompleteIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Habit Complete"
    static let description = IntentDescription("Mark any active habit complete.")

    @Parameter(title: "Habit", optionsProvider: ActiveHabitOptionsProvider())
    var habitName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.completeHabit(named: habitName)))
    }
}

struct OpenSkillIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Skill"
    static let description = IntentDescription("Open a specific skill page.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Skill")
    var skill: SkillEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: IntentSupport.openSkill(skill)))
    }
}

struct CompleteSkillSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Skill Session"
    static let description = IntentDescription("Log a single session to a skill's primary habit when that skill uses session-based logging.")

    @Parameter(title: "Skill")
    var skill: SkillEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.logPrimarySession(for: skill)))
    }
}

struct SkillProgressSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Skill Progress Summary"
    static let description = IntentDescription("Ask how much progress you have logged for a skill this week.")

    @Parameter(title: "Skill")
    var skill: SkillEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.progressSummary(for: skill)))
    }
}

struct SkillStayOnPaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Skill Pace Needed"
    static let description = IntentDescription("Ask how much more you need to do this week to stay on pace for a skill.")

    @Parameter(title: "Skill")
    var skill: SkillEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.stayOnPaceSummary(for: skill)))
    }
}

struct OpenStrengthIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Strength"
    static let description = IntentDescription("Open the Strength skill page.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: IntentSupport.openSkill(statKey: .strength)))
    }
}

struct OpenCardioIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Cardio"
    static let description = IntentDescription("Open the Cardio skill page.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: IntentSupport.openSkill(statKey: .cardio)))
    }
}

struct OpenFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Focus"
    static let description = IntentDescription("Open the Focus skill page.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: IntentSupport.openSkill(statKey: .focus)))
    }
}

struct OpenIntellectIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Intellect"
    static let description = IntentDescription("Open the Intellect skill page.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: IntentSupport.openSkill(statKey: .intellect)))
    }
}

struct StrengthWeeklyTargetIntent: AppIntent {
    static let title: LocalizedStringResource = "Strength Weekly Target"
    static let description = IntentDescription("Ask how many Strength sessions you still need this week.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.stayOnPaceSummary(for: .strength)))
    }
}

struct CardioWeeklyTargetIntent: AppIntent {
    static let title: LocalizedStringResource = "Cardio Weekly Target"
    static let description = IntentDescription("Ask how much Cardio you still need this week.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.stayOnPaceSummary(for: .cardio)))
    }
}

struct FocusWeeklyTargetIntent: AppIntent {
    static let title: LocalizedStringResource = "Focus Weekly Target"
    static let description = IntentDescription("Ask how much Focus practice you still need this week.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.stayOnPaceSummary(for: .focus)))
    }
}

struct IntellectWeeklyTargetIntent: AppIntent {
    static let title: LocalizedStringResource = "Intellect Weekly Target"
    static let description = IntentDescription("Ask how much Intellect practice you still need this week.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try IntentSupport.stayOnPaceSummary(for: .intellect)))
    }
}

struct OpenWeeklyReviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Weekly Review"
    static let description = IntentDescription("Open the weekly review screen.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentSupport.queueNavigation(.weeklyReview)
        return .result(dialog: "Opening weekly review.")
    }
}

struct OpenDashboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Dashboard"
    static let description = IntentDescription("Open the dashboard.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentSupport.queueNavigation(.dashboard)
        return .result(dialog: "Opening dashboard.")
    }
}
