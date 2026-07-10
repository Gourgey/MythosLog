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
            TrainingSummaryWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: entry.snapshot.pendingWeeklyReview ? .weeklyReview : .dashboard))
        }
        .configurationDisplayName("Mythos Log")
        .description("Your current skill levels, weekly progress, and next training prompt.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct QuickLogWidget: Widget {
    let kind = "QuickLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingArcProvider()) { entry in
            QuickLogWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: .dashboard))
        }
        .configurationDisplayName("Quick Log")
        .description("Log progress to your most relevant habits.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TrainingSummaryWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    private var snapshot: TrainingWidgetSnapshot { entry.snapshot }
    private var hasData: Bool { !snapshot.stats.isEmpty }
    private var primaryStat: TrainingWidgetStat? { snapshot.weakestStat ?? snapshot.stats.first }

    private var accent: Color {
        arcWidgetAccent(for: snapshot.trainTodayColorToken ?? primaryStat?.colorToken ?? snapshot.motivationColorToken)
    }

    private var headline: String {
        if !hasData {
            return "Open Mythos Log"
        }

        if snapshot.pendingWeeklyReview {
            return "Weekly review ready"
        }

        return snapshot.trainTodayHeadline ?? snapshot.motivationTitle
    }

    private var detail: String {
        if !hasData {
            return "Open the app once to sync your dashboard data."
        }

        return snapshot.trainTodayDetail ?? snapshot.motivationMessage
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
        arcWidgetSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                widgetEyebrow("MYTHOS LOG", accent: accent)

                Text(headline)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(widgetInk)
                    .lineLimit(2)

                if let primaryStat {
                    summaryMetric(for: primaryStat)
                } else {
                    Text("No synced skills yet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(widgetInkSecondary)
                }

                Spacer(minLength: 0)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(widgetInkSecondary)
                    .lineLimit(3)
            }
        }
    }

    private var mediumWidget: some View {
        arcWidgetSurface(accent: accent, topPadding: 28, bottomPadding: 26) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    widgetEyebrow(snapshot.appName.uppercased(), accent: accent)

                    Text(headline)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(widgetInk)
                        .lineLimit(2)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(widgetInkSecondary)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    if snapshot.pendingWeeklyReview {
                        Label("Review ready", systemImage: "calendar.badge.clock")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(widgetWarning)
                    } else if snapshot.goalsAtRiskCount > 0 {
                        Label("\(snapshot.goalsAtRiskCount) goal\(snapshot.goalsAtRiskCount == 1 ? "" : "s") at risk", systemImage: "target")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(widgetWarning)
                    }
                }

                Divider()
                    .overlay(widgetInkSecondary.opacity(0.22))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Skills")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(widgetInkSecondary)

                    if snapshot.stats.isEmpty {
                        Text("Open the app once to sync your active skills.")
                            .font(.caption)
                            .foregroundStyle(widgetInkSecondary)
                            .lineLimit(4)
                    } else {
                        ForEach(snapshot.stats.prefix(3)) { stat in
                            SkillProgressRow(stat: stat)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 150)
            }
        }
    }

    private var accessoryWidget: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headline)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let primaryStat {
                Text("\(primaryStat.name) LV \(primaryStat.level)")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                Text("\(MetricFormatting.shortMetric(primaryStat.weekActual)) / \(MetricFormatting.shortMetric(Double(primaryStat.baseline))) this week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Sync dashboard")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                Text("Open Mythos Log once")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func summaryMetric(for stat: TrainingWidgetStat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(stat.name) · LV \(stat.level)")
                .font(.caption.weight(.bold))
                .foregroundStyle(widgetInk)
                .lineLimit(1)
            Text("\(MetricFormatting.shortMetric(stat.weekActual)) / \(MetricFormatting.shortMetric(Double(stat.baseline))) this week")
                .font(.caption2)
                .foregroundStyle(widgetInkSecondary)
                .lineLimit(1)
        }
    }
}

private struct QuickLogWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingArcEntry

    private var snapshot: TrainingWidgetSnapshot { entry.snapshot }
    private var hasData: Bool { !snapshot.stats.isEmpty }
    private var habits: [TrainingWidgetHabit] {
        let limit = family == .systemMedium ? 4 : 2
        return Array(snapshot.todayHabits.prefix(limit))
    }

    private var accent: Color {
        arcWidgetAccent(for: snapshot.stats.first?.colorToken ?? snapshot.motivationColorToken)
    }

    var body: some View {
        arcWidgetSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                widgetEyebrow("QUICK LOG", accent: accent)

                if habits.isEmpty {
                    emptyState
                } else {
                    ForEach(habits) { habit in
                        quickLogRow(habit)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(hasData ? "No quick logs yet" : "Open Mythos Log")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(widgetInk)
                .lineLimit(2)
            Text(hasData ? "Add an active habit to enable widget logging." : "Open the app once to sync your habits.")
                .font(.caption)
                .foregroundStyle(widgetInkSecondary)
                .lineLimit(3)
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
                    .foregroundStyle(widgetInk)
                    .lineLimit(1)
                Text("\(MetricFormatting.shortMetric(total)) \(habit.unitLabel) today")
                    .font(.caption2)
                    .foregroundStyle(widgetInkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(intent: QuickLogIntent(habitID: habit.id.uuidString, amount: increment, habitName: habit.name)) {
                Text("+\(MetricFormatting.shortMetric(increment))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SkillProgressRow: View {
    let stat: TrainingWidgetStat

    private var progress: Double {
        guard stat.baseline > 0 else { return 0 }
        return min(max(stat.weekActual / Double(stat.baseline), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(stat.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(widgetInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("LV \(stat.level)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(widgetInkSecondary)
                    .lineLimit(1)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(arcWidgetAccent(for: stat.colorToken))

            Text("\(MetricFormatting.shortMetric(stat.weekActual)) / \(MetricFormatting.shortMetric(Double(stat.baseline)))")
                .font(.caption2)
                .foregroundStyle(widgetInkSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Widget styling

/// Primary ink for widget text on the light surface.
private let widgetInk = Color(red: 0.16, green: 0.18, blue: 0.21)
/// Secondary, softer ink for supporting copy.
private let widgetInkSecondary = Color(red: 0.42, green: 0.45, blue: 0.49)
/// Amber used for "at risk" / "review ready" callouts on the light surface.
private let widgetWarning = Color(red: 0.82, green: 0.45, blue: 0.12)

private func widgetEyebrow(_ text: String, accent: Color) -> some View {
    Text(text)
        .font(.caption2.weight(.black))
        .tracking(0.6)
        .foregroundStyle(accent.opacity(0.85))
        .lineLimit(1)
}

private func arcWidgetSurface<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
    arcWidgetSurface(accent: accent, topPadding: 24, horizontalPadding: 22, bottomPadding: 20, content: content)
}

private func arcWidgetSurface<Content: View>(
    accent: Color,
    topPadding: CGFloat,
    horizontalPadding: CGFloat = 22,
    bottomPadding: CGFloat,
    @ViewBuilder content: () -> Content
) -> some View {
    // Light background fills the whole widget; the content is inset so text
    // never sits against the widget edges. Padding is applied directly to the
    // content (no wrapping frame, which previously swallowed the inset). The
    // top gets a little extra so the eyebrow/headline sit lower from the edge.
    content()
        .padding(.top, topPadding)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.97, blue: 0.96),
                        Color(red: 0.90, green: 0.93, blue: 0.91),
                        Color(red: 0.92, green: 0.93, blue: 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [accent.opacity(0.14), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 220
                )
            }
        }
}

private func quickLogIncrement(forMeasurementRaw raw: String) -> Double {
    switch raw {
    case "pages", "minutes":
        return 10
    default:
        return 1
    }
}

private func arcWidgetAccent(for token: String) -> Color {
    switch token {
    case "strength":
        Color(red: 0.93, green: 0.39, blue: 0.28)
    case "intellect":
        Color(red: 0.35, green: 0.61, blue: 1.0)
    case "creativity":
        Color(red: 0.96, green: 0.53, blue: 0.27)
    case "emotional":
        Color(red: 0.96, green: 0.35, blue: 0.52)
    case "focus":
        Color(red: 0.32, green: 0.82, blue: 0.67)
    case "curiosity":
        Color(red: 0.73, green: 0.56, blue: 1.0)
    case "cardio":
        Color(red: 0.30, green: 0.72, blue: 0.88)
    case "cooking":
        Color(red: 0.92, green: 0.50, blue: 0.30)
    case "reading":
        Color(red: 0.45, green: 0.50, blue: 0.74)
    default:
        Color(red: 0.32, green: 0.82, blue: 0.67)
    }
}
