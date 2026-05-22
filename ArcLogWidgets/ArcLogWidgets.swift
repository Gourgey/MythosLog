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
                Text("Tap to open ArcLog")
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
