import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum DashboardTopMenuState {
    case none
    case layout
    case insights
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
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
    private let compactGridColumnCount = 2
    private let compactGridSpacing: CGFloat = 16
    private let gameGridColumnCount = 3
    private let gameGridSpacing: CGFloat = 4
    private let gameGridRowSpacing: CGFloat = 36

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var activeStats: [StatDomain] {
        stats
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name < $1.name
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private var dashboardLayoutMode: DashboardLayoutMode {
        settings?.dashboardLayoutMode ?? .compactGrid
    }

    private var displayedLayoutMode: DashboardLayoutMode {
        dashboardLayoutMode
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

                    if isReordering {
                        reorderBanner
                    }

                    trainTodayCard
                        .padding(.horizontal, displayedLayoutMode == .gameGrid ? 14 : 0)

                    switch displayedLayoutMode {
                    case .detailedCards:
                        detailedDashboard
                    case .compactGrid:
                        compactGridDashboard
                    case .gameGrid:
                        gameGridDashboard
                    }
                }
                .padding(.horizontal, displayedLayoutMode == .gameGrid ? 2 : 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? TrainingStore.refreshAllProgress(context: modelContext, reason: .appRefresh)
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
        .alert("Apple Health", isPresented: $isShowingHealthStatus) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthStatusMessage)
        }
    }

    private var commandStrip: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                commandButton(icon: "line.3.horizontal", isActive: topMenuState == .layout, accessibilityLabel: "Dashboard layout") {
                    toggleMenu(.layout)
                }

                commandButton(icon: "sparkles", isActive: topMenuState == .insights, accessibilityLabel: "Dashboard insights") {
                    toggleMenu(.insights)
                }

                #if canImport(HealthKit)
                commandButton(icon: isSyncingHealth ? "heart.circle.fill" : "heart.fill", isActive: isSyncingHealth, accessibilityLabel: "Sync Apple Health workouts") {
                    syncHealthWorkouts()
                }
                #endif
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 12) {
                if topMenuState == .layout {
                    commandMenu {
                        ForEach([DashboardLayoutMode.compactGrid, .detailedCards, .gameGrid]) { mode in
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

    private var trainTodayRecommendations: [TrainTodayRecommendation] {
        (try? TrainingStore.trainTodayRecommendations(context: modelContext, settings: settings)) ?? []
    }

    @ViewBuilder
    private var trainTodayCard: some View {
        let recs = trainTodayRecommendations
        if !recs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("TRAIN TODAY")
                    .font(.caption.weight(.black))
                    .foregroundStyle(TrainingTheme.textMuted)

                VStack(spacing: 10) {
                    ForEach(recs) { rec in
                        Button {
                            handleRecommendationTap(rec)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: rec.iconName)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(TrainingArcConfig.color(for: rec.colorToken))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(TrainingArcConfig.color(for: rec.colorToken).opacity(0.14))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rec.headline)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(TrainingTheme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text(rec.detail)
                                        .font(.caption)
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TrainingTheme.textMuted)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(TrainingTheme.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(TrainingArcConfig.color(for: rec.colorToken).opacity(0.18), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func handleRecommendationTap(_ rec: TrainTodayRecommendation) {
        if rec.hasReviewReady {
            router.open(PendingAppDestination(route: .weeklyReview))
            return
        }
        if let statKeyRaw = rec.statKeyRaw, let statKey = StatKey(rawValue: statKeyRaw) {
            router.open(
                PendingAppDestination(
                    skillDetail: PendingSkillDestination(statKeyRaw: statKey.rawValue, openLogSheet: false)
                )
            )
        }
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
                            openDetail(for: stat)
                        },
                        onQuickLogTap: { habit, value in
                            presentedLogDraft = LogEntryDraft(habit: habit, value: value)
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
        VStack(alignment: .leading, spacing: 0) {
            CenteredDashboardGridLayout(columns: compactGridColumnCount, spacing: compactGridSpacing) {
                ForEach(activeStats) { stat in
                    compactGridTile(for: stat)
                }
            }
        }
    }

    private var gameGridDashboard: some View {
        CenteredDashboardGridLayout(columns: gameGridColumnCount, spacing: gameGridSpacing, rowSpacing: gameGridRowSpacing) {
            ForEach(activeStats) { stat in
                GameDashboardTile(
                    stat: stat,
                    snapshot: snapshot(for: stat),
                    onOpenDetail: {
                        openDetail(for: stat)
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
        .padding(.top, 4)
    }

    private var reorderBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reorder Skills")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("Drag cards into the order you want. This order also drives Siri and Home Screen shortcuts.")
                    .font(.footnote)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }

            Spacer(minLength: 12)

            Button("Done") {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    isReordering = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainingArcConfig.color(for: "focus"))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TrainingTheme.card.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(TrainingTheme.borderStrong.opacity(0.18), lineWidth: 1)
        )
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
        let recent = (stat.weeklyResolutions ?? []).sorted { $0.weekStartDate < $1.weekStartDate }.suffix(3)
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

    @ViewBuilder
    private func compactGridTile(for stat: StatDomain) -> some View {
        let primaryHabit = TrainingStore.primaryHabit(for: stat)
        let quickLogTitle = primaryHabit?.measurementType == .booleanSession ? "Log Session" : "Log Progress"
        let tile = DashboardGridTile(
            stat: stat,
            snapshot: snapshot(for: stat),
            preview: TrainingStore.dashboardCardPreview(for: stat, settings: settings),
            quickLogTitle: quickLogTitle,
            isReordering: isReordering,
            onOpenDetail: {
                openDetail(for: stat)
            },
            onQuickLog: {
                presentPrimaryLog(for: stat)
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
        guard let habit = TrainingStore.primaryHabit(for: stat) else { return }
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

private struct GameDashboardTile: View {
    let stat: StatDomain
    let snapshot: SkillProgressSnapshot
    let onOpenDetail: () -> Void

    @State private var indicatorPulse = false

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var ringTint: Color {
        snapshot.weeklyTargetProgress >= 1 ? TrainingTheme.warning : accent
    }

    private var rankIndicatorTint: Color {
        guard let direction = snapshot.pendingRankChange?.direction else { return .clear }
        return direction == .up ? TrainingTheme.positiveStrong : TrainingTheme.danger
    }

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(spacing: 15) {
                Text(stat.name)
                    .font(.footnote.weight(.black))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Image(systemName: stat.iconName)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(accent)
                        .frame(width: 22, height: 22)

                    Text("LV \(snapshot.rank.level)")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
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

                Text(snapshot.weeklyTargetFractionLabel)
                    .font(.caption.weight(.black))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)

                DirectionalChargeMeter(charge: snapshot.charge.current, socketSize: 15, spacing: 7)
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 222, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if snapshot.rankChangeIndicatorVisible, let direction = snapshot.pendingRankChange?.direction {
                Image(systemName: direction == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.title3.weight(.black))
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
        .accessibilityLabel("\(stat.name), level \(snapshot.rank.level), \(DashboardChargeDots.summaryLabel(for: snapshot.charge.current))")
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
