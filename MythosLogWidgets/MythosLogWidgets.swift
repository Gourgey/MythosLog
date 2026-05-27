import AppIntents
import SwiftUI
import WidgetKit

struct TrainingArcEntry: TimelineEntry {
    let date: Date
    let snapshot: TrainingWidgetSnapshot
}

struct TrainingArcProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingArcEntry {
        TrainingArcEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingArcEntry) -> Void) {
        completion(TrainingArcEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingArcEntry>) -> Void) {
        let entry = TrainingArcEntry(date: .now, snapshot: WidgetSnapshotStore.load())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct TrainingArcStatusWidget: Widget {
    let kind = "TrainingArcStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingArcProvider()) { entry in
            TrainingArcStatsWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: entry.snapshot.pendingWeeklyReview ? .weeklyReview : .dashboard))
        }
        .configurationDisplayName("Skill Stats")
        .description("Your weekly progress and current skill levels at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TrainingArcMotivationWidget: Widget {
    let kind = "TrainingArcMotivationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingArcProvider()) { entry in
            TrainingArcMotivationWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: entry.snapshot.pendingWeeklyReview ? .weeklyReview : .dashboard))
        }
        .configurationDisplayName("Training Motivation")
        .description("A quick nudge toward the skill that needs your attention most.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TrainTodayWidget: Widget {
    let kind = "TrainTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingArcProvider()) { entry in
            TrainTodayWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: entry.snapshot.pendingWeeklyReview ? .weeklyReview : .dashboard))
        }
        .configurationDisplayName("Train Today")
        .description("The single most important action right now — review ready, goal at risk, or pace gap.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Phase 10 widgets

private func arcWidgetAccent(for token: String) -> Color {
    switch token {
    case "strength": Color(red: 0.93, green: 0.39, blue: 0.28)
    case "intellect": Color(red: 0.35, green: 0.61, blue: 1.0)
    case "creativity": Color(red: 0.96, green: 0.53, blue: 0.27)
    case "emotional": Color(red: 0.96, green: 0.35, blue: 0.52)
    case "focus": Color(red: 0.32, green: 0.82, blue: 0.67)
    case "curiosity": Color(red: 0.73, green: 0.56, blue: 1.0)
    case "cardio": Color(red: 0.30, green: 0.72, blue: 0.88)
    case "cooking": Color(red: 0.92, green: 0.50, blue: 0.30)
    case "reading": Color(red: 0.45, green: 0.50, blue: 0.74)
    default: Color(red: 0.32, green: 0.82, blue: 0.67)
    }
}

private func arcWidgetSurface<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
    content()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.black, accent.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
}

private func quickLogIncrement(forMeasurementRaw raw: String) -> Double {
    switch raw {
    case "pages", "minutes": 10
    default: 1
    }
}

struct QuickLogWidget: Widget {
    let kind = "QuickLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingArcProvider()) { entry in
            QuickLogWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Quick Log")
        .description("Log a session to your top habits without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct QuickLogWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    private var habits: [TrainingWidgetHabit] {
        let limit = family == .systemMedium ? 4 : 2
        return Array(entry.snapshot.todayHabits.prefix(limit))
    }

    var body: some View {
        arcWidgetSurface(accent: arcWidgetAccent(for: entry.snapshot.stats.first?.colorToken ?? "focus")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK LOG")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))

                if habits.isEmpty {
                    Text("No habits yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Finish onboarding to start logging.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ForEach(habits) { habit in
                        quickLogRow(habit)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private func quickLogRow(_ habit: TrainingWidgetHabit) -> some View {
        let increment = quickLogIncrement(forMeasurementRaw: habit.measurementTypeRaw)
        let pending = QuickLogQueue.pendingAmount(forHabitID: habit.id.uuidString)
        let total = habit.todayValue + pending

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(habit.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(MetricFormatting.shortMetric(total)) \(habit.unitLabel) today")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Button(intent: QuickLogIntent(habitID: habit.id.uuidString, amount: increment, habitName: habit.name)) {
                Text("+\(MetricFormatting.shortMetric(increment))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
        }
    }
}

struct WeakestStatWidget: Widget {
    let kind = "WeakestStatWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingArcProvider()) { entry in
            WeakestStatWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: .dashboard))
        }
        .configurationDisplayName("Weakest Skill")
        .description("The skill that needs attention most this week.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct WeakestStatWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    private var weakest: TrainingWidgetStat? { entry.snapshot.weakestStat }

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text("Needs attention")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(weakest?.name ?? "All skills steady")
                    .font(.headline.weight(.bold))
                if let weakest {
                    Text("LV \(weakest.level) · \(MetricFormatting.shortMetric(weakest.weekActual)) / \(MetricFormatting.shortMetric(Double(weakest.baseline)))")
                        .font(.caption2)
                }
            }
            .padding(.vertical, 2)
        } else {
            arcWidgetSurface(accent: arcWidgetAccent(for: weakest?.colorToken ?? "focus")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEEDS ATTENTION")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(weakest?.name ?? "All skills steady")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let weakest {
                        Text("Level \(weakest.level)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        Text("\(MetricFormatting.shortMetric(weakest.weekActual)) / \(MetricFormatting.shortMetric(Double(weakest.baseline))) this week")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    } else {
                        Spacer()
                        Text("Nothing is slipping right now.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(16)
            }
        }
    }
}

struct GoalAtRiskWidget: Widget {
    let kind = "GoalAtRiskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingArcProvider()) { entry in
            GoalAtRiskWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: .goals))
        }
        .configurationDisplayName("Goal at Risk")
        .description("Your most urgent goal and how many are slipping.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct GoalAtRiskWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    private var title: String {
        entry.snapshot.topGoalAtRiskTitle ?? (entry.snapshot.activeGoalCount > 0 ? "Goals on track" : "No active goals")
    }

    private var detail: String {
        if let detail = entry.snapshot.topGoalAtRiskDetail {
            return detail
        }
        return entry.snapshot.activeGoalCount > 0 ? "Every goal is on pace." : "Set a goal to start tracking."
    }

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.goalsAtRiskCount > 0 ? "Goal at risk" : "Goals")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
        } else {
            arcWidgetSurface(accent: entry.snapshot.goalsAtRiskCount > 0 ? Color(red: 0.88, green: 0.58, blue: 0.16) : arcWidgetAccent(for: "focus")) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("GOAL AT RISK", systemImage: "target")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(title)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                    Spacer()
                    if entry.snapshot.goalsAtRiskCount > 0 {
                        Text("\(entry.snapshot.goalsAtRiskCount) of \(entry.snapshot.activeGoalCount) goals slipping")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(16)
            }
        }
    }
}

struct ReviewReadyWidget: Widget {
    let kind = "ReviewReadyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingArcProvider()) { entry in
            ReviewReadyWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: entry.snapshot.pendingWeeklyReview ? .weeklyReview : .dashboard))
        }
        .configurationDisplayName("Weekly Review")
        .description("Shows when last week is ready to resolve.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

private struct ReviewReadyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    private var isReady: Bool { entry.snapshot.pendingWeeklyReview }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: isReady ? "calendar.badge.exclamationmark" : "calendar")
                    .font(.title3)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly Review")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(isReady ? "Ready to resolve" : "All caught up")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                Text(isReady ? "Lock in last week" : "Nothing to resolve")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
        default:
            arcWidgetSurface(accent: isReady ? Color(red: 0.88, green: 0.58, blue: 0.16) : arcWidgetAccent(for: "focus")) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: isReady ? "calendar.badge.clock" : "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Text(isReady ? "Weekly review ready" : "All caught up")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer()
                    Text(isReady ? "Resolve last week to apply your rank check." : "No week is waiting to resolve.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(3)
                }
                .padding(16)
            }
        }
    }
}

private struct TrainTodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    private var headline: String {
        entry.snapshot.trainTodayHeadline ?? (entry.snapshot.pendingWeeklyReview ? "Weekly review ready" : "All skills on pace")
    }

    private var detail: String {
        entry.snapshot.trainTodayDetail ?? entry.snapshot.momentumSubtitle
    }

    private var accent: Color {
        accentColor(for: entry.snapshot.trainTodayColorToken ?? entry.snapshot.motivationColorToken)
    }

    var body: some View {
        switch family {
        case .systemMedium:
            mediumWidget
        case .accessoryRectangular:
            accessoryWidget
        default:
            smallWidget
        }
    }

    private var smallWidget: some View {
        widgetSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TRAIN TODAY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(headline)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                Spacer()
                if entry.snapshot.goalsAtRiskCount > 0 {
                    Text("\(entry.snapshot.goalsAtRiskCount) goal\(entry.snapshot.goalsAtRiskCount == 1 ? "" : "s") at risk")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(16)
        }
    }

    private var mediumWidget: some View {
        widgetSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("TRAIN TODAY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(headline)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(3)
                Spacer()
                HStack(spacing: 14) {
                    if entry.snapshot.activeGoalCount > 0 {
                        Label("\(entry.snapshot.activeGoalCount) active", systemImage: "target")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    if entry.snapshot.goalsAtRiskCount > 0 {
                        Label("\(entry.snapshot.goalsAtRiskCount) at risk", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .padding(16)
        }
    }

    private var accessoryWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func widgetSurface<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color.black, accent.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }

    private func accentColor(for token: String) -> Color {
        switch token {
        case "strength": Color(red: 0.93, green: 0.39, blue: 0.28)
        case "intellect": Color(red: 0.35, green: 0.61, blue: 1.0)
        case "creativity": Color(red: 0.96, green: 0.53, blue: 0.27)
        case "emotional": Color(red: 0.96, green: 0.35, blue: 0.52)
        case "focus": Color(red: 0.32, green: 0.82, blue: 0.67)
        case "curiosity": Color(red: 0.73, green: 0.56, blue: 1.0)
        case "cardio": Color(red: 0.30, green: 0.72, blue: 0.88)
        case "cooking": Color(red: 0.92, green: 0.50, blue: 0.30)
        case "reading": Color(red: 0.45, green: 0.50, blue: 0.74)
        default: .white
        }
    }
}

private struct TrainingArcStatsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumWidget
        case .accessoryRectangular:
            accessoryWidget
        default:
            smallWidget
        }
    }

    private var smallWidget: some View {
        widgetSurface(accent: accentColor(for: entry.snapshot.weakestStat?.colorToken ?? "focus")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.snapshot.stats.first?.name ?? "No skills yet")
                    .font(.headline)
                    .foregroundStyle(.white)
                if let stat = entry.snapshot.stats.first {
                    Text("LV \(stat.level) · \(MetricFormatting.shortMetric(stat.weekActual)) / \(MetricFormatting.shortMetric(Double(stat.baseline)))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    Text(entry.snapshot.momentumSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.74))
                }
                Text(entry.snapshot.characterSummary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                Spacer()
                if let weakest = entry.snapshot.weakestStat {
                    Text("Needs attention")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(weakest.name) · LV \(weakest.level)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
        }
    }

    private var mediumWidget: some View {
        widgetSurface(accent: accentColor(for: entry.snapshot.stats.first?.colorToken ?? "focus")) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.snapshot.appName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("This Week")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                    Text(entry.snapshot.characterSummary)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    if let weakest = entry.snapshot.weakestStat {
                        Text("Needs attention: \(weakest.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }

                Divider()
                    .overlay(.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Skills")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    ForEach(entry.snapshot.stats.prefix(3)) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("LV \(stat.level) · \(MetricFormatting.shortMetric(stat.weekActual)) / \(MetricFormatting.shortMetric(Double(stat.baseline)))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    if entry.snapshot.pendingWeeklyReview {
                        Label("Weekly review ready", systemImage: "calendar.badge.clock")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .padding(16)
        }
    }

    private var accessoryWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.snapshot.stats.first?.name ?? entry.snapshot.momentumTitle)
                .font(.caption.weight(.semibold))
            Text(entry.snapshot.stats.first.map { "LV \($0.level)" } ?? "No skills yet")
                .font(.headline.weight(.bold))
            Text(entry.snapshot.weakestStat.map { "Needs: \($0.name)" } ?? "Dashboard ready")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func widgetBackground(accent: Color) -> some View {
        LinearGradient(
            colors: [Color.black, accent.opacity(0.45)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func widgetSurface<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .containerBackground(for: .widget) {
                widgetBackground(accent: accent)
            }
    }

    private func accentColor(for token: String) -> Color {
        switch token {
        case "strength": Color(red: 0.93, green: 0.39, blue: 0.28)
        case "intellect": Color(red: 0.35, green: 0.61, blue: 1.0)
        case "creativity": Color(red: 0.96, green: 0.53, blue: 0.27)
        case "emotional": Color(red: 0.96, green: 0.35, blue: 0.52)
        case "focus": Color(red: 0.32, green: 0.82, blue: 0.67)
        case "curiosity": Color(red: 0.73, green: 0.56, blue: 1.0)
        default: .white
        }
    }
}

private struct TrainingArcMotivationWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumWidget
        case .accessoryRectangular:
            accessoryWidget
        default:
            smallWidget
        }
    }

    private var accent: Color {
        accentColor(for: entry.snapshot.motivationColorToken)
    }

    private var smallWidget: some View {
        widgetSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.snapshot.motivationTitle)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                Text(entry.snapshot.motivationMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(4)
                Spacer()
                Text("Tap to open Mythos Log")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.64))
            }
            .padding(16)
        }
    }

    private var mediumWidget: some View {
        widgetSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stay Consistent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(entry.snapshot.motivationTitle)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                Text(entry.snapshot.motivationMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(4)
                Spacer()
                if let weakest = entry.snapshot.weakestStat {
                    Text("Current pressure point: \(weakest.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.74))
                }
                if entry.snapshot.goalsAtRiskCount > 0 {
                    Label("\(entry.snapshot.goalsAtRiskCount) goal\(entry.snapshot.goalsAtRiskCount == 1 ? "" : "s") at risk", systemImage: "target")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(16)
        }
    }

    private var accessoryWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.snapshot.motivationTitle)
                .font(.caption.weight(.semibold))
            Text(entry.snapshot.motivationMessage)
                .font(.caption2)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func widgetBackground(accent: Color) -> some View {
        LinearGradient(
            colors: [Color.black, accent.opacity(0.45)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func widgetSurface<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .containerBackground(for: .widget) {
                widgetBackground(accent: accent)
            }
    }

    private func accentColor(for token: String) -> Color {
        switch token {
        case "strength": Color(red: 0.93, green: 0.39, blue: 0.28)
        case "intellect": Color(red: 0.35, green: 0.61, blue: 1.0)
        case "creativity": Color(red: 0.96, green: 0.53, blue: 0.27)
        case "emotional": Color(red: 0.96, green: 0.35, blue: 0.52)
        case "focus": Color(red: 0.32, green: 0.82, blue: 0.67)
        case "curiosity": Color(red: 0.73, green: 0.56, blue: 1.0)
        default: .white
        }
    }
}
