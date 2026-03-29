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

    nonisolated static func queueNavigation(_ route: TrainingRoute) {
        let defaults = UserDefaults(suiteName: AppIdentity.appGroupIdentifier) ?? .standard
        defaults.set(route.rawValue, forKey: AppIdentity.navigationFlagKey)
    }
}

struct ActiveHabitOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let context = IntentSupport.context()
        return (try? TrainingStore.fetchActiveHabits(context: context).map(\.name)) ?? []
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

struct OpenWeeklyReviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Weekly Review"
    static let description = IntentDescription("Open the weekly review screen.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentSupport.queueNavigation(.weeklyReview)
        return .result(dialog: "Opening weekly review.")
    }
}

struct OpenDashboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Dashboard"
    static let description = IntentDescription("Open the dashboard.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentSupport.queueNavigation(.dashboard)
        return .result(dialog: "Opening dashboard.")
    }
}
