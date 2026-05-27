import SwiftData
import SwiftUI

private struct SkillDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var stats: [StatDomain]

    let destination: PendingSkillDestination
    @State private var resolvedKeyRaw: String?

    private var targetKeyRaw: String { resolvedKeyRaw ?? destination.statKeyRaw }

    private var statForKey: StatDomain? {
        stats.first { $0.statKey?.rawValue == targetKeyRaw }
    }

    var body: some View {
        Group {
            if let stat = statForKey, stat.isActive {
                SkillDetailView(stat: stat, opensLogSheetOnAppear: destination.openLogSheet)
            } else if let stat = statForKey {
                archivedPrompt(for: stat)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TrainingTheme.background.ignoresSafeArea())
            }
        }
    }

    @ViewBuilder
    private func archivedPrompt(for stat: StatDomain) -> some View {
        let parent = stat.parentSkillKey.flatMap { parentKey in
            stats.first { $0.statKey == parentKey && $0.isActive }
        }

        VStack(spacing: 16) {
            Image(systemName: "archivebox.fill")
                .font(.largeTitle)
                .foregroundStyle(TrainingTheme.textSecondary)
            Text("\(stat.name) is archived")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(TrainingTheme.textPrimary)
            Text("Enable it to log here and bring it back to your active skills, or open a related skill instead.")
                .font(.subheadline)
                .foregroundStyle(TrainingTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Enable \(stat.name)") {
                try? TrainingStore.enableSkill(stat, context: modelContext)
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainingArcConfig.color(for: stat.colorToken))

            if let parent {
                Button("Open \(parent.name) instead") {
                    resolvedKeyRaw = parent.statKey?.rawValue
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TrainingTheme.background.ignoresSafeArea())
    }
}

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @Query private var allGoals: [Goal]
    @StateObject private var router = AppRouter()
    @State private var settings: AppSettings?
    @State private var showOnboarding = false

    private var goalsAtRiskCount: Int {
        allGoals.filter { goal in
            guard goal.status == .active else { return false }
            let snapshot = TrainingStore.goalProgress(for: goal, context: modelContext)
            return snapshot.paceStatus == .atRisk || snapshot.paceStatus == .behind
        }.count
    }

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingFlowView {
                    reloadSettings()
                }
            } else {
                TabView(selection: $router.selectedRoute) {
                    NavigationStack(path: $router.rootPath) {
                        DashboardView()
                            .navigationDestination(for: DashboardNavigationDestination.self) { destination in
                                switch destination {
                                case .skillDetail(let destination):
                                    SkillDetailDestinationView(destination: destination)
                                }
                            }
                    }
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
                    .badge(goalsAtRiskCount)

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
        .environmentObject(router)
        .task {
            TrainingStore.startCloudKitEventObserver()
            _ = try? TrainingStore.reconcileSyncedData(context: modelContext)
            _ = try? TrainingStore.drainQuickLogQueue(context: modelContext)
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
        .onReceive(NotificationCenter.default.publisher(for: MythosLogAppDelegate.didReceiveShortcutNotification)) { _ in
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
            case .skillDetail(let statKey, let openLog):
                router.open(
                    PendingAppDestination(
                        skillDetail: PendingSkillDestination(statKeyRaw: statKey.rawValue, openLogSheet: openLog)
                    )
                )
            case .goalDetail(let goalID):
                router.open(.goals)
                PendingDestinationStore.queueGoal(goalID)
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
