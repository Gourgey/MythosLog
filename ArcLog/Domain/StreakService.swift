import Foundation

enum StreakCadence: Sendable {
    case daily
    case weekly(Bool)
}

enum StreakService {
    static func summary(for dates: [Date], cadence: StreakCadence, referenceDate: Date = .now) -> HabitStreakSummary {
        let normalized = normalizedUnits(from: dates, cadence: cadence)
        guard !normalized.isEmpty else {
            return HabitStreakSummary(current: 0, longest: 0, lastLoggedDate: nil)
        }

        let sorted = normalized.sorted()
        var longest = 1
        var currentRun = 1

        for index in 1..<sorted.count {
            if isNextUnit(after: sorted[index - 1], next: sorted[index], cadence: cadence) {
                currentRun += 1
                longest = max(longest, currentRun)
            } else {
                currentRun = 1
            }
        }

        let latest = sorted.last ?? referenceDate
        let current = currentStreakLength(from: sorted, cadence: cadence, referenceDate: referenceDate)
        return HabitStreakSummary(current: current, longest: longest, lastLoggedDate: latest)
    }

    private static func normalizedUnits(from dates: [Date], cadence: StreakCadence) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
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

    private static func isNextUnit(after current: Date, next: Date, cadence: StreakCadence) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        switch cadence {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: current) == next
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: current) == next
        }
    }

    private static func currentStreakLength(from dates: [Date], cadence: StreakCadence, referenceDate: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
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
            if isNextUnit(after: candidate, next: cursor, cadence: cadence) {
                streak += 1
                cursor = candidate
            } else {
                break
            }
        }

        return streak
    }
}
