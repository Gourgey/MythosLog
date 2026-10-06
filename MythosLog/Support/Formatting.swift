import Foundation

enum MetricFormatting {
    static func metric(_ value: Double, unit: String) -> String {
        let rounded = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(rounded) \(unit)"
    }

    /// Singular form of a plural unit label ("sessions" -> "session") when
    /// `count` is exactly one, so labels never read "1 sessions".
    static func unit(_ pluralUnit: String, count: Double) -> String {
        guard count == 1, pluralUnit.hasSuffix("s") else { return pluralUnit }
        return String(pluralUnit.dropLast())
    }

    static func shortMetric(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func weekday(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    // Cached: DateFormatter creation is expensive and `weekday` is called
    // per-row in day summaries. Formatting reads happen on the main actor
    // (view code), so a single shared instance is safe here.
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
}
