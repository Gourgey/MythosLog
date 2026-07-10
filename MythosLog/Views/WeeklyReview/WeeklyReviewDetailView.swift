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
                            .font(.caption.weight(.heavy))
                            .tracking(2.0)
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
        V4Card(accent: verdict.color) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("VERDICT")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Spacer()
                    Text("\(weekResolutions.count) skills")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
                Divider().overlay(TrainingTheme.border.opacity(0.5))

                V4SerifTitle(text: verdict.rawValue, size: 28)
                Text(verdict.description)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let weekFocusRecommendation {
                    V4StatusPill(text: weekFocusRecommendation, tint: verdict.color, systemImage: "scope")
                }

                if let focusSkillKey {
                    Button {
                        router.open(.goals)
                        PendingDestinationStore.queueNewGoal(statKeyRaw: focusSkillKey.rawValue)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "target")
                                .font(.caption.weight(.heavy))
                            Text("Set a goal for \(focusSkillKey.displayName)")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(verdict.color))
                    }
                    .buttonStyle(.plain)
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
            V4Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WEEK RECAP")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                    Divider().overlay(TrainingTheme.border.opacity(0.5))

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
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(TrainingTheme.textMuted)
                Text(value)
                    .font(.system(.subheadline, design: .serif).weight(.regular))
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
        V4Card(accent: TrainingTheme.warning) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(TrainingTheme.warning)
                    Text("APPLE HEALTH OVERLAPS")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.warning)
                }

                Divider().overlay(TrainingTheme.border.opacity(0.5))

                Text("Some imported workouts overlap in time. Check Apple Health, WHOOP, and Hevy before relying on these totals.")
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)

                ForEach(Array(healthOverlapWarnings.prefix(4)), id: \.workoutUUID) { workout in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(healthWarningTitle(for: workout))
                            .font(.system(.subheadline, design: .serif).weight(.regular))
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
            V4Card(accent: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.pink)
                        Text("APPLE HEALTH THIS WEEK")
                            .font(.caption.weight(.heavy))
                            .tracking(2.0)
                            .foregroundStyle(.pink)
                    }

                    Divider().overlay(TrainingTheme.border.opacity(0.5))

                    HStack(alignment: .top, spacing: 0) {
                        V4StatTile(value: V4Style.displayNumber(summary.counted), label: "Counted", tint: TrainingTheme.positiveStrong)
                        V4StatTile(value: V4Style.displayNumber(summary.duplicates), label: "Duplicates", tint: TrainingTheme.textMuted)
                        V4StatTile(value: V4Style.displayNumber(summary.needsReview), label: "Review", tint: summary.needsReview > 0 ? TrainingTheme.warning : TrainingTheme.textPrimary)
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
        let accent = TrainingArcConfig.color(for: resolution.statDomain?.colorToken ?? "focus")
        return V4Card(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(resolution.statName)
                        .font(.system(.headline, design: .serif).weight(.regular))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Spacer()
                    V4LevelBadge(level: resolution.levelAfter, tint: accent, compact: true)
                }

                Divider().overlay(TrainingTheme.border.opacity(0.5))

                HStack(alignment: .top, spacing: 0) {
                    perSkillStatTile(title: "Expected", value: MetricFormatting.shortMetric(resolution.expectedTotal), tint: TrainingTheme.textPrimary)
                    perSkillStatTile(title: "Actual", value: MetricFormatting.shortMetric(resolution.actualCompletedValue), tint: TrainingTheme.textPrimary)
                    perSkillStatTile(title: "Delta", value: MetricFormatting.shortMetric(resolution.weeklyDelta), tint: resolution.weeklyDelta < 0 ? TrainingTheme.warning : TrainingTheme.positiveStrong)
                }

                if resolution.didLevelUp {
                    V4StatusPill(text: "Ranked up this week", tint: TrainingTheme.positiveStrong, systemImage: "arrow.up")
                } else if resolution.didRegress {
                    V4StatusPill(text: "Ranked down this week", tint: TrainingTheme.warning, systemImage: "arrow.down")
                } else if resolution.weeklyDelta < 0 {
                    V4StatusPill(text: "Below baseline this week", tint: TrainingTheme.warning, systemImage: "exclamationmark.triangle.fill")
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

    private func perSkillStatTile(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(1.4)
                .foregroundStyle(TrainingTheme.textMuted)
            Text(value)
                .font(.system(.title3, design: .serif).weight(.regular))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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

}
