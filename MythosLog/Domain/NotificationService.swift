import Foundation

#if canImport(UserNotifications)
import UserNotifications

enum NotificationService {
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func refreshNotifications(using settings: AppSettings, goalsAtRiskCount: Int = 0, skillsBehindPaceCount: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            "training.daily",
            "training.evening",
            "training.weekly",
            "training.goalAtRisk",
            "training.skillBehindPace"
        ])

        if settings.dailyReminderEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Start the session"
            content.body = "Check in with your training habits early and set the tone."
            content.sound = .default

            var components = DateComponents()
            components.hour = 9
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "training.daily", content: content, trigger: trigger)
            center.add(request)
        }

        if settings.eveningReminderEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Close the day clean"
            content.body = "Review unfinished habits before the day ends."
            content.sound = .default

            var components = DateComponents()
            components.hour = 20
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "training.evening", content: content, trigger: trigger)
            center.add(request)
        }

        if settings.weeklyReviewReminderEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Weekly review ready"
            content.body = "Open the Review tab and lock in last week's rank changes."
            content.sound = .default

            var components = DateComponents()
            components.weekday = settings.weekStartsOnMonday ? 2 : 1
            components.hour = 8
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "training.weekly", content: content, trigger: trigger)
            center.add(request)
        }

        if settings.goalAtRiskReminderEnabled, goalsAtRiskCount > 0 {
            let content = UNMutableNotificationContent()
            content.title = goalsAtRiskCount == 1 ? "1 goal at risk" : "\(goalsAtRiskCount) goals at risk"
            content.body = "Catch up before the week ends to keep your goals on pace."
            content.sound = .default
            content.badge = NSNumber(value: goalsAtRiskCount)

            var components = DateComponents()
            // Fire Thursday mid-day as a mid-week nudge.
            components.weekday = settings.weekStartsOnMonday ? 5 : 4
            components.hour = 12
            components.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "training.goalAtRisk", content: content, trigger: trigger)
            center.add(request)
        }

        if settings.skillBehindPaceReminderEnabled, skillsBehindPaceCount > 0 {
            let content = UNMutableNotificationContent()
            content.title = skillsBehindPaceCount == 1 ? "1 skill behind pace" : "\(skillsBehindPaceCount) skills behind pace"
            content.body = "A short session now keeps these skills on track for the week."
            content.sound = .default

            var components = DateComponents()
            // Fire Wednesday evening as an earlier mid-week nudge.
            components.weekday = settings.weekStartsOnMonday ? 4 : 3
            components.hour = 18
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "training.skillBehindPace", content: content, trigger: trigger)
            center.add(request)
        }
    }
}
#else
enum NotificationService {
    static func requestAuthorization() async {}
    static func refreshNotifications(using settings: AppSettings, goalsAtRiskCount: Int = 0, skillsBehindPaceCount: Int = 0) {}
}
#endif
