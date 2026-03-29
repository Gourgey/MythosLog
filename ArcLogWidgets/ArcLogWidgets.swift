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
            TrainingArcWidgetEntryView(entry: entry)
                .widgetURL(TrainingRouteLink.url(for: entry.snapshot.pendingWeeklyReview ? .weeklyReview : .dashboard))
        }
        .configurationDisplayName("Training Status")
        .description("Momentum, weakest stat, and your daily habits at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TrainingArcWidgetEntryView: View {
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
        ZStack {
            widgetBackground(accent: accentColor(for: entry.snapshot.weakestStat?.colorToken ?? "focus"))
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.snapshot.momentumTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(entry.snapshot.momentumSubtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                Spacer()
                if let weakest = entry.snapshot.weakestStat {
                    Text("Weakest")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(weakest.name) · \(weakest.descriptor)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
        }
    }

    private var mediumWidget: some View {
        ZStack {
            widgetBackground(accent: accentColor(for: entry.snapshot.stats.first?.colorToken ?? "focus"))
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.snapshot.appName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(entry.snapshot.momentumTitle)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                    Text(entry.snapshot.characterSummary)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    if let weakest = entry.snapshot.weakestStat {
                        Text("Neglected: \(weakest.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }

                Divider()
                    .overlay(.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    ForEach(entry.snapshot.todayHabits.prefix(3)) { habit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("\(MetricFormatting.shortMetric(habit.todayValue)) \(habit.unitLabel)")
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
            Text(entry.snapshot.momentumTitle)
                .font(.caption.weight(.semibold))
            Text(entry.snapshot.weakestStat?.name ?? "No weakest stat")
                .font(.headline.weight(.bold))
            Text(entry.snapshot.pendingWeeklyReview ? "Weekly review pending" : "Dashboard ready")
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
