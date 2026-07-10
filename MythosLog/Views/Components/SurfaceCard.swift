import SwiftUI

/// Default card surface across the app. Matches the V4 design language —
/// cream background, fine outer border, faint inset border, soft shadow.
/// Kept as a thin wrapper over `V4Card` so the rest of the app picks up the
/// style without changing call sites.
struct SurfaceCard<Content: View>: View {
    var accent: Color = TrainingTheme.backgroundTertiary
    @ViewBuilder var content: Content

    var body: some View {
        V4Card(accent: accent) {
            content
        }
    }
}
