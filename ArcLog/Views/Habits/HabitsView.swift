import SwiftData
import SwiftUI

struct SkillDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]

    let stat: StatDomain

    @State private var logDraft: LogEntryDraft?
    @State private var presentedRankChange: PendingRankChange?
    @State private var selectedWeekStart = TrainingStore.progressionWeek(containing: .now).start
    @State private var showingFullHistory = false

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var linkedHabits: [Habit] {
        TrainingStore.activeHabits(for: stat)
    }

    private var primaryHabit: Habit? {
        linkedHabits.first
    }

    private var snapshot: SkillProgressSnapshot {
        TrainingStore.progressSnapshot(for: stat, settings: settings)
    }

    private var currentWeek: WeekRange {
        TrainingStore.progressionWeek(containing: .now)
    }

    private var selectedWeek: WeekRange {
        TrainingStore.progressionWeek(containing: selectedWeekStart)
    }

    private var selectedWeekSnapshot: SkillWeekSnapshot {
        TrainingStore.weekSnapshot(for: stat, week: selectedWeek)
    }

    private var recentSnapshots: [SkillLogEntrySnapshot] {
        TrainingStore.recentLogSnapshots(for: stat, limit: 5)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroSection
                chargeSection

                if let nextTitle = snapshot.rank.nextTitle, !snapshot.rank.isAtMaximumRank {
                    nextRankSection(nextTitle: nextTitle)
                }

                linkedHabitsSection
                weeklyHistorySection
                recentSessionsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(stat.name)
        .task {
            _ = try? TrainingStore.refreshProgress(for: stat, context: modelContext, reason: .skillOpen)
            selectedWeekStart = currentWeek.start
            presentPendingRankChangeIfNeeded()
        }
        .onChange(of: stat.pendingRankChangeRecordedAt) { _, _ in
            presentPendingRankChangeIfNeeded()
        }
        .sheet(item: $logDraft) { draft in
            NavigationStack {
                LogEntrySheetView(draft: draft, accent: accent) { submittedDraft in
                    _ = try? TrainingStore.log(
                        habit: submittedDraft.habit,
                        value: submittedDraft.value,
                        date: submittedDraft.date,
                        sessionType: submittedDraft.sessionType,
                        note: submittedDraft.note,
                        source: submittedDraft.sourceType,
                        context: modelContext
                    )

                    if settings?.hapticsEnabled ?? true {
                        HapticsService.logSuccess()
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingFullHistory) {
            NavigationStack {
                SkillHistorySheetView(stat: stat, accent: accent)
            }
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: Binding(
            get: { presentedRankChange != nil },
            set: { if !$0 { presentedRankChange = nil } }
        )) {
            if let presentedRankChange {
                RankChangeRevealView(
                    statName: stat.name,
                    change: presentedRankChange,
                    image: TrainingArcConfig.rankDefinition(for: stat.statKey ?? .strength, level: presentedRankChange.toLevel).image,
                    accent: accent,
                    hapticsEnabled: settings?.hapticsEnabled ?? true
                ) {
                    self.presentedRankChange = nil
                    try? TrainingStore.acknowledgePendingRankChange(for: stat, context: modelContext)
                }
            }
        }
    }

    private var heroSection: some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 16) {
                sectionKicker("Current Form")

                RankArtworkView(
                    habitName: stat.name,
                    level: snapshot.rank.level,
                    title: snapshot.rank.title,
                    image: snapshot.rank.image,
                    accent: accent
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(stat.name)
                        .font(.system(.title2, design: .rounded).weight(.black))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text(snapshot.overview)
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                HStack(spacing: 10) {
                    summaryPill(title: "Rank", value: "Level \(snapshot.rank.level) · \(snapshot.rank.title)", tint: accent)
                    summaryPill(title: snapshot.weeklyCounterLabel, value: snapshot.weeklyCounterValueLabel, tint: accent.opacity(0.78))
                }

                HStack(spacing: 10) {
                    summaryPill(title: "Current Target", value: MetricFormatting.shortMetric(Double(snapshot.baseline)), tint: TrainingTheme.backgroundTertiary)
                    summaryPill(title: "Pace", value: snapshot.pacingStatus.label, tint: paceTint)
                }

                if let primaryHabit {
                    Button(primaryHabit.measurementType == .booleanSession ? "Log Session" : "Log Progress") {
                        logDraft = LogEntryDraft(habit: primaryHabit)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                }
            }
        }
    }

    private var chargeSection: some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                sectionKicker("Charge")

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.bankedChargeLabel)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(snapshot.nextActionLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    Spacer()
                    chargeDots
                }

                Text(snapshot.chargeExplanation)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)

                HStack(spacing: 10) {
                    summaryPill(title: "Banks", value: snapshot.nextEvaluationLabel, tint: TrainingTheme.backgroundTertiary)
                    summaryPill(title: "Countdown", value: snapshot.bankCountdownLabel, tint: TrainingTheme.backgroundTertiary)
                }

                Text("Logs you enter this week raise your running total immediately, but the rank only changes when the Sunday bank resolves.")
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }

    private func nextRankSection(nextTitle: String) -> some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                sectionKicker("Next Rank")

                HStack(spacing: 14) {
                    RankArtworkView(
                        habitName: stat.name,
                        level: snapshot.rank.level + 1,
                        title: nextTitle,
                        image: snapshot.nextRankImage,
                        accent: accent,
                        style: .compact
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Level \(snapshot.rank.level + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TrainingTheme.textSecondary)
                        Text(nextTitle)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(snapshot.nextRankStatusLabel)
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }

                    Spacer()
                }
            }
        }
    }

    private var linkedHabitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Log Actions")

            if linkedHabits.isEmpty {
                SurfaceCard(accent: accent) {
                    Text("No active habits are linked to this skill yet.")
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            } else {
                ForEach(linkedHabits) { habit in
                    SurfaceCard(accent: accent) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(habit.name)
                                        .font(.headline)
                                        .foregroundStyle(TrainingTheme.textPrimary)
                                    Text("\(MetricFormatting.shortMetric(TrainingStore.total(for: habit, in: TrainingStore.currentWeekInterval(settings: settings)))) / \(MetricFormatting.shortMetric(habit.targetPerPeriod)) \(habit.unitLabel) this week")
                                        .font(.caption)
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                }
                                Spacer()
                                Button("Custom Log") {
                                    logDraft = LogEntryDraft(habit: habit)
                                }
                                .buttonStyle(.bordered)
                                .tint(accent)
                            }

                            HabitQuickActionButtons(habit: habit, accent: accent) { value in
                                logDraft = LogEntryDraft(habit: habit, value: value)
                            }
                        }
                    }
                }
            }
        }
    }

    private var weeklyHistorySection: some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionKicker("This Week")
                    Spacer()
                    Button {
                        showingFullHistory = true
                    } label: {
                        Text("View Full History")
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }

                HStack {
                    Button {
                        moveWeek(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)

                    Spacer()

                    VStack(spacing: 2) {
                        Text(selectedWeek.displayTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text("\(snapshot.weeklyCounterLabel): \(selectedWeekSnapshot.totalLabel)")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }

                    Spacer()

                    Button {
                        moveWeek(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                    .disabled(selectedWeek.start >= currentWeek.start)
                }

                HStack(spacing: 8) {
                    ForEach(selectedWeekSnapshot.daySummaries) { day in
                        WeekDaySummaryView(summary: day, accent: accent)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Selected Week Logs")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)

                    if selectedWeekSnapshot.logEntries.isEmpty {
                        Text("No logs in this week yet.")
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    } else {
                        ForEach(selectedWeekSnapshot.logEntries) { entry in
                            SkillLogEntryRow(entry: entry, accent: accent)
                        }
                    }
                }
            }
        }
    }

    private var recentSessionsSection: some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                sectionKicker("Recent Sessions")

                if recentSnapshots.isEmpty {
                    Text("Recent logs will show up here once you start tracking this skill.")
                        .foregroundStyle(TrainingTheme.textSecondary)
                } else {
                    ForEach(recentSnapshots) { entry in
                        SkillLogEntryRow(entry: entry, accent: accent)
                    }
                }
            }
        }
    }

    private var paceTint: Color {
        switch snapshot.pacingStatus {
        case .ahead:
            return TrainingTheme.positiveStrong
        case .behind:
            return TrainingTheme.warning
        case .onPace:
            return accent
        }
    }

    private var chargeDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<DashboardChargeDots.maximumDots, id: \.self) { index in
                Circle()
                    .fill(index < DashboardChargeDots.filledDots(from: snapshot.rank.progressToNextLevel) ? TrainingTheme.positive : .clear)
                    .overlay(
                        Circle()
                            .stroke(
                                index < DashboardChargeDots.filledDots(from: snapshot.rank.progressToNextLevel)
                                    ? TrainingTheme.positive.opacity(0.34)
                                    : Color.black.opacity(0.72),
                                lineWidth: index < DashboardChargeDots.filledDots(from: snapshot.rank.progressToNextLevel) ? 1 : 1.4
                            )
                    )
                    .frame(width: 12, height: 12)
            }
        }
    }

    private func summaryPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(TrainingTheme.textPrimary)
    }

    private func sectionKicker(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.black))
            .foregroundStyle(TrainingTheme.textMuted)
    }

    private func moveWeek(by offset: Int) {
        guard let nextDate = TrainingStore.progressionCalendar().date(byAdding: .day, value: offset * 7, to: selectedWeek.start) else {
            return
        }
        let boundedDate = min(nextDate, currentWeek.start)
        selectedWeekStart = TrainingStore.progressionWeek(containing: boundedDate).start
    }

    private func presentPendingRankChangeIfNeeded() {
        guard presentedRankChange == nil, let pending = stat.pendingRankChange else { return }
        presentedRankChange = pending
    }
}

private struct WeekDaySummaryView: View {
    let summary: DayLogSummary
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(summary.totalValue > 0 ? summary.totalLabel : "0")
                .font(.caption2.weight(.bold))
                .foregroundStyle(summary.totalValue > 0 ? accent : TrainingTheme.textSecondary)
            Text(String(Calendar.current.component(.day, from: summary.date)))
                .font(.headline.weight(.bold))
                .foregroundStyle(TrainingTheme.textPrimary)
            Text(MetricFormatting.weekday(summary.date))
                .font(.caption2)
                .foregroundStyle(TrainingTheme.textSecondary)
            Text(summary.logCount == 0 ? " " : "\(summary.logCount) logs")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(summary.logCount == 0 ? .clear : TrainingTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(summary.isToday ? accent.opacity(0.14) : TrainingTheme.card.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(summary.isToday ? accent.opacity(0.42) : TrainingTheme.border, lineWidth: summary.isToday ? 1.2 : 1)
        )
    }
}

private struct SkillLogEntryRow: View {
    let entry: SkillLogEntrySnapshot
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.habitName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Spacer()
                Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }

            Text(entry.valueLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)

            if let sessionType = entry.sessionType {
                Text(sessionType)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textSecondary)
            }

            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

private struct SkillHistorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let stat: StatDomain
    let accent: Color

    private var logs: [HabitLog] {
        TrainingStore.recentLogs(for: stat)
    }

    var body: some View {
        List {
            if logs.isEmpty {
                Text("No logs yet.")
                    .foregroundStyle(TrainingTheme.textSecondary)
            } else {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(log.habit?.name ?? stat.name)
                                .font(.headline)
                                .foregroundStyle(TrainingTheme.textPrimary)
                            Spacer()
                            Text(log.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }

                        Text(MetricFormatting.metric(log.numericValue, unit: log.habit?.unitLabel ?? ""))
                            .foregroundStyle(accent)

                        if let sessionType = log.sessionType {
                            Text(sessionType)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }

                        if !log.note.isEmpty {
                            Text(log.note)
                                .font(.caption)
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .swipeActions {
                        Button(role: .destructive) {
                            try? TrainingStore.delete(log, context: modelContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle("\(stat.name) History")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
}

private struct RankChangeRevealView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let statName: String
    let change: PendingRankChange
    let image: RankImageReference?
    let accent: Color
    let hapticsEnabled: Bool
    let dismiss: () -> Void
    @State private var pulseScale: CGFloat = 0.9
    @State private var flashOpacity = 0.16
    @State private var contentOpacity = 0.0
    @State private var contentOffset: CGFloat = 24

    private var highlight: Color {
        change.direction == .up ? .orange : .blue
    }

    private var titleText: String {
        change.direction == .up ? "Rank Increased" : "Rank Reduced"
    }

    private var subtitleText: String {
        change.direction == .up
            ? "Your weekly surplus pushed this skill into a stronger form."
            : "Recent weekly debt pulled this skill down. Keep going and build it back."
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    highlight.opacity(change.direction == .up ? 0.95 : 0.72),
                    TrainingTheme.background,
                    TrainingTheme.backgroundSecondary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Color.white
                    .opacity(flashOpacity)
                    .ignoresSafeArea()
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 24)

                AuraView(color: highlight, size: 250)
                    .scaleEffect(pulseScale)
                    .overlay(alignment: .center) {
                        Image(systemName: change.direction == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 52, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: highlight.opacity(0.45), radius: 18, x: 0, y: 6)
                    }

                VStack(spacing: 18) {
                    VStack(alignment: .center, spacing: 8) {
                        Text(titleText)
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(subtitleText)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }

                    RankArtworkView(
                        habitName: statName,
                        level: change.toLevel,
                        title: change.toTitle,
                        image: image,
                        accent: highlight
                    )
                    .frame(maxHeight: 280)

                    HStack(spacing: 12) {
                        rankDeltaPill(title: "From", value: "Lv \(change.fromLevel) · \(change.fromTitle)")
                        rankDeltaPill(title: "To", value: "Lv \(change.toLevel) · \(change.toTitle)")
                    }

                    Button("Continue") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(highlight)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(TrainingTheme.card.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: highlight.opacity(0.24), radius: 24, x: 0, y: 14)
                .opacity(contentOpacity)
                .offset(y: contentOffset)

                Spacer()
            }
            .padding(20)
        }
        .task {
            await runRevealSequence()
        }
    }

    private func runRevealSequence() async {
        guard !reduceMotion else {
            pulseScale = 1
            flashOpacity = change.direction == .up ? 0.24 : 0.12
            contentOpacity = 1
            contentOffset = 0
            return
        }

        let pulseValues: [CGFloat] = change.direction == .up ? [1.03, 1.08, 1.14] : [1.01, 1.04]
        let flashValues: [Double] = change.direction == .up ? [0.22, 0.34, 0.6] : [0.18, 0.28]

        for (index, scale) in pulseValues.enumerated() {
            withAnimation(.easeInOut(duration: change.direction == .up ? 0.22 : 0.3)) {
                pulseScale = scale
                flashOpacity = flashValues[min(index, flashValues.count - 1)]
            }
            if hapticsEnabled {
                if change.direction == .up {
                    HapticsService.rankPulse(intensity: index)
                } else {
                    HapticsService.rankDropPulse(intensity: index)
                }
            }
            try? await Task.sleep(for: .milliseconds(change.direction == .up ? 220 : 300))
            withAnimation(.easeInOut(duration: change.direction == .up ? 0.18 : 0.24)) {
                pulseScale = 0.96
                flashOpacity = change.direction == .up ? 0.14 : 0.1
            }
            try? await Task.sleep(for: .milliseconds(change.direction == .up ? 120 : 180))
        }

        withAnimation(.easeOut(duration: 0.34)) {
            flashOpacity = change.direction == .up ? 0.82 : 0.42
        }
        if hapticsEnabled {
            if change.direction == .up {
                HapticsService.success()
            } else {
                HapticsService.rankDropPulse(intensity: 1)
            }
        }
        try? await Task.sleep(for: .milliseconds(change.direction == .up ? 260 : 320))
        withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) {
            flashOpacity = change.direction == .up ? 0.08 : 0.06
            pulseScale = 1
            contentOpacity = 1
            contentOffset = 0
        }
    }

    private func rankDeltaPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlight.opacity(0.12))
        )
    }
}
