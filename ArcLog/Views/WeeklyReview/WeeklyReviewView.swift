import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeeklyResolution.weekStartDate, order: .reverse) private var resolutions: [WeeklyResolution]
    @Query(sort: \HealthImportedWorkout.startDate, order: .reverse) private var healthWorkouts: [HealthImportedWorkout]
    @Query private var settingsRecords: [AppSettings]
    @State private var selectedWeekStart: Date?

    init() {}

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var groupedWeeks: [Date] {
        Array(Set(resolutions.map(\.weekStartDate))).sorted(by: >)
    }

    private var selectedWeekResolutions: [WeeklyResolution] {
        guard let selectedWeekStart else { return [] }
        return resolutions.filter {
            $0.weekStartDate == selectedWeekStart
        }.sorted { $0.statName < $1.statName }
    }

    private var healthOverlapWarnings: [HealthImportedWorkout] {
        healthWorkouts
            .filter { $0.wasImported && $0.overlapsImportedWorkout && !$0.isDuplicate }
            .sorted { $0.startDate > $1.startDate }
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
                    if let pendingWeek = try? TrainingStore.pendingWeek(context: modelContext) {
                        SurfaceCard(accent: TrainingTheme.warning) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Training Report Ready")
                                    .font(.system(.title2, design: .rounded).weight(.bold))
                                    .foregroundStyle(TrainingTheme.textPrimary)
                                Text("Resolve \(pendingWeek.displayTitle) to apply the weekly rank check and save the report.")
                                    .foregroundStyle(TrainingTheme.textSecondary)
                                Button("Sync Week") {
                                    let batch = try? TrainingStore.resolvePendingWeek(context: modelContext)
                                    selectedWeekStart = batch?.week.start
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(TrainingTheme.warning)
                            }
                        }
                    }

                    if !healthOverlapWarnings.isEmpty {
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

                    if !groupedWeeks.isEmpty {
                        Picker("Resolved week", selection: Binding(
                            get: { selectedWeekStart ?? groupedWeeks.first ?? .now },
                            set: { selectedWeekStart = $0 }
                        )) {
                            ForEach(groupedWeeks, id: \.self) { week in
                                Text(WeekRange(start: week, end: Calendar.current.date(byAdding: .day, value: 6, to: week) ?? week).displayTitle)
                                    .tag(week)
                            }
                        }
                        .pickerStyle(.menu)

                        verdictCard

                        ForEach(selectedWeekResolutions) { resolution in
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
                    } else {
                        SurfaceCard {
                            Text("No weekly reports yet. Weekly rank checks save themselves here after each completed week resolves.")
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Review")
        .onAppear {
            selectedWeekStart = selectedWeekStart ?? groupedWeeks.first
        }
    }

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
        let resolutions = selectedWeekResolutions
        guard !resolutions.isEmpty else { return .heldForm }
        let levelUps = resolutions.filter(\.didLevelUp).count
        let regressed = resolutions.filter(\.didRegress).count
        let belowBaseline = resolutions.filter { $0.weeklyDelta < 0 }.count
        let aboveBaseline = resolutions.filter { $0.weeklyDelta > 0 }.count

        if regressed > 0 { return .regressionRisk }
        if levelUps > 0, belowBaseline == 0 { return .advanced }
        if belowBaseline > resolutions.count / 2 { return .lostMomentum }
        if aboveBaseline > 0, belowBaseline > 0 { return .mixed }
        return .heldForm
    }

    private var weekFocusRecommendation: String? {
        let resolutions = selectedWeekResolutions
        let worst = resolutions.min { $0.weeklyDelta < $1.weeklyDelta }
        guard let worst, worst.weeklyDelta < 0 else { return nil }
        return "Focus next week: \(worst.statName)"
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
                    Text("\(selectedWeekResolutions.count) skills")
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
                return "Goal met: \(goal.title)"
            }
            if actual >= resolution.expectedTotal {
                let short = max(target - actual, 0)
                return "Maintained baseline. Goal short by \(MetricFormatting.shortMetric(short))."
            }
            return "Below baseline. Goal still pending: \(goal.title)"
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
}
