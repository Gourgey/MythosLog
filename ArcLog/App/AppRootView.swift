import SwiftData
import SwiftUI

private struct SkillDetailDestinationView: View {
    @Query private var stats: [StatDomain]

    let destination: PendingSkillDestination

    private var stat: StatDomain? {
        stats.first { !$0.isArchived && $0.statKey?.rawValue == destination.statKeyRaw }
    }

    var body: some View {
        Group {
            if let stat {
                SkillDetailView(stat: stat, opensLogSheetOnAppear: destination.openLogSheet)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TrainingTheme.background.ignoresSafeArea())
            }
        }
    }
}

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var router = AppRouter()
    @State private var settings: AppSettings?
    @State private var showOnboarding = false

    private var preferredColorScheme: ColorScheme? {
        guard let settings else { return .light }
        return settings.themePreference.colorScheme
    }

    var body: some View {
        NavigationStack(path: $router.rootPath) {
            Group {
                if showOnboarding {
                    OnboardingFlowView {
                        reloadSettings()
                    }
                } else {
                    TabView(selection: $router.selectedRoute) {
                        DashboardView()
                            .tag(TrainingRoute.dashboard)
                            .tabItem {
                                Label("Dashboard", systemImage: "shield.lefthalf.filled")
                            }

                        NavigationStack {
                            WeeklyReviewView()
                        }
                        .tag(TrainingRoute.weeklyReview)
                        .tabItem {
                            Label("Review", systemImage: "calendar.badge.clock")
                        }

                        NavigationStack {
                            MoreView {
                                reloadSettings()
                            }
                        }
                        .tag(TrainingRoute.more)
                        .tabItem {
                            Label("More", systemImage: "square.grid.2x2.fill")
                        }
                    }
                }
            }
            .navigationDestination(for: DashboardNavigationDestination.self) { destination in
                switch destination {
                case .skillDetail(let destination):
                    SkillDetailDestinationView(destination: destination)
                }
            }
        }
        .environmentObject(router)
        .task {
            reloadSettings()
            consumeHomeScreenQuickActionIfNeeded()
            try? TrainingStore.refreshAllProgress(context: modelContext, reason: .appRefresh)
            consumePendingDestinationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            consumePendingDestinationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: PendingDestinationStore.didQueueNotification)) { _ in
            consumePendingDestinationIfNeeded()
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: ArcLogAppDelegate.didReceiveShortcutNotification)) { _ in
            consumeHomeScreenQuickActionIfNeeded()
        }
        #endif
        .onOpenURL { url in
            guard let link = DeepLinkRouter.parse(url) else { return }
            switch link {
            case .route(let route):
                router.open(route)
            case .externalLog(let event):
                try? ExternalEventService.ingest(event, context: modelContext)
                try? TrainingStore.refreshAllProgress(context: modelContext, reason: .logMutation)
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private func reloadSettings() {
        let storedSettings = try? TrainingStore.fetchSettings(context: modelContext)
        settings = storedSettings
        showOnboarding = !(storedSettings?.hasCompletedOnboarding ?? false)

        consumePendingDestinationIfNeeded()
    }

    private func consumePendingDestinationIfNeeded() {
        guard let pendingDestination = PendingDestinationStore.consume() else { return }
        router.open(pendingDestination)
    }

    private func consumeHomeScreenQuickActionIfNeeded() {
        #if canImport(UIKit)
        guard let pendingDestination = HomeScreenQuickActionService.consumePendingDestinationIfNeeded() else { return }
        router.open(pendingDestination)
        #endif
    }
}
