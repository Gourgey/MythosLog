import SwiftData
import SwiftUI

private enum DashboardTopMenuState {
    case none
    case layout
    case insights
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatDomain.name) private var stats: [StatDomain]
    @Query private var settingsRecords: [AppSettings]
    @State private var selectedStat: StatDomain?
    @State private var presentedLogDraft: LogEntryDraft?
    @State private var flashedStatID: UUID?
    @State private var topMenuState: DashboardTopMenuState = .none
    @State private var presentedInsight: DashboardInsightOption?
    private let compactGridColumnCount = 2
    private let compactGridSpacing: CGFloat = 16

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var activeStats: [StatDomain] {
        stats.filter { !$0.isArchived }
    }

    private var dashboardLayoutMode: DashboardLayoutMode {
        settings?.dashboardLayoutMode ?? .detailedCards
    }

    private var focusTargetID: UUID? {
        activeStats
            .filter { !snapshot(for: $0).rank.isAtMaximumRank }
            .max(by: { focusPriority(for: $0) < focusPriority(for: $1) })?
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
        ZStack {
            dashboardBackdrop

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    commandStrip

                    switch dashboardLayoutMode {
                    case .detailedCards:
                        detailedDashboard
                    case .compactGrid:
                        compactGridDashboard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? TrainingStore.refreshAllProgress(context: modelContext, reason: .appRefresh)
        }
        .navigationDestination(item: $selectedStat) { stat in
            SkillDetailView(stat: stat)
        }
        .sheet(item: $presentedLogDraft) { draft in
            NavigationStack {
                LogEntrySheetView(
                    draft: draft,
                    accent: draft.habit.statDomain.map { TrainingArcConfig.color(for: $0.colorToken) } ?? .accentColor,
                    onSave: { submittedDraft in
                        _ = try? TrainingStore.log(
                            habit: submittedDraft.habit,
                            value: submittedDraft.value,
                            date: submittedDraft.date,
                            sessionType: submittedDraft.sessionType,
                            note: submittedDraft.note,
                            source: submittedDraft.sourceType,
                            context: modelContext
                        )

                        triggerLogFeedback(for: submittedDraft.habit.statDomain?.id)

                        if settings?.hapticsEnabled ?? true {
                            HapticsService.logSuccess()
                        }
                    }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $presentedInsight) { insight in
            NavigationStack {
                DashboardInsightSheet(
                    option: insight,
                    settings: settings,
                    modelContext: modelContext
                )
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var commandStrip: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                commandButton(icon: "line.3.horizontal", isActive: topMenuState == .layout) {
                    toggleMenu(.layout)
                }

                commandButton(icon: "sparkles", isActive: topMenuState == .insights) {
                    toggleMenu(.insights)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 12) {
                if topMenuState == .layout {
                    commandMenu {
                        ForEach(DashboardLayoutMode.allCases) { mode in
                            menuButton(
                                title: mode.displayName,
                                icon: mode == .detailedCards ? "rectangle.portrait.on.rectangle.portrait" : "square.grid.3x3.fill",
                                isSelected: dashboardLayoutMode == mode
                            ) {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                    try? TrainingStore.setDashboardLayoutMode(mode, context: modelContext)
                                    topMenuState = .none
                                }
                            }
                        }
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
                            dashboardChromeAccent.opacity(0.40),
                            .white.opacity(0.70),
                            TrainingTheme.borderStrong.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: dashboardChromeAccent.opacity(0.14), radius: 20, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var detailedDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Skills")
            Text("Tap a skill card to open the character sheet. Use the action tray when you want to log immediately.")
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
                        isFocusTarget: stat.id == focusTargetID,
                        showLogFeedback: flashedStatID == stat.id,
                        onOpenDetail: {
                            selectedStat = stat
                        },
                        onQuickLogTap: { habit, value in
                            presentedLogDraft = LogEntryDraft(habit: habit, value: value)
                        }
                    )
                }
            }
        }
    }

    private var compactGridDashboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CenteredDashboardGridLayout(columns: compactGridColumnCount, spacing: compactGridSpacing) {
                ForEach(activeStats) { stat in
                    DashboardGridTile(
                        stat: stat,
                        snapshot: snapshot(for: stat)
                    ) {
                        selectedStat = stat
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.subheadline.weight(.black))
                .foregroundStyle(TrainingArcConfig.color(for: "focus"))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TrainingArcConfig.color(for: "focus").opacity(0.14))
                )

            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(TrainingTheme.textPrimary)
        }
    }

    private func commandButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
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

    private func snapshot(for stat: StatDomain) -> SkillProgressSnapshot {
        TrainingStore.progressSnapshot(for: stat, settings: settings)
    }

    private func focusPriority(for stat: StatDomain) -> Double {
        let itemSnapshot = snapshot(for: stat)
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
        let recent = stat.weeklyResolutions.sorted { $0.weekStartDate < $1.weekStartDate }.suffix(3)
        guard recent.count >= 2 else { return 0 }
        let last = recent.last?.actualCompletedValue ?? 0
        let first = recent.first?.actualCompletedValue ?? 0
        return (last - first) / max(Double(stat.currentBaseline), 1)
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

private struct CenteredDashboardGridLayout: Layout {
    let columns: Int
    let spacing: CGFloat

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

        let totalHeight = rowHeights.reduce(0, +) + CGFloat(max(rowHeights.count - 1, 0)) * spacing

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

            y += cache.rowHeights[rowIndex] + spacing
        }
    }
}

private struct DashboardInsightSheet: View {
    @Environment(\.dismiss) private var dismiss

    let option: DashboardInsightOption
    let settings: AppSettings?
    let modelContext: ModelContext

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
                        Label(option.title, systemImage: option.systemImage)
                            .font(.system(.title3, design: .rounded).weight(.black))
                            .foregroundStyle(TrainingTheme.textPrimary)

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
                        Text("Insights")
                            .font(.headline)
                            .foregroundStyle(TrainingTheme.textPrimary)

                        ForEach(bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 6)
                                Text(bullet)
                                    .font(.subheadline)
                                    .foregroundStyle(TrainingTheme.textSecondary)
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
}
