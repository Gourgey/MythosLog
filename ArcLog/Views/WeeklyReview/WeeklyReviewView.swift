import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeeklyResolution.weekStartDate, order: .reverse) private var resolutions: [WeeklyResolution]
    @Query private var settingsRecords: [AppSettings]
    @State private var selectedWeekStart: Date?

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var groupedWeeks: [Date] {
        Array(Set(resolutions.map(\.weekStartDate))).sorted(by: >)
    }

    private var selectedWeekResolutions: [WeeklyResolution] {
        guard let selectedWeekStart else { return [] }
        return resolutions.filter {
            WeekMath.isSameWeek($0.weekStartDate, selectedWeekStart, weekStartsOnMonday: settings?.weekStartsOnMonday ?? true)
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
                                Text("Resolve \(pendingWeek.displayTitle) to bank rank progress and process decay.")
                                    .foregroundStyle(TrainingTheme.textSecondary)
                                Button("Resolve Week") {
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
                                        if resolution.didLevelUp {
                                            Label("Level Up", systemImage: "arrow.up.circle.fill")
                                                .foregroundStyle(TrainingTheme.positive)
                                        } else if resolution.didRegress {
                                            Label("Regression", systemImage: "arrow.down.circle.fill")
                                                .foregroundStyle(TrainingTheme.warning)
                                        }
                                    }

                                    HStack {
                                        metricTile(title: "Baseline", value: "\(resolution.baselineAtStart)")
                                        metricTile(title: "Actual", value: MetricFormatting.shortMetric(resolution.actualCompletedValue))
                                        metricTile(title: "Rank", value: "+\(resolution.chargesEarned)")
                                    }

                                    if resolution.didStagnate || resolution.didDecay {
                                        HStack(spacing: 12) {
                                            if resolution.didStagnate {
                                                Label("Stagnation warning", systemImage: "exclamationmark.triangle.fill")
                                            }
                                            if resolution.didDecay {
                                                Label("Rank progress decay", systemImage: "bolt.slash.fill")
                                            }
                                        }
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
                            Text("No weekly reports yet. Log habits throughout the week, then resolve the last completed week here.")
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
