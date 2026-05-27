import AppIntents
import WidgetKit

/// Interactive-widget intent. Records a quick log to the app-group queue and asks
/// WidgetKit to refresh so the tap reflects immediately. The main app turns the
/// queued amount into a real session the next time it runs (see
/// `TrainingStore.drainQuickLogQueue`). No SwiftData runs in the widget process.
struct QuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Log"
    static var description = IntentDescription("Log progress to a habit from the widget.")

    @Parameter(title: "Habit ID")
    var habitID: String

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Habit")
    var habitName: String

    init() {}

    init(habitID: String, amount: Double, habitName: String) {
        self.habitID = habitID
        self.amount = amount
        self.habitName = habitName
    }

    func perform() async throws -> some IntentResult {
        QuickLogQueue.enqueue(habitID: habitID, amount: amount)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
