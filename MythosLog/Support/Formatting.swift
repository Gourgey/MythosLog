import Foundation

enum MetricFormatting {
    static func metric(_ value: Double, unit: String) -> String {
        let rounded = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(rounded) \(unit)"
    }

    static func shortMetric(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
