import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum DashboardTopMenuState {
    case none
    case layout
    case insights
}

private struct IdentifiableStat: Identifiable {
    let stat: StatDomain
    var id: UUID { stat.id }
}

private struct HoneycombWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var router: AppRouter
    @Query private var stats: [StatDomain]
    @Query private var settingsRecords: [AppSettings]
    @State private var presentedLogDraft: LogEntryDraft?
    @State private var flashedStatID: UUID?
    @State private var topMenuState: DashboardTopMenuState = .none
    @State private var presentedInsight: DashboardInsightOption?
    @State private var isReordering = false
    @State private var draggedStatID: UUID?
    @State private var isSyncingHealth = false
    @State private var healthStatusMessage = ""
    @State private var isShowingHealthStatus = false
    @State private var habitPickerStat: IdentifiableStat?
    @State private var unmatchedStat: IdentifiableStat?
    @State private var showingRankReview = false
    @State private var showingStatsSheet = false
    @State private var honeycombAvailableWidth: CGFloat = 380
    private let compactGridColumnCount = 2
    private let compactGridSpacing: CGFloat = 16
    private let gameGridColumnCount = 3
    private let gameGridSpacing: CGFloat = 4
    private let gameGridRowSpacing: CGFloat = 12

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var activeStats: [StatDomain] {
        stats
            .filter { $0.isActive }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name < $1.name
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private var pendingRankChanges: [StatDomain] {
        activeStats.filter { $0.pendingRankChange != nil }
    }

    private var dashboardLayoutMode: DashboardLayoutMode {
        settings?.dashboardLayoutMode ?? .gameGrid
    }

    private var displayedLayoutMode: DashboardLayoutMode {
        dashboardLayoutMode
    }

    private var focusTargetID: UUID? {
        // Compute each stat's snapshot exactly once. The previous form built a
        // fresh snapshot inside both the filter and each `focusPriority` call,
        // and callers evaluated this property per grid tile — so a dashboard of
        // n skills paid ~3n^2 snapshot computations per render.
        activeStats
            .compactMap { stat -> (id: UUID, priority: Double)? in
                let itemSnapshot = snapshot(for: stat)
                guard !itemSnapshot.rank.isAtMaximumRank else { return nil }
                return (stat.id, focusPriority(from: itemSnapshot))
            }
            .max { $0.priority < $1.priority }?
            .id
    }

    private var dashboardChromeAccent: Color {
        switch topMenuState {
        case .layout:
            return TrainingArcConfig.color(for: "focus")
        case .insights:
            return TrainingTheme.warning
        case .none:
            return TrainingArcConfig.color(for: "creativity")
        }
    }

    var body: some View {
        dashboardMainContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                try? TrainingStore.refreshAllProgress(context: modelContext, reason: .appRefresh)
                try? TrainingStore.refreshWidgetSnapshot(context: modelContext)
            }
            .modifier(
                DashboardPresentationModifier(
                    presentedLogDraft: $presentedLogDraft,
                    presentedInsight: $presentedInsight,
                    isShowingHealthStatus: $isShowingHealthStatus,
                    healthStatusMessage: healthStatusMessage,
                    habitPickerStat: $habitPickerStat,
                    unmatchedStat: $unmatchedStat,
                    settings: settings,
                    modelContext: modelContext,
                    onLogSaved: saveLog
                )
            )
            .sheet(isPresented: $showingRankReview) {
                NavigationStack {
                    RankChangesReviewView(stats: pendingRankChanges) { stat in
                        showingRankReview = false
                        openDetail(for: stat)
                    }
                }
            }
            .sheet(isPresented: $showingStatsSheet) {
                statsSheet
            }
    }

    private var dashboardMainContent: some View {
        ZStack {
            dashboardBackdrop

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    commandStrip

                    if isReordering {
                        reorderBanner
                    }

                    if activeStats.isEmpty {
                        dashboardEmptyState
                    } else {
                        // Skills-only first view — the circles are the priority.
                        // Standings, rank & charge, and goals live in the "This
                        // week" sheet opened from the header chip.
                        switch displayedLayoutMode {
                        case .detailedCards:
                            detailedDashboard
                        case .compactGrid:
                            compactGridDashboard
                        case .gameGrid:
                            gameGridDashboard
                        }

                        if !pendingRankChanges.isEmpty {
                            rankReviewBanner
                                .padding(.horizontal, displayedLayoutMode == .gameGrid ? 14 : 0)
                        }
                    }
                }
                .padding(.horizontal, displayedLayoutMode == .gameGrid ? 2 : 16)
                .padding(.top, 4)
                .padding(.bottom, 118)
            }
            .coordinateSpace(name: "dashboardScroll")
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [
                    TrainingTheme.background.opacity(0.98),
                    TrainingTheme.background.opacity(0.82),
                    TrainingTheme.background.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var todayKicker: some View {
        let formatted = dynamicTypeSize.isAccessibilitySize
            ? Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return V4PageKicker(title: formatted)
    }

    private var statsChip: some View {
        Button {
            if settings?.hapticsEnabled ?? true {
                HapticsService.impact(style: .light)
            }
            showingStatsSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption2.weight(.bold))
                Text("This week")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(TrainingTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(TrainingTheme.actionSurface))
            .overlay(
                Capsule().strokeBorder(TrainingTheme.borderStrong.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("This week's standing, rank, and goals")
    }

    private var statsSheet: some View {
        NavigationStack {
            ScrollView {
                dashboardSectionsView
                    .padding(16)
            }
            .background(TrainingTheme.background.ignoresSafeArea())
            .navigationTitle("This Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingStatsSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var commandStrip: some View {
        VStack(spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        todayKicker
                        Spacer(minLength: 8)
                        dashboardControlButtons
                    }

                    if !activeStats.isEmpty {
                        statsChip
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    todayKicker

                    if !activeStats.isEmpty {
                        statsChip
                    }

                    Spacer(minLength: 8)
                    dashboardControlButtons
                }
            }

            HStack(alignment: .top, spacing: 12) {
                if topMenuState == .layout {
                    commandMenu {
                        ForEach([DashboardLayoutMode.gameGrid, .compactGrid, .detailedCards]) { mode in
                            menuButton(
                                title: mode.displayName,
                                icon: layoutMenuIcon(for: mode),
                                isSelected: dashboardLayoutMode == mode
                            ) {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                    try? TrainingStore.setDashboardLayoutMode(mode, context: modelContext)
                                    isReordering = false
                                    topMenuState = .none
                                }
                            }
                        }

                        menuButton(title: "Reorder", icon: "arrow.up.arrow.down", isSelected: isReordering) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                isReordering.toggle()
                                topMenuState = .none
                            }
                        }

                        #if canImport(HealthKit)
                        menuButton(
                            title: isSyncingHealth ? "Syncing Apple Health…" : "Sync Apple Health",
                            icon: isSyncingHealth ? "heart.circle.fill" : "heart.fill",
                            isSelected: false
                        ) {
                            syncHealthWorkouts()
                        }
                        #endif
                    }
                } else {
                    Spacer(minLength: 0)
                }

                if topMenuState == .insights {
                    commandMenu {
                        ForEach(DashboardInsightOption.allCases) { option in
                            menuButton(title: option.title, icon: option.systemImage, isSelected: false) {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                    presentedInsight = option
                                    topMenuState = .none
                                }
                            }
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: topMenuState)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TrainingTheme.card.opacity(0.98),
                            .white.opacity(0.86),
                            TrainingTheme.elevatedCard.opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            dashboardChromeAccent.opacity(0.28),
                            .white.opacity(0.70),
                            TrainingTheme.borderStrong.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
        .shadow(color: dashboardChromeAccent.opacity(0.10), radius: 10, x: 0, y: 5)
    }

    private var dashboardEmptyState: some View {
        V4Card(accent: TrainingArcConfig.color(for: "focus")) {
            VStack(alignment: .leading, spacing: 10) {
                V4SerifTitle(text: "No skills yet", size: 24)
                Text("Run through onboarding (or Reset Default Profile in Settings → Debug Tools) to set baselines for your core skills.")
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }

    private var dashboardControlButtons: some View {
        HStack(spacing: 10) {
            commandButton(icon: "line.3.horizontal", isActive: topMenuState == .layout, accessibilityLabel: "Dashboard layout") {
                toggleMenu(.layout)
            }

            commandButton(icon: "sparkles", isActive: topMenuState == .insights, accessibilityLabel: "Dashboard insights") {
                toggleMenu(.insights)
            }
        }
    }

    private var needsAttentionStatKeys: Set<String> {
        let recs = (try? TrainingStore.trainTodayRecommendations(context: modelContext, settings: settings)) ?? []
        return Set(recs.compactMap { rec in
            rec.reason == .reviewReady ? nil : rec.statKeyRaw
        })
    }

    private var awaitingAttributionStatKeys: Set<String> {
        (try? TrainingStore.awaitingAttributionStatKeys(context: modelContext)) ?? []
    }

    private var rankReviewBanner: some View {
        let ups = pendingRankChanges.filter { $0.pendingRankChange?.direction == .up }.count
        let downs = pendingRankChanges.count - ups
        return Button {
            showingRankReview = true
        } label: {
            V4Card(accent: TrainingTheme.positiveStrong) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(TrainingTheme.positiveStrong.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: "rosette")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(TrainingTheme.positiveStrong)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rank changes to review")
                            .font(.system(.headline, design: .serif).weight(.regular))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        HStack(spacing: 8) {
                            if ups > 0 {
                                V4StatusPill(text: "\(ups) up", tint: TrainingTheme.positiveStrong, systemImage: "arrow.up")
                            }
                            if downs > 0 {
                                V4StatusPill(text: "\(downs) down", tint: TrainingTheme.danger, systemImage: "arrow.down")
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TrainingTheme.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dashboard sections (Phase 7)

    @ViewBuilder
    private var dashboardSectionsView: some View {
        if let sections = try? TrainingStore.dashboardSections(context: modelContext, settings: settings) {
            VStack(spacing: 14) {
                weeklyStatusCard(sections.weeklyStatus)

                if !sections.highlights.isEmpty {
                    highlightsCard(sections.highlights)
                }

                if sections.goals.hasAnyGoals {
                    goalsSummaryCard(sections.goals)
                }
            }
        }
    }

    @ViewBuilder
    private func weeklyStatusCard(_ status: DashboardWeeklyStatus) -> some View {
        if status.kind == .reviewReady {
            Button {
                router.open(PendingAppDestination(route: .weeklyReview))
            } label: {
                weeklyStatusCardBody(status)
            }
            .buttonStyle(.plain)
        } else {
            weeklyStatusCardBody(status)
        }
    }

    private func weeklyStatusCardBody(_ status: DashboardWeeklyStatus) -> some View {
        let style = weeklyStatusStyle(status.kind)
        let total = max(status.aheadCount + status.onPaceCount + status.behindCount, 1)
        return V4Card(accent: style.color) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Text("WEEKLY STANDING")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Spacer()
                    V4StatusPill(text: status.headline, tint: style.color, systemImage: style.icon)
                    if status.kind == .reviewReady {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(TrainingTheme.textMuted)
                    }
                }

                Divider()
                    .overlay(TrainingTheme.border.opacity(0.5))

                GeometryReader { proxy in
                    HStack(spacing: 4) {
                        weeklyBarSegment(
                            color: TrainingTheme.positiveStrong,
                            count: status.aheadCount,
                            total: total,
                            fullWidth: proxy.size.width
                        )
                        weeklyBarSegment(
                            color: TrainingTheme.textMuted,
                            count: status.onPaceCount,
                            total: total,
                            fullWidth: proxy.size.width
                        )
                        weeklyBarSegment(
                            color: TrainingTheme.warning,
                            count: status.behindCount,
                            total: total,
                            fullWidth: proxy.size.width
                        )
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .frame(height: 10)

                HStack(alignment: .top, spacing: 0) {
                    weeklyStandingCount(label: "ahead", value: status.aheadCount, tint: TrainingTheme.positiveStrong)
                    weeklyStandingCount(label: "on pace", value: status.onPaceCount, tint: TrainingTheme.textPrimary)
                    weeklyStandingCount(label: "behind", value: status.behindCount, tint: TrainingTheme.warning, alignment: .trailing)
                }
            }
        }
    }

    private func weeklyBarSegment(color: Color, count: Int, total: Int, fullWidth: CGFloat) -> some View {
        let fraction = Double(count) / Double(total)
        let raw = fullWidth * fraction - (count > 0 ? 4 : 0)
        let width = count > 0 ? max(raw, 18) : 0
        return Capsule()
            .fill(count > 0 ? color : color.opacity(0.0))
            .frame(width: width, height: 10)
    }

    private func weeklyStandingCount(label: String, value: Int, tint: Color, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(V4Style.displayNumber(value))
                .font(.system(.title2, design: .serif).weight(.regular))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: alignmentToFrame(alignment))
    }

    private func alignmentToFrame(_ horizontal: HorizontalAlignment) -> Alignment {
        switch horizontal {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    private func weeklyStatusStyle(_ kind: DashboardWeeklyStatus.Kind) -> (color: Color, icon: String) {
        switch kind {
        case .reviewReady:
            return (TrainingTheme.warning, "calendar.badge.clock")
        case .ahead:
            return (TrainingTheme.positiveStrong, "chart.line.uptrend.xyaxis")
        case .onPace:
            return (TrainingTheme.cold, "checkmark.circle.fill")
        case .atRisk:
            return (TrainingTheme.warning, "exclamationmark.triangle.fill")
        case .noActivity:
            return (TrainingTheme.textMuted, "moon.zzz.fill")
        }
    }

    // WS14: highlights can mix kinds (a skill ranking up, another one strong
    // week from ranking up, another close to a drop) — the card used to show
    // one pill for whichever kind sorted first and then repeat that kind's
    // fixed sentence on every row of that kind ("At risk — close to ranking
    // down" 4 times over). Grouping by kind states each shared fact once, in
    // its group header, and drops the per-row repeat — except .rankedUp,
    // whose text varies per skill ("Ranked up to X") and stays on the row.
    private func highlightsCard(_ highlights: [DashboardHighlight]) -> some View {
        let visible = Array(highlights.prefix(4))
        let orderedKinds: [DashboardHighlight.Kind] = [.rankedUp, .nearRankUp, .losingMomentum]
        let groups: [(kind: DashboardHighlight.Kind, items: [DashboardHighlight])] = orderedKinds.compactMap { kind in
            let items = visible.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }

        return V4Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("RANK & CHARGE")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(TrainingTheme.textMuted)

                Divider()
                    .overlay(TrainingTheme.border.opacity(0.5))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                        if groupIndex > 0 {
                            Divider()
                                .overlay(TrainingTheme.border.opacity(0.3))
                        }

                        highlightGroupHeader(group.kind, count: group.items.count)

                        VStack(spacing: 10) {
                            ForEach(group.items) { highlight in
                                Button {
                                    openHighlight(highlight)
                                } label: {
                                    highlightRow(highlight, showsCaption: group.kind == .rankedUp)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Never truncate silently — a card that reads "4 skills
                    // losing momentum" when 3 more are also affected reads
                    // as complete when it isn't.
                    if highlights.count > 4 {
                        Text("+\(highlights.count - 4) more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func highlightGroupHeader(_ kind: DashboardHighlight.Kind, count: Int) -> some View {
        let tint = highlightGroupTint(kind)
        return HStack(spacing: 6) {
            Image(systemName: highlightIcon(kind))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(highlightGroupLabel(kind, count: count))
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
        }
    }

    private func highlightGroupLabel(_ kind: DashboardHighlight.Kind, count: Int) -> String {
        switch kind {
        case .rankedUp:
            return count == 1 ? "Ranked up" : "Ranked up (\(count))"
        case .nearRankUp:
            return "One strong week from ranking up (\(count))"
        case .losingMomentum:
            return "At risk — close to ranking down (\(count))"
        }
    }

    private func highlightGroupTint(_ kind: DashboardHighlight.Kind) -> Color {
        switch kind {
        case .rankedUp: return TrainingTheme.positiveStrong
        case .nearRankUp: return TrainingArcConfig.color(for: "focus")
        case .losingMomentum: return TrainingTheme.warning
        }
    }

    private func highlightRow(_ highlight: DashboardHighlight, showsCaption: Bool) -> some View {
        let accent = TrainingArcConfig.color(for: highlight.colorToken)
        let level = activeStats.first(where: { $0.key == highlight.statKeyRaw })?.rankLevel ?? 0
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: highlightRingTrim(highlight))
                    .stroke(highlightColor(highlight), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                Image(systemName: highlightIcon(highlight.kind))
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(highlightColor(highlight))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(highlight.statName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    if level > 0 {
                        V4LevelBadge(level: level, tint: accent, compact: true)
                    }
                }
                if showsCaption {
                    Text(highlight.text)
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textMuted)
        }
    }

    private func highlightRingTrim(_ highlight: DashboardHighlight) -> Double {
        switch highlight.kind {
        case .rankedUp: return 1.0
        case .nearRankUp: return 0.85
        case .losingMomentum: return 0.30
        }
    }

    private func highlightIcon(_ kind: DashboardHighlight.Kind) -> String {
        switch kind {
        case .rankedUp: "arrow.up.circle.fill"
        case .nearRankUp: "bolt.fill"
        case .losingMomentum: "arrow.down.circle.fill"
        }
    }

    private func highlightColor(_ highlight: DashboardHighlight) -> Color {
        switch highlight.kind {
        case .rankedUp: TrainingTheme.positiveStrong
        case .nearRankUp: TrainingArcConfig.color(for: highlight.colorToken)
        case .losingMomentum: TrainingTheme.warning
        }
    }

    private func openHighlight(_ highlight: DashboardHighlight) {
        guard let statKeyRaw = highlight.statKeyRaw, let statKey = StatKey(rawValue: statKeyRaw) else { return }
        router.open(
            PendingAppDestination(
                skillDetail: PendingSkillDestination(statKeyRaw: statKey.rawValue, openLogSheet: false)
            )
        )
    }

    private func goalsSummaryCard(_ goals: DashboardGoalsSummary) -> some View {
        Button {
            router.open(.goals)
        } label: {
            V4Card(accent: TrainingTheme.cold) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("GOALS")
                            .font(.caption.weight(.heavy))
                            .tracking(2.0)
                            .foregroundStyle(TrainingTheme.textMuted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(TrainingTheme.textMuted)
                    }

                    Divider()
                        .overlay(TrainingTheme.border.opacity(0.5))

                    HStack(alignment: .top, spacing: 0) {
                        V4StatTile(value: V4Style.displayNumber(goals.activeCount), label: "Active", tint: TrainingTheme.textPrimary)
                        V4StatTile(value: V4Style.displayNumber(goals.atRiskCount), label: "At risk", tint: goals.atRiskCount > 0 ? TrainingTheme.warning : TrainingTheme.textPrimary)
                        V4StatTile(value: V4Style.displayNumber(goals.closeToCompletionCount), label: "Close", tint: goals.closeToCompletionCount > 0 ? TrainingTheme.positiveStrong : TrainingTheme.textPrimary)
                        V4StatTile(value: V4Style.displayNumber(goals.completedThisWeekCount), label: "Done", tint: TrainingTheme.textPrimary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var detailedDashboard: some View {
        let attention = needsAttentionStatKeys
        let unmatched = awaitingAttributionStatKeys
        // Evaluate once per render, not once per tile (see focusTargetID).
        let focusID = focusTargetID
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Skills")
            Text("Tap a skill card to open its detail. Use the button on each card to log a session directly.")
                .font(.subheadline)
                .foregroundStyle(TrainingTheme.textSecondary)

            LazyVStack(spacing: 16) {
                ForEach(activeStats) { stat in
                    let itemSnapshot = snapshot(for: stat)
                    let trend = recentTrend(for: stat)
                    let habits = TrainingStore.activeHabits(for: stat)

                    StatCard(
                        stat: stat,
                        snapshot: itemSnapshot,
                        trend: trend,
                        habits: habits,
                        isFocusTarget: stat.id == focusID,
                        showLogFeedback: flashedStatID == stat.id,
                        needsAttention: attention.contains(stat.key),
                        hasUnmatchedImports: unmatched.contains(stat.key),
                        onOpenDetail: {
                            openDetail(for: stat)
                        },
                        onQuickLogTap: { habit, value in
                            presentedLogDraft = LogEntryDraft(habit: habit, value: value)
                        },
                        onShowUnmatched: {
                            unmatchedStat = IdentifiableStat(stat: stat)
                        }
                    )
                    .modifier(ReorderHandleModifier(isVisible: isReordering))
                    .modifier(
                        ReorderDragDropModifier(
                            stat: stat,
                            isReordering: isReordering,
                            draggedStatID: $draggedStatID,
                            orderedStatIDs: activeStats.map(\.id),
                            moveAction: moveSkill
                        )
                    )
                }
            }
        }
    }

    private var compactGridDashboard: some View {
        let attention = needsAttentionStatKeys
        let unmatched = awaitingAttributionStatKeys
        return VStack(alignment: .leading, spacing: 0) {
            CenteredDashboardGridLayout(columns: compactGridColumnCount, spacing: compactGridSpacing) {
                ForEach(activeStats) { stat in
                    compactGridTile(
                        for: stat,
                        needsAttention: attention.contains(stat.key),
                        hasUnmatchedImports: unmatched.contains(stat.key)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var gameGridDashboard: some View {
        let attention = needsAttentionStatKeys
        let unmatched = awaitingAttributionStatKeys

        if activeStats.count == 7 {
            honeycombGameGridDashboard(attention: attention, unmatched: unmatched)
        } else {
            CenteredDashboardGridLayout(columns: gameGridColumnCount, spacing: gameGridSpacing, rowSpacing: gameGridRowSpacing) {
                ForEach(activeStats) { stat in
                    gameDashboardTile(
                        for: stat,
                        needsAttention: attention.contains(stat.key),
                        hasUnmatchedImports: unmatched.contains(stat.key)
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    /// Rows are sized by their own intrinsic content (name + ring + fraction
    /// row + charge meter), never by a guessed fixed height. The previous
    /// version forced each row into a hardcoded `tileWidth + 72` box read by
    /// an inline `GeometryReader`; that estimate quietly fell short of the
    /// tile's real rendered height (worse at larger Dynamic Type sizes), so
    /// the next row started before the previous one's bottom content — its
    /// charge meter — had fully cleared. Reading the available width via
    /// `.background` + a preference key instead of a size-dictating
    /// `GeometryReader` lets the VStack/HStacks size themselves naturally, so
    /// rows can never run short of the space their own content needs — at any
    /// Dynamic Type size. All three rows render at the same scale — no
    /// scroll-driven zoom on the middle row (removed per user request; it
    /// read as an unwanted "magnify" effect rather than a focus cue).
    private func honeycombGameGridDashboard(attention: Set<String>, unmatched: Set<String>) -> some View {
        let tileWidth = honeycombTileWidth(for: honeycombAvailableWidth)
        let rows = honeycombRows

        return VStack(spacing: gameGridRowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowStats in
                HStack(spacing: gameGridSpacing) {
                    ForEach(rowStats) { stat in
                        gameDashboardTile(
                            for: stat,
                            needsAttention: attention.contains(stat.key),
                            hasUnmatchedImports: unmatched.contains(stat.key)
                        )
                        .frame(width: tileWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HoneycombWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(HoneycombWidthPreferenceKey.self) { newWidth in
            if newWidth > 0 { honeycombAvailableWidth = newWidth }
        }
        .padding(.top, 2)
    }

    private var honeycombRows: [[StatDomain]] {
        [
            Array(activeStats.prefix(2)),
            Array(activeStats.dropFirst(2).prefix(3)),
            Array(activeStats.dropFirst(5).prefix(2))
        ]
    }

    private func honeycombTileWidth(for availableWidth: CGFloat) -> CGFloat {
        let rawWidth = (availableWidth - CGFloat(gameGridColumnCount - 1) * gameGridSpacing) / CGFloat(gameGridColumnCount)
        return min(max(rawWidth, 96), 124)
    }

    private func gameDashboardTile(for stat: StatDomain, needsAttention: Bool, hasUnmatchedImports: Bool) -> some View {
        GameDashboardTile(
            stat: stat,
            snapshot: snapshot(for: stat),
            needsAttention: needsAttention,
            hasUnmatchedImports: hasUnmatchedImports,
            isReordering: isReordering,
            onOpenDetail: {
                openDetail(for: stat)
            },
            onQuickLog: {
                presentPrimaryLog(for: stat)
            },
            onShowUnmatched: {
                unmatchedStat = IdentifiableStat(stat: stat)
            }
        )
        .modifier(ReorderHandleModifier(isVisible: isReordering))
        .modifier(
            ReorderDragDropModifier(
                stat: stat,
                isReordering: isReordering,
                draggedStatID: $draggedStatID,
                orderedStatIDs: activeStats.map(\.id),
                moveAction: moveSkill
            )
        )
    }

    private var reorderBanner: some View {
        V4Card(accent: TrainingArcConfig.color(for: "focus")) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    V4SerifTitle(text: "Reorder Skills", size: 22)
                    Text("Drag cards into the order you want. This order also drives Siri and Home Screen shortcuts.")
                        .font(.footnote)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                Spacer(minLength: 12)

                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        isReordering = false
                    }
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(TrainingArcConfig.color(for: "focus")))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            V4SectionHeader(number: activeStats.count, title: title)
            Spacer()
        }
    }

    private func commandButton(icon: String, isActive: Bool, accessibilityLabel: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(isActive ? Color.white : TrainingTheme.textSecondary)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(
                            isActive
                            ? LinearGradient(
                                colors: [dashboardChromeAccent, dashboardChromeAccent.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [TrainingTheme.card, TrainingTheme.elevatedCard],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder((isActive ? Color.white : TrainingTheme.borderStrong).opacity(isActive ? 0.28 : 0.18), lineWidth: 1.1)
                )
                .shadow(color: (isActive ? dashboardChromeAccent : Color.black).opacity(isActive ? 0.28 : 0.06), radius: isActive ? 14 : 6, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? icon)
    }

    private func commandMenu<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [TrainingTheme.card, TrainingTheme.elevatedCard.opacity(0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(dashboardChromeAccent.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: TrainingTheme.shadowStrong.opacity(0.8), radius: 14, x: 0, y: 8)
    }

    private func menuButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.positiveStrong)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? TrainingTheme.backgroundTertiary.opacity(0.34) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func layoutMenuIcon(for mode: DashboardLayoutMode) -> String {
        switch mode {
        case .compactGrid:
            return "square.grid.3x3.fill"
        case .detailedCards:
            return "rectangle.portrait.on.rectangle.portrait"
        case .gameGrid:
            return "gamecontroller.fill"
        }
    }

    private func snapshot(for stat: StatDomain) -> SkillProgressSnapshot {
        TrainingStore.progressSnapshot(for: stat, settings: settings)
    }

    private func focusPriority(from itemSnapshot: SkillProgressSnapshot) -> Double {
        var score = itemSnapshot.rank.progressToNextLevel

        switch itemSnapshot.focusState {
        case .pendingRankChange:
            score += 0.55
        case .nearCharge:
            score += 0.30
        case .aheadOfTarget:
            score += 0.18
        case .neutral:
            score += 0.05
        case .behindTarget:
            score -= 0.20
        }

        if itemSnapshot.pacingStatus == .ahead {
            score += 0.05
        }

        return score
    }

    private func recentTrend(for stat: StatDomain) -> Double {
        let recent = (stat.weeklyResolutions ?? []).sorted { $0.weekStartDate < $1.weekStartDate }.suffix(3)
        guard recent.count >= 2 else { return 0 }
        let last = recent.last?.actualCompletedValue ?? 0
        let first = recent.first?.actualCompletedValue ?? 0
        return (last - first) / max(Double(stat.currentBaseline), 1)
    }

    private func saveLog(_ draft: LogEntryDraft) {
        _ = try? TrainingStore.log(
            habit: draft.habit,
            value: draft.value,
            date: draft.date,
            sessionType: draft.sessionType,
            note: draft.note,
            source: draft.sourceType,
            context: modelContext
        )

        triggerLogFeedback(for: draft.habit.statDomain?.id)

        if settings?.hapticsEnabled ?? true {
            HapticsService.logSuccess()
        }
    }

    private func triggerLogFeedback(for statID: UUID?) {
        guard let statID else { return }
        flashedStatID = statID

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if flashedStatID == statID {
                flashedStatID = nil
            }
        }
    }

    private func toggleMenu(_ target: DashboardTopMenuState) {
        if settings?.hapticsEnabled ?? true {
            HapticsService.impact(style: .rigid)
        }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            topMenuState = topMenuState == target ? .none : target
        }
    }

    @ViewBuilder
    private func compactGridTile(for stat: StatDomain, needsAttention: Bool, hasUnmatchedImports: Bool) -> some View {
        let primaryHabit = TrainingStore.primaryHabit(for: stat)
        let quickLogTitle = primaryHabit?.measurementType == .booleanSession ? "Log Session" : "Log Progress"
        let tile = DashboardGridTile(
            stat: stat,
            snapshot: snapshot(for: stat),
            preview: TrainingStore.dashboardCardPreview(for: stat, settings: settings),
            quickLogTitle: quickLogTitle,
            isReordering: isReordering,
            needsAttention: needsAttention,
            hasUnmatchedImports: hasUnmatchedImports,
            onOpenDetail: {
                openDetail(for: stat)
            },
            onQuickLog: {
                presentPrimaryLog(for: stat)
            },
            onShowUnmatched: {
                unmatchedStat = IdentifiableStat(stat: stat)
            }
        )

        if isReordering {
            tile
                .modifier(ReorderHandleModifier(isVisible: true))
                .modifier(
                    ReorderDragDropModifier(
                        stat: stat,
                        isReordering: true,
                        draggedStatID: $draggedStatID,
                        orderedStatIDs: activeStats.map(\.id),
                        moveAction: moveSkill
                    )
                )
        } else {
            tile
        }
    }

    private func openDetail(for stat: StatDomain, opensLogSheetOnAppear: Bool = false) {
        guard let statKey = stat.statKey else { return }
        router.open(
            PendingAppDestination(
                skillDetail: PendingSkillDestination(
                    statKeyRaw: statKey.rawValue,
                    openLogSheet: opensLogSheetOnAppear
                )
            )
        )
    }

    private func presentPrimaryLog(for stat: StatDomain) {
        let habits = TrainingStore.activeHabits(for: stat)
        guard let habit = TrainingStore.primaryHabit(for: stat) ?? habits.first else { return }
        // Confirm the long-press with a haptic as the quick-log popup appears.
        if settings?.hapticsEnabled ?? true {
            HapticsService.impact(style: .medium)
        }
        // Open the log popup directly on the primary habit. When the skill has
        // several habits the sheet's eyebrow becomes a habit picker, so the
        // selection lives inside the same popup instead of a separate dialog.
        presentedLogDraft = LogEntryDraft(habit: habit)
    }

    #if canImport(HealthKit)
    private func syncHealthWorkouts() {
        guard !isSyncingHealth else { return }
        isSyncingHealth = true
        topMenuState = .none

        Task {
            let message: String

            if HealthImportService.authorizationState() == .connected {
                message = (try? await HealthImportService.syncNow()) ?? "Apple Health sync could not complete."
            } else {
                message = await HealthImportService.requestAuthorizationAndSync()
            }
            HealthImportService.startWorkoutObserverIfEnabled()

            await MainActor.run {
                try? TrainingStore.refreshAllProgress(context: modelContext, reason: .appRefresh)
                healthStatusMessage = message
                isShowingHealthStatus = true
                isSyncingHealth = false
            }
        }
    }
    #endif

    private func moveSkill(_ draggedID: UUID, _ targetID: UUID) {
        guard draggedID != targetID else { return }
        var orderedIDs = activeStats.map(\.id)
        guard
            let sourceIndex = orderedIDs.firstIndex(of: draggedID),
            let targetIndex = orderedIDs.firstIndex(of: targetID)
        else {
            return
        }

        let movedID = orderedIDs.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex : targetIndex
        orderedIDs.insert(movedID, at: insertionIndex)
        try? TrainingStore.setSkillOrder(orderedIDs, context: modelContext)
    }

    private var dashboardBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 0.96),
                    Color(red: 0.86, green: 0.91, blue: 0.89),
                    Color(red: 0.90, green: 0.92, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [TrainingArcConfig.color(for: "focus").opacity(0.28), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 300
            )
            .offset(x: -80, y: -120)

            RadialGradient(
                colors: [TrainingArcConfig.color(for: "creativity").opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 280
            )
            .offset(x: 90, y: -30)

            RadialGradient(
                colors: [TrainingTheme.positiveStrong.opacity(0.12), .clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 240
            )
            .offset(x: -80, y: 180)

            LinearGradient(
                colors: [.white.opacity(0.28), .clear, .white.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct DashboardPresentationModifier: ViewModifier {
    @Binding var presentedLogDraft: LogEntryDraft?
    @Binding var presentedInsight: DashboardInsightOption?
    @Binding var isShowingHealthStatus: Bool
    let healthStatusMessage: String
    @Binding var habitPickerStat: IdentifiableStat?
    @Binding var unmatchedStat: IdentifiableStat?
    let settings: AppSettings?
    let modelContext: ModelContext
    let onLogSaved: (LogEntryDraft) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $presentedLogDraft) { draft in
                NavigationStack {
                    LogEntrySheetView(
                        draft: draft,
                        accent: draft.habit.statDomain.map { TrainingArcConfig.color(for: $0.colorToken) } ?? .accentColor,
                        onSave: onLogSaved
                    )
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $presentedInsight) { insight in
                NavigationStack {
                    DashboardInsightSheet(
                        option: insight,
                        settings: settings,
                        modelContext: modelContext,
                        onLogStat: { stat in
                            guard let habit = TrainingStore.primaryHabit(for: stat) else { return }
                            presentedInsight = nil
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                presentedLogDraft = LogEntryDraft(habit: habit)
                            }
                        }
                    )
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Apple Health", isPresented: $isShowingHealthStatus) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(healthStatusMessage)
            }
            .confirmationDialog(
                habitPickerStat.map { "Log which habit for \($0.stat.name)?" } ?? "",
                isPresented: Binding(
                    get: { habitPickerStat != nil },
                    set: { if !$0 { habitPickerStat = nil } }
                ),
                titleVisibility: .visible,
                presenting: habitPickerStat
            ) { wrapper in
                ForEach(TrainingStore.activeHabits(for: wrapper.stat)) { habit in
                    Button(habit.name) {
                        presentedLogDraft = LogEntryDraft(habit: habit)
                        habitPickerStat = nil
                    }
                }
                Button("Cancel", role: .cancel) { habitPickerStat = nil }
            }
            #if canImport(HealthKit)
            .sheet(item: $unmatchedStat) { wrapper in
                UnmatchedWorkoutSheet(stat: wrapper.stat)
            }
            #endif
    }
}

private struct GameDashboardTile: View {
    let stat: StatDomain
    let snapshot: SkillProgressSnapshot
    let needsAttention: Bool
    let hasUnmatchedImports: Bool
    let isReordering: Bool
    let onOpenDetail: () -> Void
    let onQuickLog: () -> Void
    let onShowUnmatched: () -> Void

    @State private var indicatorPulse = false

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var ringTint: Color { accent }

    private var rankIndicatorTint: Color {
        guard let direction = snapshot.pendingRankChange?.direction else { return .clear }
        return direction == .up ? TrainingTheme.positiveStrong : TrainingTheme.danger
    }

    private var quickLogTitle: String {
        TrainingStore.primaryHabit(for: stat)?.measurementType == .booleanSession ? "Log Session" : "Log Progress"
    }

    @ViewBuilder
    var body: some View {
        if isReordering {
            tileContent
        } else {
            // One exclusive gesture so the long-press timing is honored: a
            // 0.4s hold fires the quick log (haptic + popup at that instant);
            // a quick tap falls through to opening the skill.
            tileContent
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .onEnded { _ in onQuickLog() }
                        .exclusively(before: TapGesture().onEnded { onOpenDetail() })
                )
                .accessibilityAction { onOpenDetail() }
                .accessibilityAction(named: Text(quickLogTitle)) { onQuickLog() }
        }
    }

    private var tileContent: some View {
            VStack(spacing: 7) {
                Text(stat.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    // Reserves a symmetric gutter on both sides for the
                    // rank-change badge and attention dot (each anchored to a
                    // top corner of the tile below) so neither ever overlaps
                    // the name — reserved unconditionally rather than only
                    // when a badge/dot is present, so the label doesn't shift
                    // when one appears or clears, and stays visually centered
                    // (WS13) instead of drifting toward the unreserved side.
                    .padding(.horizontal, 26)
                    .frame(maxWidth: .infinity)

                ZStack {
                    Circle()
                        .stroke(TrainingTheme.borderStrong.opacity(0.16), lineWidth: 3)
                        .padding(2)

                    Circle()
                        .trim(from: 0, to: snapshot.weeklyTargetProgress)
                        .stroke(ringTint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: snapshot.weeklyTargetProgress)

                    RankArtworkView(
                        habitName: stat.name,
                        level: snapshot.rank.level,
                        title: snapshot.rank.title,
                        image: snapshot.rank.image,
                        accent: accent,
                        style: .dashboardBare
                    )
                    .padding(8)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Text(snapshot.weeklyTargetFractionLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("·")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textMuted)
                    Text("LV \(V4Style.displayNumber(snapshot.rank.level))")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)

                DirectionalChargeMeter(charge: snapshot.charge.current, socketSize: 9, spacing: 3)
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
                    // Charged tiles should stand out against neutral ones —
                    // at charge 0 every tile carried the same visual weight,
                    // so the grid couldn't be scanned for what needs
                    // attention at a glance.
                    .opacity(snapshot.charge.current == 0 ? 0.6 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: 182, alignment: .top)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
            if snapshot.rankChangeIndicatorVisible, let direction = snapshot.pendingRankChange?.direction {
                Image(systemName: direction == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.title3.weight(.black))
                    .dynamicTypeSize(.large)
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(rankIndicatorTint)
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.85), lineWidth: 1.4)
                    )
                    .shadow(color: rankIndicatorTint.opacity(0.55), radius: indicatorPulse ? 10 : 4, x: 0, y: 0)
                    .scaleEffect(indicatorPulse ? 1.06 : 0.96)
                    .padding(6)
                    .accessibilityLabel(direction == .up ? "Rank up available" : "Rank drop pending")
                    .onAppear { indicatorPulse = true }
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: indicatorPulse)
            }
        }
        .overlay(alignment: .topLeading) {
            if hasUnmatchedImports {
                UnmatchedBadge(accent: accent, action: onShowUnmatched)
                    .padding(6)
            } else if needsAttention {
                AttentionDot(accent: accent)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = ["\(stat.name)", "level \(snapshot.rank.level)", DashboardChargeDots.summaryLabel(for: snapshot.charge.current)]
        if hasUnmatchedImports { parts.append("unmatched workouts to review") }
        else if needsAttention { parts.append("needs attention this week") }
        return parts.joined(separator: ", ")
    }
}

struct AttentionDot: View {
    let accent: Color

    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white, lineWidth: 1.4))
            .shadow(color: accent.opacity(0.45), radius: 4, x: 0, y: 1)
            .accessibilityHidden(true)
    }
}

struct UnmatchedBadge: View {
    let accent: Color
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(accent))
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .overlay(
                    Circle()
                        .stroke(accent.opacity(pulse ? 0 : 0.55), lineWidth: 2.5)
                        .scaleEffect(pulse ? 1.6 : 1)
                )
                .shadow(color: accent.opacity(0.5), radius: 6, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review unmatched workouts")
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

private struct ReorderHandleModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isVisible {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textMuted)
                        .padding(12)
                }
            }
    }
}

private struct ReorderDragDropModifier: ViewModifier {
    let stat: StatDomain
    let isReordering: Bool
    @Binding var draggedStatID: UUID?
    let orderedStatIDs: [UUID]
    let moveAction: (UUID, UUID) -> Void

    func body(content: Content) -> some View {
        if isReordering {
            content
                .onDrag {
                    draggedStatID = stat.id
                    return NSItemProvider(object: stat.id.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: DashboardGridReorderDropDelegate(
                        targetStatID: stat.id,
                        draggedStatID: $draggedStatID,
                        orderedStatIDs: orderedStatIDs,
                        moveAction: moveAction
                    )
                )
        } else {
            content
        }
    }
}

private struct DashboardGridReorderDropDelegate: DropDelegate {
    let targetStatID: UUID
    @Binding var draggedStatID: UUID?
    let orderedStatIDs: [UUID]
    let moveAction: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedStatID, draggedStatID != targetStatID else { return }
        guard orderedStatIDs.contains(draggedStatID), orderedStatIDs.contains(targetStatID) else { return }
        moveAction(draggedStatID, targetStatID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedStatID = nil
        return true
    }
}

private struct CenteredDashboardGridLayout: Layout {
    let columns: Int
    let spacing: CGFloat
    let rowSpacing: CGFloat

    init(columns: Int, spacing: CGFloat, rowSpacing: CGFloat? = nil) {
        self.columns = columns
        self.spacing = spacing
        self.rowSpacing = rowSpacing ?? spacing
    }

    struct CacheData {
        var sizes: [CGSize] = []
        var rowHeights: [CGFloat] = []
        var totalHeight: CGFloat = 0
        var columnWidth: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> CacheData {
        CacheData()
    }

    func updateCache(_ cache: inout CacheData, subviews: Subviews) {
        if cache.sizes.count != subviews.count {
            cache = CacheData()
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let width = proposal.width ?? 0
        guard !subviews.isEmpty, columns > 0, width > 0 else {
            cache = CacheData()
            return CGSize(width: width, height: 0)
        }

        let columnWidth = max((width - CGFloat(columns - 1) * spacing) / CGFloat(columns), 0)
        let sizes = subviews.map { subview in
            subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
        }

        let rowHeights = stride(from: 0, to: sizes.count, by: columns).map { start in
            sizes[start..<Swift.min(start + columns, sizes.count)].map(\.height).max() ?? 0
        }

        let totalHeight = rowHeights.reduce(0, +) + CGFloat(max(rowHeights.count - 1, 0)) * rowSpacing

        cache = CacheData(
            sizes: sizes,
            rowHeights: rowHeights,
            totalHeight: totalHeight,
            columnWidth: columnWidth
        )

        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        guard !subviews.isEmpty, columns > 0 else { return }

        if cache.sizes.count != subviews.count || cache.columnWidth == 0 {
            _ = sizeThatFits(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews, cache: &cache)
        }

        var y = bounds.minY

        for rowIndex in 0..<cache.rowHeights.count {
            let start = rowIndex * columns
            let end = Swift.min(start + columns, subviews.count)
            let count = end - start
            let rowWidth = CGFloat(count) * cache.columnWidth + CGFloat(max(count - 1, 0)) * spacing
            let xOrigin = bounds.minX + (bounds.width - rowWidth) / 2

            for itemOffset in 0..<count {
                let index = start + itemOffset
                let x = xOrigin + CGFloat(itemOffset) * (cache.columnWidth + spacing)
                let rowHeight = cache.rowHeights[rowIndex]
                let itemSize = cache.sizes[index]
                let yOffset = (rowHeight - itemSize.height) / 2

                subviews[index].place(
                    at: CGPoint(x: x, y: y + yOffset),
                    proposal: ProposedViewSize(width: cache.columnWidth, height: rowHeight)
                )
            }

            y += cache.rowHeights[rowIndex] + rowSpacing
        }
    }
}

private struct DashboardInsightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var stats: [StatDomain]

    let option: DashboardInsightOption
    let settings: AppSettings?
    let modelContext: ModelContext
    let onLogStat: (StatDomain) -> Void

    private var workAnalysis: WorkFocusAnalysis {
        (try? TrainingStore.workFocusAnalysis(context: modelContext, settings: settings)) ??
        WorkFocusAnalysis(headline: "No insight yet.", focusSkillName: "No Skill", recommendations: ["Keep logging to build local insights."])
    }

    private var monthlyAnalysis: MonthlyImprovementAnalysis {
        (try? TrainingStore.monthlyImprovementAnalysis(context: modelContext, settings: settings)) ??
        MonthlyImprovementAnalysis(headline: "No monthly insight yet.", summary: "More history is needed.", improvedSkills: ["Keep logging to build local insights."])
    }

    private var standardDayAnalysis: StandardDayAnalysis {
        (try? TrainingStore.standardDayAnalysis(context: modelContext, settings: settings)) ??
        StandardDayAnalysis(headline: "No routine insight yet.", rhythmSummary: "More history is needed.", suggestions: ["Keep logging to build local insights."])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SurfaceCard(accent: accent) {
                    VStack(alignment: .leading, spacing: 10) {
                        // The navigation bar already shows `option.title` —
                        // repeating it here as a second heading was pure
                        // duplication. Keep just the icon as a visual accent.
                        Image(systemName: option.systemImage)
                            .font(.system(.title3, design: .rounded).weight(.black))
                            .foregroundStyle(accent)

                        Text(headline)
                            .font(.headline)
                            .foregroundStyle(TrainingTheme.textPrimary)

                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                }

                SurfaceCard(accent: accent) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(option == .standardDay ? "Tips" : "Insights")
                            .font(.headline)
                            .foregroundStyle(TrainingTheme.textPrimary)

                        ForEach(bullets, id: \.self) { bullet in
                            if let stat = workStat(for: bullet) {
                                Button {
                                    onLogStat(stat)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        insightBullet(bullet)
                                        Spacer(minLength: 8)
                                        Text(logActionTitle(for: stat))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(accent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(accent.opacity(0.12)))
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(logActionTitle(for: stat)) \(stat.name)")
                                .accessibilityHint(bullet)
                            } else {
                                insightBullet(bullet)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle(option.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }

    private var accent: Color {
        switch option {
        case .whatToWorkOn:
            return TrainingTheme.warning
        case .whatImproved:
            return TrainingTheme.positiveStrong
        case .standardDay:
            return TrainingTheme.cold
        }
    }

    private var headline: String {
        switch option {
        case .whatToWorkOn:
            return workAnalysis.headline
        case .whatImproved:
            return monthlyAnalysis.headline
        case .standardDay:
            return standardDayAnalysis.headline
        }
    }

    private var summary: String {
        switch option {
        case .whatToWorkOn:
            return "Your weakest current momentum point is \(workAnalysis.focusSkillName). These are the smallest useful moves to stabilize it."
        case .whatImproved:
            return monthlyAnalysis.summary
        case .standardDay:
            return standardDayAnalysis.rhythmSummary
        }
    }

    private var bullets: [String] {
        switch option {
        case .whatToWorkOn:
            return workAnalysis.recommendations
        case .whatImproved:
            return monthlyAnalysis.improvedSkills
        case .standardDay:
            return standardDayAnalysis.suggestions
        }
    }

    private func workStat(for bullet: String) -> StatDomain? {
        guard option == .whatToWorkOn,
              let name = bullet.split(separator: ":", maxSplits: 1).first.map(String.init)
        else { return nil }
        return stats.first { $0.isActive && $0.name == name }
    }

    private func logActionTitle(for stat: StatDomain) -> String {
        TrainingStore.primaryHabit(for: stat)?.measurementType == .booleanSession ? "Log" : "Update"
    }

    private func insightBullet(_ bullet: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(bullet)
                .font(.subheadline)
                .foregroundStyle(TrainingTheme.textSecondary)
                .multilineTextAlignment(.leading)
        }
    }
}
