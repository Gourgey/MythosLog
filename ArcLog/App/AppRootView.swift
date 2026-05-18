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
    @Query private var settingsRecords: [AppSettings]
    @StateObject private var router = AppRouter()
    @State private var settings: AppSettings?
    @State private var showOnboarding = false

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
                            GoalsView()
                        }
                        .tag(TrainingRoute.goals)
                        .tabItem {
                            Label("Goals", systemImage: "target")
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
            TrainingStore.startCloudKitEventObserver()
            _ = try? TrainingStore.reconcileSyncedData(context: modelContext)
            reloadSettings()
            consumeHomeScreenQuickActionIfNeeded()
            try? TrainingStore.refreshAllProgress(context: modelContext, reason: .appRefresh)
            consumePendingDestinationIfNeeded()
        }
        .onChange(of: settingsRecords.map { "\($0.id)|\($0.hasCompletedOnboarding)|\($0.updatedAt.timeIntervalSinceReferenceDate)" }) { _, _ in
            reloadSettings()
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
        .preferredColorScheme(.light)
    }

    private func reloadSettings() {
        let storedSettings = try? TrainingStore.fetchExistingSettings(context: modelContext)
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
