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
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if goals.isEmpty {
                        emptyState
                    } else {
                        if !activeGoals.isEmpty {
                            section(title: "Active", goals: activeGoals)
                        }
                        if !pausedGoals.isEmpty {
                            section(title: "Paused", goals: pausedGoals)
                        }
                        if !completedGoals.isEmpty {
                            section(title: "Completed", goals: completedGoals)
                        }
                        if !archivedGoals.isEmpty {
                            section(title: "Archived", goals: archivedGoals)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Goals")
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

    private var emptyState: some View {
        SurfaceCard(accent: TrainingArcConfig.color(for: "focus")) {
            VStack(alignment: .leading, spacing: 12) {
                Text("No goals yet")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)

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
                    Label("Create your first goal", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(TrainingArcConfig.color(for: "focus"))
            }
        }
    }

    private func explainerRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TrainingTheme.textPrimary)
            Text(body)
                .font(.footnote)
                .foregroundStyle(TrainingTheme.textSecondary)
        }
    }

    private func section(title: String, goals: [Goal]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(TrainingTheme.textMuted)

            ForEach(goals) { goal in
                GoalCardView(goal: goal) {
                    presentedEditor = GoalEditorSeed(goal: goal, initialStatKey: nil)
                }
                .environment(\.modelContext, modelContext)
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
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    let onTap: () -> Void

    private var accent: Color {
        if let key = goal.linkedStatKey {
            return TrainingArcConfig.color(for: TrainingArcConfig.definition(for: key).colorToken)
        }
        return TrainingArcConfig.color(for: "focus")
    }

    private var progress: GoalProgressSnapshot {
        TrainingStore.goalProgress(for: goal, context: modelContext)
    }

    var body: some View {
        Button(action: onTap) {
            SurfaceCard(accent: accent) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.displayTitle)
                                .font(.headline)
                                .foregroundStyle(TrainingTheme.textPrimary)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                        Spacer()
                        statusPill
                    }

                    progressBar

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
        return "\(scope) · \(goal.type.displayName)"
    }

    private var statusPill: some View {
        Text(progress.statusLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(statusColor)
            )
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
        Goal.autoDerivedTitle(
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
        .background(TrainingTheme.background.ignoresSafeArea())
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
