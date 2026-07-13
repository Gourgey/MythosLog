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
        (habit.logs ?? []).sorted { $0.date > $1.date }
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
                V4Card(accent: accent) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let statName = habit.statDomain?.name {
                            Text(statName.uppercased())
                                .font(.caption.weight(.heavy))
                                .tracking(1.8)
                                .foregroundStyle(accent)
                        }
                        V4SerifTitle(text: habit.name, size: 28)
                        Text(habit.notes.isEmpty ? "No notes yet." : habit.notes)
                            .foregroundStyle(TrainingTheme.textSecondary)
                            .font(.subheadline)

                        Divider().overlay(TrainingTheme.border.opacity(0.5))

                        HStack(alignment: .top, spacing: 0) {
                            V4StatTile(value: V4Style.displayNumber(streak.current), label: "Current streak", tint: accent)
                            V4StatTile(value: V4Style.displayNumber(streak.longest), label: "Longest", tint: TrainingTheme.textPrimary)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                HabitQuickActionButtons(habit: habit, accent: accent) { value in
                    logDraft = LogEntryDraft(habit: habit, value: value)
                }
                Button {
                    logDraft = LogEntryDraft(habit: habit)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.heavy))
                        Text("Custom Log")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            } header: {
                Text("QUICK LOG")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(TrainingTheme.textMuted)
            }

            Section {
                if recentLogs.isEmpty {
                    Text("No logs yet.")
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .font(.subheadline)
                } else {
                    ForEach(recentLogs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(MetricFormatting.metric(log.numericValue, unit: habit.unitLabel))
                                    .font(.system(.subheadline, design: .serif).weight(.regular))
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                    .monospacedDigit()
                                Spacer()
                                Text(log.date, style: .date)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                            if !log.note.isEmpty {
                                Text(log.note)
                                    .font(.caption)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                            if let sessionType = log.sessionType {
                                Text(sessionType)
                                    .font(.caption2.weight(.bold))
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
            } header: {
                Text("RECENT LOGS")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(TrainingTheme.textMuted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
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
    }
}

struct LogEntrySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @FocusState private var focusedField: FocusField?
    @State private var workingDraft: LogEntryDraft
    @State private var isSaving = false
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

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var isReadingHabit: Bool {
        habit.statDomain?.statKey == .reading
    }

    private var sessionTypePlaceholder: String {
        isReadingHabit ? "Book title (optional)" : "Session type (optional)"
    }

    private var skillName: String {
        habit.statDomain?.name ?? "Skill"
    }

    private var siblingHabits: [Habit] {
        guard let stat = habit.statDomain else { return [habit] }
        let active = TrainingStore.activeHabits(for: stat)
        return active.isEmpty ? [habit] : active
    }

    @ViewBuilder
    private func habitEyebrow(showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            if let icon = habit.statDomain?.iconName {
                Image(systemName: icon)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(accent)
            }
            Text("\(skillName.uppercased()) · \(habit.name.uppercased())")
                .font(.caption.weight(.heavy))
                .tracking(1.6)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
            }
        }
    }

    private func selectHabit(_ newHabit: Habit) {
        guard newHabit.id != habit.id else { return }
        workingDraft.habit = newHabit
        workingDraft.value = newHabit.measurementType.defaultIncrement
    }

    private var screenTitle: String {
        habit.measurementType == .booleanSession ? "Log a Session" : "Log Progress"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    if siblingHabits.count > 1 {
                        Menu {
                            ForEach(siblingHabits) { option in
                                Button {
                                    selectHabit(option)
                                } label: {
                                    if option.id == habit.id {
                                        Label(option.name, systemImage: "checkmark")
                                    } else {
                                        Text(option.name)
                                    }
                                }
                            }
                        } label: {
                            habitEyebrow(showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        habitEyebrow(showsChevron: false)
                    }

                    V4SerifTitle(text: screenTitle, size: 34)
                }
                .padding(.top, 8)

                Divider()
                    .overlay(TrainingTheme.border.opacity(0.5))

                logFieldRow(label: "WHEN") {
                    DatePicker("", selection: $workingDraft.date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                Divider()
                    .overlay(TrainingTheme.border.opacity(0.5))

                if habit.measurementType != .booleanSession {
                    logFieldRow(label: "AMOUNT") {
                        HStack(spacing: 8) {
                            TextField("0", value: $workingDraft.value, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(.title3, design: .serif).weight(.regular))
                                .focused($focusedField, equals: .amount)
                                .frame(maxWidth: 120)
                            Text(habit.unitLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(habit.measurementType.quickStepValues(weeklyBaseline: habit.statDomain?.currentBaseline ?? 0), id: \.self) { step in
                            Button {
                                workingDraft.value += step
                            } label: {
                                Text("+\(Int(step))")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(accent.opacity(0.10))
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(accent.opacity(0.25), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    Divider()
                        .overlay(TrainingTheme.border.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTE")
                        .font(.caption.weight(.heavy))
                        .tracking(1.6)
                        .foregroundStyle(TrainingTheme.textMuted)

                    TextField(sessionTypePlaceholder, text: $workingDraft.sessionType)
                        .focused($focusedField, equals: .sessionType)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .font(.system(.subheadline, design: .serif))
                        .italic()

                    TextField("Notes (optional)", text: $workingDraft.note, axis: .vertical)
                        .focused($focusedField, equals: .note)
                        .lineLimit(2...4)
                        .font(.system(.subheadline, design: .serif))
                        .italic()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.985, green: 0.975, blue: 0.955).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button {
                    save()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.heavy))
                        Text(habit.measurementType == .booleanSession ? "Complete Session" : "Save Log")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(accent)
                    )
                }
                .disabled(isSaving)
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text("Save for later")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color(red: 0.97, green: 0.96, blue: 0.94))
                        )
                        .overlay(
                            Capsule().strokeBorder(TrainingTheme.border.opacity(0.7), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                Color(red: 0.985, green: 0.975, blue: 0.955).opacity(0.98)
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(red: 0.93, green: 0.92, blue: 0.89)))
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            if isReadingHabit,
               workingDraft.sessionType.isEmpty,
               let last = settings?.lastReadingBookTitle,
               !last.isEmpty {
                workingDraft.sessionType = last
            }
        }
    }

    private func logFieldRow<Content: View>(label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.caption.weight(.heavy))
                .tracking(1.6)
                .foregroundStyle(TrainingTheme.textMuted)
                .frame(width: 92, alignment: .leading)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, 4)
    }


    private func save() {
        guard !isSaving else { return }
        isSaving = true

        if habit.measurementType == .booleanSession {
            workingDraft.value = 1
        } else {
            workingDraft.value = max(0, workingDraft.value)
        }

        if isReadingHabit {
            let trimmed = workingDraft.sessionType.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let settings {
                settings.lastReadingBookTitle = trimmed
                settings.updatedAt = .now
                try? modelContext.save()
            }
        }

        onSave(workingDraft)
        dismiss()
    }
}
