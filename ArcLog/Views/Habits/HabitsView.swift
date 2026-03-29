import SwiftData
import SwiftUI

struct SkillDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]

    let stat: StatDomain

    @State private var manualLoggingHabit: Habit?

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var linkedHabits: [Habit] {
        TrainingStore.activeHabits(for: stat)
    }

    private var recentLogs: [HabitLog] {
        TrainingStore.recentLogs(for: stat)
    }

    private var currentWeekInterval: DateInterval {
        TrainingStore.currentWeekInterval(settings: settings)
    }

    private var snapshot: SkillProgressSnapshot {
        TrainingStore.progressSnapshot(for: stat, settings: settings)
    }

    var body: some View {
        List {
            Section {
                SurfaceCard(accent: accent) {
                    VStack(alignment: .leading, spacing: 16) {
                        RankArtworkView(
                            habitName: stat.name,
                            level: snapshot.rank.level,
                            title: snapshot.rank.title,
                            image: snapshot.rank.image,
                            accent: accent
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(stat.name)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(TrainingTheme.textPrimary)
                            Text(snapshot.overview)
                                .font(.subheadline)
                                .foregroundStyle(TrainingTheme.textSecondary)
                            Text("Level \(snapshot.rank.level) of \(snapshot.rank.maximumLevel)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }

                        HStack(spacing: 10) {
                            summaryPill(
                                title: "Rank",
                                value: snapshot.rank.title,
                                tint: accent
                            )
                            summaryPill(
                                title: snapshot.charge.label,
                                value: "\(snapshot.charge.current) / \(snapshot.charge.maximum)",
                                tint: TrainingTheme.backgroundTertiary
                            )
                        }

                        HStack(spacing: 10) {
                            summaryPill(
                                title: "This Week",
                                value: "\(MetricFormatting.shortMetric(snapshot.currentWeekActual)) / \(snapshot.baseline)",
                                tint: accent.opacity(0.7)
                            )
                            summaryPill(
                                title: "Next Rank",
                                value: snapshot.rank.isAtMaximumRank
                                    ? "Maximum"
                                    : "\(snapshot.rank.progressUnits) / \(snapshot.rank.progressRequired)",
                                tint: TrainingTheme.backgroundTertiary
                            )
                        }

                        ProgressView(value: min(max(snapshot.rank.progressToNextLevel, 0), 1))
                            .tint(accent)

                        if snapshot.rank.isAtMaximumRank {
                            Text("You are at the current maximum rank for this skill.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)
                        } else if snapshot.earnedRankProgressThisWeek > 0 {
                            Text("+\(snapshot.earnedRankProgressThisWeek) rank progress banked from this week")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let nextTitle = snapshot.rank.nextTitle, !snapshot.rank.isAtMaximumRank {
                Section("Next Rank") {
                    SurfaceCard(accent: accent) {
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Level \(snapshot.rank.level + 1)")
                                    .font(.headline)
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Text(nextTitle)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                            Spacer()
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section("Linked Habits") {
                if linkedHabits.isEmpty {
                    Text("No active habits are linked to this skill yet.")
                        .foregroundStyle(TrainingTheme.textSecondary)
                } else {
                    ForEach(linkedHabits) { habit in
                        SurfaceCard(accent: accent) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(habit.name)
                                            .font(.headline)
                                            .foregroundStyle(TrainingTheme.textPrimary)
                                        Text("\(MetricFormatting.shortMetric(TrainingStore.total(for: habit, in: currentWeekInterval))) / \(MetricFormatting.shortMetric(habit.targetPerPeriod)) \(habit.unitLabel) this \(habit.scheduleType.displayName.lowercased())")
                                            .font(.caption)
                                            .foregroundStyle(TrainingTheme.textSecondary)
                                    }
                                    Spacer()
                                    Button("Manual Log") {
                                        manualLoggingHabit = habit
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(accent)
                                }

                                HabitQuickActionButtons(habit: habit, accent: accent) { value in
                                    log(habit: habit, value: value)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            Section("Recent Logs") {
                if recentLogs.isEmpty {
                    Text("Logs for this skill will show up here.")
                        .foregroundStyle(TrainingTheme.textSecondary)
                } else {
                    ForEach(recentLogs) { log in
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

                            if !log.note.isEmpty {
                                Text(log.note)
                                    .font(.caption)
                                    .foregroundStyle(TrainingTheme.textSecondary)
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
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(stat.name)
        .sheet(item: $manualLoggingHabit) { habit in
            NavigationStack {
                List {
                    Section("Manual Log") {
                        HabitManualLogForm(habit: habit, accent: accent, dismissOnSubmit: true)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(TrainingTheme.background.ignoresSafeArea())
                .navigationTitle(habit.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            manualLoggingHabit = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func summaryPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func log(habit: Habit, value: Double) {
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
}
