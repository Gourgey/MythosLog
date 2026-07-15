import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @Query private var stats: [StatDomain]
    @Query(sort: \WeeklyResolution.weekStartDate, order: .reverse) private var resolutions: [WeeklyResolution]
    @Query private var settingsRecords: [AppSettings]
    @State private var detailWeekStart: Date?
    @State private var showExplainer = false
    @AppStorage("weeklyReview.hasSeenExplainer") private var hasSeenExplainer = false

    init() {}

    private var settings: AppSettings? { settingsRecords.first }

    private var activeStats: [StatDomain] {
        stats
            .filter(\.isActive)
            .sorted {
                if $0.sortOrder == $1.sortOrder { return $0.name < $1.name }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private var latestResolvedWeekStart: Date? {
        resolutions.first?.weekStartDate
    }

    private var resolvedWeekStarts: [Date] {
        Array(Set(resolutions.map(\.weekStartDate))).sorted(by: >)
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
                VStack(alignment: .leading, spacing: 22) {
                    reviewPageHeader
                    thisWeekSection
                    lastWeekSection
                    pastReviewsLink
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 118)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detailWeekStart) { weekStart in
            WeeklyReviewDetailView(weekStart: weekStart)
        }
        .sheet(isPresented: $showExplainer) {
            NavigationStack {
                WeeklyReviewExplainerSheet()
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            if !hasSeenExplainer, latestResolvedWeekStart != nil {
                showExplainer = true
                hasSeenExplainer = true
            }
        }
    }

    private var reviewPageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            V4PageKicker(title: "Weekly Diagnostic")
        }
    }

    // MARK: - This Week

    private var currentReviewItems: [ReviewSkillItem] {
        activeStats
            .map { stat in
                let snapshot = TrainingStore.progressSnapshot(for: stat, settings: settings)
                let remaining = max(Double(snapshot.baseline) - snapshot.currentWeekActual, 0)
                let urgency = reviewUrgency(for: snapshot)
                return ReviewSkillItem(stat: stat, snapshot: snapshot, remaining: remaining, urgency: urgency)
            }
            .sorted { lhs, rhs in
                if lhs.urgency != rhs.urgency { return lhs.urgency.sortOrder < rhs.urgency.sortOrder }
                if lhs.remaining != rhs.remaining { return lhs.remaining > rhs.remaining }
                return lhs.stat.name < rhs.stat.name
            }
    }

    // These three previously mixed two independent axes: `skillsBehindCount`
    // was pacing-based (this week's progress-to-target) while
    // `skillsAtRegressionRiskCount` was charge-based (accumulated across
    // weeks) — a skill on pace *this* week can still carry enough negative
    // charge from past weeks to be a regression risk, so the two aren't
    // nested and the three tiles didn't sum to the total skill count.
    // `reviewUrgency` already assigns each item to exactly one bucket
    // (regressionRisk checked first, then behindPace, then steady/complete)
    // — deriving all three counts from that single classification instead
    // makes them genuinely disjoint and guarantees they sum to the total.
    private var skillsAtRegressionRiskCount: Int {
        currentReviewItems.filter { $0.urgency == .regressionRisk }.count
    }

    private var skillsBehindCount: Int {
        currentReviewItems.filter { $0.urgency == .behindPace }.count
    }

    private var skillsOnPaceOrCompleteCount: Int {
        currentReviewItems.filter { $0.urgency == .steady || $0.urgency == .complete }.count
    }

    private var recoveryItems: [ReviewSkillItem] {
        currentReviewItems
            .filter { $0.urgency == .regressionRisk || $0.urgency == .behindPace }
            .prefix(3)
            .map { $0 }
    }

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            V4PageKicker(title: "This Week · Live", accent: TrainingTheme.textMuted)

            if activeStats.isEmpty {
                V4Card {
                    Text("No active skills yet. Start onboarding to begin a week.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            } else {
                thisWeekSummaryCard
                recoveryPlannerCard
                V4Card(padding: 4) {
                    VStack(spacing: 0) {
                        ForEach(Array(currentReviewItems.enumerated()), id: \.element.id) { index, item in
                            currentWeekRow(item)
                            if index < currentReviewItems.count - 1 {
                                Divider()
                                    .overlay(TrainingTheme.border.opacity(0.4))
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private var thisWeekSummaryCard: some View {
        V4Card(accent: summaryAccent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("THIS WEEK")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Spacer()
                    V4StatusPill(text: diagnosticHeadline, tint: summaryAccent, systemImage: diagnosticIcon)
                }

                HStack(alignment: .top, spacing: 0) {
                    V4StatTile(value: V4Style.displayNumber(skillsBehindCount), label: "behind", tint: skillsBehindCount > 0 ? TrainingTheme.warning : TrainingTheme.textPrimary)
                    V4StatTile(value: V4Style.displayNumber(skillsOnPaceOrCompleteCount), label: "on pace", tint: TrainingTheme.textPrimary)
                    V4StatTile(value: V4Style.displayNumber(skillsAtRegressionRiskCount), label: "at risk", tint: skillsAtRegressionRiskCount > 0 ? TrainingTheme.danger : TrainingTheme.textPrimary)
                }

                Text(diagnosticSummaryText)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recoveryPlannerCard: some View {
        V4Card(accent: recoveryItems.isEmpty ? TrainingTheme.cold : TrainingTheme.warning) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("NEXT MOVES")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Spacer()
                    Image(systemName: recoveryItems.isEmpty ? "checkmark.circle.fill" : "arrow.triangle.turn.up.right.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(recoveryItems.isEmpty ? TrainingTheme.positiveStrong : TrainingTheme.warning)
                }

                if recoveryItems.isEmpty {
                    Text("No recovery task is urgent. Keep logging normally to protect your current ranks.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(recoveryItems) { item in
                            recoveryTaskRow(item)
                        }
                    }
                }
            }
        }
    }

    private func recoveryTaskRow(_ item: ReviewSkillItem) -> some View {
        let accent = TrainingArcConfig.color(for: item.stat.colorToken)
        return Button {
            openSkill(item.stat, openLogSheet: true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.urgency.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(accent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.stat.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text(taskText(for: item))
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(logActionTitle(for: item.stat))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent.opacity(0.12)))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.66))
            )
        }
        .buttonStyle(.plain)
    }

    private func currentWeekRow(_ item: ReviewSkillItem) -> some View {
        let stat = item.stat
        let snapshot = item.snapshot
        let accent = TrainingArcConfig.color(for: stat.colorToken)

        return Button {
            openSkill(stat, openLogSheet: false)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: stat.iconName)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.name)
                        .font(.system(.headline, design: .serif).weight(.regular))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text(progressLine(for: item))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 8)

                V4StatusPill(text: item.urgency.label(for: snapshot.pacingStatus), tint: item.urgency.tint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var summaryAccent: Color {
        if skillsAtRegressionRiskCount > 0 { return TrainingTheme.danger }
        if skillsBehindCount > 0 { return TrainingTheme.warning }
        return TrainingTheme.cold
    }

    private var diagnosticHeadline: String {
        if skillsAtRegressionRiskCount > 0 { return "At risk" }
        if skillsBehindCount > 0 { return "Behind" }
        return "On Track"
    }

    private var diagnosticIcon: String {
        if skillsAtRegressionRiskCount > 0 { return "exclamationmark.triangle.fill" }
        if skillsBehindCount > 0 { return "clock.badge.exclamationmark" }
        return "checkmark.circle.fill"
    }

    private var diagnosticSummaryText: String {
        if let risk = currentReviewItems.first(where: { $0.urgency == .regressionRisk }) {
            return "\(risk.stat.name) is closest to ranking down. Stabilize it before adding extra stretch work."
        }
        if let behind = currentReviewItems.first(where: { $0.urgency == .behindPace }) {
            return "\(behind.stat.name) is furthest behind this week. \(taskText(for: behind))"
        }
        return "No skill is behind or at risk. Keep the baseline rhythm steady."
    }

    private func reviewUrgency(for snapshot: SkillProgressSnapshot) -> ReviewSkillUrgency {
        if snapshot.pendingRankChange?.direction == .down ||
            (snapshot.charge.current <= -2 && snapshot.rank.level > TrainingArcConfig.minimumRankLevel) {
            return .regressionRisk
        }

        if snapshot.pacingStatus == .behind {
            return .behindPace
        }

        if snapshot.currentWeekActual >= Double(snapshot.baseline) {
            return .complete
        }

        return .steady
    }

    private func progressLine(for item: ReviewSkillItem) -> String {
        let unit = TrainingStore.weeklyUnitLabel(for: item.stat)
        return "\(item.snapshot.weeklyTargetFractionLabel) \(unit) · \(neededText(for: item))"
    }

    private func neededText(for item: ReviewSkillItem) -> String {
        guard item.remaining > 0 else { return "baseline complete" }
        return "needs \(MetricFormatting.shortMetric(item.remaining)) more"
    }

    private func taskText(for item: ReviewSkillItem) -> String {
        let unit = TrainingStore.weeklyUnitLabel(for: item.stat)
        guard item.remaining > 0 else {
            return "Baseline complete; keep this skill steady through the week."
        }
        return "\(MetricFormatting.shortMetric(item.remaining)) \(unit) still needed to protect Level \(item.snapshot.rank.level)."
    }

    private func logActionTitle(for stat: StatDomain) -> String {
        TrainingStore.primaryHabit(for: stat)?.measurementType == .booleanSession ? "Log" : "Update"
    }

    private func openSkill(_ stat: StatDomain, openLogSheet: Bool) {
        guard let statKey = stat.statKey else { return }
        router.open(
            PendingAppDestination(
                skillDetail: PendingSkillDestination(
                    statKeyRaw: statKey.rawValue,
                    openLogSheet: openLogSheet
                )
            )
        )
    }

    // MARK: - Last Week

    @ViewBuilder
    private var lastWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let latestResolvedWeekStart {
                    V4PageKicker(
                        title: "Last Week · \(WeekMath.weekRange(startingAt: latestResolvedWeekStart).displayTitle)",
                        accent: TrainingTheme.textMuted
                    )
                } else {
                    V4PageKicker(title: "Last Week", accent: TrainingTheme.textMuted)
                }
                Spacer()
                Button {
                    showExplainer = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
                .accessibilityLabel("How weekly review works")
            }

            if let latestResolvedWeekStart {
                resolvedSummaryCard(weekStart: latestResolvedWeekStart)
            } else {
                V4Card {
                    Text("No resolved weeks yet. Your previous week will appear here automatically after Sunday at midnight.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }
        }
    }

    private func resolvedSummaryCard(weekStart: Date) -> some View {
        let weekResolutions = resolutions
            .filter { $0.weekStartDate == weekStart }
            .sorted { $0.statName < $1.statName }
        let verdict = computeVerdict(weekResolutions)
        let levelUps = weekResolutions.filter(\.didLevelUp).count
        let regressed = weekResolutions.filter(\.didRegress).count
        let belowBaseline = weekResolutions.filter { $0.weeklyDelta < 0 }.count

        return Button {
            detailWeekStart = weekStart
        } label: {
            V4Card(padding: 16, accent: verdict.color) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(verdict.color.opacity(0.14))
                                .frame(width: 44, height: 44)
                            Image(systemName: verdict.icon)
                                .font(.headline.weight(.black))
                                .foregroundStyle(verdict.color)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            V4SerifTitle(text: verdict.rawValue, size: 23)
                            if belowBaseline > 0 {
                                Text("\(belowBaseline) \(belowBaseline == 1 ? "skill needs" : "skills need") recovery")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(verdict.color)
                            } else {
                                Text("\(weekResolutions.count) \(weekResolutions.count == 1 ? "skill" : "skills") resolved")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(verdict.color)
                            }
                        }

                        Spacer()
                    }

                    Text(verdict.description)
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if belowBaseline > 0 {
                        recoveryChipStrip(for: weekResolutions, verdict: verdict)
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            V4StatTile(value: V4Style.displayNumber(weekResolutions.count), label: "Resolved", tint: TrainingTheme.textPrimary)
                            if levelUps > 0 {
                                V4StatTile(value: V4Style.displayNumber(levelUps), label: "Rank ups", tint: TrainingTheme.positiveStrong)
                            }
                            if regressed > 0 {
                                V4StatTile(value: V4Style.displayNumber(regressed), label: "Drops", tint: TrainingTheme.danger)
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Text(belowBaseline > 0 ? "View Recovery Tasks" : "View Weekly Breakdown")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(verdict.color)
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func recoveryChipStrip(for resolutions: [WeeklyResolution], verdict: VerdictDescriptor) -> some View {
        let allLostSkills = resolutions.filter { $0.weeklyDelta < 0 }
        let visibleLostSkills = Array(allLostSkills.prefix(4))
        let remainingCount = max(allLostSkills.count - visibleLostSkills.count, 0)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Recover these this week to rebuild charge before they rank down.")
                .font(.caption)
                .foregroundStyle(TrainingTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(visibleLostSkills, id: \.id) { resolution in
                    recoveryChip(resolution: resolution)
                }
                if remainingCount > 0 {
                    recoveryMoreChip(count: remainingCount, tint: verdict.color)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func recoveryChip(resolution: WeeklyResolution) -> some View {
        let stat = activeStats.first(where: { $0.name == resolution.statName })
        let accent: Color = stat.map { TrainingArcConfig.color(for: $0.colorToken) } ?? TrainingTheme.warning
        let iconName: String = stat?.iconName ?? "circle"

        return VStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
            Text(resolution.statName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 0.8)
        )
    }

    private func recoveryMoreChip(count: Int, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
            Text("+\(count) more")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 0.8)
        )
    }

    // MARK: - Past Reviews

    @ViewBuilder
    private var pastReviewsLink: some View {
        if resolvedWeekStarts.count > 1 {
            NavigationLink {
                WeeklyReviewHistoryView(
                    weekStarts: resolvedWeekStarts,
                    resolutions: resolutions
                ) { weekStart in
                    detailWeekStart = weekStart
                }
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.bold))
                    Text("View past reviews")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(TrainingTheme.textSecondary)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(TrainingTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(TrainingTheme.borderStrong.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Verdict helper

    fileprivate struct VerdictDescriptor {
        let rawValue: String
        let color: Color
        let description: String
        let icon: String
    }

    private func computeVerdict(_ resolutions: [WeeklyResolution]) -> VerdictDescriptor {
        guard !resolutions.isEmpty else {
            return VerdictDescriptor(rawValue: "Held Form", color: TrainingTheme.cold, description: "Baselines maintained across the board.", icon: "shield.lefthalf.filled")
        }
        let levelUps = resolutions.filter(\.didLevelUp).count
        let regressed = resolutions.filter(\.didRegress).count
        let belowBaseline = resolutions.filter { $0.weeklyDelta < 0 }.count
        let aboveBaseline = resolutions.filter { $0.weeklyDelta > 0 }.count

        if regressed > 0 {
            return VerdictDescriptor(rawValue: "At Risk", color: TrainingTheme.danger, description: "Skills ranked down or are close to dropping.", icon: "arrow.down.right.circle.fill")
        }
        if levelUps > 0, belowBaseline == 0 {
            return VerdictDescriptor(rawValue: "Advanced", color: TrainingTheme.positiveStrong, description: "Skills moved forward this week.", icon: "arrow.up.right.circle.fill")
        }
        if belowBaseline > resolutions.count / 2 {
            return VerdictDescriptor(rawValue: "Lost Momentum", color: TrainingTheme.warning, description: "Most skills landed below baseline.", icon: "arrow.down.right")
        }
        if aboveBaseline > 0, belowBaseline > 0 {
            return VerdictDescriptor(rawValue: "Mixed Week", color: TrainingTheme.warning, description: "Some skills advanced, others slipped.", icon: "arrow.up.arrow.down")
        }
        return VerdictDescriptor(rawValue: "Held Form", color: TrainingTheme.cold, description: "Baselines maintained across the board.", icon: "shield.lefthalf.filled")
    }
}

private enum ReviewSkillUrgency: Equatable {
    case regressionRisk
    case behindPace
    case steady
    case complete

    var sortOrder: Int {
        switch self {
        case .regressionRisk: return 0
        case .behindPace: return 1
        case .steady: return 2
        case .complete: return 3
        }
    }

    var tint: Color {
        switch self {
        case .regressionRisk: return TrainingTheme.danger
        case .behindPace: return TrainingTheme.warning
        case .steady: return TrainingTheme.cold
        case .complete: return TrainingTheme.positiveStrong
        }
    }

    var icon: String {
        switch self {
        case .regressionRisk: return "exclamationmark.triangle.fill"
        case .behindPace: return "clock.badge.exclamationmark"
        case .steady: return "circle.dashed"
        case .complete: return "checkmark.circle.fill"
        }
    }

    func label(for pacing: SkillPacingStatus) -> String {
        switch self {
        case .regressionRisk: return "At risk"
        case .behindPace: return "Behind"
        case .steady: return pacing.label
        case .complete: return "Complete"
        }
    }
}

private struct ReviewSkillItem: Identifiable {
    let stat: StatDomain
    let snapshot: SkillProgressSnapshot
    let remaining: Double
    let urgency: ReviewSkillUrgency

    var id: UUID { stat.id }
}

// MARK: - History list

struct WeeklyReviewHistoryView: View {
    let weekStarts: [Date]
    let resolutions: [WeeklyResolution]
    let onSelect: (Date) -> Void

    var body: some View {
        List {
            ForEach(weekStarts, id: \.self) { weekStart in
                Button {
                    onSelect(weekStart)
                } label: {
                    historyRow(for: weekStart)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Past Reviews")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyRow(for weekStart: Date) -> some View {
        let weekResolutions = resolutions.filter { $0.weekStartDate == weekStart }
        let title = WeekMath.weekRange(startingAt: weekStart).displayTitle
        let levelUps = weekResolutions.filter(\.didLevelUp).count
        let regressed = weekResolutions.filter(\.didRegress).count

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("\(weekResolutions.count) skills · \(levelUps) up · \(regressed) down")
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TrainingTheme.textMuted)
        }
    }
}

// MARK: - Explainer

struct WeeklyReviewExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explainerSection(
                    icon: "calendar.badge.checkmark",
                    title: "How weekly review works",
                    body: "Each week your skill logs roll into a weekly stat. When the week ends, the app calculates whether each skill met its baseline and whether any ranks should change."
                )

                explainerSection(
                    icon: "moon.zzz.fill",
                    title: "Automatic at midnight Sunday",
                    body: "Every Sunday at midnight your previous week is finalized. Rank changes apply on their own — there's nothing to press."
                )

                explainerSection(
                    icon: "sparkles",
                    title: "Rank changes",
                    body: "If a skill ranked up or down, the new character appears on the Dashboard the next time you open the app. You'll see the change as it happens."
                )

                explainerSection(
                    icon: "list.bullet.rectangle",
                    title: "After it's locked in",
                    body: "You'll see a verdict (Advanced, Held Form, Mixed Week, etc.), a recap of your best/worst skills, and a per-skill breakdown. Tap any past week to revisit it."
                )
            }
            .padding(20)
        }
        .navigationTitle("How review works")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func explainerSection(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(TrainingArcConfig.color(for: "focus"))
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(TrainingArcConfig.color(for: "focus").opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }
}
