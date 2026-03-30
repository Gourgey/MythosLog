import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \StatDomain.name) private var stats: [StatDomain]
    @State private var selectedStatKey: String?

    private var selectedStat: StatDomain? {
        let active = stats.filter { !$0.isArchived }
        let preferred = active.first { $0.key == selectedStatKey }
        return preferred ?? active.first
    }

    private var chartData: [WeeklyResolution] {
        selectedStat?.weeklyResolutions.sorted { $0.weekStartDate < $1.weekStartDate } ?? []
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.backgroundSecondary, TrainingTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if stats.filter({ !$0.isArchived }).isEmpty {
                        SurfaceCard {
                            Text("History fills in once you have habits, logs, and at least one resolved week.")
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                    } else {
                        Picker("Stat", selection: Binding(
                            get: { selectedStatKey ?? stats.first(where: { !$0.isArchived })?.key ?? "" },
                            set: { selectedStatKey = $0 }
                        )) {
                            ForEach(stats.filter { !$0.isArchived }) { stat in
                                Text(stat.name).tag(stat.key)
                            }
                        }
                        .pickerStyle(.segmented)

                        SurfaceCard(accent: selectedStat.map { TrainingArcConfig.color(for: $0.colorToken) } ?? .white) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(selectedStat?.name ?? "History")
                                    .font(.headline)
                                    .foregroundStyle(TrainingTheme.textPrimary)

                                Chart(chartData) { week in
                                    BarMark(
                                        x: .value("Week", week.weekStartDate, unit: .weekOfYear),
                                        y: .value("Actual", week.actualCompletedValue)
                                    )
                                    .foregroundStyle(TrainingArcConfig.color(for: selectedStat?.colorToken ?? "focus").gradient)

                                    LineMark(
                                        x: .value("Week", week.weekStartDate, unit: .weekOfYear),
                                        y: .value("Baseline", week.expectedTotal)
                                    )
                                    .foregroundStyle(TrainingTheme.textSecondary)

                                    LineMark(
                                        x: .value("Week", week.weekStartDate, unit: .weekOfYear),
                                        y: .value("Level", Double(week.levelAfter))
                                    )
                                    .lineStyle(.init(lineWidth: 2, dash: [4, 4]))
                                    .foregroundStyle(TrainingTheme.warning)
                                }
                                .frame(height: 240)
                            }
                        }

                        if let stat = selectedStat {
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Trend Summary")
                                        .font(.headline)
                                        .foregroundStyle(TrainingTheme.textPrimary)
                                    Text("Overview: \(stat.descriptor)")
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                    Text("Rank: \(stat.currentTierName) · Level \(stat.rankLevel)/\(TrainingArcConfig.maximumRankLevel)")
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                    Text("Current charge: \(stat.chargeValue)")
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                    Text("Banked units: \(MetricFormatting.shortMetric(stat.bankedProgressUnits))")
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                }
                            }
                        }

                        ForEach(chartData.reversed()) { resolution in
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(WeekRange(start: resolution.weekStartDate, end: resolution.weekEndDate).displayTitle)
                                        .font(.headline)
                                        .foregroundStyle(TrainingTheme.textPrimary)
                                    Text(resolution.summaryText)
                                        .font(.subheadline)
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("History")
        .onAppear {
            selectedStatKey = selectedStatKey ?? stats.first(where: { !$0.isArchived })?.key
        }
    }
}
