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

/// Reports a view's laid-out size without dictating it.
///
/// Deliberately not a `PreferenceKey`: a preference published from inside a
/// `.background`/`.overlay` branch never reaches the host view's preference
/// stream, so the matching `onPreferenceChange` silently never fires and the
/// reader is left holding its default forever. Writing the measurement to
/// state directly from the probe is the form that actually delivers.
private struct SizeReaderModifier: ViewModifier {
    let onSizeChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onSizeChange(proxy.size) }
                    .onChange(of: proxy.size) { _, newSize in onSizeChange(newSize) }
            }
        )
    }
}

private extension View {
    func measuringSize(_ onSizeChange: @escaping (CGSize) -> Void) -> some View {
        modifier(SizeReaderModifier(onSizeChange: onSizeChange))
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
    @State private var dashboardViewportHeight: CGFloat = 0
    @State private var commandStripHeight: CGFloat = 0
    /// Height a honeycomb tile spends on everything that is not the ring: the
    /// name above it, the fraction/level row and charge meter below it, plus
    /// the `VStack` spacing between them. Measured at 65–66pt at the default
    /// text size; carried a point over so the estimate errs toward a slightly
    /// larger bottom gap rather than a row that runs into the tab bar. Scaled
    /// so it tracks Dynamic Type, where the labels are what actually grow.
    @ScaledMetric(relativeTo: .body) private var compactHoneycombTileChromeHeight: CGFloat = 67
    /// The same allowance for iPad, whose tiles use larger labels, charge
    /// dots and spacing (see `GameDashboardTile`).
    @ScaledMetric(relativeTo: .body) private var regularHoneycombTileChromeHeight: CGFloat = 112
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let twoColumnColumns = 2
    private let twoColumnSpacing: CGFloat = 16
    private let gameGridColumnCount = 3
    private var gameGridSpacing: CGFloat { isRegularWidth ? 20 : 6 }
    private let gameGridRowSpacing: CGFloat = 24
    private let dashboardContentSpacing: CGFloat = 18
    private let dashboardContentTopPadding: CGFloat = 4
    private let honeycombTopPadding: CGFloat = 2
    /// Breathing room kept between the last thing in the scroll view — the
    /// bottom honeycomb row's charge meter, usually — and the floating tab
    /// bar. It only needs to be a gap: the tab bar is installed as a bottom
    /// `safeAreaInset` by the shell, so the scroll view is already short of
    /// it and this does not have to clear the bar's own height.
    private let dashboardBottomGap: CGFloat = 20

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    private var honeycombTileChromeHeight: CGFloat {
        isRegularWidth ? regularHoneycombTileChromeHeight : compactHoneycombTileChromeHeight
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

            // The honeycomb sizes itself against the space this scroll view
            // actually gets, so read that height rather than assuming a device.
            GeometryReader { proxy in
                dashboardScrollContent
                    .onAppear { dashboardViewportHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        dashboardViewportHeight = newHeight
                    }
            }
        }
    }

    private var dashboardScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: dashboardContentSpacing) {
                commandStrip
                    .measuringSize { size in
                        // Only the collapsed strip is a stable reference.
                        // An open layout/insights menu grows it, and
                        // letting that through would shrink every ring for
                        // as long as the menu is up.
                        if size.height > 0, topMenuState == .none {
                            commandStripHeight = size.height
                        }
                    }

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
                            .environment(\.isDashboardArtwork, true)
                    case .twoColumn:
                        twoColumnDashboard
                            .environment(\.isDashboardArtwork, true)
                    case .gameGrid:
                        gameGridDashboard
                            .environment(\.isDashboardArtwork, true)
                    }

                    if !pendingRankChanges.isEmpty {
                        rankReviewBanner
                            .padding(.horizontal, displayedLayoutMode == .gameGrid ? 14 : 0)
                    }
                }
            }
            .padding(.horizontal, displayedLayoutMode == .gameGrid ? 12 : 16)
            .padding(.top, dashboardContentTopPadding)
            .padding(.bottom, dashboardBottomGap)
        }
        .coordinateSpace(name: "dashboardScroll")
    }

    private var todayKicker: some View {
        let weekday = Date.now.formatted(.dateTime.weekday(.abbreviated))
        let date = Date.now.formatted(.dateTime.day().month(.abbreviated))
        return Text("\(weekday) · \(date)".uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(TrainingTheme.textPrimary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var statsChip: some View {
        Button {
            if settings?.hapticsEnabled ?? true {
                HapticsService.impact(style: .light)
            }
            showingStatsSheet = true
        } label: {
            Text("This week")
                .font(.caption.weight(.medium))
                .foregroundStyle(TrainingTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(TrainingTheme.actionSurface))
                .frame(minHeight: 44)

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
                    Spacer(minLength: 4)

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
                        ForEach([DashboardLayoutMode.gameGrid, .twoColumn, .detailedCards]) { mode in
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
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
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
        HStack(spacing: 0) {
            commandButton(icon: "square.grid.2x2", isActive: topMenuState == .layout, accessibilityLabel: "Dashboard layout") {
                toggleMenu(.layout)
            }

            commandButton(icon: "sparkles", isActive: topMenuState == .insights, accessibilityLabel: "Dashboard insights") {
                toggleMenu(.insights)
            }
        }
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

    private var twoColumnDashboard: some View {
        let unmatched = awaitingAttributionStatKeys
        return VStack(alignment: .leading, spacing: 0) {
            CenteredDashboardGridLayout(columns: twoColumnColumns, spacing: twoColumnSpacing) {
                ForEach(activeStats) { stat in
                    twoColumnTile(
                        for: stat,
                        hasUnmatchedImports: unmatched.contains(stat.key)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var gameGridDashboard: some View {
        let unmatched = awaitingAttributionStatKeys

        if activeStats.count == 7 {
            honeycombGameGridDashboard(unmatched: unmatched)
        } else {
            CenteredDashboardGridLayout(columns: gameGridColumnCount, spacing: gameGridSpacing, rowSpacing: gameGridRowSpacing) {
                ForEach(activeStats) { stat in
                    gameDashboardTile(
                        for: stat,
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
    /// charge meter — had fully cleared. Measuring the available width with a
    /// passive probe instead of a size-dictating `GeometryReader` lets the
    /// VStack/HStacks size themselves naturally, so rows can never run short
    /// of the space their own content needs — at any Dynamic Type size. Only
    /// the ring *width* is ever computed; every height stays intrinsic.
    /// All three rows render at the same scale — no
    /// scroll-driven zoom on the middle row (removed per user request; it
    /// read as an unwanted "magnify" effect rather than a focus cue).
    private func honeycombGameGridDashboard(unmatched: Set<String>) -> some View {
        let tileWidth = honeycombTileWidth(for: honeycombAvailableWidth)
        let rows = honeycombRows

        return VStack(spacing: gameGridRowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowStats in
                HStack(spacing: gameGridSpacing) {
                    ForEach(rowStats) { stat in
                        gameDashboardTile(
                            for: stat,
                            hasUnmatchedImports: unmatched.contains(stat.key)
                        )
                        .frame(width: tileWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .measuringSize { size in
            if size.width > 0 { honeycombAvailableWidth = size.width }
        }
        .padding(.top, honeycombTopPadding)
    }

    private var honeycombRows: [[StatDomain]] {
        [
            Array(activeStats.prefix(2)),
            Array(activeStats.dropFirst(2).prefix(3)),
            Array(activeStats.dropFirst(5).prefix(2))
        ]
    }

    /// Vertical space the honeycomb may fill: the scroll viewport (already
    /// short of the floating tab bar, which the shell installs as a bottom
    /// `safeAreaInset`) minus the command strip above it, the stack spacing on
    /// either side of it, and the gap we want left under the final row.
    /// Zero until both measurements land, which the caller treats as "not
    /// known yet" and falls back to width-only sizing for one layout pass.
    private var honeycombHeightBudget: CGFloat {
        guard dashboardViewportHeight > 0, commandStripHeight > 0 else { return 0 }
        return dashboardViewportHeight
            - dashboardContentTopPadding
            - commandStripHeight
            - dashboardContentSpacing
            - honeycombTopPadding
            - dashboardBottomGap
    }

    /// Tiles grow to whichever the screen allows less of: the width three of
    /// them plus their gutters can share, or the width whose resulting square
    /// ring still lets all three rows finish above the tab bar. Sizing against
    /// both — rather than the old flat 124pt ceiling, which left a tall dead
    /// strip on big phones and overshot small ones — is what makes the bottom
    /// row land the same distance above the bar on every device.
    private func honeycombTileWidth(for availableWidth: CGFloat) -> CGFloat {
        let widthCap = (availableWidth - CGFloat(gameGridColumnCount - 1) * gameGridSpacing) / CGFloat(gameGridColumnCount)

        let budget = honeycombHeightBudget
        guard budget > 0 else { return clampedHoneycombTileWidth(widthCap) }

        let rowCount = CGFloat(max(honeycombRows.count, 1))
        let heightPerRow = (budget - (rowCount - 1) * gameGridRowSpacing) / rowCount
        // A row is as tall as its ring plus the labels stacked around it, so
        // the ring may be as wide as the row's share of the budget less that.
        let heightCap = heightPerRow - honeycombTileChromeHeight

        return clampedHoneycombTileWidth(min(widthCap, heightCap))
    }

    /// iPhone rings top out at 160pt; iPad lets them grow until the three
    /// rows fill the screen, as they do on a phone.
    private func clampedHoneycombTileWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, 96), isRegularWidth ? 340 : 160)
    }

    private func gameDashboardTile(for stat: StatDomain, hasUnmatchedImports: Bool) -> some View {
        GameDashboardTile(
            stat: stat,
            snapshot: snapshot(for: stat),
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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(TrainingTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(isActive ? TrainingTheme.actionSurface : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? icon)
    }

    private func commandMenu<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .background(TrainingTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(TrainingTheme.border, lineWidth: 0.5))
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
        case .twoColumn:
            return "square.grid.2x2.fill"
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
    private func twoColumnTile(for stat: StatDomain, hasUnmatchedImports: Bool) -> some View {
        let primaryHabit = TrainingStore.primaryHabit(for: stat)
        let quickLogTitle = primaryHabit?.measurementType == .booleanSession ? "Log Session" : "Log Progress"
        let tile = DashboardGridTile(
            stat: stat,
            snapshot: snapshot(for: stat),
            preview: TrainingStore.dashboardCardPreview(for: stat, settings: settings),
            quickLogTitle: quickLogTitle,
            isReordering: isReordering,
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
        TrainingTheme.background.ignoresSafeArea()
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
    let hasUnmatchedImports: Bool
    let isReordering: Bool
    let onOpenDetail: () -> Void
    let onQuickLog: () -> Void
    let onShowUnmatched: () -> Void

    @State private var indicatorPulse = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// iPad tiles are roughly twice the size of iPhone ones, so their labels,
    /// ring stroke and charge dots scale up to match.
    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var ringTint: Color { accent }
    private var ringLineWidth: CGFloat { isRegularWidth ? 5 : 3 }
    private var labelFont: Font { isRegularWidth ? .title3 : .caption }

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
            VStack(spacing: isRegularWidth ? 12 : 7) {
                Text(stat.name)
                    .font((isRegularWidth ? Font.title2 : .subheadline).weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)

                ZStack {
                    Circle()
                        .stroke(TrainingTheme.backgroundTertiary, lineWidth: ringLineWidth)
                        .padding(2)

                    Circle()
                        .trim(from: 0, to: snapshot.weeklyTargetProgress)
                        .stroke(ringTint, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
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
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Text(snapshot.weeklyTargetFractionLabel)
                        .font(labelFont.weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("·")
                        .font(labelFont.weight(.bold))
                        .foregroundStyle(TrainingTheme.textMuted)
                    Text("LV \(V4Style.displayNumber(snapshot.rank.level))")
                        .font(labelFont.weight(.semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)

                DashboardChargeTrack(charge: snapshot.charge.current, dotSize: isRegularWidth ? 12 : 7)
                    .frame(height: isRegularWidth ? 18 : 12)
                    .frame(maxWidth: .infinity)

            }
            // No minimum height: the tile is exactly as tall as its ring plus
            // its labels. A floor here used to hold rows open past what their
            // content needed, which the honeycomb's height budget then had to
            // spend anyway — squeezing the rings to pay for empty space.
            // Tiles in a row share a width, so they stay the same height.
            .frame(maxWidth: .infinity, alignment: .top)
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
                    .offset(y: 28)
                    .accessibilityLabel(direction == .up ? "Rank up available" : "Rank drop pending")
                    .onAppear { indicatorPulse = true }
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: indicatorPulse)
            }
        }
        .overlay(alignment: .topLeading) {
            if hasUnmatchedImports {
                UnmatchedBadge(accent: accent, action: onShowUnmatched)
                    .padding(6)
                    .offset(y: 28)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = ["\(stat.name)", "level \(snapshot.rank.level)", DashboardChargeDots.summaryLabel(for: snapshot.charge.current)]
        if hasUnmatchedImports { parts.append("unmatched workouts to review") }
        return parts.joined(separator: ", ")
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
