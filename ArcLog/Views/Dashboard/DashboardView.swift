import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \StatDomain.name) private var stats: [StatDomain]
    @Query(sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.name)]) private var habits: [Habit]
    @Query private var settingsRecords: [AppSettings]

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var activeStats: [StatDomain] {
        stats.filter { !$0.isArchived }
    }

    private var activeHabits: [Habit] {
        habits.filter(\.active)
    }

    private var currentWeek: WeekRange {
        WeekMath.weekRange(containing: .now, weekStartsOnMonday: settings?.weekStartsOnMonday ?? true)
    }

    private var currentInterval: DateInterval {
        TrainingStore.currentWeekInterval(settings: settings)
    }

    private var todayInterval: DateInterval {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        return DateInterval(start: start, end: end)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let pendingWeek = try? TrainingStore.pendingWeek(context: modelContext) {
                        dashboardBanner(
                            title: "Weekly Review Pending",
                            detail: "Resolve \(pendingWeek.displayTitle) to bank rank progress and keep the build stable.",
                            accent: TrainingTheme.warning,
                            buttonTitle: "Open"
                        ) {
                            router.open(.weeklyReview)
                        }
                    }

                    HStack(spacing: 12) {
                        if let weakest = try? TrainingStore.weakestStat(context: modelContext) {
                            slimInsightCard(
                                title: "Needs Attention",
                                value: weakest.name,
                                detail: "\(MetricFormatting.shortMetric(TrainingStore.currentWeekTotal(for: weakest, settings: settings))) / \(weakest.currentBaseline)",
                                accent: TrainingTheme.warning
                            )
                        }

                        if let focusStat = activeStats.max(by: {
                            TrainingStore.projectedStoredRankProgress(for: $0, settings: settings)
                                < TrainingStore.projectedStoredRankProgress(for: $1, settings: settings)
                        }) {
                            let snapshot = TrainingStore.progressSnapshot(for: focusStat, settings: settings)
                            slimInsightCard(
                                title: "Closest Level-Up",
                                value: focusStat.name,
                                detail: snapshot.rank.isAtMaximumRank
                                    ? "Maximum rank reached"
                                    : "\(snapshot.rank.progressUnits) / \(snapshot.rank.progressRequired) to next rank",
                                accent: TrainingArcConfig.color(for: focusStat.colorToken)
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Skills")
                        Text("Compact progress cards so you can scan the whole build faster.")
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12, alignment: .top),
                                GridItem(.flexible(), spacing: 12, alignment: .top)
                            ],
                            spacing: 12
                        ) {
                            ForEach(activeStats) { stat in
                                let snapshot = TrainingStore.progressSnapshot(for: stat, settings: settings)
                                let trend = recentTrend(for: stat)

                                NavigationLink {
                                    SkillDetailView(stat: stat)
                                } label: {
                                    StatCard(
                                        stat: stat,
                                        snapshot: snapshot,
                                        trend: trend
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Today's Habits")
                        if activeHabits.isEmpty {
                            emptyState("No habits yet", detail: "Starter habits are managed from your dashboard flow and settings.")
                        } else {
                            ForEach(activeHabits) { habit in
                                HabitQuickLogRow(
                                    habit: habit,
                                    todayValue: TrainingStore.total(for: habit, in: todayInterval),
                                    hapticsEnabled: settings?.hapticsEnabled ?? true
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Dashboard")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(TrainingTheme.textPrimary)
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }

    private func dashboardBanner(
        title: String,
        detail: String,
        accent: Color,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        SurfaceCard(accent: accent) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
                Spacer()
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
        }
    }

    private func slimInsightCard(title: String, value: String, detail: String, accent: Color) -> some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textSecondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }

    private func recentTrend(for stat: StatDomain) -> Double {
        let recent = stat.weeklyResolutions.sorted { $0.weekStartDate < $1.weekStartDate }.suffix(3)
        guard recent.count >= 2 else { return 0 }
        let last = recent.last?.actualCompletedValue ?? 0
        let first = recent.first?.actualCompletedValue ?? 0
        return (last - first) / max(Double(stat.currentBaseline), 1)
    }
}
