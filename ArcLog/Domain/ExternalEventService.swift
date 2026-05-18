import Foundation
import SwiftData

// External apps log into ArcLog via the deep-link URL scheme handled by
// DeepLinkRouter. Examples:
//   arclog://log?stat=curiosity&value=1&note=Topic
//   arclog://log?habit=habit.reading.session&value=30&note=Kindre
//   arclog://log?stat=reading&value=30&note=Book%20title&date=2026-05-12T18:30:00Z
// Query parameters: habit (Habit.systemKey) OR stat (StatKey.rawValue), value
// (Double, defaults to 1), note (URL-encoded text), date (ISO8601, defaults to
// .now). The matched Habit's measurementType determines how value is interpreted.

enum ExternalEventService {
    @MainActor
    static func ingest(_ event: ExternalLogEvent, context: ModelContext) throws {
        let habits = try TrainingStore.fetchHabits(context: context)
        let targetHabit: Habit? = {
            if let systemKey = event.habitSystemKey {
                return habits.first(where: { $0.systemKey == systemKey && $0.active })
            }

            if let statKey = event.statKey {
                return habits.first(where: { $0.statDomain?.key == statKey.rawValue && $0.active })
            }

            return nil
        }()

        guard let targetHabit else { return }

        _ = try TrainingStore.log(
            habit: targetHabit,
            value: event.value,
            date: event.date,
            note: event.note,
            source: .integration,
            context: context
        )
    }
}
