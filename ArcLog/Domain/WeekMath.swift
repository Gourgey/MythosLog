import Foundation

struct WeekRange: Hashable, Sendable {
    let start: Date
    let end: Date

    var displayTitle: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start, to: end)
    }
}

enum WeekMath {
    static func calendar(weekStartsOnMonday: Bool) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = weekStartsOnMonday ? 2 : 1
        return calendar
    }

    static func startOfWeek(for date: Date, weekStartsOnMonday: Bool, calendar baseCalendar: Calendar? = nil) -> Date {
        let calendar = baseCalendar ?? self.calendar(weekStartsOnMonday: weekStartsOnMonday)
        let components = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    static func weekRange(containing date: Date, weekStartsOnMonday: Bool, calendar baseCalendar: Calendar? = nil) -> WeekRange {
        let calendar = baseCalendar ?? self.calendar(weekStartsOnMonday: weekStartsOnMonday)
        let start = startOfWeek(for: date, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return WeekRange(start: start, end: end)
    }

    static func lastCompletedWeek(before now: Date, weekStartsOnMonday: Bool, calendar baseCalendar: Calendar? = nil) -> WeekRange {
        let calendar = baseCalendar ?? self.calendar(weekStartsOnMonday: weekStartsOnMonday)
        let currentWeekStart = startOfWeek(for: now, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
        return weekRange(containing: lastWeekStart, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
    }

    static func dateInterval(for week: WeekRange, calendar: Calendar) -> DateInterval {
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: week.end) ?? week.end
        return DateInterval(start: week.start, end: endExclusive)
    }

    static func isSameWeek(_ lhs: Date, _ rhs: Date, weekStartsOnMonday: Bool, calendar baseCalendar: Calendar? = nil) -> Bool {
        let calendar = baseCalendar ?? self.calendar(weekStartsOnMonday: weekStartsOnMonday)
        return startOfWeek(for: lhs, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar) ==
            startOfWeek(for: rhs, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
    }

    static func weekOffset(from start: Date, to end: Date, weekStartsOnMonday: Bool, calendar baseCalendar: Calendar? = nil) -> Int {
        let calendar = baseCalendar ?? self.calendar(weekStartsOnMonday: weekStartsOnMonday)
        let lhs = startOfWeek(for: start, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
        let rhs = startOfWeek(for: end, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
        return calendar.dateComponents([.weekOfYear], from: lhs, to: rhs).weekOfYear ?? 0
    }
}
