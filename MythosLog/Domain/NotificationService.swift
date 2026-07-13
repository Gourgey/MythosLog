import Foundation

#if canImport(UserNotifications)
import UserNotifications

enum NotificationService {
    private static let managedIdentifiers = [
        "training.daily",
        "training.evening",
        "training.weekly",
        "training.goalAtRisk",
        "training.skillBehindPace"
    ]

    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func refreshNotifications(using settings: AppSettings, goalsAtRiskCount: Int = 0, skillsBehindPaceCount: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: managedIdentifiers)

        // Weekday numbering is Gregorian (1 = Sunday). When the week starts on
        // Monday every weekday-anchored reminder shifts forward by one.
        let weekdayShift = settings.weekStartsOnMonday ? 1 : 0

        if settings.dailyReminderEnabled {
            schedule(
                on: center,
                identifier: "training.daily",
                title: "Start the session",
                body: "Check in with your training habits early and set the tone.",
                hour: 9
            )
        }

        if settings.eveningReminderEnabled {
            schedule(
                on: center,
                identifier: "training.evening",
                title: "Close the day clean",
                body: "Review unfinished habits before the day ends.",
                hour: 20
            )
        }

        if settings.weeklyReviewReminderEnabled {
            schedule(
                on: center,
                identifier: "training.weekly",
                title: "Weekly review ready",
                body: "Last week was finalized overnight. Open Review to see what changed.",
                weekday: 1 + weekdayShift,
                hour: 8
            )
        }

        if settings.goalAtRiskReminderEnabled, goalsAtRiskCount > 0 {
            // Fire Thursday mid-day as a mid-week nudge.
            schedule(
                on: center,
                identifier: "training.goalAtRisk",
                title: goalsAtRiskCount == 1 ? "1 goal at risk" : "\(goalsAtRiskCount) goals at risk",
                body: "Catch up before the week ends to keep your goals on pace.",
                weekday: 4 + weekdayShift,
                hour: 12,
                minute: 30,
                badge: goalsAtRiskCount
            )
        }

        if settings.skillBehindPaceReminderEnabled, skillsBehindPaceCount > 0 {
            // Fire Wednesday evening as an earlier mid-week nudge.
            schedule(
                on: center,
                identifier: "training.skillBehindPace",
                title: skillsBehindPaceCount == 1 ? "1 skill behind pace" : "\(skillsBehindPaceCount) skills behind pace",
                body: "A short session now keeps these skills on track for the week.",
                weekday: 3 + weekdayShift,
                hour: 18
            )
        }
    }

    private static func schedule(
        on center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String,
        weekday: Int? = nil,
        hour: Int,
        minute: Int = 0,
        badge: Int? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let badge {
            content.badge = NSNumber(value: badge)
        }

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
#else
enum NotificationService {
    static func requestAuthorization() async {}
    static func refreshNotifications(using settings: AppSettings, goalsAtRiskCount: Int = 0, skillsBehindPaceCount: Int = 0) {}
}
#endif
