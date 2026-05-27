import AppIntents

struct TrainingArcAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .navy }

    static var appShortcuts: [AppShortcut] {
        return [
        AppShortcut(
            intent: LogGymSessionIntent(),
            phrases: [
                "Log gym session in \(.applicationName)",
                "Record strength training in \(.applicationName)",
                "Completed a gym session in \(.applicationName)"
            ],
            shortTitle: "Gym Session",
            systemImageName: "figure.strengthtraining.traditional"
        ),
        AppShortcut(
            intent: LogJournalSessionIntent(),
            phrases: [
                "Log journal session in \(.applicationName)",
                "Record a journal entry in \(.applicationName)"
            ],
            shortTitle: "Journal Session",
            systemImageName: "heart.text.square.fill"
        ),
        AppShortcut(
            intent: LogReadingPagesIntent(),
            phrases: [
                "Log reading pages in \(.applicationName)",
                "Record reading in \(.applicationName)"
            ],
            shortTitle: "Reading Pages",
            systemImageName: "book.pages.fill"
        ),
        AppShortcut(
            intent: LogMeditationMinutesIntent(),
            phrases: [
                "Log meditation minutes in \(.applicationName)",
                "Record meditation in \(.applicationName)"
            ],
            shortTitle: "Meditation",
            systemImageName: "brain.head.profile"
        ),
        AppShortcut(
            intent: LogCuriositySessionIntent(),
            phrases: [
                "Log curiosity session in \(.applicationName)",
                "Record research session in \(.applicationName)"
            ],
            shortTitle: "Curiosity",
            systemImageName: "sparkles.rectangle.stack.fill"
        ),
        AppShortcut(
            intent: OpenSkillIntent(),
            phrases: [
                "Open \(\.$skill) in \(.applicationName)",
                "Open \(\.$skill) skill in \(.applicationName)"
            ],
            shortTitle: "Open Skill",
            systemImageName: "sparkles.rectangle.stack.fill"
        ),
        AppShortcut(
            intent: CompleteSkillSessionIntent(),
            phrases: [
                "Completed a \(\.$skill) session in \(.applicationName)",
                "Log a \(\.$skill) session in \(.applicationName)"
            ],
            shortTitle: "Log Skill",
            systemImageName: "plus.circle.fill"
        ),
        AppShortcut(
            intent: SkillProgressSummaryIntent(),
            phrases: [
                "How many have I done for \(\.$skill) in \(.applicationName)",
                "How much progress do I have for \(\.$skill) in \(.applicationName)",
                "How many \(\.$skill) sessions have I done this week in \(.applicationName)"
            ],
            shortTitle: "Skill Progress",
            systemImageName: "chart.bar.fill"
        ),
        AppShortcut(
            intent: SkillStayOnPaceIntent(),
            phrases: [
                "How many do I need to stay on pace for \(\.$skill) in \(.applicationName)",
                "How much more do I need for \(\.$skill) in \(.applicationName)",
                "How many \(\.$skill) sessions do I need to meet my weekly target in \(.applicationName)",
                "How many \(\.$skill) sessions do I need this week in \(.applicationName)",
                "How many \(\.$skill) do I need this week in \(.applicationName)",
                "What is my weekly target for \(\.$skill) in \(.applicationName)"
            ],
            shortTitle: "Weekly Target",
            systemImageName: "target"
        ),
        AppShortcut(
            intent: OpenDashboardIntent(),
            phrases: [
                "Open dashboard in \(.applicationName)",
                "Show training dashboard in \(.applicationName)"
            ],
            shortTitle: "Dashboard",
            systemImageName: "shield.lefthalf.filled"
        )
        ]
    }
}
