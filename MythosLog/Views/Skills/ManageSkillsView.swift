import SwiftData
import SwiftUI

/// Skill Library — open each skill's settings, enable optional skills,
/// archive/restore, and reorder the active set. Archiving never deletes logs,
/// goals, or history (see TrainingStore).
struct ManageSkillsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatDomain.sortOrder) private var stats: [StatDomain]
    @Query private var settingsRecords: [AppSettings]

    private var activeStats: [StatDomain] {
        stats.filter { $0.isActive }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var showsPersonalMax: Bool {
        settingsRecords.first?.showPersonalMaxInUI ?? true
    }

    private var inactiveStats: [StatDomain] {
        stats.filter { !$0.isActive }.sorted { lhs, rhs in
            if lhs.isCore != rhs.isCore { return rhs.isCore }
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(activeStats) { stat in
                    NavigationLink {
                        ManagedSkillSettingsView(stat: stat)
                    } label: {
                        skillRow(stat, isActive: true)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            archive(stat)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }
                }
                .onMove(perform: moveActive)
            } header: {
                Text("ACTIVE SKILLS")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(TrainingTheme.textMuted)
            } footer: {
                Text("Tap a skill for its settings and personal-max reassessment. Drag to reorder; swipe to archive.")
                    .font(.caption)
            }

            if !inactiveStats.isEmpty {
                Section {
                    ForEach(inactiveStats) { stat in
                        NavigationLink {
                            ManagedSkillSettingsView(stat: stat)
                        } label: {
                            skillRow(stat, isActive: false)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                enable(stat)
                            } label: {
                                Label(stat.isCore ? "Restore" : "Enable", systemImage: "plus.circle")
                            }
                            .tint(TrainingTheme.positive)
                        }
                    }
                } header: {
                    Text("OPTIONAL & ARCHIVED")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                } footer: {
                    Text("Open any skill to review its settings, then enable or restore it when you're ready. Nothing here is deleted.")
                        .font(.caption)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.985, green: 0.975, blue: 0.955).ignoresSafeArea())
        .navigationTitle("Manage Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TrainingTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private func skillRow(_ stat: StatDomain, isActive: Bool) -> some View {
        let accent = TrainingArcConfig.color(for: stat.colorToken)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(isActive ? 0.16 : 0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: stat.iconName.isEmpty ? "circle" : stat.iconName)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stat.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isActive ? TrainingTheme.textPrimary : TrainingTheme.textSecondary)
                    if !stat.isCore {
                        Text("OPTIONAL")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(TrainingTheme.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TrainingTheme.border.opacity(0.4)))
                    }
                }
                Text(stat.descriptor)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .lineLimit(2)
                if showsPersonalMax {
                    Text(calibrationLine(for: stat))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textMuted)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !isActive {
                Text(stat.isCore ? "ARCHIVED" : "OFF")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(TrainingTheme.textMuted)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func calibrationLine(for stat: StatDomain) -> String {
        let unit = TrainingStore.weeklyUnitLabel(for: stat)
        guard let max = stat.personalMaxValue else {
            return "Baseline \(stat.currentBaseline) \(unit) · Max not set"
        }
        return "Baseline \(stat.currentBaseline) · Max \(max) \(unit)"
    }

    private func moveActive(from source: IndexSet, to destination: Int) {
        var ids = activeStats.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        try? TrainingStore.setSkillOrder(ids, context: modelContext)
    }

    private func enable(_ stat: StatDomain) {
        try? TrainingStore.enableSkill(stat, context: modelContext)
    }

    private func archive(_ stat: StatDomain) {
        try? TrainingStore.archiveSkill(stat, context: modelContext)
    }
}

private struct ManagedSkillSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    let stat: StatDomain

    @State private var isEditingCalibration = false
    @State private var isReassessingPersonalMax = false

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var unit: String {
        TrainingStore.weeklyUnitLabel(for: stat)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.16))
                            .frame(width: 48, height: 48)
                        Image(systemName: stat.iconName.isEmpty ? "circle" : stat.iconName)
                            .font(.title3.weight(.black))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stat.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(stat.isActive ? "Active skill" : (stat.isCore ? "Archived skill" : "Optional skill"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                }
                .padding(.vertical, 4)

                Text(stat.descriptor)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }

            Section("Weekly calibration") {
                LabeledContent("Baseline", value: "\(stat.currentBaseline) \(unit)")
                LabeledContent("Target", value: stat.targetValue.map { "\($0) \(unit)" } ?? "Not set")
                LabeledContent("Personal max", value: stat.personalMaxValue.map { "\($0) \(unit)" } ?? "Not set")
                LabeledContent("Maintenance", value: stat.maintenanceFloor.map { "\($0) \(unit)" } ?? "Not set")

                Button {
                    isReassessingPersonalMax = true
                } label: {
                    Label("Reassess Personal Max", systemImage: "gauge.with.dots.needle.67percent")
                }

                Button {
                    isEditingCalibration = true
                } label: {
                    Label("Edit Calibration & Units", systemImage: "slider.horizontal.3")
                }
            }

            if stat.isActive {
                Section("Skill") {
                    NavigationLink {
                        SkillDetailView(stat: stat)
                    } label: {
                        Label("Open Skill", systemImage: "arrow.up.right.square")
                    }

                    Button(role: .destructive) {
                        try? TrainingStore.archiveSkill(stat, context: modelContext)
                    } label: {
                        Label("Archive Skill", systemImage: "archivebox")
                    }
                }
            } else {
                Section("Skill") {
                    Button {
                        try? TrainingStore.enableSkill(stat, context: modelContext)
                    } label: {
                        Label(stat.isCore ? "Restore Skill" : "Enable Skill", systemImage: "plus.circle.fill")
                    }
                    .foregroundStyle(accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle("\(stat.name) Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(accent)
        .sheet(isPresented: $isEditingCalibration) {
            NavigationStack {
                SkillCalibrationSheet(stat: stat)
            }
        }
        .sheet(isPresented: $isReassessingPersonalMax) {
            NavigationStack {
                PersonalMaxReassessmentView(stat: stat)
            }
        }
    }
}

private struct MaxSuggestion: Identifiable {
    let label: String
    let value: Int

    var id: String { label }
}

private struct PersonalMaxReassessmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let stat: StatDomain
    @State private var valueText: String

    init(stat: StatDomain) {
        self.stat = stat
        _valueText = State(initialValue: (stat.personalMaxValue ?? stat.targetValue ?? stat.currentBaseline).description)
    }

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var unit: String {
        TrainingStore.weeklyUnitLabel(for: stat)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Baseline", value: "\(stat.currentBaseline) \(unit)")
                LabeledContent("Target", value: stat.targetValue.map { "\($0) \(unit)" } ?? "Not set")
                LabeledContent("Current max", value: stat.personalMaxValue.map { "\($0) \(unit)" } ?? "Not set")
                if let enteredMax {
                    LabeledContent("Reassessed level") {
                        HStack(spacing: 6) {
                            Text("Level \(stat.rankLevel)")
                                .foregroundStyle(TrainingTheme.textSecondary)
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(TrainingTheme.textSecondary)
                            Text("Level \(reassessedLevel(for: enteredMax))")
                                .fontWeight(.bold)
                                .foregroundStyle(accent)
                        }
                    }
                }
                if let best = bestWeek {
                    LabeledContent("Best resolved week", value: "\(MetricFormatting.shortMetric(best)) \(unit)")
                }
            } header: {
                Text("Where \(stat.name) stands")
            }

            Section {
                HStack {
                    Text("Maximum")
                    Spacer()
                    TextField("Maximum", text: $valueText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                    Stepper("") {
                        adjust(by: stepSize)
                    } onDecrement: {
                        adjust(by: -stepSize)
                    }
                    .labelsHidden()
                }

                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions) { option in
                                Button {
                                    valueText = "\(option.value)"
                                } label: {
                                    Text("\(option.label) · \(option.value)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(accent.opacity(0.14)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("New maximum")
            } footer: {
                Text("The most you'd believably log for \(stat.name) in one strong week. Saving recalculates your current level; past logs and resolved weeks stay unchanged.")
                    .font(.caption)
            }

            if let enteredMax, let rankKey = stat.rankKey {
                Section {
                    ForEach(TrainingArcConfig.minimumRankLevel...TrainingArcConfig.maximumRankLevel, id: \.self) { level in
                        let isReassessedLevel = level == reassessedLevel(for: enteredMax)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Level \(level) · \(TrainingArcConfig.rankTitle(for: rankKey, level: level))")
                                    .font(.subheadline.weight(isReassessedLevel ? .bold : .medium))
                                Spacer()
                                if isReassessedLevel {
                                    Text("YOUR LEVEL")
                                        .font(.caption2.weight(.heavy))
                                        .tracking(0.8)
                                        .foregroundStyle(accent)
                                }
                            }
                            Text("Baseline: \(rankBaseline(for: level, rankKey: rankKey, personalMax: enteredMax)) \(unit) per week")
                                .font(.caption)
                                .foregroundStyle(isReassessedLevel ? accent : TrainingTheme.textSecondary)
                                .monospacedDigit()

                            if isReassessedLevel {
                                Text("Your working baseline remains \(stat.currentBaseline) \(unit) per week.")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text("Rank baselines after reassessment")
                } footer: {
                    Text("Each value is the minimum weekly baseline where that rank begins. Your working baseline is preserved when it falls between two rank starts.")
                        .font(.caption)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle("Reassess \(stat.name) Max")
        .navigationBarTitleDisplayMode(.inline)
        .tint(accent)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(Int(valueText) == nil)
            }
        }
    }

    private var bestWeek: Double? {
        (stat.weeklyResolutions ?? []).map(\.actualCompletedValue).max().flatMap { $0 > 0 ? $0 : nil }
    }

    private var enteredMax: Int? {
        guard let entered = Int(valueText) else { return nil }
        return TrainingArcConfig.clampCalibration(
            baseline: stat.currentBaseline,
            target: stat.targetValue,
            personalMax: max(entered, 0),
            maintenance: stat.maintenanceFloor
        ).max
    }

    private func reassessedLevel(for personalMax: Int) -> Int {
        guard let rankKey = stat.rankKey else { return stat.rankLevel }
        return TrainingArcConfig.rankLevel(
            for: rankKey,
            weeklyValue: Double(stat.currentBaseline),
            personalMax: personalMax
        )
    }

    private func rankBaseline(for level: Int, rankKey: StatKey, personalMax: Int) -> Int {
        TrainingArcConfig.requiredWeeklyValue(
            for: rankKey,
            level: level,
            personalMax: personalMax
        )
    }

    private var suggestions: [MaxSuggestion] {
        var options: [MaxSuggestion] = []
        if let bestWeek {
            options.append(MaxSuggestion(label: "Best week", value: Int(bestWeek.rounded())))
        }
        if let rankKey = stat.rankKey {
            options.append(
                MaxSuggestion(
                    label: "Suggested",
                    value: TrainingArcConfig.suggestedPersonalMaxValue(
                        for: rankKey,
                        baseline: stat.currentBaseline,
                        target: stat.targetValue
                    )
                )
            )
        }
        if let current = stat.personalMaxValue {
            options.append(MaxSuggestion(label: "Keep current", value: current))
        }
        var seen = Set<Int>()
        return options.filter { seen.insert($0.value).inserted }
    }

    private var stepSize: Int {
        max(Int(MeasurementType.niceStep(Double(max(stat.currentBaseline, 1)) / 6)), 1)
    }

    private func adjust(by delta: Int) {
        let current = Int(valueText) ?? stat.personalMaxValue ?? stat.currentBaseline
        valueText = "\(max(current + delta, 0))"
    }

    private func save() {
        guard let entered = Int(valueText) else { return }
        try? TrainingStore.reassessPersonalMax(
            for: stat,
            personalMax: max(entered, 0),
            context: modelContext
        )
        dismiss()
    }
}
