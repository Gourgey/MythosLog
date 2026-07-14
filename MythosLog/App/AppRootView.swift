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
    @State private var goalsAtRiskCount = 0

    /// Recomputes the Goals-tab badge. This walks every active goal's pace
    /// through the store, so it must run on explicit change signals — never
    /// from a computed property in `body`, which would re-run the whole walk on
    /// every render (tab switches, router changes, animations included).
    private func refreshGoalsAtRiskCount() {
        goalsAtRiskCount = allGoals.reduce(into: 0) { count, goal in
            guard goal.status == .active else { return }
            let snapshot = TrainingStore.goalProgress(for: goal, context: modelContext)
            if snapshot.paceStatus == .atRisk || snapshot.paceStatus == .behind {
                count += 1
            }
        }
    }

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingFlowView {
                    reloadSettings()
                }
            } else {
                tabContent
            }
        }
        .environmentObject(router)
        .task {
            TrainingStore.startCloudKitEventObserver()
            TrainingStore.refreshAppState()
            reloadSettings()
            consumeHomeScreenQuickActionIfNeeded()
            refreshGoalsAtRiskCount()
            consumePendingDestinationIfNeeded()
        }
        .onChange(of: settingsRecords.map { "\($0.id)|\($0.hasCompletedOnboarding)|\($0.updatedAt.timeIntervalSinceReferenceDate)" }) { _, _ in
            reloadSettings()
        }
        .onChange(of: allGoals.map { "\($0.id)|\($0.statusRaw)|\($0.targetValue)|\($0.updatedAt.timeIntervalSinceReferenceDate)" }) { _, _ in
            refreshGoalsAtRiskCount()
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
                refreshGoalsAtRiskCount()
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

    @ViewBuilder
    private var tabContent: some View {
        switch router.selectedRoute {
        case .dashboard:
            dashboardStack
        case .weeklyReview:
            weeklyReviewStack
        case .goals:
            goalsStack
        case .more:
            moreStack
        }
    }

    private var dashboardStack: some View {
        NavigationStack(path: $router.rootPath) {
            DashboardView()
                .safeAreaInset(edge: .bottom, spacing: 0) { rootTabBar }
                .navigationDestination(for: DashboardNavigationDestination.self) { destination in
                    switch destination {
                    case .skillDetail(let destination):
                        SkillDetailDestinationView(destination: destination)
                    }
                }
        }
    }

    private var weeklyReviewStack: some View {
        NavigationStack {
            WeeklyReviewView()
                .safeAreaInset(edge: .bottom, spacing: 0) { rootTabBar }
        }
    }

    private var goalsStack: some View {
        NavigationStack {
            GoalsView()
                .safeAreaInset(edge: .bottom, spacing: 0) { rootTabBar }
        }
    }

    private var moreStack: some View {
        NavigationStack {
            MoreView {
                reloadSettings()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { rootTabBar }
        }
    }

    /// Attached to each tab's root content view, never to a pushed
    /// `navigationDestination`. A `safeAreaInset` applied outside the
    /// `NavigationStack` still visually renders on top of pushed
    /// destinations, but pushed views don't inherit its safe-area report —
    /// so a detail screen's own bottom-pinned controls (e.g.
    /// `SkillDetailView`'s sticky log button) land directly underneath the
    /// still-visible bar instead of above it. Scoping the inset to the root
    /// view makes the bar disappear entirely once something is pushed,
    /// which is both correct and the standard pattern for detail screens.
    private var rootTabBar: some View {
        CompactRootTabBar(
            selection: router.selectedRoute,
            goalsBadgeCount: goalsAtRiskCount
        ) { route in
            router.open(route)
        }
    }
}

private struct CompactRootTabBar: View {
    let selection: TrainingRoute
    let goalsBadgeCount: Int
    let onSelect: (TrainingRoute) -> Void

    private let items: [CompactRootTabItem] = [
        CompactRootTabItem(route: .dashboard, title: "Dashboard", systemImage: "rectangle.grid.2x2.fill"),
        CompactRootTabItem(route: .weeklyReview, title: "Review", systemImage: "calendar.badge.clock"),
        CompactRootTabItem(route: .goals, title: "Goals", systemImage: "target"),
        CompactRootTabItem(route: .more, title: "More", systemImage: "square.grid.2x2.fill")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        onSelect(item.route)
                    }
                } label: {
                    tabItem(item)
                }
                .buttonStyle(LiquidTabButtonStyle(isSelected: selection == item.route))
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.route ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(height: 64)
        .background(
            Capsule()
                .fill(.white.opacity(0.30))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.95), .white.opacity(0.36), TrainingTheme.borderStrong.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.28), lineWidth: 4)
                .blur(radius: 7)
                .padding(2)
        )
        .shadow(color: TrainingTheme.shadowStrong.opacity(0.34), radius: 24, x: 0, y: 14)
        .shadow(color: .white.opacity(0.75), radius: 8, x: 0, y: -2)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(.clear)
    }

    private func tabItem(_ item: CompactRootTabItem) -> some View {
        let isSelected = selection == item.route
        let tint = isSelected ? Color.accentColor : TrainingTheme.textSecondary

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 19, weight: isSelected ? .bold : .semibold))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: 22)

                Text(item.title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.54) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? .white.opacity(0.86) : .clear, lineWidth: 0.8)
            )
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.14) : .clear,
                radius: 8,
                x: 0,
                y: 4
            )

            if item.route == .goals, goalsBadgeCount > 0 {
                Text(goalsBadgeLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(minWidth: 19, minHeight: 19)
                    .padding(.horizontal, goalsBadgeCount > 9 ? 4 : 0)
                    .background(Capsule().fill(TrainingTheme.danger))
                    .offset(x: -18, y: -3)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private var goalsBadgeLabel: String {
        goalsBadgeCount > 9 ? "9+" : "\(goalsBadgeCount)"
    }
}

private struct LiquidTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : (isSelected ? 1.02 : 1.0))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSelected)
    }
}

private struct CompactRootTabItem: Identifiable {
    let route: TrainingRoute
    let title: String
    let systemImage: String

    var id: TrainingRoute { route }
}
