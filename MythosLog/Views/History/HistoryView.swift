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
        stats.filter { $0.isActive }.sorted { $0.sortOrder < $1.sortOrder }
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
                    historyPageHeader

                    if activeStats.isEmpty {
                        V4Card {
                            Text("History appears after you resolve your first week.")
                                .foregroundStyle(TrainingTheme.textSecondary)
                                .font(.subheadline)
                        }
                    } else if allResolutions.isEmpty {
                        V4Card {
                            VStack(alignment: .leading, spacing: 8) {
                                V4SerifTitle(text: "No resolved weeks yet", size: 24)
                                Text("Once you resolve your first weekly review, History will fill with charts, trends, and per-skill summaries.")
                                    .font(.subheadline)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                        }
                    } else {
                        rangePicker
                        if resolutionsInRange.isEmpty {
                            V4Card {
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
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedStatKey = selectedStatKey ?? activeStats.first?.key
        }
    }

    private var historyPageHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            V4PageKicker(title: "Long-Term Trends")
            Text("History")
                .font(.system(size: 38, weight: .regular, design: .serif))
                .foregroundStyle(TrainingTheme.textPrimary)
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// Per-active-stat, range-filtered/sorted resolutions, computed once and
    /// shared by every derived count/best/worst below. `improvedSkills()`,
    /// `stagnatingSkills()`, `regressingSkills()`, `bestSkillName()`, and
    /// `mostNeglectedSkillName()` each used to re-filter and re-sort every
    /// stat's `weeklyResolutions` independently — 5 full passes over the same
    /// data on every render of `overallSummary`.
    private var skillRangeSummaries: [(stat: StatDomain, resolutions: [WeeklyResolution])] {
        activeStats.map { stat in
            let resolutions = (stat.weeklyResolutions ?? [])
                .filter { rangeInterval.contains($0.weekStartDate) }
                .sorted { $0.weekStartDate < $1.weekStartDate }
            return (stat, resolutions)
        }
    }

    private struct SkillTrendCounts {
        var improved = 0
        var stagnating = 0
        var regressing = 0
        var best: (name: String, ratio: Double)?
        var worst: (name: String, ratio: Double)?
    }

    private func skillTrendCounts(from summaries: [(stat: StatDomain, resolutions: [WeeklyResolution])]) -> SkillTrendCounts {
        var counts = SkillTrendCounts()
        for (stat, resolutions) in summaries {
            if resolutions.count >= 2 {
                let firstHalf = resolutions.prefix(resolutions.count / 2).map(\.actualCompletedValue).reduce(0, +)
                let secondHalf = resolutions.suffix(resolutions.count / 2).map(\.actualCompletedValue).reduce(0, +)
                if secondHalf > firstHalf * 1.05 {
                    counts.improved += 1
                } else if secondHalf < firstHalf * 0.95 {
                    counts.regressing += 1
                }
            }
            if !resolutions.isEmpty, resolutions.allSatisfy({ $0.didStagnate || abs($0.weeklyDelta) < 0.001 }) {
                counts.stagnating += 1
            }

            let total = resolutions.map(\.actualCompletedValue).reduce(0, +)
            let ratio = total / max(Double(stat.currentBaseline), 1)
            if counts.best == nil || ratio > counts.best!.ratio {
                counts.best = (stat.name, ratio)
            }
            if counts.worst == nil || ratio < counts.worst!.ratio {
                counts.worst = (stat.name, ratio)
            }
        }
        return counts
    }

    private var overallSummary: some View {
        let totalLogs = logsInRange.count
        let weeks = resolutionsInRange
        let weekCount = weeks.count
        let counts = skillTrendCounts(from: skillRangeSummaries)
        let improved = counts.improved
        let stagnating = counts.stagnating
        let regressing = counts.regressing

        let best = counts.best?.name
        let worst = counts.worst?.name

        return V4Card(accent: TrainingArcConfig.color(for: "focus")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("OVERALL")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Spacer()
                    Text(range.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                Divider().overlay(TrainingTheme.border.opacity(0.5))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    summaryStat(title: "Logs", value: totalLogs)
                    summaryStat(title: "Weeks", value: weekCount)
                    summaryStat(title: "Improving", value: improved)
                    summaryStat(title: "Stagnating", value: stagnating)
                    summaryStat(title: "Regressing", value: regressing)
                    summaryStat(title: "Skills", value: activeStats.count)
                }

                if best != nil || worst != nil {
                    Divider().overlay(TrainingTheme.border.opacity(0.4))
                }
                if let best {
                    HStack(spacing: 8) {
                        Text("STRONGEST")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.6)
                            .foregroundStyle(TrainingTheme.textMuted)
                        Text(best)
                            .font(.system(.subheadline, design: .serif).weight(.regular))
                            .foregroundStyle(TrainingTheme.positiveStrong)
                    }
                }
                if let worst {
                    HStack(spacing: 8) {
                        Text("MOST NEGLECTED")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.6)
                            .foregroundStyle(TrainingTheme.textMuted)
                        Text(worst)
                            .font(.system(.subheadline, design: .serif).weight(.regular))
                            .foregroundStyle(TrainingTheme.warning)
                    }
                }
            }
        }
    }

    private func summaryStat(title: String, value: Int) -> some View {
        V4StatTile(value: V4Style.displayNumber(value), label: title)
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

        return V4Card(accent: TrainingArcConfig.color(for: stat.colorToken)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: stat.iconName)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(TrainingArcConfig.color(for: stat.colorToken))
                    Text(stat.name.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingArcConfig.color(for: stat.colorToken))
                }

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
        let accent = TrainingArcConfig.color(for: stat.colorToken)
        return V4Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("TREND")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(TrainingTheme.textMuted)

                Divider().overlay(TrainingTheme.border.opacity(0.5))

                Text(trend)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    V4LevelBadge(level: stat.rankLevel, tint: accent, compact: true)
                    Text(stat.currentTierName)
                        .font(.system(.subheadline, design: .serif).weight(.regular))
                        .foregroundStyle(TrainingTheme.textPrimary)
                }

                if let target = stat.targetValue {
                    Text("Active target: \(target) \(TrainingStore.weeklyUnitLabel(for: stat)) per week")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func recentResolutions(for stat: StatDomain) -> some View {
        let recent = (stat.weeklyResolutions ?? [])
            .filter { rangeInterval.contains($0.weekStartDate) }
            .sorted { $0.weekStartDate > $1.weekStartDate }
        let accent = TrainingArcConfig.color(for: stat.colorToken)

        return VStack(alignment: .leading, spacing: 10) {
            Text("RESOLVED WEEKS")
                .font(.caption.weight(.heavy))
                .tracking(2.0)
                .foregroundStyle(TrainingTheme.textMuted)
            if recent.isEmpty {
                V4Card {
                    Text("No resolved weeks in this range yet.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            } else {
                ForEach(recent) { resolution in
                    V4Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(WeekRange(start: resolution.weekStartDate, end: resolution.weekEndDate).displayTitle)
                                    .font(.system(.subheadline, design: .serif).weight(.regular))
                                    .italic()
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Spacer()
                                V4LevelBadge(level: resolution.levelAfter, tint: accent, compact: true)
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
}
