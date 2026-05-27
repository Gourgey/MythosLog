import WidgetKit
import SwiftUI

@main
struct MythosLogWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrainingArcStatusWidget()
        TrainingArcMotivationWidget()
        TrainTodayWidget()
        QuickLogWidget()
        WeakestStatWidget()
        GoalAtRiskWidget()
        ReviewReadyWidget()
    }
}
