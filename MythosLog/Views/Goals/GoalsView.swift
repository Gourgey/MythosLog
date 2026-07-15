import SwiftData
import SwiftUI

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @State private var presentedEditor: GoalEditorSeed?
    @State private var initialStatKey: StatKey?

    init(initialStatKey: StatKey? = nil) {
        self._initialStatKey = State(initialValue: initialStatKey)
    }

    private var activeGoals: [Goal] { goals.filter { $0.status == .active } }
    private var completedGoals: [Goal] { goals.filter { $0.status == .completed } }
    private var pausedGoals: [Goal] { goals.filter { $0.status == .paused } }
    private var archivedGoals: [Goal] { goals.filter { $0.status == .archived || $0.status == .failed } }

    var body: some View {
        // `GoalCardView` used to recompute `TrainingStore.goalProgress(for:context:)`
        // itself (an @Environment-fetched context) — each access fetched the
        // entire HabitLog + StatDomain tables, and the card read it 4 separate
        // times (status pill, progress bar, current/target line, pace color),
        // once per goal, on every render. Fetched once here and threaded down
        // as a plain snapshot instead, mirroring the SkillGoalRow batching fix.
        let inputs = TrainingStore.goalProgressInputs(context: modelContext)

        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    goalsPageHeader

                    if goals.isEmpty {
                        emptyState
                    } else {
                        if !activeGoals.isEmpty {
                            section(title: "Active", goals: activeGoals, inputs: inputs)
                        }
                        if !pausedGoals.isEmpty {
                            section(title: "Paused", goals: pausedGoals, inputs: inputs)
                        }
                        if !completedGoals.isEmpty {
                            section(title: "Completed", goals: completedGoals, inputs: inputs)
                        }
                        if !archivedGoals.isEmpty {
                            section(title: "Archived", goals: archivedGoals, inputs: inputs)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentedEditor = GoalEditorSeed(goal: nil, initialStatKey: initialStatKey)
                } label: {
                    Label("New Goal", systemImage: "plus")
                }
            }
        }
        .sheet(item: $presentedEditor) { seed in
            NavigationStack {
                GoalEditorView(goal: seed.goal, initialStatKey: seed.initialStatKey)
            }
            .presentationDetents([.large])
        }
        .onAppear {
            if !goals.isEmpty, let key = initialStatKey {
                presentedEditor = GoalEditorSeed(goal: nil, initialStatKey: key)
                self.initialStatKey = nil
            }
            consumePendingGoalIfNeeded()
            consumePendingNewGoalIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: PendingDestinationStore.didQueueGoalNotification)) { _ in
            consumePendingGoalIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: PendingDestinationStore.didQueueNewGoalNotification)) { _ in
            consumePendingNewGoalIfNeeded()
        }
    }

    private func consumePendingGoalIfNeeded() {
        guard let pendingID = PendingDestinationStore.consumeGoal() else { return }
        if let match = goals.first(where: { $0.id == pendingID }) {
            presentedEditor = GoalEditorSeed(goal: match, initialStatKey: nil)
        }
    }

    private func consumePendingNewGoalIfNeeded() {
        guard let raw = PendingDestinationStore.consumeNewGoal(), let key = StatKey(rawValue: raw) else { return }
        presentedEditor = GoalEditorSeed(goal: nil, initialStatKey: key)
    }

    private var goalsPageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            V4PageKicker(title: "Targets & Pacing")
        }
    }

    private var emptyState: some View {
        let accent = TrainingArcConfig.color(for: "focus")
        return V4Card(accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                V4SerifTitle(text: "No goals yet", size: 28)

                VStack(alignment: .leading, spacing: 8) {
                    explainerRow(
                        title: "Goal",
                        body: "A time-scoped target with a deadline. Lives here on the Goals tab, has a priority, and shows up in your weekly review."
                    )
                    explainerRow(
                        title: "Skill target / baseline",
                        body: "Your steady-state weekly expectations for a skill. Lives on the skill itself (set during calibration) and drives the dashboard rings and rank progression."
                    )
                }

                Text("Create a goal when you want to push a skill above its baseline for a defined stretch of time.")
                    .font(.footnote)
                    .foregroundStyle(TrainingTheme.textSecondary)

                Button {
                    presentedEditor = GoalEditorSeed(goal: nil, initialStatKey: initialStatKey)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.heavy))
                        Text("Create your first goal")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func explainerRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.subheadline, design: .serif).weight(.regular))
                .foregroundStyle(TrainingTheme.textPrimary)
            Text(body)
                .font(.footnote)
                .foregroundStyle(TrainingTheme.textSecondary)
        }
    }

    private func section(title: String, goals: [Goal], inputs: TrainingStore.GoalProgressInputs) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(2.0)
                .foregroundStyle(TrainingTheme.textMuted)

            ForEach(goals) { goal in
                GoalCardView(goal: goal, progress: TrainingStore.goalProgress(for: goal, inputs: inputs)) {
                    presentedEditor = GoalEditorSeed(goal: goal, initialStatKey: nil)
                }
            }
        }
    }
}

private struct GoalEditorSeed: Identifiable {
    var id: UUID { goal?.id ?? UUID() }
    var goal: Goal?
    var initialStatKey: StatKey?
}

private struct GoalCardView: View {
    let goal: Goal
    let progress: GoalProgressSnapshot
    let onTap: () -> Void

    private var accent: Color {
        if let key = goal.linkedStatKey {
            return TrainingArcConfig.color(for: TrainingArcConfig.definition(for: key).colorToken)
        }
        return TrainingArcConfig.color(for: "focus")
    }

    var body: some View {
        Button(action: onTap) {
            V4Card(accent: accent) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.displayTitle)
                                .font(.system(.headline, design: .serif).weight(.regular))
                                .foregroundStyle(TrainingTheme.textPrimary)
                            Text(subtitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TrainingTheme.textSecondary)
                                .tracking(0.5)
                        }
                        Spacer()
                        statusPill
                    }

                    progressBar

                    HStack {
                        Text("\(MetricFormatting.shortMetric(progress.currentValue)) / \(MetricFormatting.shortMetric(progress.targetValue))")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                            .monospacedDigit()
                        Spacer()
                        Text(progress.timeRemainingLabel)
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }

                    if !goal.affectsProgression {
                        Text("Tracking only — doesn’t affect charge or rank.")
                            .font(.caption2)
                            .foregroundStyle(TrainingTheme.textMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let scope: String = {
            if let key = goal.linkedStatKey { return key.displayName }
            return "Overall"
        }()
        return "\(scope.uppercased()) · \(goal.type.displayName.uppercased())"
    }

    private var statusPill: some View {
        V4StatusPill(text: progress.statusLabel, tint: statusColor)
    }

    private var statusColor: Color {
        switch goal.status {
        case .completed: return TrainingTheme.positive
        case .paused: return TrainingTheme.textMuted
        case .archived, .failed: return TrainingTheme.textSecondary
        case .active:
            switch progress.paceStatus {
            case .complete: return TrainingTheme.positive
            case .ahead: return TrainingTheme.positive
            case .onPace: return accent
            case .atRisk: return TrainingTheme.warning
            case .behind: return TrainingTheme.danger
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(TrainingTheme.backgroundTertiary.opacity(0.4))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent)
                    .frame(width: proxy.size.width * progress.progressRatio)
            }
        }
        .frame(height: 8)
    }
}

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var statsFromQuery: [StatDomain]

    let existingGoal: Goal?
    let initialStatKey: StatKey?

    @State private var title: String
    @State private var notes: String
    @State private var scope: GoalScope
    @State private var linkedStatKey: StatKey?
    @State private var linkedHabitID: UUID?
    @State private var type: GoalType
    @State private var measurementType: MeasurementType
    @State private var targetValueText: String
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var priority: GoalPriority
    @State private var affectsProgression: Bool
    @State private var isRecoveryMode: Bool

    init(goal: Goal?, initialStatKey: StatKey?) {
        self.existingGoal = goal
        self.initialStatKey = initialStatKey
        _title = State(initialValue: goal?.title ?? "")
        _notes = State(initialValue: goal?.notes ?? "")
        _scope = State(initialValue: goal?.scope ?? (initialStatKey == nil ? .overall : .skill))
        _linkedStatKey = State(initialValue: goal?.linkedStatKey ?? initialStatKey)
        _linkedHabitID = State(initialValue: goal?.linkedHabitID)
        _type = State(initialValue: goal?.type ?? .weeklyTarget)
        _measurementType = State(initialValue: goal?.measurementType ?? .count)
        _targetValueText = State(initialValue: goal.map { String(format: "%g", $0.targetValue) } ?? "")
        let defaultEnd = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: .now) ?? .now
        _hasEndDate = State(initialValue: goal?.endDate != nil)
        _endDate = State(initialValue: goal?.endDate ?? defaultEnd)
        _priority = State(initialValue: goal?.priority ?? .normal)
        _affectsProgression = State(initialValue: goal?.affectsProgression ?? false)
        _isRecoveryMode = State(initialValue: goal?.isRecoveryMode ?? false)
    }

    private var availableStats: [StatDomain] {
        statsFromQuery.filter { $0.isActive }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var linkedStat: StatDomain? {
        guard scope == .skill, let key = linkedStatKey else { return nil }
        return availableStats.first { $0.statKey == key }
    }

    private var habitsForLinkedSkill: [Habit] {
        guard let linkedStat else { return [] }
        return TrainingStore.activeHabits(for: linkedStat)
    }

    private var resolvedTarget: Double {
        Double(targetValueText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Current weekly baseline of the linked skill — only meaningful for a
    /// skill-scoped weekly-target goal.
    private var linkedBaseline: Int? {
        guard type == .weeklyTarget, let linkedStat else { return nil }
        return linkedStat.currentBaseline
    }

    private var targetBelowBaseline: Bool {
        guard let baseline = linkedBaseline, baseline > 0 else { return false }
        return resolvedTarget > 0 && resolvedTarget < Double(baseline)
    }

    /// A weekly target below baseline only makes sense in recovery mode; otherwise
    /// it would quietly undercut the user's honest baseline.
    private var recoveryGateViolated: Bool {
        targetBelowBaseline && !isRecoveryMode
    }

    private var canSave: Bool {
        resolvedTarget > 0 && !recoveryGateViolated
    }

    private var autoDerivedTitlePreview: String {
        // Before a target is entered, `Goal.autoDerivedTitle` would render
        // literal nonsense like "0 count this week" as the field's
        // placeholder. Show a unit-aware example until there's a real target
        // to preview, then live-update to the generated title as before.
        guard resolvedTarget > 0 else {
            let exampleTarget: Double = switch measurementType {
            case .booleanSession, .count: 3
            case .pages: 20
            case .minutes: 30
            case .customNumber: 10
            }
            let exampleTitle = Goal.autoDerivedTitle(
                type: type,
                measurementType: measurementType,
                targetValue: exampleTarget,
                linkedStatKey: linkedStatKey
            )
            return "e.g. \(exampleTitle)"
        }
        return Goal.autoDerivedTitle(
            type: type,
            measurementType: measurementType,
            targetValue: resolvedTarget,
            linkedStatKey: linkedStatKey
        )
    }

    var body: some View {
        Form {
            Section {
                TextField(autoDerivedTitlePreview, text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Goal")
            } footer: {
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Leave blank to use the auto-generated title shown above.")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }

            Section("Scope") {
                Picker("Scope", selection: $scope) {
                    ForEach(GoalScope.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                if scope == .skill {
                    Picker("Skill", selection: $linkedStatKey) {
                        Text("—").tag(StatKey?.none)
                        ForEach(availableStats) { stat in
                            if let key = stat.statKey {
                                Text(stat.name).tag(StatKey?.some(key))
                            }
                        }
                    }

                    if !habitsForLinkedSkill.isEmpty {
                        Picker("Habit", selection: $linkedHabitID) {
                            Text("Any habit").tag(UUID?.none)
                            ForEach(habitsForLinkedSkill) { habit in
                                Text(habit.name).tag(UUID?.some(habit.id))
                            }
                        }
                        Text("Limit this goal to one habit, or leave on “Any habit” to count every habit in the skill.")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                }
            }
            .onChange(of: linkedStatKey) { _, _ in
                linkedHabitID = nil
            }
            .onChange(of: scope) { _, newScope in
                if newScope != .skill { linkedHabitID = nil }
            }

            Section("Type") {
                Picker("Goal Type", selection: $type) {
                    ForEach(GoalType.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Measured In", selection: $measurementType) {
                    ForEach(MeasurementType.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section("Target") {
                HStack {
                    TextField("Target value", text: $targetValueText)
                        .keyboardType(.decimalPad)
                    Text(measurementType.defaultUnitLabel)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                if let baseline = linkedBaseline, targetBelowBaseline {
                    Label(
                        "Target is below this skill's baseline (\(baseline)). Turn on Recovery mode to set an easier target on purpose.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.warning)
                }
            }

            Section("Timing") {
                Toggle("Has end date", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("Ends", selection: $endDate, displayedComponents: [.date])
                }
            }

            Section {
                Picker("Priority", selection: $priority) {
                    ForEach(GoalPriority.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Priority")
            } footer: {
                Text("Higher priority sorts this goal to the top of the Goals list and weekly review nudges. It doesn't change how the goal is scored.")
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }

            Section {
                Toggle("Goal affects progression", isOn: $affectsProgression)
                Text("By default goals are tracking-only. Turn this on if you want meeting this goal to also reward bonus Charge.")
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)

                Toggle("Recovery mode", isOn: $isRecoveryMode)
                Text("Use when the target is intentionally lower than baseline — for example, easing back after illness. Meeting a recovery target still rewards bonus Charge even if below baseline.")
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            } header: {
                Text("Influence")
            }

            if let existingGoal {
                Section("Status") {
                    if existingGoal.status == .active {
                        Button("Mark as Complete") {
                            try? TrainingStore.setGoalStatus(existingGoal, status: .completed, context: modelContext)
                            dismiss()
                        }
                        Button("Pause") {
                            try? TrainingStore.setGoalStatus(existingGoal, status: .paused, context: modelContext)
                            dismiss()
                        }
                    }
                    if existingGoal.status == .paused {
                        Button("Resume") {
                            try? TrainingStore.setGoalStatus(existingGoal, status: .active, context: modelContext)
                            dismiss()
                        }
                    }
                    if existingGoal.status != .archived {
                        Button("Archive") {
                            try? TrainingStore.setGoalStatus(existingGoal, status: .archived, context: modelContext)
                            dismiss()
                        }
                    }
                    Button("Delete", role: .destructive) {
                        try? TrainingStore.deleteGoal(existingGoal, context: modelContext)
                        dismiss()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.985, green: 0.975, blue: 0.955).ignoresSafeArea())
        .navigationTitle(existingGoal == nil ? "New Goal" : "Edit Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(existingGoal == nil ? "Save" : "Update") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEnd = hasEndDate ? endDate : nil
        let resolvedScope = scope == .skill ? GoalScope.skill : GoalScope.overall
        let resolvedStatKey = resolvedScope == .skill ? linkedStatKey : nil
        let resolvedHabitID = resolvedStatKey != nil ? linkedHabitID : nil

        if let existingGoal {
            existingGoal.title = trimmedTitle
            existingGoal.notes = trimmedNotes
            existingGoal.scope = resolvedScope
            existingGoal.linkedStatKey = resolvedStatKey
            existingGoal.linkedHabitID = resolvedHabitID
            existingGoal.type = type
            existingGoal.measurementType = measurementType
            existingGoal.targetValue = resolvedTarget
            existingGoal.endDate = resolvedEnd
            existingGoal.priority = priority
            existingGoal.affectsProgression = affectsProgression
            existingGoal.isRecoveryMode = isRecoveryMode
            try? TrainingStore.updateGoal(existingGoal, context: modelContext)
        } else {
            _ = try? TrainingStore.createGoal(
                title: trimmedTitle,
                notes: trimmedNotes,
                scope: resolvedScope,
                linkedStatKey: resolvedStatKey,
                linkedHabitID: resolvedHabitID,
                type: type,
                measurementType: measurementType,
                targetValue: resolvedTarget,
                startDate: .now,
                endDate: resolvedEnd,
                priority: priority,
                affectsMetrics: false,
                affectsProgression: affectsProgression,
                isRecoveryMode: isRecoveryMode,
                context: modelContext
            )
        }

        dismiss()
    }
}
