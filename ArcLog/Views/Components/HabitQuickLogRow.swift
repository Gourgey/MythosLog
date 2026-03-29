import SwiftData
import SwiftUI

struct HabitQuickLogRow: View {
    @Environment(\.modelContext) private var modelContext
    let habit: Habit
    let todayValue: Double
    let hapticsEnabled: Bool

    private var steps: [Double] {
        habit.measurementType.quickStepValues
    }

    var body: some View {
        SurfaceCard(accent: habit.statDomain.map { TrainingArcConfig.color(for: $0.colorToken) } ?? TrainingTheme.backgroundTertiary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(habit.statDomain?.name ?? "Unlinked")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                    Spacer()
                    Text("Today \(MetricFormatting.metric(todayValue, unit: habit.unitLabel))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                HabitQuickActionButtons(habit: habit, accent: habit.statDomain.map { TrainingArcConfig.color(for: $0.colorToken) } ?? .accentColor) { value in
                    log(value)
                }
            }
        }
    }

    private func log(_ value: Double) {
        _ = try? TrainingStore.log(
            habit: habit,
            value: value,
            date: .now,
            note: "",
            source: .manual,
            context: modelContext
        )

        if hapticsEnabled {
            HapticsService.impact()
        }
    }
}

struct HabitQuickActionButtons: View {
    let habit: Habit
    let accent: Color
    let onLog: (Double) -> Void

    private var steps: [Double] {
        habit.measurementType.quickStepValues
    }

    var body: some View {
        if habit.measurementType == .booleanSession {
            Button {
                onLog(1)
            } label: {
                Label("Complete Session", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .accessibilityLabel("Mark \(habit.name) complete")
        } else {
            HStack(spacing: 10) {
                ForEach(steps, id: \.self) { step in
                    Button {
                        onLog(step)
                    } label: {
                        Text("+\(Int(step))")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }
            }
        }
    }
}
