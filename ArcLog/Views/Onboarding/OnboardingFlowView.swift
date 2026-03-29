import SwiftData
import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var step = 0
    @State private var selectedHabitKeys = Set(TrainingArcConfig.defaultHabitTemplates.map(\.systemKey))
    @State private var baselines = Dictionary(uniqueKeysWithValues: TrainingArcConfig.statTemplates.map { ($0.key, $0.defaultBaseline) })
    @State private var enableNotifications = false
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                TabView(selection: $step) {
                    introStep.tag(0)
                    habitsStep.tag(1)
                    baselineStep.tag(2)
                    reviewStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack {
                    if step > 0 {
                        Button("Back") {
                            withAnimation { step -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(step == 3 ? "Begin Training" : "Next") {
                        if step == 3 {
                            completeOnboarding()
                        } else {
                            withAnimation { step += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrainingArcConfig.color(for: "focus"))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private var introStep: some View {
        VStack(spacing: 28) {
            Spacer()

            AuraView(color: TrainingArcConfig.color(for: "focus"), size: 180)

            VStack(spacing: 12) {
                Text(AppIdentity.displayName)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("A personal training system where real habits harden into earned stats.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .padding(.horizontal, 32)
            }

            SurfaceCard(accent: TrainingArcConfig.color(for: "strength")) {
                Text("Hit the baseline to maintain the build. Exceed it to earn rank progress. Charge reflects your current momentum.")
                    .font(.body)
                    .foregroundStyle(TrainingTheme.textPrimary)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var habitsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose Your Starter Habits")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)

                Text("All seven core stats are included. Pick the habits you want seeded on day one.")
                    .foregroundStyle(TrainingTheme.textSecondary)

                ForEach(TrainingArcConfig.defaultHabitTemplates) { template in
                    let isSelected = selectedHabitKeys.contains(template.systemKey)
                    SurfaceCard(accent: TrainingArcConfig.color(for: template.statKey == .strength ? "strength" : template.statKey.rawValue)) {
                        Button {
                            if isSelected {
                                selectedHabitKeys.remove(template.systemKey)
                            } else {
                                selectedHabitKeys.insert(template.systemKey)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? accentColor(for: template) : TrainingTheme.textSecondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name)
                                        .font(.headline)
                                        .foregroundStyle(TrainingTheme.textPrimary)
                                    Text("\(template.statKey.displayName) · \(MetricFormatting.metric(template.targetPerPeriod, unit: template.unitLabel)) per \(template.scheduleType.displayName.lowercased())")
                                        .font(.caption)
                                        .foregroundStyle(TrainingTheme.textSecondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
    }

    private var baselineStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set Initial Baselines")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("This is the standard you want to maintain each week before extra work becomes rank progress.")
                    .foregroundStyle(TrainingTheme.textSecondary)

                ForEach(TrainingArcConfig.statTemplates) { template in
                    SurfaceCard(accent: TrainingArcConfig.color(for: template.colorToken)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.key.displayName)
                                    .font(.headline)
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Text("Default habit target: \(template.defaultBaseline)")
                                    .font(.caption)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                            }
                            Spacer()
                            Stepper(value: Binding(
                                get: { baselines[template.key] ?? template.defaultBaseline },
                                set: { baselines[template.key] = max(1, $0) }
                            ), in: 1...120) {
                                Text("\(baselines[template.key] ?? template.defaultBaseline)")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(TrainingTheme.textPrimary)
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Weekly Resolution")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("Each week ends with a training report. Surplus effort becomes rank progress. Charge remains your current momentum signal. Neglect still triggers stagnation and, eventually, regression.")
                    .foregroundStyle(TrainingTheme.textSecondary)

                SurfaceCard(accent: TrainingArcConfig.color(for: "curiosity")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Baseline 3, actual 5 = +2 rank progress", systemImage: "bolt.fill")
                        Label("Reach 4 stored progress to raise the rank by 1", systemImage: "arrow.up.circle.fill")
                        Label("Charge fills from current-week momentum", systemImage: "flame.fill")
                        Label("Miss the build for too long and the system pushes back", systemImage: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(TrainingTheme.textPrimary)
                }

                Toggle(isOn: $enableNotifications) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable reminders")
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text("Daily prompts, evening cleanup, and weekly review reminder.")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(24)
        }
    }

    private func completeOnboarding() {
        try? TrainingStore.seedDefaultProfile(
            context: modelContext,
            baselines: baselines,
            selectedHabitKeys: selectedHabitKeys,
            completeOnboarding: true
        )

        if enableNotifications {
            Task {
                await NotificationService.requestAuthorization()
                if let settings = try? TrainingStore.fetchSettings(context: modelContext) {
                    settings.dailyReminderEnabled = true
                    settings.eveningReminderEnabled = true
                    settings.weeklyReviewReminderEnabled = true
                    try? modelContext.save()
                    NotificationService.refreshNotifications(using: settings)
                }
            }
        }

        onComplete()
        dismiss()
    }

    private func accentColor(for template: HabitTemplate) -> Color {
        TrainingArcConfig.color(for: template.statKey.rawValue)
    }
}
