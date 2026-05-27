import Foundation

/// Lightweight app-group queue backing the interactive Quick Log widget.
///
/// The widget extension cannot touch SwiftData, so a widget button records the
/// user's intent here (habit UUID -> accumulated amount). The main app drains the
/// queue into real `HabitLog`s on next launch/foreground. The widget reads the
/// pending amount back so the tap shows immediate progress before the app runs.
enum QuickLogQueue {
    private static let key = "training.arc.quicklog.pending"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppIdentity.appGroupIdentifier)
    }

    /// habit UUID string -> amount awaiting persistence.
    static func pending() -> [String: Double] {
        (defaults?.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }

    static func pendingAmount(forHabitID habitID: String) -> Double {
        pending()[habitID] ?? 0
    }

    static func enqueue(habitID: String, amount: Double) {
        guard amount > 0, let defaults else { return }
        var dict = pending()
        dict[habitID, default: 0] += amount
        defaults.set(dict, forKey: key)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
