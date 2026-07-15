import SwiftData
import SwiftUI

struct SkillDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @Query private var skillGoals: [Goal]
    @Query private var unmatchedWorkouts: [HealthImportedWorkout]

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
    @State private var showingHabitEditorForNew = false
    @State private var editingHabit: Habit?
    @State private var showingUnmatched = false
    @State private var scrollOffset: CGFloat = 0

    /// `skillGoals`/`unmatchedWorkouts` are `@Query`-backed (not manual
    /// `context.fetch`/`fetchCount` calls) so scroll-driven re-renders of this
    /// view (see `scrollOffset` below) don't re-run a database round trip on
    /// every frame — SwiftData only re-evaluates them when the underlying
    /// model type actually changes.
    init(stat: StatDomain, opensLogSheetOnAppear: Bool = false) {
        self.stat = stat
        self.opensLogSheetOnAppear = opensLogSheetOnAppear
        let statKeyRaw = stat.statKey?.rawValue ?? "__none__"
        _skillGoals = Query(
            filter: #Predicate<Goal> { $0.linkedStatKeyRaw == statKeyRaw },
            sort: [SortDescriptor(\Goal.statusRaw), SortDescriptor(\Goal.createdAt, order: .reverse)]
        )
        let statKey = stat.key
        _unmatchedWorkouts = Query(
            filter: #Predicate<HealthImportedWorkout> { record in
                record.statKeyRaw == statKey &&
                record.awaitingHabitAssignment == true &&
                record.isDuplicate == false
            }
        )
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

    private var unmatchedCount: Int {
        unmatchedWorkouts.count
    }

    private var unmatchedImportsBanner: some View {
        Button {
            showingUnmatched = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "questionmark")
                        .font(.headline.weight(.black))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(unmatchedCount == 1 ? "1 imported workout to review" : "\(unmatchedCount) imported workouts to review")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text("Match these Apple Health workouts to a \(stat.name) habit so they count.")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TrainingTheme.textMuted)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(accent.opacity(0.40), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the imported workouts to resolve")
    }

    private var currentWeek: WeekRange {
        TrainingStore.progressionWeek(containing: .now)
    }

    private var selectedWeek: WeekRange {
        TrainingStore.progressionWeek(containing: selectedWeekStart)
    }

    private func effectiveSelectedDay(in weekSnapshot: SkillWeekSnapshot) -> Date {
        let calendar = TrainingStore.progressionCalendar()
        let normalizedSelectedDay = calendar.startOfDay(for: selectedDay)

        if weekSnapshot.daySummaries.contains(where: { calendar.isDate($0.date, inSameDayAs: normalizedSelectedDay) }) {
            return normalizedSelectedDay
        }

        return defaultSelectedDay(for: selectedWeek)
    }

    private func selectedDayLogs(in weekSnapshot: SkillWeekSnapshot, day: Date) -> [SkillLogEntrySnapshot] {
        let calendar = TrainingStore.progressionCalendar()
        return weekSnapshot.logEntries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        // Computed once per body evaluation rather than as instance computed
        // properties: `scrollOffset` (below) changes on every scroll frame,
        // and each of these previously re-ran its full TrainingStore query on
        // every access from every section — the classic per-render O(n)
        // blowup already fixed elsewhere in this audit (Dashboard, goal
        // badge). Threading single values through keeps it to one query per
        // render regardless of how many sections read it.
        let snapshot = TrainingStore.progressSnapshot(for: stat, settings: settings)
        let weekSnapshot = TrainingStore.weekSnapshot(for: stat, week: selectedWeek, context: modelContext)
        let effectiveDay = effectiveSelectedDay(in: weekSnapshot)
        let dayLogs = selectedDayLogs(in: weekSnapshot, day: effectiveDay)

        ScrollView(showsIndicators: false) {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SkillDetailScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named("skillDetailScroll")).minY
                )
            }
            .frame(height: 0)

            VStack(alignment: .leading, spacing: 18) {
                heroSection(snapshot: snapshot)

                if unmatchedCount > 0 {
                    unmatchedImportsBanner
                }

                weeklyHistorySection(snapshot: snapshot, weekSnapshot: weekSnapshot, effectiveDay: effectiveDay, dayLogs: dayLogs)
                calibrationSection()
                progressionSection(snapshot: snapshot)
                goalsSection
                linkedHabitsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .coordinateSpace(name: "skillDetailScroll")
        .background(
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let primaryHabit {
                StickyLogButton(
                    title: primaryHabit.measurementType == .booleanSession ? "Log Session" : "Log Progress",
                    accent: accent
                ) {
                    logDraft = LogEntryDraft(habit: primaryHabit)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(stat.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .opacity(compactTitleOpacity)
            }
        }
        .onPreferenceChange(SkillDetailScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
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
                    let saved = try? TrainingStore.log(
                        habit: submittedDraft.habit,
                        value: submittedDraft.value,
                        date: submittedDraft.date,
                        sessionType: submittedDraft.sessionType,
                        note: submittedDraft.note,
                        source: submittedDraft.sourceType,
                        context: modelContext
                    )

                    if saved != nil, settings?.hapticsEnabled ?? true {
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
        .sheet(isPresented: $showingHabitEditorForNew) {
            HabitEditorView(habit: nil, initialStatID: stat.id)
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(habit: habit)
        }
        #if canImport(HealthKit)
        .sheet(isPresented: $showingUnmatched) {
            UnmatchedWorkoutSheet(stat: stat)
        }
        #endif
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

    private func heroSection(snapshot: SkillProgressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: stat.iconName)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(accent)
                Text(stat.name.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.8)
                    .foregroundStyle(accent)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                V4SerifTitle(text: snapshot.rank.title, size: 36)

                Spacer(minLength: 8)

                V4LevelBadge(level: snapshot.rank.level, tint: accent)
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

            HStack(alignment: .top, spacing: 0) {
                heroMetric(title: snapshot.weeklyCounterLabel, value: snapshot.weeklyCounterValueLabel, tint: TrainingTheme.textPrimary)
                Rectangle()
                    .fill(TrainingTheme.border.opacity(0.4))
                    .frame(width: 1, height: 36)
                heroPaceMetric(title: "Pace", status: snapshot.pacingStatus, tint: paceTint(for: snapshot))
            }
            .padding(.vertical, 4)
        }
    }

    private var compactTitleOpacity: Double {
        let revealStart: CGFloat = -92
        let revealDistance: CGFloat = 58
        return Double(min(max((revealStart - scrollOffset) / revealDistance, 0), 1))
    }

    private func heroPaceMetric(title: String, status: SkillPacingStatus, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(TrainingTheme.textMuted)
            V4StatusPill(text: status.label, tint: tint)
        }
        .frame(maxWidth: .infinity)
    }

    private func openInitialLogSheetIfNeeded() {
        guard opensLogSheetOnAppear, !hasOpenedInitialLogSheet, let primaryHabit else { return }
        hasOpenedInitialLogSheet = true
        logDraft = LogEntryDraft(habit: primaryHabit)
    }

    private func calibrationSection() -> some View {
        V4Card(padding: 16, accent: TrainingTheme.textMuted) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("CALIBRATION")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Spacer()
                    Button {
                        showingCalibrationSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .bold))
                            Text("Recalibrate")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(accent.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(TrainingTheme.border.opacity(0.5))

                HStack(alignment: .top, spacing: 0) {
                    calibrationCell(title: "Baseline", value: "\(stat.currentBaseline)")
                    Rectangle()
                        .fill(TrainingTheme.border.opacity(0.4))
                        .frame(width: 1, height: 36)
                    calibrationCell(title: "Target", value: stat.targetValue.map { "\($0)" } ?? "—")
                    if settings?.showPersonalMaxInUI ?? true {
                        Rectangle()
                            .fill(TrainingTheme.border.opacity(0.4))
                            .frame(width: 1, height: 36)
                        calibrationCell(title: "Personal Max", value: stat.personalMaxValue.map { "\($0)" } ?? "—")
                    }
                }
            }
        }
    }

    private func calibrationCell(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(TrainingTheme.textMuted)
            Text(value)
                .font(.system(.title, design: .serif).weight(.regular))
                .foregroundStyle(TrainingTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GOALS")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(TrainingTheme.textMuted)
                Spacer()
                Button {
                    showingGoalEditorForNew = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .heavy))
                        Text("Add")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accent.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }

            if skillGoals.isEmpty {
                Text("No growth goal yet — add one to push past your baseline.")
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // One shared fetch of logs/stats for every goal row instead of
                // each SkillGoalRow independently re-fetching the whole log
                // table (goalProgress(for:context:) fetches every HabitLog in
                // the store) on every access.
                let inputs = TrainingStore.goalProgressInputs(context: modelContext)
                ForEach(skillGoals) { goal in
                    SkillGoalRow(goal: goal, accent: accent, progress: TrainingStore.goalProgress(for: goal, inputs: inputs)) {
                        editingGoal = goal
                    }
                }
            }
        }
    }

    // WS12: CHARGE and NEXT RANK used to be two cards that both ended in the
    // same `nextRankStatusLabel` sentence ("3 more positive charge steps will
    // unlock Steady Trainee.") — merged into one PROGRESSION card that states
    // it once, with a single help button covering both halves.
    private func progressionSection(snapshot: SkillProgressSnapshot) -> some View {
        let nextTitle = snapshot.rank.isAtMaximumRank ? nil : snapshot.rank.nextTitle

        return V4Card(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PROGRESSION")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Spacer()
                    Button {
                        presentedHelpTopic = .progression
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TrainingTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(TrainingTheme.border.opacity(0.5))

                HStack(alignment: .top, spacing: 14) {
                    if let nextTitle {
                        RankArtworkView(
                            habitName: stat.name,
                            level: snapshot.rank.level + 1,
                            title: nextTitle,
                            image: snapshot.nextRankImage,
                            accent: accent,
                            style: .compact
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let nextTitle {
                            Text("LOCKED · LV \(V4Style.displayNumber(snapshot.rank.level + 1))")
                                .font(.caption2.weight(.heavy))
                                .tracking(1.4)
                                .foregroundStyle(TrainingTheme.textMuted)
                            V4SerifTitle(text: nextTitle, size: 22)
                        }

                        Text(snapshot.bankedChargeLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                            .monospacedDigit()

                        chargeDots(snapshot: snapshot)
                            .frame(maxWidth: .infinity)

                        Text(snapshot.nextRankStatusLabel)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var linkedHabitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LOG ACTIONS")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(TrainingTheme.textMuted)
                Spacer()
                Button {
                    showingHabitEditorForNew = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .heavy))
                        Text("Add")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accent.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }

            if linkedHabits.isEmpty {
                V4Card(accent: accent) {
                    Text("No active habits are linked to this skill yet. Tap Add to create one (for example Tennis, Swimming, or Running under Cardio).")
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            } else {
                // With one habit the baseline caption sits under its own card
                // (kept — a single fact in its usual place). With several,
                // repeating the identical sentence on every card said the
                // same thing N times, so it moves up here to be stated once.
                if linkedHabits.count > 1 {
                    Text("Each logs toward \(stat.name)'s weekly baseline (\(stat.currentBaseline)/week).")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textMuted)
                }

                ForEach(linkedHabits) { habit in
                    let progressUnit = habit.measurementType == .booleanSession
                        ? (habit.targetPerPeriod == 1 ? "session" : "sessions")
                        : habit.unitLabel
                    V4Card(accent: accent) {
                        VStack(spacing: 12) {
                            VStack(spacing: 4) {
                                Text(habit.name)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                    .multilineTextAlignment(.center)
                                Text("\(MetricFormatting.shortMetric(TrainingStore.total(for: habit, in: TrainingStore.currentWeekInterval(settings: settings)))) / \(MetricFormatting.shortMetric(habit.targetPerPeriod)) \(progressUnit) this week")
                                    .font(.caption)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .monospacedDigit()
                                if linkedHabits.count == 1 {
                                    Text("Counts toward your weekly baseline (\(stat.currentBaseline)/week).")
                                        .font(.caption2)
                                        .foregroundStyle(TrainingTheme.textMuted)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            HabitQuickActionButtons(habit: habit, accent: accent) { value in
                                logDraft = LogEntryDraft(habit: habit, value: value)
                            }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            editingHabit = habit
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accent)
                                .padding(8)
                                .background(Circle().fill(accent.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .accessibilityLabel("Edit \(habit.name)")
                    }
                }
            }
        }
    }

    private func weeklyHistorySection(
        snapshot: SkillProgressSnapshot,
        weekSnapshot: SkillWeekSnapshot,
        effectiveDay: Date,
        dayLogs: [SkillLogEntrySnapshot]
    ) -> some View {
        V4Card(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        Text("THIS WEEK")
                            .font(.caption.weight(.heavy))
                            .tracking(2.0)
                            .foregroundStyle(TrainingTheme.textMuted)

                        Button {
                            presentedHelpTopic = .thisWeek
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(TrainingTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("This Week help")
                    }

                    Spacer()
                    Button {
                        showingFullHistory = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Full History")
                                .font(.caption.weight(.bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .overlay(TrainingTheme.border.opacity(0.5))

                HStack(spacing: 8) {
                    Button {
                        moveWeek(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(accent.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 2) {
                        Text(selectedWeek.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text("\(snapshot.weeklyCounterValueLabel) logged")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }

                    Spacer()

                    Button {
                        moveWeek(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selectedWeek.start >= currentWeek.start ? TrainingTheme.textMuted : accent)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill((selectedWeek.start >= currentWeek.start ? TrainingTheme.textMuted : accent).opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedWeek.start >= currentWeek.start)
                }

                HStack(spacing: 6) {
                    ForEach(weekSnapshot.daySummaries) { day in
                        WeekDaySummaryView(
                            summary: day,
                            accent: accent,
                            isSelected: isSelectedDay(day.date, effectiveDay: effectiveDay)
                        ) {
                            selectedDay = TrainingStore.progressionCalendar().startOfDay(for: day.date)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedDayLogTitle(for: effectiveDay))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)

                    if dayLogs.isEmpty {
                        Text("No logs on this day.")
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    } else {
                        ForEach(dayLogs) { entry in
                            SkillLogEntryRow(entry: entry, accent: accent)
                        }
                    }
                }
            }
        }
    }

    private func paceTint(for snapshot: SkillProgressSnapshot) -> Color {
        switch snapshot.pacingStatus {
        case .ahead:
            return TrainingTheme.positiveStrong
        case .behind:
            return TrainingTheme.warning
        case .onPace:
            return accent
        }
    }

    private func chargeDots(snapshot: SkillProgressSnapshot) -> some View {
        SignedChargeMeter(charge: snapshot.charge.current, pendingProgress: snapshot.weeklyTargetProgress, socketSize: 14, spacing: 7)
    }

    private func selectedDayLogTitle(for day: Date) -> String {
        let weekday = day.formatted(.dateTime.weekday(.wide))
        let date = day.formatted(.dateTime.month(.abbreviated).day())
        return "\(weekday) Logs · \(date)"
    }

    private func heroMetric(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(TrainingTheme.textMuted)
            Text(value)
                .font(.system(.title2, design: .serif).weight(.regular))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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

    private func isSelectedDay(_ date: Date, effectiveDay: Date) -> Bool {
        TrainingStore.progressionCalendar().isDate(date, inSameDayAs: effectiveDay)
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
        case .progression:
            // Only evaluated when the help sheet is actually opened (a rare,
            // user-initiated event), so a fresh snapshot here is fine — no
            // need to thread it through from `body`. Covers both halves of
            // the merged PROGRESSION card (WS12) in one sheet.
            let chargeExplanation = TrainingStore.progressSnapshot(for: stat, settings: settings).chargeExplanation
            return "\(chargeExplanation)\n\n\(topic.body)"
        default:
            return topic.body
        }
    }

    private func presentPendingRankChangeIfNeeded() {
        guard presentedRankChange == nil, let pending = stat.pendingRankChange else { return }
        presentedRankChange = pending
    }
}

private struct SkillDetailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct StickyLogButton: View {
    let title: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.heavy))
                Text(title)
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.28), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private enum SkillHelpTopic: String, Identifiable {
    case currentForm
    case progression
    case thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentForm:
            return "Current Form"
        case .progression:
            return "Progression"
        case .thisWeek:
            return "This Week"
        }
    }

    var body: String {
        switch self {
        case .currentForm:
            return "Tap the character art to open the full roster and browse every form in this skill's progression."
        case .progression:
            // Charge is snapshot-dependent (helpBody(for:) overrides this case
            // with the live explanation); this static copy only covers the
            // next-rank half and is never shown on its own.
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
                V4Diamond(
                    size: 9,
                    filled: summary.totalValue > 0,
                    tint: summary.totalValue > 0 ? accent : TrainingTheme.textMuted.opacity(0.7)
                )
                Text(String(Calendar.current.component(.day, from: summary.date)))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .monospacedDigit()
                Text(MetricFormatting.weekday(summary.date))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.10) : Color(red: 0.97, green: 0.96, blue: 0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var borderColor: Color {
        if isSelected {
            return accent.opacity(0.65)
        }
        if summary.isToday {
            return accent.opacity(0.32)
        }
        return TrainingTheme.border.opacity(0.7)
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.4 : 1
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
                ? "Your past week pushed this skill above its current rank. Tap Reveal to see the new rank."
                : "Your past week pulled this skill below its rank target. Tap Reveal to see the new rank."
        case .revealing, .resolved:
            return change.direction == .up
                ? "Your weekly surplus pushed this skill into a higher rank."
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
                .overlay(alignment: .topTrailing) {
                    // topTrailing (not .top) so this doesn't sit on top of
                    // the "LV n" pill, which RankArtworkView's .compact
                    // style renders at topLeading.
                    Image(systemName: change.direction == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(highlight)
                        .background(
                            Circle()
                                .fill(.white)
                                .frame(width: 50, height: 50)
                        )
                        .offset(x: 12, y: -18)
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
                Label("Reveal", systemImage: change.direction == .up ? "sparkles" : "arrow.down.circle.fill")
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
            rankDeltaPill(title: "From", value: "LV \(change.fromLevel)\n\(change.fromTitle)")
            Image(systemName: change.direction == .up ? "arrow.right" : "arrow.right")
                .font(.title3.weight(.bold))
                .foregroundStyle(highlight)
            rankDeltaPill(title: "To", value: "LV \(change.toLevel)\n\(change.toTitle)")
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
                    value: "\(resolution.storedChargesAfter)"
                )
            }

            Text("Charge resets to 0 after a rank change.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)

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
    let goal: Goal
    let accent: Color
    let progress: GoalProgressSnapshot
    let onTap: () -> Void

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
                    Text("\(stat.name) is currently measured in \(unitLabel). Changing the unit affects how new logs and quick-log buttons behave — past logs keep their original units.")
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
