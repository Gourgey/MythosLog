import SwiftData
import SwiftUI

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatDomain.name) private var stats: [StatDomain]

    let habit: Habit?
    var initialStatID: UUID? = nil

    @State private var name = ""
    @State private var notes = ""
    @State private var selectedStatID: UUID?
    @State private var measurementType: MeasurementType = .booleanSession
    @State private var unitLabel = "session"
    @State private var scheduleType: ScheduleType = .weekly
    @State private var targetPerPeriod = 1.0
    @State private var active = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Core") {
                    TextField("Habit name", text: $name)
                    Picker("Stat domain", selection: $selectedStatID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(stats.filter { $0.isActive }) { stat in
                            Text(stat.name).tag(Optional(stat.id))
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section("Tracking") {
                    Picker("Measurement", selection: $measurementType) {
                        ForEach(MeasurementType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: measurementType) { _, newValue in
                        unitLabel = newValue.defaultUnitLabel
                    }

                    TextField("Unit label", text: $unitLabel)
                    Picker("Schedule", selection: $scheduleType) {
                        ForEach(ScheduleType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    HStack {
                        Text("Target")
                        Spacer()
                        TextField("Target", value: $targetPerPeriod, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Habit is active", isOn: $active)
                }
            }
            .scrollContentBackground(.hidden)
            .background(TrainingTheme.background.ignoresSafeArea())
            .navigationTitle(habit == nil ? "New Habit" : "Edit Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let habit else {
            if selectedStatID == nil { selectedStatID = initialStatID }
            return
        }
        name = habit.name
        notes = habit.notes
        selectedStatID = habit.statDomain?.id
        measurementType = habit.measurementType
        unitLabel = habit.unitLabel
        scheduleType = habit.scheduleType
        targetPerPeriod = habit.targetPerPeriod
        active = habit.active
    }

    private func save() {
        let selectedStat = stats.first(where: { $0.id == selectedStatID })

        if let habit {
            habit.name = name
            habit.notes = notes
            habit.statDomain = selectedStat
            habit.measurementType = measurementType
            habit.unitLabel = unitLabel
            habit.scheduleType = scheduleType
            habit.targetPerPeriod = targetPerPeriod
            habit.active = active
            habit.updatedAt = .now
        } else {
            // Match UnmatchedWorkoutSheet's per-stat ordering (max sortOrder
            // among the stat's own active habits + 1) rather than a global
            // habit count, so habits created from either path sort correctly
            // against each other within a skill's Log Actions list.
            let nextOrder: Int
            if let selectedStat {
                nextOrder = (TrainingStore.activeHabits(for: selectedStat).map(\.sortOrder).max() ?? -1) + 1
            } else {
                nextOrder = (try? TrainingStore.fetchHabits(context: modelContext).count) ?? 0
            }
            let created = Habit(
                name: name,
                notes: notes,
                measurementType: measurementType,
                unitLabel: unitLabel,
                scheduleType: scheduleType,
                targetPerPeriod: targetPerPeriod,
                active: active,
                sortOrder: nextOrder,
                statDomain: selectedStat
            )
            modelContext.insert(created)
        }

        try? modelContext.save()
        TrainingStore.recordLocalWrite(reason: habit == nil ? "created habit" : "updated habit")
        try? TrainingStore.refreshWidgetSnapshot(context: modelContext)
        dismiss()
    }
}
