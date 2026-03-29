import SwiftData
import SwiftUI

struct HabitDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    let habit: Habit

    @State private var showingEditor = false

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var accent: Color {
        habit.statDomain.map { TrainingArcConfig.color(for: $0.colorToken) } ?? TrainingTheme.backgroundTertiary
    }

    private var recentLogs: [HabitLog] {
        habit.logs.sorted { $0.date > $1.date }
    }

    private var streakCadence: StreakCadence {
        habit.scheduleType == .daily ? .daily : .weekly(settings?.weekStartsOnMonday ?? true)
    }

    private var streak: HabitStreakSummary {
        StreakService.summary(for: recentLogs.map(\.date), cadence: streakCadence)
    }

    var body: some View {
        List {
            Section {
                SurfaceCard(accent: accent) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(habit.name)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(habit.notes.isEmpty ? "No notes yet." : habit.notes)
                            .foregroundStyle(TrainingTheme.textSecondary)
                        HStack {
                            Label("Current streak \(streak.current)", systemImage: "flame.fill")
                            Spacer()
                            Label("Longest \(streak.longest)", systemImage: "flag.pattern.checkered")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("Quick Log") {
                HabitQuickActionButtons(habit: habit, accent: accent) { value in
                    _ = try? TrainingStore.log(
                        habit: habit,
                        value: value,
                        date: .now,
                        note: "",
                        source: .manual,
                        context: modelContext
                    )
                    if settings?.hapticsEnabled ?? true {
                        HapticsService.impact()
                    }
                }
                HabitManualLogForm(habit: habit, accent: accent)
            }

            Section("Recent Logs") {
                if recentLogs.isEmpty {
                    Text("No logs yet.")
                        .foregroundStyle(TrainingTheme.textSecondary)
                } else {
                    ForEach(recentLogs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(MetricFormatting.metric(log.numericValue, unit: habit.unitLabel))
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Spacer()
                                Text(log.date, style: .date)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                            if !log.note.isEmpty {
                                Text(log.note)
                                    .font(.caption)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                        }
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
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle(habit.name)
        .toolbar {
            Button("Edit") {
                showingEditor = true
            }
        }
        .sheet(isPresented: $showingEditor) {
            HabitEditorView(habit: habit)
        }
    }
}

struct HabitManualLogForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]

    let habit: Habit
    let accent: Color
    var dismissOnSubmit = false

    @State private var amount: Double
    @State private var logDate = Date()
    @State private var note = ""
    @State private var sourceType: LogSourceType = .manual

    init(habit: Habit, accent: Color, dismissOnSubmit: Bool = false) {
        self.habit = habit
        self.accent = accent
        self.dismissOnSubmit = dismissOnSubmit
        _amount = State(initialValue: habit.measurementType.defaultIncrement)
    }

    private var settings: AppSettings? {
        settingsRecords.first
    }

    var body: some View {
        DatePicker("Date", selection: $logDate, displayedComponents: [.date])

        if habit.measurementType != .booleanSession {
            HStack {
                Text("Amount")
                Spacer()
                TextField("Amount", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            HStack(spacing: 10) {
                ForEach(habit.measurementType.quickStepValues, id: \.self) { step in
                    Button("+\(Int(step))") {
                        amount += step
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }
            }
        }

        Picker("Source", selection: $sourceType) {
            ForEach(LogSourceType.allCases) { source in
                Text(source.displayName).tag(source)
            }
        }
        TextField("Note", text: $note)

        Button(habit.measurementType == .booleanSession ? "Mark Complete" : "Log Entry") {
            addLog()
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
    }

    private func addLog() {
        _ = try? TrainingStore.log(
            habit: habit,
            value: habit.measurementType == .booleanSession ? 1 : amount,
            date: logDate,
            note: note,
            source: sourceType,
            context: modelContext
        )

        if settings?.hapticsEnabled ?? true {
            HapticsService.success()
        }

        amount = habit.measurementType.defaultIncrement
        note = ""
        sourceType = .manual
        logDate = .now

        if dismissOnSubmit {
            dismiss()
        }
    }
}
