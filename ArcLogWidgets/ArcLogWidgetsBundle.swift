import WidgetKit
import SwiftUI

@main
struct ArcLogWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrainingArcStatusWidget()
        TrainingArcMotivationWidget()
        TrainTodayWidget()
    }
}
