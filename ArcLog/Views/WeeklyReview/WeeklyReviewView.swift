import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeeklyResolution.weekStartDate, order: .reverse) private var resolutions: [WeeklyResolution]
    @Query private var settingsRecords: [AppSettings]
    @State private var selectedWeekStart: Date?

    init() {}

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var groupedWeeks: [Date] {
        Array(Set(resolutions.map(\.weekStartDate))).sorted(by: >)
    }

    private var selectedWeekResolutions: [WeeklyResolution] {
        guard let selectedWeekStart else { return [] }
        return resolutions.filter {
            $0.weekStartDate == selectedWeekStart
        }.sorted { $0.statName < $1.statName }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let pendingWeek = try? TrainingStore.pendingWeek(context: modelContext) {
                        SurfaceCard(accent: TrainingTheme.warning) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Training Report Ready")
                                    .font(.system(.title2, design: .rounded).weight(.bold))
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Text("Resolve \(pendingWeek.displayTitle) to apply the weekly rank check and save the report.")
                                    .foregroundStyle(TrainingTheme.textSecondary)
                                Button("Sync Week") {
                                    let batch = try? TrainingStore.resolvePendingWeek(context: modelContext)
                                    selectedWeekStart = batch?.week.start
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(TrainingTheme.warning)
                            }
                        }
                    }

                    if !groupedWeeks.isEmpty {
                        Picker("Resolved week", selection: Binding(
                            get: { selectedWeekStart ?? groupedWeeks.first ?? .now },
                            set: { selectedWeekStart = $0 }
                        )) {
                            ForEach(groupedWeeks, id: \.self) { week in
                                Text(WeekRange(start: week, end: Calendar.current.date(byAdding: .day, value: 6, to: week) ?? week).displayTitle)
                                    .tag(week)
                            }
                        }
                        .pickerStyle(.menu)

                        ForEach(selectedWeekResolutions) { resolution in
                            SurfaceCard(accent: TrainingArcConfig.color(for: resolution.statDomain?.colorToken ?? "focus")) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(resolution.statName)
                                            .font(.headline)
                                            .foregroundStyle(TrainingTheme.textPrimary)
                                        Spacer()
                                        Text("Level \(resolution.levelAfter)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(TrainingTheme.textSecondary)
                                    }

                                    HStack {
                                        metricTile(title: "Expected", value: MetricFormatting.shortMetric(resolution.expectedTotal))
                                        metricTile(title: "Actual", value: MetricFormatting.shortMetric(resolution.actualCompletedValue))
                                        metricTile(title: "Delta", value: MetricFormatting.shortMetric(resolution.weeklyDelta))
                                    }

                                    if resolution.didLevelUp {
                                        Label("Ranked up this week", systemImage: "arrow.up.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(TrainingTheme.positive)
                                    } else if resolution.didRegress {
                                        Label("Ranked down this week", systemImage: "arrow.down.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(TrainingTheme.warning)
                                    } else if resolution.weeklyDelta < 0 {
                                        Label("Banked debt this week", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(TrainingTheme.warning)
                                    }

                                    Text(resolution.summaryText)
                                        .font(.subheadline)
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                }
                            }
                        }
                    } else {
                        SurfaceCard {
                            Text("No weekly reports yet. Weekly rank checks save themselves here after each completed week resolves.")
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Review")
        .onAppear {
            selectedWeekStart = selectedWeekStart ?? groupedWeeks.first
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TrainingTheme.textSecondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(TrainingTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
