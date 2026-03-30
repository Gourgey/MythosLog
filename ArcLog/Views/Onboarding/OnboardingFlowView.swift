import SwiftData
import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedBaselineKey: StatKey?
    @State private var step = 0
    @State private var selectedHabitKeys = Set(TrainingArcConfig.defaultHabitTemplates.map(\.systemKey))
    @State private var baselines = Dictionary(uniqueKeysWithValues: TrainingArcConfig.statTemplates.map { ($0.key, $0.defaultBaseline) })
    @State private var baselineDrafts = Dictionary(uniqueKeysWithValues: TrainingArcConfig.statTemplates.map { ($0.key, "\($0.defaultBaseline)") })
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
                Text("Set the baseline that matches your real current form. Your starting rank comes from that baseline, while charge reflects banked weekly surplus toward the next rank.")
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
                Text("Find your Rank")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("Set the amount you honestly do in a normal week. Your starting level updates live, along with the next and lower baseline targets.")
                    .foregroundStyle(TrainingTheme.textSecondary)

                ForEach(TrainingArcConfig.statTemplates) { template in
                    baselineCard(for: template)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedBaselineKey = nil
                }
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedBaselineKey = nil
            }
        )
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Weekly Resolution")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("The weekly report becomes a summary screen. Rank updates after completed weeks are resolved, while charge tracks banked surplus toward the next rank.")
                    .foregroundStyle(TrainingTheme.textSecondary)

                SurfaceCard(accent: TrainingArcConfig.color(for: "curiosity")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your opening baseline assigns your starting rank", systemImage: "figure.stand")
                        Label("Your latest completed week resolves at the end of Sunday", systemImage: "calendar")
                        Label("Charge now banks surplus across weeks toward the next rank", systemImage: "flame.fill")
                        Label("Backdated logs can still update the current build when they matter", systemImage: "clock.arrow.circlepath")
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

    private func baselineCard(for template: StatTemplate) -> some View {
        let onboarding = TrainingArcConfig.onboardingConfiguration(for: template.key)
        let baseline = baselines[template.key] ?? template.defaultBaseline
        let currentLevel = TrainingArcConfig.rankLevel(for: template.key, weeklyValue: Double(baseline))
        let currentTitle = TrainingArcConfig.rankTitle(for: template.key, level: currentLevel)
        let lowerThreshold = TrainingArcConfig.lowerRankThreshold(for: template.key, level: currentLevel)
        let nextThreshold = TrainingArcConfig.nextRankThreshold(for: template.key, level: currentLevel)

        return SurfaceCard(accent: TrainingArcConfig.color(for: template.colorToken)) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.key.displayName)
                        .font(.headline)
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text(onboarding.question)
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                HStack(spacing: 14) {
                    baselineAdjustButton(systemName: "minus", action: {
                        adjustBaseline(for: template.key, delta: -1)
                    })

                    VStack(spacing: 4) {
                        Text("\(baseline)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(TrainingArcConfig.baselineValueLabel(for: template.key, value: baseline))
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    baselineAdjustButton(systemName: "plus", action: {
                        adjustBaseline(for: template.key, delta: 1)
                    })
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(onboarding.quickAdjustments, id: \.self) { amount in
                            quickAdjustmentButton(title: "-\(amount)") {
                                adjustBaseline(for: template.key, delta: -amount)
                            }

                            quickAdjustmentButton(title: "+\(amount)") {
                                adjustBaseline(for: template.key, delta: amount)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack(spacing: 12) {
                    Text(onboarding.manualEntryLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textSecondary)

                    TextField(onboarding.manualEntryLabel, text: bindingForBaselineDraft(of: template.key))
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedBaselineKey, equals: template.key)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(TrainingTheme.background.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(TrainingTheme.border, lineWidth: 1)
                        )
                        .frame(maxWidth: 140)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Level \(currentLevel) · \(currentTitle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textPrimary)

                    Text(lowerRankText(for: template.key, currentLevel: currentLevel, threshold: lowerThreshold))
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)

                    Text(nextRankText(for: template.key, currentLevel: currentLevel, threshold: nextThreshold))
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }
        }
    }

    private func baselineAdjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(TrainingTheme.background.opacity(0.7))
                )
                .overlay(
                    Circle()
                        .strokeBorder(TrainingTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private func quickAdjustmentButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(TrainingTheme.background.opacity(0.55))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(TrainingTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func bindingForBaselineDraft(of key: StatKey) -> Binding<String> {
        Binding(
            get: { baselineDrafts[key] ?? "\(baselines[key] ?? TrainingArcConfig.definition(for: key).defaultBaseline)" },
            set: { updateBaselineDraft($0, for: key) }
        )
    }

    private func updateBaselineDraft(_ draft: String, for key: StatKey) {
        let onboarding = TrainingArcConfig.onboardingConfiguration(for: key)
        let digitsOnly = draft.filter(\.isNumber)
        baselineDrafts[key] = digitsOnly

        guard !digitsOnly.isEmpty else { return }
        let parsedValue = Int(digitsOnly) ?? onboarding.minimumValue
        let clampedValue = min(max(parsedValue, onboarding.minimumValue), onboarding.maximumValue)
        baselines[key] = clampedValue
        baselineDrafts[key] = "\(clampedValue)"
    }

    private func adjustBaseline(for key: StatKey, delta: Int) {
        let onboarding = TrainingArcConfig.onboardingConfiguration(for: key)
        let currentValue = baselines[key] ?? TrainingArcConfig.definition(for: key).defaultBaseline
        let nextValue = min(max(currentValue + delta, onboarding.minimumValue), onboarding.maximumValue)
        baselines[key] = nextValue
        baselineDrafts[key] = "\(nextValue)"
    }

    private func lowerRankText(for key: StatKey, currentLevel: Int, threshold: Int?) -> String {
        guard let threshold else {
            return "Lower rank: Level 1 starts at \(TrainingArcConfig.baselineValueLabel(for: key, value: TrainingArcConfig.requiredWeeklyValue(for: key, level: 1)))."
        }

        return "Lower rank: Level \(currentLevel - 1) at \(TrainingArcConfig.baselineValueLabel(for: key, value: threshold))."
    }

    private func nextRankText(for key: StatKey, currentLevel: Int, threshold: Int?) -> String {
        guard let threshold else {
            return "Next rank: You are already at Level \(TrainingArcConfig.maximumRankLevel)."
        }

        return "Next rank: Level \(currentLevel + 1) at \(TrainingArcConfig.baselineValueLabel(for: key, value: threshold))."
    }
}
