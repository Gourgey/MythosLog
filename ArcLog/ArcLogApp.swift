import SwiftUI
import SwiftData
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
final class ArcLogAppDelegate: NSObject, UIApplicationDelegate {
    static let didReceiveShortcutNotification = Notification.Name("ArcLogAppDelegate.didReceiveShortcut")
    static var pendingShortcutItem: UIApplicationShortcutItem?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            Self.pendingShortcutItem = shortcutItem
            return false
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Self.pendingShortcutItem = shortcutItem
        NotificationCenter.default.post(name: Self.didReceiveShortcutNotification, object: nil)
        completionHandler(true)
    }
}

enum HomeScreenQuickActionService {
    private static let skillActionPrefix = "skill."
    private static let statKeyUserInfoKey = "statKey"
    private static let openLogUserInfoKey = "openLog"

    @MainActor
    static func refresh(using container: ModelContainer) {
        let context = ModelContext(container)
        guard let settings = try? TrainingStore.fetchSettings(context: context), settings.hasCompletedOnboarding else {
            UIApplication.shared.shortcutItems = []
            return
        }

        let stats = (try? TrainingStore.fetchActiveStats(context: context)) ?? []
        UIApplication.shared.shortcutItems = Array(stats.prefix(4)).compactMap { stat in
            guard let statKey = stat.statKey else { return nil }
            let icon = UIApplicationShortcutIcon(systemImageName: stat.iconName)
            return UIApplicationShortcutItem(
                type: "\(skillActionPrefix)\(statKey.rawValue)",
                localizedTitle: stat.name,
                localizedSubtitle: "Open skill",
                icon: icon,
                userInfo: [
                    statKeyUserInfoKey: statKey.rawValue as NSString,
                    openLogUserInfoKey: false as NSNumber
                ]
            )
        }
    }

    @MainActor
    static func consumePendingShortcutIfNeeded() {
        guard let destination = consumePendingDestinationIfNeeded() else { return }
        PendingDestinationStore.queue(destination)
    }

    @MainActor
    static func consumePendingDestinationIfNeeded() -> PendingAppDestination? {
        guard let shortcutItem = ArcLogAppDelegate.pendingShortcutItem else { return nil }
        ArcLogAppDelegate.pendingShortcutItem = nil
        return destination(for: shortcutItem)
    }

    @MainActor
    static func queueDestination(for shortcutItem: UIApplicationShortcutItem) {
        guard let destination = destination(for: shortcutItem) else { return }
        PendingDestinationStore.queue(destination)
    }

    private static func destination(for shortcutItem: UIApplicationShortcutItem) -> PendingAppDestination? {
        guard
            shortcutItem.type.hasPrefix(skillActionPrefix),
            let statKeyRaw = (shortcutItem.userInfo?[statKeyUserInfoKey] as? NSString).map(String.init) ?? shortcutItem.type.split(separator: ".").last.map(String.init),
            let statKey = StatKey(rawValue: statKeyRaw)
        else {
            return nil
        }

        let openLogSheet = (shortcutItem.userInfo?[openLogUserInfoKey] as? NSNumber)?.boolValue ?? false
        return PendingAppDestination(
            skillDetail: PendingSkillDestination(statKeyRaw: statKey.rawValue, openLogSheet: openLogSheet)
        )
    }
}
#endif

@main
struct ArcLogApp: App {
    private let sharedModelContainer = TrainingStore.sharedModelContainer
    @Environment(\.scenePhase) private var scenePhase
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(ArcLogAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    #if canImport(AppIntents)
                    TrainingArcAppShortcuts.updateAppShortcutParameters()
                    #endif
                    #if canImport(HealthKit)
                    await HealthImportService.syncIfEnabled()
                    HealthImportService.startWorkoutObserverIfEnabled()
                    #endif
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            TrainingStore.refreshAppState()
            #if canImport(UIKit)
            HomeScreenQuickActionService.refresh(using: sharedModelContainer)
            #endif
            #if canImport(AppIntents)
            Task {
                TrainingArcAppShortcuts.updateAppShortcutParameters()
            }
            #endif
            #if canImport(HealthKit)
            Task {
                await HealthImportService.syncIfEnabled()
                HealthImportService.startWorkoutObserverIfEnabled()
            }
            #endif
        }
    }
}
