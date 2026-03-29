import SwiftUI

struct SurfaceCard<Content: View>: View {
    var accent: Color = TrainingTheme.backgroundTertiary
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [TrainingTheme.card, accent.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(TrainingTheme.border, lineWidth: 1)
        )
        .shadow(color: TrainingTheme.shadow, radius: 18, x: 0, y: 10)
    }
}
