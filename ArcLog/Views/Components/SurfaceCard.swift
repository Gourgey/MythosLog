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
                        colors: [TrainingTheme.card, TrainingTheme.elevatedCard.opacity(0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(accent.opacity(0.12), lineWidth: 0.9)
        )
        .shadow(color: TrainingTheme.shadow.opacity(0.7), radius: 9, x: 0, y: 5)
    }
}
