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
                .widgetURL(TrainingRouteLink.url(for: .dashboard))
        }
        .configurationDisplayName("Mythos Log")
        .description("Your skills at a glance, with weekly progress rings.")
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

    private var skills: [TrainingWidgetStat] {
        let limit = family == .systemMedium ? 7 : (family == .systemSmall ? 2 : 3)
        // Keep snapshot order for skills at the same level.
        return entry.snapshot.stats.enumerated()
            .sorted { lhs, rhs in
                lhs.element.level == rhs.element.level
                    ? lhs.offset < rhs.offset
                    : lhs.element.level > rhs.element.level
            }
            .prefix(limit)
            .map(\.element)
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = family == .systemMedium
                ? (skills.count > 3 ? (skills.count + 1) / 2 : skills.count)
                : skills.count
            let rows = family == .systemMedium && skills.count > 3 ? 2 : 1
            let spacing: CGFloat = family == .accessoryRectangular ? 10 : 16
            let diameter = max(0, min(
                family == .accessoryRectangular ? 48 : 64,
                (geometry.size.width - CGFloat(max(columns - 1, 0)) * spacing) / CGFloat(max(columns, 1)),
                (geometry.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            ))

            if skills.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 28, weight: .light))
                    Text("Open Mythos Log to sync skills")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        ForEach(skills.prefix(max(columns, 1))) { stat in
                            SkillProgressCircle(stat: stat, diameter: diameter)
                        }
                    }
                    if rows > 1 {
                        HStack(spacing: spacing) {
                            ForEach(skills.dropFirst(columns)) { stat in
                                SkillProgressCircle(stat: stat, diameter: diameter)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
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

private struct SkillProgressCircle: View {
    let stat: TrainingWidgetStat
    let diameter: CGFloat

    private var progress: Double {
        guard stat.baseline > 0, stat.weekActual.isFinite else { return 0 }
        return min(max(stat.weekActual / Double(stat.baseline), 0), 1)
    }

    private var icon: String {
        if let iconName = stat.iconName, !iconName.isEmpty { return iconName }
        // Older snapshots do not include the skill's icon.
        switch stat.colorToken {
        case "strength": return "figure.strengthtraining.traditional"
        case "intellect": return "brain.head.profile"
        case "creativity": return "paintbrush.pointed.fill"
        case "emotional": return "heart.text.square.fill"
        case "focus": return "scope"
        case "curiosity": return "sparkles.rectangle.stack.fill"
        case "cardio": return "figure.run"
        case "cooking": return "fork.knife"
        case "reading": return "book.pages.fill"
        default: return "sparkles"
        }
    }

    var body: some View {
        let accent = arcWidgetAccent(for: stat.colorToken)
        let lineWidth: CGFloat = diameter < 50 ? 3 : 4

        ZStack {
            Circle()
                .stroke(accent.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: icon)
                .font(.system(size: diameter * 0.34, weight: .medium))
                .foregroundStyle(accent)
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stat.name), level \(stat.level)")
        .accessibilityValue("\(Int(progress * 100)) percent of weekly target")
    }
}

// MARK: - Widget styling

/// Primary ink for widget text on the light surface.
private let widgetInk = Color(red: 0.16, green: 0.18, blue: 0.21)
/// Secondary, softer ink for supporting copy.
private let widgetInkSecondary = Color(red: 0.42, green: 0.45, blue: 0.49)

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
