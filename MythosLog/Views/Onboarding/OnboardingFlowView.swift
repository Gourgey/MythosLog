import SwiftData
import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: OnboardingField?
    @State private var step = 0
    @State private var selectedSkillKeys = TrainingArcConfig.coreSkillKeys
    @State private var baselines = Dictionary(uniqueKeysWithValues: TrainingArcConfig.statTemplates.map { ($0.key, $0.defaultBaseline) })
    @State private var baselineDrafts = Dictionary(uniqueKeysWithValues: TrainingArcConfig.statTemplates.map { ($0.key, "\($0.defaultBaseline)") })
    @State private var goalDrafts: [StatKey: String] = [:]
    /// Skills whose Level 10 goal (rather than current amount) is the value
    /// the large editor on their card is changing.
    @State private var editingGoalKeys: Set<StatKey> = []
    @State private var enableNotifications = false
    let onComplete: () -> Void

    private enum OnboardingField: Hashable {
        case baseline(StatKey)
        case goal(StatKey)
    }

    private static let skillsStep = 2
    private static let lastStep = 4

    /// Only the skills chosen on the skills step are calibrated and seeded active.
    private var selectedTemplates: [StatTemplate] {
        TrainingArcConfig.statTemplates.filter { selectedSkillKeys.contains($0.key) }
    }

    private var canAdvance: Bool {
        step != Self.skillsStep || !selectedSkillKeys.isEmpty
    }

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
                    chargeStep.tag(1)
                    skillsStep.tag(2)
                    baselineStep.tag(3)
                    reviewStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack {
                    if step > 0 {
                        Button("Back") {
                            withAnimation { step -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    // Drawn here rather than by the page TabView, whose dots
                    // float over the scrolling content.
                    HStack(spacing: 8) {
                        ForEach(0...Self.lastStep, id: \.self) { index in
                            Circle()
                                .fill(index == step ? TrainingTheme.textPrimary : TrainingTheme.border)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Page \(step + 1) of \(Self.lastStep + 1)")

                    Spacer()

                    Button(step == Self.lastStep ? "Begin Training" : "Next") {
                        focusedField = nil
                        if step == Self.lastStep {
                            completeOnboarding()
                        } else {
                            withAnimation { step += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrainingArcConfig.color(for: "focus"))
                    .foregroundStyle(.white)
                    .disabled(!canAdvance)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .onChange(of: step) { oldStep, _ in
            // Swiping past the skills page with nothing chosen would seed an
            // empty dashboard.
            if oldStep == Self.skillsStep, selectedSkillKeys.isEmpty {
                step = Self.skillsStep
            }
        }
    }

    // MARK: - Step I: what the app is

    private var introStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                V4PageKicker(title: "Welcome")
                Text(AppIdentity.displayName)
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("Train real habits. Watch a character grow with them.")
                    .font(.system(.title3, design: .serif))
                    .italic()
                    .foregroundStyle(TrainingTheme.textSecondary)

                exampleFrame(caption: "Example: the Cardio character at Level 2, Level 5 and Level 9.") {
                    HStack(alignment: .bottom, spacing: 8) {
                        exampleCharacter(asset: "Cardio_Level_2", level: 2, title: TrainingArcConfig.rankTitle(for: .cardio, level: 2))
                        exampleCharacter(asset: "Cardio_Level_5", level: 5, title: TrainingArcConfig.rankTitle(for: .cardio, level: 5))
                        exampleCharacter(asset: "Cardio_Level_9", level: 9, title: TrainingArcConfig.rankTitle(for: .cardio, level: 9))
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    introPoint(
                        symbol: "square.grid.2x2",
                        title: "Pick your skills",
                        detail: "Strength, Cardio, Focus, Cooking and more. Each skill has its own character with 10 ranks."
                    )
                    introPoint(
                        symbol: "plus.circle",
                        title: "Log what you actually do",
                        detail: "A gym session, a run, a home-cooked meal. Logging takes a tap."
                    )
                    introPoint(
                        symbol: "calendar",
                        title: "Each week counts",
                        detail: "When the week ends, it's compared to what your rank asks for. Doing more builds charge; enough charge ranks you up."
                    )
                }
            }
            .padding(24)
        }
    }

    // MARK: - Step II: how charge works

    private var chargeStep: some View {
        let accent = TrainingArcConfig.color(for: "strength")
        let rankTitle = TrainingArcConfig.rankTitle(for: .strength, level: 4)
        let nextTitle = TrainingArcConfig.rankTitle(for: .strength, level: 5)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                V4PageKicker(title: "How Ranks Move")
                Text("Charge")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("Every rank asks for a set amount each week. Charge tracks how your weeks compare to it. It runs from −4 to +4: the four dots on the left fill red as you fall behind, the four on the right fill green as you get ahead.")
                    .foregroundStyle(TrainingTheme.textSecondary)

                exampleFrame(caption: "Example: a Strength skill at Level 4, which asks for 3 sessions a week.") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            V4LevelBadge(level: 4, tint: accent, compact: true)
                            Text(rankTitle)
                                .font(.system(.headline, design: .serif))
                                .foregroundStyle(TrainingTheme.textPrimary)
                            Spacer()
                            Text("3 sessions / week")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }

                        Divider().overlay(TrainingTheme.border.opacity(0.5))

                        chargeExampleRow(week: "Week 1", logged: "5 sessions", result: "2 above → +2", charge: 2)
                        chargeExampleRow(week: "Week 2", logged: "4 sessions", result: "1 above → +3", charge: 3)
                        chargeExampleRow(week: "Week 3", logged: "4 sessions", result: "+4 → Level 5, \(nextTitle)", charge: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    chargeRule(symbol: "arrow.up.circle.fill", tint: TrainingTheme.positive, text: "Beat your rank's weekly amount and you earn charge. The further above, the more you earn.")
                    chargeRule(symbol: "arrow.down.circle.fill", tint: TrainingTheme.danger, text: "Fall short and you lose charge, and any charge you'd built fades by one.")
                    chargeRule(symbol: "equal.circle.fill", tint: TrainingTheme.textSecondary, text: "Hit it exactly and charge holds where it is.")
                    chargeRule(symbol: "sparkles", tint: accent, text: "Reach +4 to rank up. Drop to −4 and you rank down. Either way, charge resets to 0.")
                }

                Text("Weeks end on Sunday night. Your logs during the week fill in a preview dot, so you can see the next charge coming.")
                    .font(.footnote)
                    .foregroundStyle(TrainingTheme.textMuted)
            }
            .padding(24)
        }
    }

    // MARK: - Step III: choose skills

    private var skillsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                V4PageKicker(title: "Step I")
                Text("Choose Your Skills")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(TrainingTheme.textPrimary)

                Text("Only the skills you pick appear on your dashboard. You can add or archive skills any time in Manage Skills.")
                    .foregroundStyle(TrainingTheme.textSecondary)

                ForEach(TrainingArcConfig.statTemplates) { template in
                    skillSelectionCard(for: template)
                }

                if selectedSkillKeys.isEmpty {
                    Text("Pick at least one skill to continue.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TrainingTheme.danger)
                }
            }
            .padding(24)
        }
    }

    private func skillSelectionCard(for template: StatTemplate) -> some View {
        let isSelected = selectedSkillKeys.contains(template.key)
        let accent = TrainingArcConfig.color(for: template.colorToken)
        let starter = TrainingArcConfig.definition(for: template.key).starterHabit

        return SurfaceCard(accent: accent) {
            Button {
                if isSelected {
                    selectedSkillKeys.remove(template.key)
                } else {
                    selectedSkillKeys.insert(template.key)
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? accent : TrainingTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(template.key.displayName, systemImage: template.iconName)
                            .font(.headline)
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text("Starts with: \(starter.name)")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    // MARK: - Step IV: current level and goal

    private var baselineStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                V4PageKicker(title: "Step II")
                Text("Find your Rank")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("For each skill, set what you honestly do in a normal week. That sets your starting rank.")
                    .foregroundStyle(TrainingTheme.textSecondary)
                Text("Optionally tap Level 10 goal to set the weekly amount you're working toward. Reaching it is the top rank, and the ranks in between are spread evenly up to it.")
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)

                ForEach(selectedTemplates) { template in
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
                    focusedField = nil
                }
            }
        }
    }

    private func goalBinding(for key: StatKey) -> Binding<String> {
        Binding(
            get: { goalDrafts[key] ?? "" },
            set: { draft in
                let digitsOnly = draft.filter(\.isNumber)
                let maximum = TrainingArcConfig.onboardingConfiguration(for: key).maximumValue
                if let value = Int(digitsOnly), value > maximum {
                    goalDrafts[key] = "\(maximum)"
                } else {
                    goalDrafts[key] = digitsOnly
                }
            }
        )
    }

    /// −/+ on the goal starts from the current amount when no goal is set,
    /// and never goes below it.
    private func adjustGoal(for key: StatKey, baseline: Int, delta: Int) {
        let maximum = TrainingArcConfig.onboardingConfiguration(for: key).maximumValue
        let start = Int(goalDrafts[key] ?? "") ?? baseline
        let next = min(max(start + delta, baseline), maximum)
        goalDrafts[key] = "\(next)"
    }

    private func selectEditor(goal: Bool, for key: StatKey) {
        let wasTyping = focusedField != nil
        if goal {
            editingGoalKeys.insert(key)
        } else {
            editingGoalKeys.remove(key)
        }
        // Keep the keyboard on the newly selected value rather than leaving it
        // attached to a field that just disappeared.
        if wasTyping {
            focusedField = goal ? .goal(key) : .baseline(key)
        }
    }

    private func clampedGoal(for key: StatKey, baseline: Int) -> Int? {
        TrainingArcConfig.clampCalibration(
            baseline: baseline,
            target: nil,
            personalMax: Int(goalDrafts[key] ?? ""),
            maintenance: nil
        ).max
    }

    // MARK: - Step V: weekly rhythm and reminders

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                V4PageKicker(title: "Step III")
                Text("Your Week")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("Log as you go. Each Monday, last week is scored and you get a short review of what changed.")
                    .foregroundStyle(TrainingTheme.textSecondary)

                SurfaceCard(accent: TrainingArcConfig.color(for: "intellect")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your starting rank comes from the weekly amounts you just set", systemImage: "figure.stand")
                        Label("Weeks close at the end of Sunday, then charge updates", systemImage: "calendar")
                        Label("Forgot to log? Pick an earlier date when logging and it still counts", systemImage: "clock.arrow.circlepath")
                        Label("Change any skill's weekly amount or Level 10 goal later with Recalibrate", systemImage: "slider.horizontal.3")
                    }
                    .font(.subheadline)
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

    // MARK: - Example visuals

    private func exampleFrame<Content: View>(caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(TrainingTheme.borderStrong.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: TrainingTheme.shadow, radius: 12, y: 6)
            Text(caption)
                .font(.caption)
                .foregroundStyle(TrainingTheme.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private func exampleCharacter(asset: String, level: Int, title: String) -> some View {
        VStack(spacing: 6) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
            V4LevelBadge(level: level, tint: TrainingArcConfig.color(for: "cardio"), compact: true)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func introPoint(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(TrainingArcConfig.color(for: "focus"))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chargeExampleRow(week: String, logged: String, result: String, charge: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(week.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(TrainingTheme.textMuted)
                Spacer()
                Text("Logged \(logged)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
            }
            HStack {
                SignedChargeMeter(charge: charge, socketSize: 12, spacing: 5)
                Spacer()
                Text(result)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TrainingTheme.positive)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func chargeRule(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(TrainingTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func completeOnboarding() {
        try? TrainingStore.seedDefaultProfile(
            context: modelContext,
            baselines: baselines,
            selectedSkillKeys: selectedSkillKeys,
            completeOnboarding: true
        )

        if let stats = try? TrainingStore.fetchStats(context: modelContext) {
            for stat in stats {
                guard let key = stat.statKey else { continue }
                // Goals typed for a skill that was then deselected are ignored.
                let goal = selectedSkillKeys.contains(key) ? Int(goalDrafts[key] ?? "") : nil
                let clamped = TrainingArcConfig.clampCalibration(
                    baseline: stat.currentBaseline,
                    target: nil,
                    personalMax: goal,
                    maintenance: nil
                )
                // One goal value: it scales the rank ladder (personal max) and
                // is mirrored into the legacy target field.
                stat.targetValue = clamped.max
                stat.personalMaxValue = clamped.max
                stat.maintenanceFloor = clamped.maintenance
                let reassessedLevel = TrainingArcConfig.rankLevel(
                    for: key,
                    weeklyValue: Double(stat.currentBaseline),
                    personalMax: clamped.max
                )
                stat.rankLevel = reassessedLevel
                stat.acknowledgedRankLevel = reassessedLevel
                stat.progressionAnchorDate = .now
                stat.progressionAnchorLevel = reassessedLevel
                stat.progressionAnchorBaseline = stat.currentBaseline
                TrainingStore.updateDerivedFields(for: stat)
            }
            try? modelContext.save()
        }

        if enableNotifications {
            Task {
                await NotificationService.requestAuthorization()
                if let settings = try? TrainingStore.fetchSettings(context: modelContext) {
                    settings.dailyReminderEnabled = true
                    settings.eveningReminderEnabled = true
                    settings.weeklyReviewReminderEnabled = true
                    settings.updatedAt = .now
                    try? modelContext.save()
                    TrainingStore.recordLocalWrite(reason: "enabled onboarding notifications")
                    NotificationService.refreshNotifications(using: settings)
                }
            }
        }

        onComplete()
        dismiss()
    }

    private func baselineCard(for template: StatTemplate) -> some View {
        let onboarding = TrainingArcConfig.onboardingConfiguration(for: template.key)
        let baseline = baselines[template.key] ?? template.defaultBaseline
        let goal = clampedGoal(for: template.key, baseline: baseline)
        let typedGoal = Int(goalDrafts[template.key] ?? "")
        let currentLevel = TrainingArcConfig.rankLevel(
            for: template.key,
            weeklyValue: Double(baseline),
            personalMax: goal
        )
        let currentTitle = TrainingArcConfig.rankTitle(for: template.key, level: currentLevel)
        let lowerThreshold = TrainingArcConfig.lowerRankThreshold(for: template.key, level: currentLevel, personalMax: goal)
        let nextThreshold = TrainingArcConfig.nextRankThreshold(for: template.key, level: currentLevel, personalMax: goal)
        let accent = TrainingArcConfig.color(for: template.colorToken)
        let isEditingGoal = editingGoalKeys.contains(template.key)

        return SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(template.key.displayName, systemImage: template.iconName)
                        .font(.headline)
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text(onboarding.question)
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                HStack(spacing: 10) {
                    valueSelector(
                        title: "Current",
                        value: "\(baseline)",
                        isSelected: !isEditingGoal,
                        accent: accent
                    ) {
                        selectEditor(goal: false, for: template.key)
                    }
                    valueSelector(
                        title: "Level 10 goal",
                        value: goal.map { "\($0)" } ?? "—",
                        isSelected: isEditingGoal,
                        accent: accent
                    ) {
                        selectEditor(goal: true, for: template.key)
                    }
                }

                HStack(spacing: 14) {
                    baselineAdjustButton(systemName: "minus", label: isEditingGoal ? "Lower \(template.key.displayName) goal" : "Decrease \(template.key.displayName)") {
                        if isEditingGoal {
                            adjustGoal(for: template.key, baseline: baseline, delta: -1)
                        } else {
                            adjustBaseline(for: template.key, delta: -1)
                        }
                    }

                    Group {
                        if isEditingGoal {
                            TextField("—", text: goalBinding(for: template.key))
                                .focused($focusedField, equals: .goal(template.key))
                                .accessibilityLabel("\(template.key.displayName) Level 10 goal")
                        } else {
                            TextField("0", text: bindingForBaselineDraft(of: template.key))
                                .focused($focusedField, equals: .baseline(template.key))
                                .accessibilityLabel("\(template.key.displayName) per week")
                        }
                    }
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(isEditingGoal ? accent : TrainingTheme.textPrimary)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(TrainingTheme.background.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isEditingGoal ? accent.opacity(0.6) : TrainingTheme.border, lineWidth: 1)
                    )

                    baselineAdjustButton(systemName: "plus", label: isEditingGoal ? "Raise \(template.key.displayName) goal" : "Increase \(template.key.displayName)") {
                        if isEditingGoal {
                            adjustGoal(for: template.key, baseline: baseline, delta: 1)
                        } else {
                            adjustBaseline(for: template.key, delta: 1)
                        }
                    }
                }

                if isEditingGoal {
                    VStack(spacing: 10) {
                        Text(goal.map { "\(TrainingArcConfig.baselineValueLabel(for: template.key, value: $0)) reaches Level 10" } ?? "Optional. Leave blank to use the standard scale.")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                            .multilineTextAlignment(.center)

                        if let typedGoal, let goal, typedGoal < goal {
                            Text("A goal can't be below your current amount, so it counts as \(goal).")
                                .font(.caption)
                                .foregroundStyle(TrainingTheme.warning)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 10) {
                            Button {
                                goalDrafts[template.key] = "\(TrainingArcConfig.suggestedGoalValue(for: template.key, baseline: baseline))"
                            } label: {
                                Label("Suggest", systemImage: "wand.and.stars")
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .buttonStyle(.bordered)
                            .tint(accent)

                            if goal != nil {
                                Button("Clear") {
                                    goalDrafts[template.key] = nil
                                }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(TrainingTheme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(TrainingArcConfig.baselineValueLabel(for: template.key, value: baseline))
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .frame(maxWidth: .infinity)
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

    /// One of the two tappable values at the top of a skill card. The
    /// selected one is what the large editor below is changing.
    private func valueSelector(title: String, value: String, isSelected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? accent : TrainingTheme.textMuted)
                Text(value)
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(isSelected ? TrainingTheme.textPrimary : TrainingTheme.textSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.55) : TrainingTheme.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit this value")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func baselineAdjustButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
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
        .accessibilityLabel(label)
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
