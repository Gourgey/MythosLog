import SwiftData
import SwiftUI

struct HabitDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    let habit: Habit

    @State private var showingEditor = false
    @State private var logDraft: LogEntryDraft?

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
                    logDraft = LogEntryDraft(habit: habit, value: value)
                }
                Button("Custom Log") {
                    logDraft = LogEntryDraft(habit: habit)
                }
                .buttonStyle(.bordered)
                .tint(accent)
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
                            if let sessionType = log.sessionType {
                                Text(sessionType)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(accent)
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
    }
}

struct LogEntrySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?
    @State private var workingDraft: LogEntryDraft
    let accent: Color
    let onSave: (LogEntryDraft) -> Void

    private enum FocusField: Hashable {
        case amount
        case sessionType
        case note
    }

    init(draft: LogEntryDraft, accent: Color, onSave: @escaping (LogEntryDraft) -> Void) {
        self.accent = accent
        self.onSave = onSave
        _workingDraft = State(initialValue: draft)
    }

    private var habit: Habit {
        workingDraft.habit
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SurfaceCard(accent: accent) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(habit.name)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(TrainingTheme.textPrimary)

                        Text("Choose the date and time for this entry, then confirm it with Enter.")
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)

                        HStack(spacing: 12) {
                            DatePicker("Date", selection: $workingDraft.date, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                            DatePicker("Time", selection: $workingDraft.date, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.compact)
                        }
                    }
                }

                SurfaceCard(accent: accent) {
                    VStack(alignment: .leading, spacing: 14) {
                        if habit.measurementType != .booleanSession {
                            HStack {
                                Text("Amount")
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Spacer()
                                TextField("Amount", value: $workingDraft.value, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .amount)
                                    .frame(maxWidth: 140)
                            }

                            HStack(spacing: 10) {
                                ForEach(habit.measurementType.quickStepValues, id: \.self) { step in
                                    Button("+\(Int(step))") {
                                        workingDraft.value += step
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(accent)
                                }
                            }
                        } else {
                            Label("This will log one completed session.", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(accent)
                        }

                        TextField("Session type (optional)", text: $workingDraft.sessionType)
                            .focused($focusedField, equals: .sessionType)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)

                        TextField("Notes (optional)", text: $workingDraft.note, axis: .vertical)
                            .focused($focusedField, equals: .note)
                            .lineLimit(2...4)
                    }
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                    .overlay(TrainingTheme.border.opacity(0.4))

                Button("Enter") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .background(TrainingTheme.background.opacity(0.96))
        }
        .navigationTitle(habit.measurementType == .booleanSession ? "Log Session" : "Log Progress")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }

    private func save() {
        if habit.measurementType == .booleanSession {
            workingDraft.value = 1
        } else {
            workingDraft.value = max(0, workingDraft.value)
        }
        onSave(workingDraft)
        dismiss()
    }
}
