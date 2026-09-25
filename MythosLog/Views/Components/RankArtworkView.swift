import SwiftUI

/// Geometry of the commissioned rank PNGs, measured off the shipped assets
/// rather than guessed: all 133 files are 672x1008 (2:3) and the drawn art
/// starts 13% down the canvas and ends at 98% of it, so 15% of every file is
/// transparent padding — 124 of the 133 match those bounds exactly and the
/// nine that don't (four Focus, two Intellect, one Creativity plus their
/// locked twins) start *lower*, so treating 13%/98% as the content band never
/// crops anything. The hero treatment sizes the canvas from that band instead
/// of the file, which is what lets the character reach the edges of its row.
enum RankArtworkGeometry {
    static let canvasAspectRatio: CGFloat = 672.0 / 1008.0
    static let contentTop: CGFloat = 0.13
    static let contentBottom: CGFloat = 0.98
    static let contentHeightFraction = contentBottom - contentTop

    /// Visible height of the hero. The ceiling here is the skill page, not the
    /// art: measured on a 402pt phone, 450 is the tallest the row can be while
    /// the baseline/pace figures under it still clear the sticky Log button
    /// with the longest rank titles (the ones that wrap to two lines). At this
    /// height the canvas behind the art is ~370pt wide, so on that phone the
    /// character is already spanning the full content column.
    static let heroHeight: CGFloat = 450

    /// Height the full PNG must be drawn at for its *content band* to stand
    /// `heroHeight` tall.
    static var heroCanvasHeight: CGFloat { heroHeight / contentHeightFraction }

    /// Transparent strip left below the art once the canvas is that tall, so
    /// the character's feet can be pinned to the bottom of the row.
    static var heroBottomPadding: CGFloat { heroCanvasHeight * (1 - contentBottom) }
}

enum RankArtworkStyle: Sendable {
    case hero
    case compact
    case tile
    case dashboardCompact
    case dashboardTile
    case dashboardBare
}

enum ArtworkPreferences {
    static let dashboardIconsKey = "appearance.dashboardIcons"
    static let appIconsKey = "appearance.appIcons"
}

private struct DashboardArtworkContextKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDashboardArtwork: Bool {
        get { self[DashboardArtworkContextKey.self] }
        set { self[DashboardArtworkContextKey.self] = newValue }
    }
}

struct RankArtworkView: View {
    @AppStorage(ArtworkPreferences.dashboardIconsKey) private var dashboardIcons = false
    @AppStorage(ArtworkPreferences.appIconsKey) private var appIcons = false
    @Environment(\.isDashboardArtwork) private var isDashboardArtwork
    let habitName: String
    let level: Int
    let title: String
    let image: RankImageReference?
    let accent: Color
    var style: RankArtworkStyle = .hero

    var body: some View {
        if appIcons || (isDashboardArtwork && dashboardIcons) {
            iconArtwork
                .accessibilityLabel("\(habitName), \(title), level \(level)")
        } else {
            artwork
        }
    }

    @ViewBuilder
    private var iconArtwork: some View {
        switch style {
        case .hero:
            skillIcon.frame(height: 200)
        case .compact:
            skillIcon.frame(width: 84, height: 112)
        case .tile:
            skillIcon.frame(width: 92, height: 92)
        case .dashboardCompact:
            skillIcon.frame(width: 104, height: 136)
        case .dashboardTile:
            skillIcon.frame(height: 220)
        case .dashboardBare:
            skillIcon
        }
    }

    private var skillIcon: some View {
        GeometryReader { proxy in
            Image(systemName: statFallbackIcon)
                .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.40, weight: .medium))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var artwork: some View {
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
        case .dashboardBare:
            dashboardBareArtwork
        }
    }

    // `scaledToFit` sizes the art by whichever axis runs out first, and with a
    // 2:3 canvas on a phone that is always the height — so the figure sat in a
    // narrow column and paid for 15% of transparent padding on top of that,
    // leaving wide dead bands either side of it. Drawing the canvas tall
    // enough that its *content band* fills the row's height (and clipping the
    // padding that then hangs off the top) makes the art width-limited
    // instead, which is the largest the character can be drawn whole.
    private var heroArtwork: some View {
        ZStack(alignment: .bottom) {
            if let image {
                heroCharacterImage(for: image)
            } else {
                placeholderArtwork
            }
        }
        .frame(maxWidth: .infinity)
        // `.bottom`, emphatically not the default `.center`: the canvas inside
        // this row is deliberately taller than the row, and centring it would
        // hang half the overflow below the row for `.clipped()` to cut the
        // character's feet off.
        .frame(height: RankArtworkGeometry.heroHeight, alignment: .bottom)
        .clipped()
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
                dashboardCharacterImage(for: image, horizontalPadding: 8, topPadding: 8)
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
                dashboardCharacterImage(for: image, horizontalPadding: 8, topPadding: 10)
            } else {
                dashboardTilePlaceholderArtwork
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: accent.opacity(0.24), radius: 16, x: 0, y: 8)
    }

    // The commissioned PNGs share a transparent top margin of roughly 15%.
    // Compensate for it in the character-first dashboard treatment so the
    // visible art, rather than its invisible canvas, fills the ring. Keeping
    // the scale bottom-anchored lets the character break the top edge by a
    // few points without drifting into the progress text below. This style is
    // intentionally not clipped: the slight overlap makes the figure read as
    // the foreground while the fallback crest remains naturally contained.
    private var dashboardBareArtwork: some View {
        ZStack {
            if let image {
                dashboardCharacterImage(for: image, horizontalPadding: 0, topPadding: 0)
                    .scaleEffect(1.2, anchor: .bottom)
            } else {
                barePlaceholderArtwork
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // Skills without commissioned artwork fall back to a crest built from
    // the skill's own icon and its current rank title — never a literal
    // "Placeholder" label, which previously shipped verbatim on the rank-
    // change ceremony (the single most emotionally loaded screen in the
    // app) and on the skill detail hero.
    private var placeholderArtwork: some View {
        VStack(spacing: 14) {
            Image(systemName: statFallbackIcon)
                .font(.system(size: 88, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.95), .white.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }

    private var compactPlaceholderArtwork: some View {
        VStack(spacing: 10) {
            Image(systemName: statFallbackIcon)
                .font(.system(size: 30, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.92), .white.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

    private var barePlaceholderArtwork: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [TrainingTheme.backgroundSecondary.opacity(0.94), .white.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1.3)
                )
                .shadow(color: accent.opacity(0.08), radius: 7, x: 0, y: 3)

            VStack(spacing: 4) {
                Image(systemName: statFallbackIcon)
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent.opacity(0.72))

                Text(habitInitial)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(TrainingTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(8)
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
    private func heroCharacterImage(for reference: RankImageReference) -> some View {
        switch reference {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: RankArtworkGeometry.heroCanvasHeight, alignment: .bottom)
                // Slides the canvas down until the art's baseline — not the
                // transparent strip below it — rests on the bottom of the row.
                .offset(y: RankArtworkGeometry.heroBottomPadding)
        }
    }

    @ViewBuilder
    private func dashboardCharacterImage(for reference: RankImageReference, horizontalPadding: CGFloat, topPadding: CGFloat) -> some View {
        switch reference {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
        }
    }

    private func dashboardArtworkShell(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        TrainingTheme.card,
                        .white.opacity(0.94),
                        TrainingTheme.elevatedCard.opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(TrainingTheme.borderStrong.opacity(0.18), lineWidth: 0.9)
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

                Image(systemName: statFallbackIcon)
                    .font(.system(size: crestSize * 0.4, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
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

    private var statFallbackIcon: String {
        if let definition = TrainingArcConfig.habitDefinitions.first(where: {
            $0.displayName.localizedCaseInsensitiveCompare(habitName) == .orderedSame
        }) {
            return definition.iconName
        }
        switch habitName.lowercased() {
        case "strength":
            return "figure.strengthtraining.traditional"
        case "intellect":
            return "book.closed.fill"
        case "creativity":
            return "paintbrush.pointed.fill"
        case "emotional":
            return "heart.text.square.fill"
        case "focus":
            return "scope"
        case "curiosity":
            return "sparkles.rectangle.stack.fill"
        case "cardio":
            return "figure.run"
        case "cooking":
            return "fork.knife"
        case "reading":
            return "book.pages.fill"
        default:
            return "person.crop.circle.fill"
        }
    }
}
