import SwiftData
import SwiftUI

struct WeeklyReviewDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \WeeklyResolution.weekStartDate, order: .reverse) private var resolutions: [WeeklyResolution]
    @Query(sort: \HealthImportedWorkout.startDate, order: .reverse) private var healthWorkouts: [HealthImportedWorkout]
    @Query private var settingsRecords: [AppSettings]

    let weekStart: Date

    private var settings: AppSettings? { settingsRecords.first }

    private var weekResolutions: [WeeklyResolution] {
        resolutions
            .filter { $0.weekStartDate == weekStart }
            .sorted { $0.statName < $1.statName }
    }

    private var weekInterval: DateInterval? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: weekStart)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private var healthOverlapWarnings: [HealthImportedWorkout] {
        guard let interval = weekInterval else { return [] }
        return healthWorkouts
            .filter { interval.contains($0.startDate) }
            .filter { $0.wasImported && $0.overlapsImportedWorkout && !$0.isDuplicate }
            .sorted { $0.startDate > $1.startDate }
    }

    private struct HealthWeekSummary {
        var counted: Int
        var duplicates: Int
        var needsReview: Int
        var sources: [String]

        var hasActivity: Bool { counted > 0 || duplicates > 0 || needsReview > 0 }
    }

    private var healthWeekSummary: HealthWeekSummary {
        guard let interval = weekInterval else {
            return HealthWeekSummary(counted: 0, duplicates: 0, needsReview: 0, sources: [])
        }
        let weekWorkouts = healthWorkouts.filter { interval.contains($0.startDate) }
        let counted = weekWorkouts.filter { $0.wasImported && !$0.isDuplicate }.count
        let duplicates = weekWorkouts.filter(\.isDuplicate).count
        let needsReview = weekWorkouts.filter { $0.wasImported && $0.overlapsImportedWorkout && !$0.isDuplicate }.count
        let sources = Array(Set(weekWorkouts.compactMap { workout -> String? in
            guard let name = workout.sourceName, !name.isEmpty else { return nil }
            return name
        })).sorted()
        return HealthWeekSummary(counted: counted, duplicates: duplicates, needsReview: needsReview, sources: sources)
    }

    private var weekTitle: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return WeekRange(start: weekStart, end: end).displayTitle
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    verdictCard
                    weeklyRecapCard

                    if !healthOverlapWarnings.isEmpty {
                        healthOverlapsCard
                    }

                    healthWeekCard

                    if !weekResolutions.isEmpty {
                        Text("PER SKILL")
                            .font(.caption.weight(.black))
                            .foregroundStyle(TrainingTheme.textMuted)

                        ForEach(weekResolutions) { resolution in
                            perSkillCard(resolution)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(weekTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Verdict

    private enum WeeklyVerdict: String {
        case advanced = "Advanced"
        case heldForm = "Held Form"
        case mixed = "Mixed Week"
        case lostMomentum = "Lost Momentum"
        case regressionRisk = "Regression Risk"

        var color: Color {
            switch self {
            case .advanced: return TrainingTheme.positiveStrong
            case .heldForm: return TrainingTheme.cold
            case .mixed: return TrainingTheme.warning
            case .lostMomentum: return TrainingTheme.warning
            case .regressionRisk: return TrainingTheme.danger
            }
        }

        var description: String {
            switch self {
            case .advanced: return "Skills moved forward this week."
            case .heldForm: return "Baselines maintained across the board."
            case .mixed: return "Some skills advanced, others slipped."
            case .lostMomentum: return "Most skills landed below baseline."
            case .regressionRisk: return "Skills ranked down or are close to dropping."
            }
        }
    }

    private var weekVerdict: WeeklyVerdict {
        guard !weekResolutions.isEmpty else { return .heldForm }
        let levelUps = weekResolutions.filter(\.didLevelUp).count
        let regressed = weekResolutions.filter(\.didRegress).count
        let belowBaseline = weekResolutions.filter { $0.weeklyDelta < 0 }.count
        let aboveBaseline = weekResolutions.filter { $0.weeklyDelta > 0 }.count

        if regressed > 0 { return .regressionRisk }
        if levelUps > 0, belowBaseline == 0 { return .advanced }
        if belowBaseline > weekResolutions.count / 2 { return .lostMomentum }
        if aboveBaseline > 0, belowBaseline > 0 { return .mixed }
        return .heldForm
    }

    private var weekFocusRecommendation: String? {
        let worst = weekResolutions.min { $0.weeklyDelta < $1.weeklyDelta }
        guard let worst, worst.weeklyDelta < 0 else { return nil }
        return "Focus next week: \(worst.statName)"
    }

    private var focusSkillKey: StatKey? {
        let worst = weekResolutions.min(by: { $0.weeklyDelta < $1.weeklyDelta })
        guard let worst, worst.weeklyDelta < 0 else { return nil }
        return StatKey(rawValue: worst.statKey)
    }

    @ViewBuilder
    private var verdictCard: some View {
        let verdict = weekVerdict
        SurfaceCard(accent: verdict.color) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(verdict.rawValue)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Spacer()
                    Text("\(weekResolutions.count) skills")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
                Text(verdict.description)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
                if let weekFocusRecommendation {
                    Text(weekFocusRecommendation)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(verdict.color)
                }

                if let focusSkillKey {
                    Button {
                        router.open(.goals)
                        PendingDestinationStore.queueNewGoal(statKeyRaw: focusSkillKey.rawValue)
                    } label: {
                        Label("Set a goal for \(focusSkillKey.displayName)", systemImage: "target")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(verdict.color)
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Recap

    @ViewBuilder
    private var weeklyRecapCard: some View {
        if let recap = try? TrainingStore.weeklyRecap(weekStart: weekStart, context: modelContext, settings: settings),
           recap.hasContent {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Week Recap")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)

                    if let best = recap.bestSkillName {
                        recapRow(
                            icon: "trophy.fill",
                            color: TrainingTheme.positiveStrong,
                            title: "Best trained",
                            value: [best, recap.bestSkillDetail].compactMap { $0 }.joined(separator: " · ")
                        )
                    }

                    if let neglected = recap.neglectedSkillName {
                        recapRow(
                            icon: "exclamationmark.circle.fill",
                            color: TrainingTheme.warning,
                            title: "Most neglected",
                            value: [neglected, recap.neglectedSkillDetail].compactMap { $0 }.joined(separator: " · ")
                        )
                    }

                    if !recap.gainedChargeSkills.isEmpty {
                        recapRow(
                            icon: "arrow.up.circle.fill",
                            color: TrainingTheme.positive,
                            title: "Gained charge",
                            value: recap.gainedChargeSkills.joined(separator: ", ")
                        )
                    }

                    if !recap.lostChargeSkills.isEmpty {
                        recapRow(
                            icon: "arrow.down.circle.fill",
                            color: TrainingTheme.warning,
                            title: "Lost charge",
                            value: recap.lostChargeSkills.joined(separator: ", ")
                        )
                    }

                    if !recap.goalsCompleted.isEmpty {
                        recapRow(
                            icon: "checkmark.seal.fill",
                            color: TrainingTheme.cold,
                            title: "Goals completed",
                            value: recap.goalsCompleted.joined(separator: ", ")
                        )
                    }

                    if let goalsLine = goalsRecapLine(recap) {
                        recapRow(
                            icon: "target",
                            color: TrainingTheme.cold,
                            title: "Goals",
                            value: goalsLine
                        )
                    }
                }
            }
        }
    }

    private func recapRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textSecondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
    }

    private func goalsRecapLine(_ recap: WeeklyRecap) -> String? {
        var parts: [String] = []
        if recap.goalsProgressedCount > 0 {
            parts.append("\(recap.goalsProgressedCount) progressed this week")
        }
        if recap.goalsAtRiskCount > 0 {
            parts.append("\(recap.goalsAtRiskCount) at risk now")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Health cards

    private var healthOverlapsCard: some View {
        SurfaceCard(accent: TrainingTheme.warning) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Apple Health Overlaps", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)

                Text("Some imported workouts overlap in time. Check Apple Health, WHOOP, and Hevy before relying on these totals.")
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)

                ForEach(Array(healthOverlapWarnings.prefix(4)), id: \.workoutUUID) { workout in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(healthWarningTitle(for: workout))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Text(healthWarningDetail(for: workout))
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var healthWeekCard: some View {
        let summary = healthWeekSummary
        if summary.hasActivity {
            SurfaceCard(accent: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text("Apple Health This Week")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                    }

                    HStack(spacing: 12) {
                        metricTile(title: "Counted", value: "\(summary.counted)")
                        metricTile(title: "Duplicates", value: "\(summary.duplicates)")
                        metricTile(title: "Review", value: "\(summary.needsReview)")
                    }

                    Text(healthSummaryDetail(summary))
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }
        }
    }

    private func healthSummaryDetail(_ summary: HealthWeekSummary) -> String {
        var parts: [String] = []
        if summary.counted > 0 {
            parts.append("\(summary.counted) workout\(summary.counted == 1 ? "" : "s") counted toward progress")
        }
        if summary.duplicates > 0 {
            parts.append("\(summary.duplicates) ignored as duplicate\(summary.duplicates == 1 ? "" : "s")")
        }
        if summary.needsReview > 0 {
            parts.append("\(summary.needsReview) overlap\(summary.needsReview == 1 ? "" : "s") to review")
        }
        var detail = parts.joined(separator: ", ") + "."
        if !summary.sources.isEmpty {
            detail += " From \(summary.sources.joined(separator: ", "))."
        }
        return detail
    }

    private func healthWarningTitle(for workout: HealthImportedWorkout) -> String {
        let source = workout.sourceName?.isEmpty == false ? workout.sourceName ?? "Apple Health" : "Apple Health"
        let skill = StatKey(rawValue: workout.statKeyRaw)?.displayName ?? "Workout"
        return "\(source) \(skill)"
    }

    private func healthWarningDetail(for workout: HealthImportedWorkout) -> String {
        let interval = "\(workout.startDate.formatted(date: .abbreviated, time: .shortened))-\(workout.endDate.formatted(date: .omitted, time: .shortened))"
        guard let related = workout.relatedWorkoutUUID.flatMap({ relatedID in healthWorkouts.first { $0.workoutUUID == relatedID } }) else {
            return "\(interval) overlaps another imported workout."
        }

        let relatedSource = related.sourceName?.isEmpty == false ? related.sourceName ?? "Apple Health" : "Apple Health"
        return "\(interval) overlaps \(relatedSource)."
    }

    // MARK: - Per-skill

    private func perSkillCard(_ resolution: WeeklyResolution) -> some View {
        SurfaceCard(accent: TrainingArcConfig.color(for: resolution.statDomain?.colorToken ?? "focus")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(resolution.statName)
                        .font(.headline)
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Spacer()
                    Text("Level \(resolution.levelAfter)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                HStack {
                    metricTile(title: "Expected", value: MetricFormatting.shortMetric(resolution.expectedTotal))
                    metricTile(title: "Actual", value: MetricFormatting.shortMetric(resolution.actualCompletedValue))
                    metricTile(title: "Delta", value: MetricFormatting.shortMetric(resolution.weeklyDelta))
                }

                if resolution.didLevelUp {
                    Label("Ranked up this week", systemImage: "arrow.up.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.positive)
                } else if resolution.didRegress {
                    Label("Ranked down this week", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.warning)
                } else if resolution.weeklyDelta < 0 {
                    Label("Below baseline this week", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.warning)
                }

                Text(goalAwareStatus(for: resolution))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)

                Text(resolution.summaryText)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }

    private func goalAwareStatus(for resolution: WeeklyResolution) -> String {
        guard let statKey = StatKey(rawValue: resolution.statKey) else { return "" }
        let goals = (try? TrainingStore.fetchGoals(for: statKey, context: modelContext)) ?? []
        let weeklyGoals = goals.filter { $0.status == .active && $0.type == .weeklyTarget }

        if let goal = weeklyGoals.first {
            let actual = resolution.actualCompletedValue
            let target = goal.targetValue
            if actual >= target {
                return "Goal met: \(goal.displayTitle)"
            }
            if actual >= resolution.expectedTotal {
                let short = max(target - actual, 0)
                return "Maintained baseline. Goal short by \(MetricFormatting.shortMetric(short))."
            }
            return "Below baseline. Goal still pending: \(goal.displayTitle)"
        }

        if resolution.actualCompletedValue == 0 {
            return "No activity logged."
        }
        if resolution.weeklyDelta >= 0 {
            return "Beat or matched baseline."
        }
        return "Below baseline."
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TrainingTheme.textSecondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(TrainingTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
