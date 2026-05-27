import SwiftData
import SwiftUI

struct SkillDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]

    let stat: StatDomain
    let opensLogSheetOnAppear: Bool

    @State private var logDraft: LogEntryDraft?
    @State private var presentedRankChange: PendingRankChange?
    @State private var selectedWeekStart = TrainingStore.progressionWeek(containing: .now).start
    @State private var selectedDay = TrainingStore.progressionCalendar().startOfDay(for: .now)
    @State private var showingFullHistory = false
    @State private var showingCharacterRoster = false
    @State private var presentedHelpTopic: SkillHelpTopic?
    @State private var hasOpenedInitialLogSheet = false
    @State private var showingCalibrationSheet = false
    @State private var showingGoalEditorForNew = false
    @State private var editingGoal: Goal?

    init(stat: StatDomain, opensLogSheetOnAppear: Bool = false) {
        self.stat = stat
        self.opensLogSheetOnAppear = opensLogSheetOnAppear
    }

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
        TrainingStore.weekSnapshot(for: stat, week: selectedWeek, context: modelContext)
    }

    private var effectiveSelectedDay: Date {
        let calendar = TrainingStore.progressionCalendar()
        let normalizedSelectedDay = calendar.startOfDay(for: selectedDay)

        if selectedWeekSnapshot.daySummaries.contains(where: { calendar.isDate($0.date, inSameDayAs: normalizedSelectedDay) }) {
            return normalizedSelectedDay
        }

        return defaultSelectedDay(for: selectedWeek)
    }

    private var selectedDayLogs: [SkillLogEntrySnapshot] {
        let calendar = TrainingStore.progressionCalendar()
        return selectedWeekSnapshot.logEntries.filter { calendar.isDate($0.date, inSameDayAs: effectiveSelectedDay) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroSection
                calibrationSection
                chargeSection

                if let nextTitle = snapshot.rank.nextTitle, !snapshot.rank.isAtMaximumRank {
                    nextRankSection(nextTitle: nextTitle)
                }

                goalsSection
                linkedHabitsSection
                weeklyHistorySection
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
            selectedDay = defaultSelectedDay(for: currentWeek)
            try? TrainingStore.markRankChangeSeen(for: stat, context: modelContext)
            presentPendingRankChangeIfNeeded()
            openInitialLogSheetIfNeeded()
        }
        .onChange(of: stat.pendingRankChangeRecordedAt) { _, _ in
            presentPendingRankChangeIfNeeded()
        }
        .onChange(of: selectedWeekStart) { _, _ in
            selectedDay = defaultSelectedDay(for: selectedWeek)
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
        .sheet(item: $presentedHelpTopic) { topic in
            SkillHelpSheet(title: topic.title, bodyText: helpBody(for: topic))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFullHistory) {
            NavigationStack {
                SkillHistorySheetView(stat: stat, accent: accent)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingCalibrationSheet) {
            NavigationStack {
                SkillCalibrationSheet(stat: stat)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingGoalEditorForNew) {
            NavigationStack {
                GoalEditorView(goal: nil, initialStatKey: stat.statKey)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingGoal) { goal in
            NavigationStack {
                GoalEditorView(goal: goal, initialStatKey: stat.statKey)
            }
            .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showingCharacterRoster) {
            SkillCharacterRosterView(stat: stat)
        }
        .fullScreenCover(isPresented: Binding(
            get: { presentedRankChange != nil },
            set: { if !$0 { presentedRankChange = nil } }
        )) {
            if let presentedRankChange {
                RankChangeRevealView(
                    statName: stat.name,
                    statKey: stat.statKey ?? .strength,
                    change: presentedRankChange,
                    resolution: TrainingStore.latestRankChangeResolution(for: stat),
                    weeklyUnitLabel: TrainingStore.weeklyUnitLabel(for: stat),
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(snapshot.rank.title)
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("LV \(snapshot.rank.level)")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(accent)
            }

            Button {
                showingCharacterRoster = true
            } label: {
                RankArtworkView(
                    habitName: stat.name,
                    level: snapshot.rank.level,
                    title: snapshot.rank.title,
                    image: snapshot.rank.image,
                    accent: accent
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stat.name) character roster")
            .accessibilityHint("Opens the full progression roster for this skill.")

            HStack(spacing: 16) {
                heroMetric(title: snapshot.weeklyCounterLabel, value: snapshot.weeklyCounterValueLabel, tint: accent)
                heroMetric(title: "Pace", value: snapshot.pacingStatus.label, tint: paceTint)
            }
            .frame(maxWidth: .infinity)

            if let primaryHabit {
                HStack {
                    Spacer()

                    Button(primaryHabit.measurementType == .booleanSession ? "Log Session" : "Log Progress") {
                        logDraft = LogEntryDraft(habit: primaryHabit)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Spacer()
                }
            }
        }
    }

    private func openInitialLogSheetIfNeeded() {
        guard opensLogSheetOnAppear, !hasOpenedInitialLogSheet, let primaryHabit else { return }
        hasOpenedInitialLogSheet = true
        logDraft = LogEntryDraft(habit: primaryHabit)
    }

    private var skillGoals: [Goal] {
        guard let statKey = stat.statKey else { return [] }
        return (try? TrainingStore.fetchGoals(for: statKey, context: modelContext)) ?? []
    }

    private var calibrationSection: some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionKicker("Calibration")
                    Spacer()
                    Button {
                        showingCalibrationSheet = true
                    } label: {
                        Label("Recalibrate", systemImage: "slider.horizontal.3")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }

                HStack(spacing: 0) {
                    calibrationCell(title: "Baseline", value: "\(stat.currentBaseline)")
                    Divider().frame(height: 36)
                    calibrationCell(title: "Target", value: stat.targetValue.map { "\($0)" } ?? "—")
                    if settings?.showPersonalMaxInUI ?? true {
                        Divider().frame(height: 36)
                        calibrationCell(title: "Personal Max", value: stat.personalMaxValue.map { "\($0)" } ?? "—")
                    }
                }

                Text(calibrationStatusLabel)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }

    private func calibrationCell(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textMuted)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(TrainingTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var calibrationStatusLabel: String {
        let actual = TrainingStore.currentWeekTotal(for: stat, settings: settings)
        let baseline = Double(stat.currentBaseline)
        let target = stat.targetValue.map(Double.init)
        let unit = TrainingStore.weeklyUnitLabel(for: stat)

        if let target {
            if actual >= target { return "Goal target met this week. Strong work." }
            if actual >= baseline { return "Maintained baseline. Goal still short by \(MetricFormatting.shortMetric(target - actual)) \(unit)." }
            return "Below baseline. Focus here to hold form."
        }

        if baseline > 0, actual >= baseline { return "Maintained baseline this week." }
        if baseline > 0 { return "Below baseline. \(MetricFormatting.shortMetric(baseline - actual)) \(unit) to maintain." }
        return "No baseline set yet."
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Goals")
                Spacer()
                Button {
                    showingGoalEditorForNew = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(accent)
            }

            if skillGoals.isEmpty {
                SurfaceCard(accent: accent) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This skill is training from baseline only.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text("Create a goal when you want to push beyond your current weekly normal.")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                }
            } else {
                ForEach(skillGoals) { goal in
                    SkillGoalRow(goal: goal, accent: accent) {
                        editingGoal = goal
                    }
                }
            }
        }
    }

    private var chargeSection: some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeaderRow("Charge", topic: .charge)

                Text(snapshot.bankedChargeLabel)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(TrainingTheme.textPrimary)

                chargeDots
                    .frame(maxWidth: .infinity)

                Text(snapshot.nextRankStatusLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func nextRankSection(nextTitle: String) -> some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeaderRow("Next Rank", topic: .nextRank)

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
                        Text("LV \(snapshot.rank.level + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TrainingTheme.textSecondary)
                        Text(nextTitle)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(snapshot.nextRankStatusLabel)
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)
                            .lineLimit(2)
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
                        VStack(spacing: 12) {
                            VStack(spacing: 4) {
                                Text(habit.name)
                                    .font(.headline)
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                    .multilineTextAlignment(.center)
                                Text("\(MetricFormatting.shortMetric(TrainingStore.total(for: habit, in: TrainingStore.currentWeekInterval(settings: settings)))) / \(MetricFormatting.shortMetric(habit.targetPerPeriod)) \(habit.unitLabel) this week")
                                    .font(.caption)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)

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
                    HStack(spacing: 10) {
                        sectionKicker("This Week")

                        Button {
                            presentedHelpTopic = .thisWeek
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TrainingTheme.textMuted)
                                .frame(width: 26, height: 26)
                                .background(
                                    Circle()
                                        .fill(.white.opacity(0.72))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("This Week help")
                    }

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
                        WeekDaySummaryView(
                            summary: day,
                            accent: accent,
                            isSelected: isSelectedDay(day.date)
                        ) {
                            selectedDay = TrainingStore.progressionCalendar().startOfDay(for: day.date)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedDayLogTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)

                    if selectedDayLogs.isEmpty {
                        Text("No logs on this day.")
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    } else {
                        ForEach(selectedDayLogs) { entry in
                            SkillLogEntryRow(entry: entry, accent: accent)
                        }
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
        SignedChargeMeter(charge: snapshot.charge.current, pendingProgress: snapshot.weeklyTargetProgress, socketSize: 14, spacing: 7)
    }

    private var selectedDayLogTitle: String {
        let weekday = effectiveSelectedDay.formatted(.dateTime.weekday(.wide))
        let date = effectiveSelectedDay.formatted(.dateTime.month(.abbreviated).day())
        return "\(weekday) Logs · \(date)"
    }

    private func heroMetric(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textMuted)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(tint)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeaderRow(_ title: String, topic: SkillHelpTopic?) -> some View {
        HStack(spacing: 10) {
            sectionKicker(title)

            Spacer(minLength: 8)

            if let topic {
                Button {
                    presentedHelpTopic = topic
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TrainingTheme.textMuted)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.72))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) help")
            }
        }
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

    private func isSelectedDay(_ date: Date) -> Bool {
        TrainingStore.progressionCalendar().isDate(date, inSameDayAs: effectiveSelectedDay)
    }

    private func defaultSelectedDay(for week: WeekRange) -> Date {
        let calendar = TrainingStore.progressionCalendar()
        if calendar.isDate(week.start, inSameDayAs: currentWeek.start) {
            return calendar.startOfDay(for: .now)
        }
        return calendar.startOfDay(for: week.start)
    }

    private func helpBody(for topic: SkillHelpTopic) -> String {
        switch topic {
        case .charge:
            return snapshot.chargeExplanation
        default:
            return topic.body
        }
    }

    private func presentPendingRankChangeIfNeeded() {
        guard presentedRankChange == nil, let pending = stat.pendingRankChange else { return }
        presentedRankChange = pending
    }
}

private enum SkillHelpTopic: String, Identifiable {
    case currentForm
    case charge
    case nextRank
    case thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentForm:
            return "Current Form"
        case .charge:
            return "Charge"
        case .nextRank:
            return "Next Rank"
        case .thisWeek:
            return "This Week"
        }
    }

    var body: String {
        switch self {
        case .currentForm:
            return "Tap the character art to open the full roster and browse every form in this skill's progression."
        case .charge:
            return "Charge runs from -4 to +4. Use the help details here to see exactly how this skill's current rank converts strong or weak weeks into charge."
        case .nextRank:
            return "This preview shows the next form you are building toward. Locked forms stay ahead of you until you gain enough Charge."
        case .thisWeek:
            return "This section shows your current progression week. Tap any day tile to swap the lower log list to that day while today's border stays visible for orientation."
        }
    }
}

private struct SkillHelpSheet: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(TrainingTheme.textPrimary)

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(TrainingTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(TrainingTheme.background.ignoresSafeArea())
    }
}

private struct WeekDaySummaryView: View {
    let summary: DayLogSummary
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(summary.totalValue > 0 ? summary.totalLabel : "0")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle((summary.totalValue > 0 || isSelected) ? accent : TrainingTheme.textSecondary)
                Text(String(Calendar.current.component(.day, from: summary.date)))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(MetricFormatting.weekday(summary.date))
                    .font(.caption2)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.16) : TrainingTheme.card.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var borderColor: Color {
        if summary.isToday {
            return accent.opacity(0.42)
        }
        if isSelected {
            return accent.opacity(0.24)
        }
        return TrainingTheme.border
    }

    private var borderWidth: CGFloat {
        summary.isToday ? 1.2 : 1
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

            if let attribution = entry.healthAttribution {
                HealthAttributionView(attribution: attribution)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// Compact, honest provenance for an Apple Health import: where it came from,
/// which skill it touched, and whether it actually counted toward the week.
struct HealthAttributionView: View {
    let attribution: HealthLogAttribution

    private var skillColor: Color {
        TrainingArcConfig.color(for: attribution.mappedSkillColorToken)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink)
                Text(attribution.sourceDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textSecondary)
            }

            FlowChips(chips: chips)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TrainingTheme.background.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(TrainingTheme.border, lineWidth: 1)
        )
    }

    private var chips: [HealthAttributionChip] {
        var result: [HealthAttributionChip] = []
        result.append(HealthAttributionChip(text: attribution.mappedSkillName, tint: skillColor, systemImage: "arrow.triangle.branch"))

        if attribution.durationMinutes > 0 {
            result.append(HealthAttributionChip(text: "\(Int(attribution.durationMinutes.rounded())) min", tint: TrainingTheme.textSecondary, systemImage: "clock"))
        }

        if attribution.ignoredAsDuplicate {
            result.append(HealthAttributionChip(text: "Ignored duplicate", tint: TrainingTheme.textSecondary, systemImage: "doc.on.doc"))
        } else if attribution.countedTowardWeeklyProgress {
            result.append(HealthAttributionChip(text: "Counted this week", tint: TrainingTheme.positive, systemImage: "checkmark.circle"))
        } else {
            result.append(HealthAttributionChip(text: "Not counted", tint: TrainingTheme.textSecondary, systemImage: "minus.circle"))
        }

        if attribution.affectedGoal {
            result.append(HealthAttributionChip(text: "Counts toward a goal", tint: TrainingTheme.cold, systemImage: "target"))
        }

        if attribution.needsReview {
            result.append(HealthAttributionChip(text: "Overlap — review", tint: TrainingTheme.warning, systemImage: "exclamationmark.triangle"))
        }

        return result
    }
}

private struct HealthAttributionChip: Identifiable {
    let id = UUID()
    let text: String
    let tint: Color
    let systemImage: String
}

private struct FlowChips: View {
    let chips: [HealthAttributionChip]

    var body: some View {
        FlexibleChipLayout(spacing: 6, lineSpacing: 6) {
            ForEach(chips) { chip in
                HStack(spacing: 4) {
                    Image(systemName: chip.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                    Text(chip.text)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(chip.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(chip.tint.opacity(0.12))
                )
            }
        }
    }
}

/// Lightweight wrapping layout so attribution chips flow onto multiple lines
/// without overflowing narrow log rows.
private struct FlexibleChipLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = (rows.last?.isEmpty == true ? 0 : spacing) + size.width
            if currentRowWidth + needed > maxWidth, rows.last?.isEmpty == false {
                rows.append([size])
                currentRowWidth = size.width
            } else {
                rows[rows.count - 1].append(size)
                currentRowWidth += needed
            }
        }

        let height = rows.reduce(CGFloat.zero) { partial, row in
            let rowHeight = row.map(\.height).max() ?? 0
            return partial + rowHeight
        } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: maxWidth == .infinity ? (rows.first?.reduce(0) { $0 + $1.width } ?? 0) : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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

    private var attributionResolver: TrainingStore.HealthAttributionContext {
        TrainingStore.healthAttributionContext(context: modelContext)
    }

    var body: some View {
        let resolver = attributionResolver
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

                        if let attribution = resolver.attribution(for: log) {
                            HealthAttributionView(attribution: attribution)
                                .padding(.top, 2)
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

private enum RankRevealPhase {
    case summary
    case revealing
    case resolved
}

private struct RankChangeRevealView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let statName: String
    let statKey: StatKey
    let change: PendingRankChange
    let resolution: WeeklyResolution?
    let weeklyUnitLabel: String
    let accent: Color
    let hapticsEnabled: Bool
    let dismiss: () -> Void

    @State private var phase: RankRevealPhase = .summary
    @State private var burstToken = 0
    @State private var showNewEmblem = false

    private var fromImage: RankImageReference? {
        TrainingArcConfig.rankDefinition(for: statKey, level: change.fromLevel).image
    }

    private var toImage: RankImageReference? {
        TrainingArcConfig.rankDefinition(for: statKey, level: change.toLevel).image
    }

    private var highlight: Color {
        change.direction == .up ? TrainingTheme.positiveStrong : TrainingTheme.danger
    }

    private var titleText: String {
        switch phase {
        case .summary:
            return change.direction == .up ? "Rank Up Pending" : "Rank Drop Pending"
        case .revealing:
            return change.direction == .up ? "Rank Increased" : "Rank Reduced"
        case .resolved:
            return change.direction == .up ? "Rank Increased" : "Rank Reduced"
        }
    }

    private var subtitleText: String {
        switch phase {
        case .summary:
            return change.direction == .up
                ? "Your past week pushed this skill above its current rank. Tap Reveal to see the new form."
                : "Your past week pulled this skill below its rank target. Tap Reveal to see the new form."
        case .revealing, .resolved:
            return change.direction == .up
                ? "Your weekly surplus pushed this skill into a stronger form."
                : "Recent weekly debt pulled this skill down. Keep going and build it back."
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    highlight.opacity(change.direction == .up ? 0.78 : 0.65),
                    TrainingTheme.background,
                    TrainingTheme.backgroundSecondary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 12)

                    emblemStack
                        .frame(height: 280)

                    titleBlock

                    if phase == .summary, let resolution {
                        weeklySummaryCard(resolution: resolution)
                    }

                    if phase == .resolved {
                        deltaPills
                    }

                    actionRow
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var emblemStack: some View {
        ZStack {
            AuraView(color: highlight, size: 240)
                .opacity(phase == .revealing ? 0.85 : 0.55)

            if phase == .revealing || phase == .resolved {
                ParticleBurstView(
                    style: change.direction == .up ? .confetti : .smoke,
                    tint: change.direction == .up ? .yellow : .gray,
                    triggerToken: burstToken
                )
                .frame(width: 320, height: 320)
            }

            if phase == .summary {
                RankArtworkView(
                    habitName: statName,
                    level: change.fromLevel,
                    title: change.fromTitle,
                    image: fromImage,
                    accent: highlight,
                    style: .compact
                )
                .overlay(alignment: .top) {
                    Image(systemName: change.direction == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(highlight)
                        .background(
                            Circle()
                                .fill(.white)
                                .frame(width: 50, height: 50)
                        )
                        .offset(y: -22)
                }
                .transition(.opacity)
            }

            if phase == .revealing || phase == .resolved {
                RankArtworkView(
                    habitName: statName,
                    level: change.toLevel,
                    title: change.toTitle,
                    image: toImage,
                    accent: highlight,
                    style: .compact
                )
                .scaleEffect(showNewEmblem ? 1 : 0.4)
                .opacity(showNewEmblem ? 1 : 0)
                .animation(.spring(response: 0.62, dampingFraction: 0.78), value: showNewEmblem)
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text(titleText)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(TrainingTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitleText)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(TrainingTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch phase {
        case .summary:
            Button {
                triggerReveal()
            } label: {
                Label("Reveal", systemImage: change.direction == .up ? "sparkles" : "cloud.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .tint(highlight)
            .controlSize(.large)
        case .revealing:
            ProgressView()
                .controlSize(.regular)
                .tint(highlight)
                .padding(.vertical, 4)
        case .resolved:
            Button("Continue") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(highlight)
            .controlSize(.large)
            .frame(maxWidth: 280)
        }
    }

    private var deltaPills: some View {
        HStack(spacing: 10) {
            rankDeltaPill(title: "From", value: "Lv \(change.fromLevel)\n\(change.fromTitle)")
            Image(systemName: change.direction == .up ? "arrow.right" : "arrow.right")
                .font(.title3.weight(.bold))
                .foregroundStyle(highlight)
            rankDeltaPill(title: "To", value: "Lv \(change.toLevel)\n\(change.toTitle)")
        }
    }

    private func weeklySummaryCard(resolution: WeeklyResolution) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last Week")
                .font(.caption.weight(.black))
                .foregroundStyle(TrainingTheme.textMuted)

            HStack {
                summaryStat(
                    label: "Logged",
                    value: "\(MetricFormatting.shortMetric(resolution.actualCompletedValue)) \(weeklyUnitLabel)"
                )
                Spacer(minLength: 8)
                summaryStat(
                    label: "Target",
                    value: "\(MetricFormatting.shortMetric(resolution.expectedTotal)) \(weeklyUnitLabel)"
                )
            }

            HStack {
                summaryStat(
                    label: "Charges Earned",
                    value: resolution.chargesEarned > 0 ? "+\(resolution.chargesEarned)" : "\(resolution.chargesEarned)"
                )
                Spacer(minLength: 8)
                summaryStat(
                    label: "Final Charge",
                    value: DashboardChargeDots.summaryLabel(for: resolution.storedChargesAfter)
                )
            }

            if !resolution.summaryText.isEmpty {
                Text(resolution.summaryText)
                    .font(.footnote)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TrainingTheme.card.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(highlight.opacity(0.22), lineWidth: 1)
        )
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(TrainingTheme.textMuted)
            Text(value)
                .font(.headline.weight(.heavy))
                .foregroundStyle(TrainingTheme.textPrimary)
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
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlight.opacity(0.12))
        )
    }

    private func triggerReveal() {
        if hapticsEnabled {
            if change.direction == .up {
                HapticsService.success()
            } else {
                HapticsService.rankDropPulse(intensity: 2)
            }
        }

        withAnimation(.easeInOut(duration: 0.32)) {
            phase = .revealing
        }
        burstToken += 1

        Task { @MainActor in
            if reduceMotion {
                showNewEmblem = true
            } else {
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation { showNewEmblem = true }
                if hapticsEnabled {
                    HapticsService.impact(style: .medium)
                }
            }

            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 1300))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                phase = .resolved
            }
        }
    }
}

struct SkillGoalRow: View {
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    let accent: Color
    let onTap: () -> Void

    private var progress: GoalProgressSnapshot {
        TrainingStore.goalProgress(for: goal, context: modelContext)
    }

    var body: some View {
        Button(action: onTap) {
            SurfaceCard(accent: accent) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(goal.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Spacer()
                        Text(progress.statusLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(statusColor))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(TrainingTheme.backgroundTertiary.opacity(0.4))
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(accent)
                                .frame(width: proxy.size.width * progress.progressRatio)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(MetricFormatting.shortMetric(progress.currentValue)) / \(MetricFormatting.shortMetric(progress.targetValue))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                            .monospacedDigit()
                        Spacer()
                        Text(progress.timeRemainingLabel)
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch goal.status {
        case .completed: return TrainingTheme.positive
        case .paused: return TrainingTheme.textMuted
        case .archived, .failed: return TrainingTheme.textSecondary
        case .active:
            switch progress.paceStatus {
            case .complete, .ahead: return TrainingTheme.positive
            case .onPace: return accent
            case .atRisk: return TrainingTheme.warning
            case .behind: return TrainingTheme.danger
            }
        }
    }
}

struct SkillCalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let stat: StatDomain

    @State private var baselineText: String
    @State private var targetText: String
    @State private var maxText: String
    @State private var maintenanceText: String
    @State private var primaryMeasurementType: MeasurementType

    init(stat: StatDomain) {
        self.stat = stat
        _baselineText = State(initialValue: "\(stat.currentBaseline)")
        _targetText = State(initialValue: stat.targetValue.map { "\($0)" } ?? "")
        _maxText = State(initialValue: stat.personalMaxValue.map { "\($0)" } ?? "")
        _maintenanceText = State(initialValue: stat.maintenanceFloor.map { "\($0)" } ?? "")
        _primaryMeasurementType = State(initialValue: TrainingStore.primaryHabit(for: stat)?.measurementType ?? .count)
    }

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var statKey: StatKey {
        stat.statKey ?? .strength
    }

    private var unitLabel: String {
        TrainingStore.weeklyUnitLabel(for: stat)
    }

    private var suggestedBaselineSummary: String {
        let recent = (stat.weeklyResolutions ?? []).sorted { $0.weekStartDate > $1.weekStartDate }.prefix(4)
        guard !recent.isEmpty else { return "Not enough history yet for a suggestion." }
        let average = recent.map(\.actualCompletedValue).reduce(0, +) / Double(recent.count)
        return "Last \(recent.count) weeks averaged \(MetricFormatting.shortMetric(average)) \(unitLabel)."
    }

    var body: some View {
        Form {
            Section {
                Text("These values define your steady-state weekly expectations — what drives the dashboard rings and rank progression.")
                    .font(.footnote)
                    .foregroundStyle(TrainingTheme.textSecondary)
                Text("If you want a time-scoped push above these (with a deadline and priority), create a Goal on the Goals tab instead.")
                    .font(.footnote)
                    .foregroundStyle(TrainingTheme.textSecondary)
            } header: {
                Text("Skill Targets vs Goals")
            }

            Section {
                Text(suggestedBaselineSummary)
                    .font(.footnote)
                    .foregroundStyle(TrainingTheme.textSecondary)
            } header: {
                Text("Recent Performance")
            }

            if TrainingStore.primaryHabit(for: stat) != nil {
                Section {
                    Picker("Tracked as", selection: $primaryMeasurementType) {
                        ForEach(MeasurementType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } header: {
                    Text("Measurement Unit")
                } footer: {
                    Text("Changing the unit affects how new logs and quick-log buttons behave. Past logs keep their original units.")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }

            Section {
                calibrationField(title: "Baseline", text: $baselineText, hint: "What you honestly do in a normal week.")
            } header: {
                Text("Baseline (required)")
            }

            Section {
                calibrationField(title: "Target", text: $targetText, hint: "What you’re training toward. Leave blank if none.")
                calibrationField(title: "Personal Max", text: $maxText, hint: "Your believable maximum in a strong week.")
                calibrationField(title: "Maintenance Floor", text: $maintenanceText, hint: "Lowest acceptable maintenance level (optional).")
            } header: {
                Text("Optional Calibration")
            } footer: {
                Text("Goals don’t replace your baseline. Missing an ambitious target while still meeting baseline counts as ‘maintained’.")
                    .font(.caption)
            }

            Section {
                Button {
                    let suggestedTarget = TrainingArcConfig.suggestedTargetValue(for: statKey, baseline: parsedBaseline)
                    targetText = "\(suggestedTarget)"
                    let suggestedMax = TrainingArcConfig.suggestedPersonalMaxValue(for: statKey, baseline: parsedBaseline, target: suggestedTarget)
                    maxText = "\(suggestedMax)"
                } label: {
                    Label("Suggest values for me", systemImage: "wand.and.stars")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle("Recalibrate \(stat.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
    }

    private func calibrationField(title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, text: text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(unitLabel)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(TrainingTheme.textMuted)
        }
    }

    private var parsedBaseline: Int {
        Int(baselineText) ?? stat.currentBaseline
    }

    private func save() {
        let baseline = max(0, parsedBaseline)
        let target = Int(targetText)
        let personalMax = Int(maxText)
        let maintenance = Int(maintenanceText)
        let clamped = TrainingArcConfig.clampCalibration(
            baseline: baseline,
            target: target,
            personalMax: personalMax,
            maintenance: maintenance
        )

        stat.currentBaseline = baseline
        stat.targetValue = clamped.target
        stat.personalMaxValue = clamped.max
        stat.maintenanceFloor = clamped.maintenance
        stat.updatedAt = .now

        if let primary = TrainingStore.primaryHabit(for: stat),
           primary.measurementType != primaryMeasurementType {
            primary.measurementType = primaryMeasurementType
            primary.updatedAt = .now
        }

        try? modelContext.save()
        _ = try? TrainingStore.refreshProgress(for: stat, context: modelContext, reason: .appRefresh)
        dismiss()
    }
}
