import AppIntents

struct TrainingArcAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .navy }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogGymSessionIntent(),
            phrases: [
                "Log gym session in \(.applicationName)",
                "Record strength training in \(.applicationName)"
            ],
            shortTitle: "Gym Session",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: LogJournalSessionIntent(),
            phrases: [
                "Log journal session in \(.applicationName)",
                "Record a journal entry in \(.applicationName)"
            ],
            shortTitle: "Journal Session",
            systemImageName: "heart.text.square.fill"
        )
        AppShortcut(
            intent: LogReadingPagesIntent(),
            phrases: [
                "Log reading pages in \(.applicationName)",
                "Record reading in \(.applicationName)"
            ],
            shortTitle: "Reading Pages",
            systemImageName: "book.pages.fill"
        )
        AppShortcut(
            intent: LogMeditationMinutesIntent(),
            phrases: [
                "Log meditation minutes in \(.applicationName)",
                "Record meditation in \(.applicationName)"
            ],
            shortTitle: "Meditation",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: LogCuriositySessionIntent(),
            phrases: [
                "Log curiosity session in \(.applicationName)",
                "Record research session in \(.applicationName)"
            ],
            shortTitle: "Curiosity",
            systemImageName: "sparkles.rectangle.stack.fill"
        )
        AppShortcut(
            intent: MarkHabitCompleteIntent(),
            phrases: [
                "Mark habit complete in \(.applicationName)",
                "Complete a habit in \(.applicationName)"
            ],
            shortTitle: "Complete Habit",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: OpenWeeklyReviewIntent(),
            phrases: [
                "Open weekly review in \(.applicationName)",
                "Show training report in \(.applicationName)"
            ],
            shortTitle: "Weekly Review",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: OpenDashboardIntent(),
            phrases: [
                "Open dashboard in \(.applicationName)",
                "Show training dashboard in \(.applicationName)"
            ],
            shortTitle: "Dashboard",
            systemImageName: "shield.lefthalf.filled"
        )
    }
}
