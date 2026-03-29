import Foundation
import SwiftData

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
