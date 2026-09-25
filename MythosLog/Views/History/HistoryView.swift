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

/// The two ways the all-skills chart can read a range. `levels` is the default:
/// one line per skill showing rank level week by week. `baselineShare` answers
/// the other question — how much did I actually log against what that skill
/// asked of me — on a shared 0-100%+ scale, so skills measured in minutes and
/// skills measured in pages are directly comparable.
enum HistoryChartMode: String, CaseIterable, Identifiable {
    case levels
    case baselineShare

    var id: String { rawValue }

    var label: String {
        switch self {
        case .levels: "Levels"
        case .baselineShare: "% of Baseline"
        }
    }

    var caption: String {
        switch self {
        case .levels: "Rank level for every skill, week by week."
        case .baselineShare: "What you logged each week as a share of that skill's baseline."
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
    @State private var showsSkillDetail = false
    @State private var chartMode: HistoryChartMode = .levels

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
                        QuietCard {
                            Text("History appears after you resolve your first week.")
                                .foregroundStyle(TrainingTheme.textSecondary)
                                .font(.subheadline)
                        }
                    } else if allResolutions.isEmpty {
                        QuietCard {
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
                            QuietCard {
                                Text("No resolved weeks in this range. Try widening the range or resolve another week.")
                                    .font(.subheadline)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                        }
                        Picker("History view", selection: $showsSkillDetail) {
                            Text("Overview").tag(false)
                            Text("By Skill").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if showsSkillDetail {
                            statPicker
                            if let stat = selectedStat {
                                statChart(for: stat)
                                statSummary(for: stat)
                                DisclosureGroup("Resolved weeks") {
                                    recentResolutions(for: stat)
                                }
                                .id(stat.id)
                            }
                        } else {
                            allSkillsSection
                            overallSummary
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
        .toolbarBackground(TrainingTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            selectedStatKey = selectedStatKey ?? activeStats.first?.key
        }
    }

    // WS15: the nav bar already titles this screen "History" — the in-scroll
    // serif repeat said the same word twice in the first two lines. Review
    // and Goals both rely on the kicker alone with no in-scroll hero; this
    // now matches that pattern.
    private var historyPageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            V4PageKicker(title: "Long-Term Trends")
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

    // MARK: - All skills

    private struct SkillSeriesPoint: Identifiable {
        let id: String
        let weekStart: Date
        let level: Double
        let baselinePercent: Double

        func value(for mode: HistoryChartMode) -> Double {
            switch mode {
            case .levels: level
            case .baselineShare: baselinePercent
            }
        }
    }

    private struct SkillSeries: Identifiable {
        let statKey: String
        let name: String
        let color: Color
        let points: [SkillSeriesPoint]
        /// Everything logged in this range over everything the range asked for.
        /// This is the "attention" measure: it's baseline-relative, so a skill
        /// with a small baseline can still top the list by consistently
        /// clearing it.
        let effortRatio: Double
        var isFocus: Bool

        var id: String { statKey }
    }

    /// Series for every active skill, with the highest-effort ones flagged so
    /// the chart can foreground them and grey the rest back.
    private var skillSeries: [SkillSeries] {
        let built: [SkillSeries] = skillRangeSummaries.map { stat, resolutions in
            let points = resolutions.map { resolution in
                SkillSeriesPoint(
                    id: "\(stat.key)-\(resolution.weekStartDate.timeIntervalSince1970)",
                    weekStart: resolution.weekStartDate,
                    level: Double(resolution.levelAfter),
                    baselinePercent: baselinePercent(for: resolution)
                )
            }
            let expected = resolutions.map(\.expectedTotal).reduce(0, +)
            let actual = resolutions.map(\.actualCompletedValue).reduce(0, +)
            return SkillSeries(
                statKey: stat.key,
                name: stat.name,
                color: TrainingArcConfig.color(for: stat.colorToken),
                points: points,
                effortRatio: expected > 0 ? actual / expected : 0,
                isFocus: false
            )
        }

        // Roughly the top third, so the highlight stays meaningful whether the
        // user tracks three skills or nine.
        let ranked = built.sorted { $0.effortRatio > $1.effortRatio }
        let focusCount = max(1, min(3, (ranked.count + 2) / 3))
        var focusKeys = Set(ranked.prefix(focusCount).filter { $0.effortRatio > 0 }.map(\.statKey))
        // Nothing logged anywhere in the range — no skill got "more" attention,
        // so don't grey every line back for no reason.
        if focusKeys.isEmpty { focusKeys = Set(built.map(\.statKey)) }

        return built.map { series in
            var copy = series
            copy.isFocus = focusKeys.contains(series.statKey)
            return copy
        }
    }

    private func baselinePercent(for resolution: WeeklyResolution) -> Double {
        let baseline = resolution.expectedTotal > 0 ? resolution.expectedTotal : Double(resolution.baselineAtStart)
        guard baseline > 0 else { return resolution.actualCompletedValue > 0 ? 100 : 0 }
        return resolution.actualCompletedValue / baseline * 100
    }

    private var allSkillsSection: some View {
        let series = skillSeries
        let plotted = series.filter { !$0.points.isEmpty }

        return QuietCard(accent: TrainingArcConfig.color(for: "focus")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ALL SKILLS")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Spacer()
                    Text(range.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                Picker("Chart", selection: $chartMode) {
                    ForEach(HistoryChartMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(chartMode.caption)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if plotted.isEmpty {
                    Text("No resolved weeks in this range yet.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .frame(height: 120, alignment: .center)
                        .frame(maxWidth: .infinity)
                } else {
                    combinedChart(plotted)
                    Divider().overlay(TrainingTheme.border.opacity(0.5))
                    DisclosureGroup("Effort by skill") {
                        attentionRanking(plotted)
                    }
                }
            }
        }
    }

    /// One drawn point, with its styling already resolved. Flattening the
    /// series into this before the `Chart` builder keeps every mark expression
    /// small — the nested ForEach with inline ternaries per mark was more than
    /// the type checker would take.
    private struct PlotPoint: Identifiable {
        let id: String
        let seriesName: String
        let date: Date
        let value: Double
        let color: Color
        let lineWidth: Double
        let symbolSize: Double
    }

    private func plotPoints(_ series: [SkillSeries]) -> [PlotPoint] {
        series.flatMap { skill -> [PlotPoint] in
            let color = skill.color.opacity(skill.isFocus ? 1 : 0.22)
            let lineWidth: Double = skill.isFocus ? 2.4 : 1
            // A one-week range draws no line at all, so single-point series get
            // a dot even when they aren't highlighted.
            let symbolSize: Double = skill.isFocus ? 26 : (skill.points.count == 1 ? 18 : 0)
            let mode = chartMode
            return skill.points.map { point in
                PlotPoint(
                    id: point.id,
                    seriesName: skill.name,
                    date: point.weekStart,
                    value: point.value(for: mode),
                    color: color,
                    lineWidth: lineWidth,
                    symbolSize: symbolSize
                )
            }
        }
    }

    private func yDomain(_ series: [SkillSeries]) -> ClosedRange<Double> {
        switch chartMode {
        case .levels:
            return 1...Double(TrainingArcConfig.maximumRankLevel)
        case .baselineShare:
            let peak = series.flatMap(\.points).map(\.baselinePercent).max() ?? 100
            return 0...max(peak * 1.1, 120)
        }
    }

    private func yAxisLabel(_ raw: Double?) -> String {
        guard let raw else { return "" }
        return chartMode == .levels ? "LV \(Int(raw))" : "\(Int(raw))%"
    }

    private func combinedChart(_ series: [SkillSeries]) -> some View {
        let marks = plotPoints(series)
        let symbols = marks.filter { $0.symbolSize > 0 }
        // Levels hold flat and then jump on resolution night — interpolating
        // them would draw a rise that never happened. Percentages join straight
        // for the same reason: a curve through weekly totals invents peaks
        // between the weeks it's drawn from.
        let interpolation: InterpolationMethod = chartMode == .levels ? .stepEnd : .linear

        return Chart {
            ForEach(marks) { mark in
                LineMark(
                    x: .value("Week", mark.date, unit: .weekOfYear),
                    y: .value("Value", mark.value),
                    series: .value("Skill", mark.seriesName)
                )
                .foregroundStyle(mark.color)
                .lineStyle(StrokeStyle(lineWidth: mark.lineWidth, lineCap: .round, lineJoin: .round))
                .interpolationMethod(interpolation)
            }

            ForEach(symbols) { mark in
                PointMark(
                    x: .value("Week", mark.date, unit: .weekOfYear),
                    y: .value("Value", mark.value)
                )
                .foregroundStyle(mark.color)
                .symbolSize(mark.symbolSize)
            }

            if chartMode == .baselineShare {
                RuleMark(y: .value("Baseline", 100))
                    .foregroundStyle(TrainingTheme.textSecondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    // Trailing put the label half outside the plot and it
                    // clipped to "Basel…" — leading keeps it inside.
                    .annotation(position: .top, alignment: .leading) {
                        Text("Baseline")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
            }
        }
        .frame(height: 230)
        .chartYScale(domain: yDomain(series))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(TrainingTheme.border.opacity(0.5))
                AxisValueLabel {
                    Text(yAxisLabel(value.as(Double.self)))
                        .font(.caption2)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(TrainingTheme.border.opacity(0.35))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartLegend(.hidden)
    }

    /// Doubles as the chart's legend and as the answer to "which skills did I
    /// actually give effort to?" — same colors, same highlight, ordered by
    /// effort. Tapping a row drives the per-skill section below.
    private func attentionRanking(_ series: [SkillSeries]) -> some View {
        let ranked = series.sorted { $0.effortRatio > $1.effortRatio }
        let peak = max(ranked.first?.effortRatio ?? 0, 0.01)

        return VStack(alignment: .leading, spacing: 8) {
            Text("MOST EFFORT THIS RANGE")
                .font(.caption2.weight(.heavy))
                .tracking(1.6)
                .foregroundStyle(TrainingTheme.textMuted)

            ForEach(ranked) { skill in
                Button {
                    selectedStatKey = skill.statKey
                    showsSkillDetail = true
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(skill.color.opacity(skill.isFocus ? 1 : 0.3))
                            .frame(width: 8, height: 8)
                        Text(skill.name)
                            .font(.subheadline.weight(skill.isFocus ? .semibold : .regular))
                            .foregroundStyle(skill.isFocus ? TrainingTheme.textPrimary : TrainingTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(TrainingTheme.border.opacity(0.35))
                                .frame(height: 5)
                            Capsule()
                                .fill(skill.color.opacity(skill.isFocus ? 1 : 0.3))
                                .frame(width: 74 * min(skill.effortRatio / peak, 1), height: 5)
                        }
                        .frame(width: 74)
                        Text("\(Int((skill.effortRatio * 100).rounded()))%")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(skill.isFocus ? TrainingTheme.textPrimary : TrainingTheme.textMuted)
                            .frame(width: 46, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(skill.name), \(Int((skill.effortRatio * 100).rounded()))% of baseline this range")
            }

            Text("Percent of each skill's own baseline logged across this range — highlighted skills got the most effort.")
                .font(.caption2)
                .foregroundStyle(TrainingTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct SkillTrendCounts {
        var improved = 0
        var stagnating = 0
        var regressing = 0
    }

    private func skillTrendCounts(from summaries: [(stat: StatDomain, resolutions: [WeeklyResolution])]) -> SkillTrendCounts {
        var counts = SkillTrendCounts()
        for (_, resolutions) in summaries {
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
        }
        return counts
    }

    private var overallSummary: some View {
        let totalLogs = logsInRange.count
        // `resolutionsInRange` is one row per skill per week (7 skills x N
        // weeks), so counting rows overcounts "Weeks" by roughly the active
        // skill count. Count distinct week-start dates instead.
        let weekCount = Set(resolutionsInRange.map(\.weekStartDate)).count
        let counts = skillTrendCounts(from: skillRangeSummaries)
        let improved = counts.improved
        let stagnating = counts.stagnating
        let regressing = counts.regressing

        return QuietCard(accent: TrainingArcConfig.color(for: "focus")) {
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

                // STRONGEST / MOST NEGLECTED used to live here as two names.
                // The all-skills card above now ranks every skill by the same
                // baseline-relative measure, with numbers and the matching
                // chart colors — the two-name version said strictly less.
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

    // WS15: the actual-value bars already carry the skill's accent via
    // `.gradient` below, but a week with zero logged activity draws a
    // zero-height bar — invisible — leaving only the neutral baseline
    // reference line on screen, which is what read as "flat dark ink on a
    // bare grid". Rather than tint the baseline line itself (it's
    // deliberately neutral so it reads as a reference, not another data
    // series, against the accent-colored actual bars), a soft accent wash
    // behind the whole plot keeps the skill's identity present even when
    // that week's bar has nothing to show.
    private func statChart(for stat: StatDomain) -> some View {
        let accent = TrainingArcConfig.color(for: stat.colorToken)
        let chartData = (stat.weeklyResolutions ?? [])
            .filter { rangeInterval.contains($0.weekStartDate) }
            .sorted { $0.weekStartDate < $1.weekStartDate }

        return QuietCard(accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: stat.iconName)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(accent)
                    Text(stat.name.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(accent)
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
                            .foregroundStyle(accent.gradient)
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
                    .chartPlotStyle { plotContent in
                        plotContent.background(
                            LinearGradient(
                                colors: [accent.opacity(0.10), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }
        }
    }

    private func statSummary(for stat: StatDomain) -> some View {
        let trend = trendInsight(for: stat)
        let accent = TrainingArcConfig.color(for: stat.colorToken)
        return QuietCard {
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
                QuietCard {
                    Text("No resolved weeks in this range yet.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            } else {
                ForEach(recent) { resolution in
                    QuietCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(WeekRange(start: resolution.weekStartDate, end: resolution.weekEndDate).displayTitle)
                                    .font(.subheadline.weight(.semibold))
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
