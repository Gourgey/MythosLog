import SwiftUI

struct RankArtworkView: View {
    let habitName: String
    let level: Int
    let title: String
    let image: RankImageReference?
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.28),
                            TrainingTheme.backgroundSecondary,
                            TrainingTheme.background
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1.2)
                )

            backgroundOrnament

            if let image {
                configuredImage(for: image)
            } else {
                placeholderArtwork
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    pill(text: "LEVEL \(level)")
                    pill(text: habitName.uppercased())
                }

                Text(title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .lineLimit(2)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: accent.opacity(0.14), radius: 20, x: 0, y: 10)
    }

    private var backgroundOrnament: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 210, height: 210)
                .blur(radius: 6)
                .offset(x: 92, y: -54)

            Circle()
                .stroke(accent.opacity(0.14), lineWidth: 1)
                .frame(width: 170, height: 170)
                .offset(x: 70, y: -32)
        }
    }

    private var placeholderArtwork: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.95), .white.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Placeholder Artwork")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(TrainingTheme.background.opacity(0.58))
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 26)
    }

    @ViewBuilder
    private func configuredImage(for reference: RankImageReference) -> some View {
        switch reference {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func pill(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(TrainingTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(TrainingTheme.background.opacity(0.58))
            )
    }
}
