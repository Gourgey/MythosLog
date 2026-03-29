import Foundation

#if canImport(UserNotifications)
import UserNotifications

enum NotificationService {
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func refreshNotifications(using settings: AppSettings) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            "training.daily",
            "training.evening",
            "training.weekly"
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
            content.body = "Resolve the week and lock in your earned progress."
            content.sound = .default

            var components = DateComponents()
            components.weekday = settings.weekStartsOnMonday ? 2 : 1
            components.hour = 8
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "training.weekly", content: content, trigger: trigger)
            center.add(request)
        }
    }
}
#else
enum NotificationService {
    static func requestAuthorization() async {}
    static func refreshNotifications(using settings: AppSettings) {}
}
#endif
