import SwiftData
import SwiftUI
#if canImport(HealthKit)
import HealthKit

struct UnmatchedWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var workouts: [HealthImportedWorkout]

    let stat: StatDomain

    init(stat: StatDomain) {
        self.stat = stat
        let statKey = stat.key
        _workouts = Query(
            filter: #Predicate<HealthImportedWorkout> { record in
                record.statKeyRaw == statKey &&
                record.awaitingHabitAssignment == true &&
                record.isDuplicate == false
            },
            sort: \HealthImportedWorkout.startDate,
            order: .reverse
        )
    }

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var habits: [Habit] {
        TrainingStore.activeHabits(for: stat)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TrainingTheme.background.ignoresSafeArea()
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "checkmark.circle.fill",
                        description: Text("No unmatched workouts for \(stat.name).")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("These workouts were imported from Apple Health but don't match any \(stat.name) habit. Choose what to do with each.")
                                .font(.subheadline)
                                .foregroundStyle(TrainingTheme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

                            ForEach(workouts) { record in
                                workoutRow(record)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("\(stat.name) imports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func workoutRow(_ record: HealthImportedWorkout) -> some View {
        let activityName = Self.displayName(for: record.activityTypeRaw)
        let source = record.sourceName?.isEmpty == false ? record.sourceName ?? "Apple Health" : "Apple Health"
        let date = record.startDate.formatted(date: .abbreviated, time: .shortened)
        let duration = formatDuration(record.durationMinutes)
        let matchingCount = matchingWorkouts(for: record).count
        let scopeText = matchingCount == 1 ? "this workout" : "\(matchingCount) \(activityName) workouts"

        return SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activityName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text("\(date) · \(duration) · \(source)")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                if habits.isEmpty {
                    Text("You don't have any habits in \(stat.name) yet.")
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                } else {
                    Menu {
                        ForEach(habits) { habit in
                            Button(habit.name) {
                                attribute(record: record, to: habit)
                            }
                        }
                    } label: {
                        actionLabel(text: "Log \(scopeText) to existing habit", icon: "tray.full.fill", tint: accent)
                    }
                }

                Button {
                    createNewHabitAndAttribute(record: record, name: activityName)
                } label: {
                    actionLabel(text: "Create \"\(activityName)\" and log \(scopeText)", icon: "plus.circle.fill", tint: TrainingTheme.positiveStrong)
                }

                Button {
                    ignore(record: record)
                } label: {
                    actionLabel(text: "Ignore \(scopeText)", icon: "xmark.circle", tint: TrainingTheme.textMuted)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func actionLabel(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.9)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func attribute(record: HealthImportedWorkout, to habit: Habit) {
        let records = matchingWorkouts(for: record)
        guard !records.isEmpty else { return }

        for pendingRecord in records {
            attributeSingle(record: pendingRecord, to: habit)
        }

        try? modelContext.save()
    }

    private func attributeSingle(record: HealthImportedWorkout, to habit: Habit) {
        let value = loggedValue(for: record, habit: habit)
        let sessionType = record.sourceName ?? "Apple Health"
        let note = "Imported from Apple Health\(record.sourceName.map { " via \($0)" } ?? "")"
        guard (try? TrainingStore.log(
            habit: habit,
            value: value,
            date: record.endDate,
            sessionType: sessionType,
            note: note,
            source: .health,
            healthWorkoutUUID: record.workoutUUID,
            context: modelContext
        )) != nil else {
            return
        }

        record.habitSystemKey = habit.systemKey
        record.wasImported = true
        record.awaitingHabitAssignment = false
    }

    private func createNewHabitAndAttribute(record: HealthImportedWorkout, name: String) {
        let measurementType: MeasurementType = .minutes
        let nextSortOrder = (habits.map(\.sortOrder).max() ?? -1) + 1
        let habit = Habit(
            systemKey: "user-\(UUID().uuidString.prefix(8))",
            name: name,
            notes: "",
            measurementType: measurementType,
            unitLabel: measurementType.defaultUnitLabel,
            scheduleType: .weekly,
            targetPerPeriod: 0,
            active: true,
            sortOrder: nextSortOrder,
            statDomain: stat
        )
        modelContext.insert(habit)
        try? modelContext.save()
        attribute(record: record, to: habit)
    }

    private func ignore(record: HealthImportedWorkout) {
        for pendingRecord in matchingWorkouts(for: record) {
            pendingRecord.habitSystemKey = nil
            pendingRecord.awaitingHabitAssignment = false
            pendingRecord.wasImported = false
        }
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func matchingWorkouts(for record: HealthImportedWorkout) -> [HealthImportedWorkout] {
        workouts.filter { candidate in
            candidate.statKeyRaw == record.statKeyRaw &&
            candidate.activityTypeRaw == record.activityTypeRaw &&
            candidate.awaitingHabitAssignment &&
            !candidate.isDuplicate
        }
    }

    private func loggedValue(for record: HealthImportedWorkout, habit: Habit) -> Double {
        switch habit.measurementType {
        case .booleanSession: return 1
        case .minutes: return max(1, record.durationMinutes.rounded())
        case .count, .customNumber, .pages: return 1
        }
    }

    private func formatDuration(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        if rounded >= 60 {
            let hours = rounded / 60
            let mins = rounded % 60
            return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
        }
        return "\(max(rounded, 1)) min"
    }

    static func displayName(for activityTypeRaw: Int) -> String {
        if let raw = UInt(exactly: activityTypeRaw),
           let type = HKWorkoutActivityType(rawValue: raw),
           let supported = SupportedWorkoutType.all.first(where: { $0.activityType == type }) {
            return supported.displayName
        }
        return "Workout"
    }
}
#endif
