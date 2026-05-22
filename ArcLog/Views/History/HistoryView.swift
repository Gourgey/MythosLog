import Charts
import SwiftData
import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
    case month1
    case month3
    case month6
    case month12
    case allTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month1: "1M"
        case .month3: "3M"
        case .month6: "6M"
        case .month12: "12M"
        case .allTime: "All"
        }
    }

    var monthOffset: Int? {
        switch self {
        case .month1: 1
        case .month3: 3
        case .month6: 6
        case .month12: 12
        case .allTime: nil
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatDomain.name) private var stats: [StatDomain]
    @Query(sort: \WeeklyResolution.weekStartDate, order: .forward) private var allResolutions: [WeeklyResolution]
    @Query(sort: \HabitLog.date, order: .reverse) private var allLogs: [HabitLog]
    @State private var selectedStatKey: String?
    @State private var range: HistoryRange = .month3

    private var activeStats: [StatDomain] {
        stats.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedStat: StatDomain? {
        let preferred = activeStats.first { $0.key == selectedStatKey }
        return preferred ?? activeStats.first
    }

    private var rangeInterval: DateInterval {
        let end = Date.now
        guard let months = range.monthOffset else {
            let earliest = allResolutions.first?.weekStartDate ?? allLogs.last?.date ?? Calendar.current.date(byAdding: .month, value: -12, to: end) ?? end
            return DateInterval(start: earliest, end: end)
        }
        let start = Calendar.current.date(byAdding: .month, value: -months, to: end) ?? end
        return DateInterval(start: start, end: end)
    }

    private var resolutionsInRange: [WeeklyResolution] {
        allResolutions.filter { rangeInterval.contains($0.weekStartDate) }
    }

    private var logsInRange: [HabitLog] {
        allLogs.filter { rangeInterval.contains($0.date) }
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
                    if activeStats.isEmpty {
                        SurfaceCard {
                            Text("History appears after you resolve your first week.")
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                    } else if allResolutions.isEmpty {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No resolved weeks yet")
                                    .font(.headline)
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Text("Once you resolve your first weekly review, History will fill with charts, trends, and per-skill summaries.")
                                    .font(.subheadline)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                        }
                    } else {
                        rangePicker
                        if resolutionsInRange.isEmpty {
                            SurfaceCard {
                                Text("No resolved weeks in this range. Try widening the range or resolve another week.")
                                    .font(.subheadline)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                        }
                        overallSummary
                        statPicker
                        if let stat = selectedStat {
                            statChart(for: stat)
                            statSummary(for: stat)
                            recentResolutions(for: stat)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("History")
        .onAppear {
            selectedStatKey = selectedStatKey ?? activeStats.first?.key
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var overallSummary: some View {
        let totalLogs = logsInRange.count
        let weeks = resolutionsInRange
        let weekCount = weeks.count
        let improved = improvedSkills().count
        let stagnating = stagnatingSkills().count
        let regressing = regressingSkills().count

        let best = bestSkillName()
        let worst = mostNeglectedSkillName()

        return SurfaceCard(accent: TrainingArcConfig.color(for: "focus")) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Overall")
                    .font(.headline)
                    .foregroundStyle(TrainingTheme.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    summaryStat(title: "Logs", value: "\(totalLogs)")
                    summaryStat(title: "Weeks Resolved", value: "\(weekCount)")
                    summaryStat(title: "Skills Improving", value: "\(improved)")
                    summaryStat(title: "Stagnating", value: "\(stagnating)")
                    summaryStat(title: "Regressing", value: "\(regressing)")
                    summaryStat(title: "Range", value: range.label)
                }

                if let best { Text("Strongest: \(best)").font(.caption).foregroundStyle(TrainingTheme.textSecondary) }
                if let worst { Text("Most neglected: \(worst)").font(.caption).foregroundStyle(TrainingTheme.textSecondary) }
            }
        }
    }

    private func summaryStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textMuted)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(TrainingTheme.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TrainingTheme.backgroundTertiary.opacity(0.4))
        )
    }

    private var statPicker: some View {
        Picker("Stat", selection: Binding(
            get: { selectedStatKey ?? activeStats.first?.key ?? "" },
            set: { selectedStatKey = $0 }
        )) {
            ForEach(activeStats) { stat in
                Text(stat.name).tag(stat.key)
            }
        }
        .pickerStyle(.menu)
    }

    private func statChart(for stat: StatDomain) -> some View {
        let chartData = (stat.weeklyResolutions ?? [])
            .filter { rangeInterval.contains($0.weekStartDate) }
            .sorted { $0.weekStartDate < $1.weekStartDate }

        return SurfaceCard(accent: TrainingArcConfig.color(for: stat.colorToken)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(stat.name)
                    .font(.headline)
                    .foregroundStyle(TrainingTheme.textPrimary)

                if chartData.isEmpty {
                    Text("No resolved weeks in this range yet.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .frame(height: 120, alignment: .center)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(chartData) { week in
                            BarMark(
                                x: .value("Week", week.weekStartDate, unit: .weekOfYear),
                                y: .value("Actual", week.actualCompletedValue)
                            )
                            .foregroundStyle(TrainingArcConfig.color(for: stat.colorToken).gradient)
                        }

                        ForEach(chartData) { week in
                            LineMark(
                                x: .value("Week", week.weekStartDate, unit: .weekOfYear),
                                y: .value("Baseline", week.expectedTotal)
                            )
                            .foregroundStyle(TrainingTheme.textSecondary)
                        }

                        if let target = stat.targetValue {
                            RuleMark(y: .value("Target", target))
                                .foregroundStyle(TrainingTheme.warning.opacity(0.85))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .annotation(position: .topTrailing, alignment: .trailing) {
                                    Text("Target")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(TrainingTheme.warning)
                                }
                        }

                        if let max = stat.personalMaxValue {
                            RuleMark(y: .value("Max", max))
                                .foregroundStyle(TrainingTheme.positiveStrong.opacity(0.85))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                .annotation(position: .topTrailing, alignment: .trailing) {
                                    Text("Max")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(TrainingTheme.positiveStrong)
                                }
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private func statSummary(for stat: StatDomain) -> some View {
        let trend = trendInsight(for: stat)
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trend")
                    .font(.headline)
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(trend)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
                Text("Rank: \(stat.currentTierName) · Level \(stat.rankLevel)/\(TrainingArcConfig.maximumRankLevel)")
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
                if let target = stat.targetValue {
                    Text("Active target: \(target) \(TrainingStore.weeklyUnitLabel(for: stat)) per week")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }
        }
    }

    private func recentResolutions(for stat: StatDomain) -> some View {
        let recent = (stat.weeklyResolutions ?? [])
            .filter { rangeInterval.contains($0.weekStartDate) }
            .sorted { $0.weekStartDate > $1.weekStartDate }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Resolved Weeks")
                .font(.headline)
                .foregroundStyle(TrainingTheme.textPrimary)
            if recent.isEmpty {
                SurfaceCard {
                    Text("No resolved weeks in this range yet.")
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            } else {
                ForEach(recent) { resolution in
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(WeekRange(start: resolution.weekStartDate, end: resolution.weekEndDate).displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Spacer()
                                Text("LV \(resolution.levelAfter)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                            Text(resolution.summaryText)
                                .font(.caption)
                                .foregroundStyle(TrainingTheme.textSecondary)
                            if let healthNote = healthSourceNote(for: resolution) {
                                Label(healthNote, systemImage: "heart.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(TrainingTheme.cold)
                            }
                        }
                    }
                }
            }
        }
    }

    private func healthSourceNote(for resolution: WeeklyResolution) -> String? {
        let weekInterval = DateInterval(start: resolution.weekStartDate, end: resolution.weekEndDate)
        let healthLogs = allLogs.filter { log in
            guard let key = log.habit?.statDomain?.statKey?.rawValue, key == resolution.statKey else { return false }
            return log.sourceType == .health && weekInterval.contains(log.date)
        }
        guard !healthLogs.isEmpty else { return nil }
        if healthLogs.count == 1 {
            return "Includes 1 Apple Health import"
        }
        return "Includes \(healthLogs.count) Apple Health imports"
    }

    private func trendInsight(for stat: StatDomain) -> String {
        let resolutions = (stat.weeklyResolutions ?? [])
            .filter { rangeInterval.contains($0.weekStartDate) }
            .sorted { $0.weekStartDate < $1.weekStartDate }

        guard resolutions.count >= 2 else {
            return "Not enough resolved weeks in this range to identify a trend."
        }

        let firstHalf = resolutions.prefix(resolutions.count / 2).map(\.actualCompletedValue).reduce(0, +)
        let secondHalf = resolutions.suffix(resolutions.count / 2).map(\.actualCompletedValue).reduce(0, +)
        guard firstHalf > 0 else {
            return "\(stat.name) had no activity earlier in this range; recent weeks added \(MetricFormatting.shortMetric(secondHalf))."
        }
        let change = (secondHalf - firstHalf) / firstHalf * 100
        if abs(change) < 5 {
            return "\(stat.name) is holding steady across this range."
        }
        if change > 0 {
            return "\(stat.name) is up \(Int(change))% across this range."
        }
        return "\(stat.name) is down \(Int(abs(change)))% across this range."
    }

    private func improvedSkills() -> [StatDomain] {
        activeStats.filter { stat in
            let resolutions = (stat.weeklyResolutions ?? [])
                .filter { rangeInterval.contains($0.weekStartDate) }
                .sorted { $0.weekStartDate < $1.weekStartDate }
            guard resolutions.count >= 2 else { return false }
            let firstHalf = resolutions.prefix(resolutions.count / 2).map(\.actualCompletedValue).reduce(0, +)
            let secondHalf = resolutions.suffix(resolutions.count / 2).map(\.actualCompletedValue).reduce(0, +)
            return secondHalf > firstHalf * 1.05
        }
    }

    private func stagnatingSkills() -> [StatDomain] {
        activeStats.filter { stat in
            let resolutions = (stat.weeklyResolutions ?? [])
                .filter { rangeInterval.contains($0.weekStartDate) }
            guard !resolutions.isEmpty else { return false }
            return resolutions.allSatisfy { $0.didStagnate || abs($0.weeklyDelta) < 0.001 }
        }
    }

    private func regressingSkills() -> [StatDomain] {
        activeStats.filter { stat in
            let resolutions = (stat.weeklyResolutions ?? [])
                .filter { rangeInterval.contains($0.weekStartDate) }
                .sorted { $0.weekStartDate < $1.weekStartDate }
            guard resolutions.count >= 2 else { return false }
            let firstHalf = resolutions.prefix(resolutions.count / 2).map(\.actualCompletedValue).reduce(0, +)
            let secondHalf = resolutions.suffix(resolutions.count / 2).map(\.actualCompletedValue).reduce(0, +)
            return secondHalf < firstHalf * 0.95
        }
    }

    private func bestSkillName() -> String? {
        let scored = activeStats.map { stat -> (StatDomain, Double) in
            let total = (stat.weeklyResolutions ?? [])
                .filter { rangeInterval.contains($0.weekStartDate) }
                .map(\.actualCompletedValue)
                .reduce(0, +)
            let baseline = max(Double(stat.currentBaseline), 1)
            return (stat, total / baseline)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0.name
    }

    private func mostNeglectedSkillName() -> String? {
        let scored = activeStats.compactMap { stat -> (StatDomain, Double)? in
            let total = (stat.weeklyResolutions ?? [])
                .filter { rangeInterval.contains($0.weekStartDate) }
                .map(\.actualCompletedValue)
                .reduce(0, +)
            let baseline = max(Double(stat.currentBaseline), 1)
            return (stat, total / baseline)
        }
        return scored.min(by: { $0.1 < $1.1 })?.0.name
    }
}
