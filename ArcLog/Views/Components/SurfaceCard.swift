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
                        colors: [TrainingTheme.card, TrainingTheme.elevatedCard, accent.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(accent.opacity(0.16).opacity(0.7), lineWidth: 1.1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(TrainingTheme.borderStrong.opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: TrainingTheme.shadowStrong, radius: 16, x: 0, y: 10)
    }
}
