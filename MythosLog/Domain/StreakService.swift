import Foundation

enum StreakCadence: Sendable {
    case daily
    case weekly(Bool)
}

enum StreakService {
    static func summary(for dates: [Date], cadence: StreakCadence, referenceDate: Date = .now) -> HabitStreakSummary {
        let calendar = Calendar(identifier: .gregorian)
        let normalized = normalizedUnits(from: dates, cadence: cadence, calendar: calendar)
        guard !normalized.isEmpty else {
            return HabitStreakSummary(current: 0, longest: 0, lastLoggedDate: nil)
        }

        let sorted = normalized.sorted()
        var longest = 1
        var currentRun = 1

        for index in 1..<sorted.count {
            if isNextUnit(after: sorted[index - 1], next: sorted[index], cadence: cadence, calendar: calendar) {
                currentRun += 1
                longest = max(longest, currentRun)
            } else {
                currentRun = 1
            }
        }

        let latest = sorted.last ?? referenceDate
        let current = currentStreakLength(from: sorted, cadence: cadence, referenceDate: referenceDate, calendar: calendar)
        return HabitStreakSummary(current: current, longest: longest, lastLoggedDate: latest)
    }

    private static func normalizedUnits(from dates: [Date], cadence: StreakCadence, calendar: Calendar) -> [Date] {
        let normalized = dates.map { date -> Date in
            switch cadence {
            case .daily:
                return calendar.startOfDay(for: date)
            case .weekly(let weekStartsOnMonday):
                return WeekMath.startOfWeek(for: date, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
            }
        }
        return Array(Set(normalized))
    }

    /// Whether `next` is exactly one cadence unit after `current`. Compares
    /// calendar-day distance rather than raw `Date` equality so daylight-saving
    /// transitions (which shift wall-clock midnight by an hour in some zones)
    /// can't silently break an otherwise-consecutive run.
    private static func isNextUnit(after current: Date, next: Date, cadence: StreakCadence, calendar: Calendar) -> Bool {
        let dayGap = calendar.dateComponents([.day], from: current, to: next).day
        switch cadence {
        case .daily:
            return dayGap == 1
        case .weekly:
            return dayGap == 7
        }
    }

    private static func currentStreakLength(from dates: [Date], cadence: StreakCadence, referenceDate: Date, calendar: Calendar) -> Int {
        let referenceUnit: Date
        let graceUnit: Date

        switch cadence {
        case .daily:
            referenceUnit = calendar.startOfDay(for: referenceDate)
            graceUnit = calendar.date(byAdding: .day, value: -1, to: referenceUnit) ?? referenceUnit
        case .weekly(let weekStartsOnMonday):
            referenceUnit = WeekMath.startOfWeek(for: referenceDate, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
            graceUnit = calendar.date(byAdding: .day, value: -7, to: referenceUnit) ?? referenceUnit
        }

        guard let latest = dates.last else { return 0 }
        guard latest == referenceUnit || latest == graceUnit else { return 0 }

        var streak = 1
        var cursor = latest
        for candidate in dates.dropLast().reversed() {
            if isNextUnit(after: candidate, next: cursor, cadence: cadence, calendar: calendar) {
                streak += 1
                cursor = candidate
            } else {
                break
            }
        }

        return streak
    }
}
