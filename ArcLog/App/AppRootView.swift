import SwiftData
import SwiftUI

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
        Group {
            if showOnboarding {
                OnboardingFlowView {
                    reloadSettings()
                }
            } else {
                TabView(selection: $router.selectedRoute) {
                    NavigationStack {
                        DashboardView()
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
            reloadSettings()
            try? TrainingStore.refreshAllProgress(context: modelContext, reason: .appRefresh)
        }
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

        if let route = UserDefaults(suiteName: AppIdentity.appGroupIdentifier)?
            .string(forKey: AppIdentity.navigationFlagKey)
            .flatMap(TrainingRoute.init(rawValue:)) {
            router.open(route)
            UserDefaults(suiteName: AppIdentity.appGroupIdentifier)?
                .removeObject(forKey: AppIdentity.navigationFlagKey)
        }
    }
}
