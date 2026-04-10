import SwiftUI

enum RankArtworkStyle: Sendable {
    case hero
    case compact
    case tile
    case dashboardCompact
    case dashboardTile
}

struct RankArtworkView: View {
    let habitName: String
    let level: Int
    let title: String
    let image: RankImageReference?
    let accent: Color
    var style: RankArtworkStyle = .hero

    var body: some View {
        switch style {
        case .hero:
            heroArtwork
        case .compact:
            compactArtwork
        case .tile:
            tileArtwork
        case .dashboardCompact:
            dashboardCompactArtwork
        case .dashboardTile:
            dashboardTileArtwork
        }
    }

    private var heroArtwork: some View {
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

    private var compactArtwork: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.22),
                            TrainingTheme.backgroundSecondary,
                            TrainingTheme.background
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                )

            compactBackgroundOrnament

            if let image {
                configuredImage(for: image)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                compactPlaceholderArtwork
            }

            pill(text: "LV \(level)")
                .padding(10)
        }
        .frame(width: 84, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: accent.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private var tileArtwork: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.18),
                            TrainingTheme.backgroundSecondary,
                            TrainingTheme.card
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(accent.opacity(0.16), lineWidth: 1)
                )

            compactBackgroundOrnament

            if let image {
                configuredImage(for: image)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                tilePlaceholderArtwork
            }

            pill(text: "LV \(level)")
                .padding(10)
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: accent.opacity(0.10), radius: 10, x: 0, y: 6)
    }

    private var dashboardCompactArtwork: some View {
        ZStack(alignment: .topLeading) {
            dashboardArtworkShell(cornerRadius: 24)

            if let image {
                dashboardCharacterImage(for: image, scale: 1.16)
            } else {
                dashboardCompactPlaceholderArtwork
            }

            dashboardLevelPill
                .padding(10)
        }
        .frame(width: 104, height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: accent.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    private var dashboardTileArtwork: some View {
        ZStack {
            dashboardArtworkShell(cornerRadius: 26)

            if let image {
                dashboardCharacterImage(for: image, scale: 1.28)
            } else {
                dashboardTilePlaceholderArtwork
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: accent.opacity(0.24), radius: 16, x: 0, y: 8)
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

    private var compactBackgroundOrnament: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 72, height: 72)
                .blur(radius: 4)
                .offset(x: 24, y: -6)

            Circle()
                .stroke(accent.opacity(0.12), lineWidth: 1)
                .frame(width: 52, height: 52)
                .offset(x: 20, y: -2)
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

    private var compactPlaceholderArtwork: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.92), .white.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Placeholder")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(TrainingTheme.background.opacity(0.56))
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.top, 12)
    }

    private var tilePlaceholderArtwork: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.94), .white.opacity(0.74)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text(habitName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dashboardCompactPlaceholderArtwork: some View {
        dashboardGlyphPlaceholder(crestSize: 50, bottomLabel: title.uppercased())
            .padding(.top, 14)
    }

    private var dashboardTilePlaceholderArtwork: some View {
        dashboardGlyphPlaceholder(crestSize: 78, bottomLabel: habitName.uppercased())
            .padding(.top, 14)
    }

    @ViewBuilder
    private func configuredImage(for reference: RankImageReference) -> some View {
        switch reference {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func dashboardCharacterImage(for reference: RankImageReference, scale: CGFloat) -> some View {
        switch reference {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .clipped()
        }
    }

    private func dashboardArtworkShell(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        TrainingTheme.card,
                        .white.opacity(0.94),
                        TrainingTheme.elevatedCard.opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(TrainingTheme.borderStrong.opacity(0.24), lineWidth: 1.2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                    .padding(2)
            )
    }

    private func dashboardGlyphPlaceholder(crestSize: CGFloat, bottomLabel: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: crestSize * 0.26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [TrainingTheme.backgroundSecondary, .white.opacity(0.94)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: crestSize * 0.26, style: .continuous)
                            .strokeBorder(TrainingTheme.borderStrong.opacity(0.20), lineWidth: 1)
                    )

                Text(habitInitial)
                    .font(.system(size: crestSize * 0.42, design: .rounded).weight(.black))
                    .foregroundStyle(accent.opacity(0.88))
            }
            .frame(width: crestSize, height: crestSize)
            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 3)

            Text(bottomLabel)
                .font(.caption2.weight(.black))
                .foregroundStyle(TrainingTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    private var dashboardLevelPill: some View {
        Text("LV \(level)")
            .font(.caption2.weight(.black))
            .foregroundStyle(accent.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.white.opacity(0.92))
            )
            .overlay(
                Capsule()
                    .strokeBorder(accent.opacity(0.18), lineWidth: 0.9)
            )
    }
    private var habitInitial: String {
        habitName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() } ?? "?"
    }
}
