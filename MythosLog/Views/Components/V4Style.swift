import SwiftUI

/// V4 visual language helpers. Used to apply the "premium / progression-led"
/// styling pass on top of the existing app — never changes data or layout
/// behavior, only adds a consistent set of typographic and decorative pieces
/// that the dashboard, skill detail, roster, review, log sheet, and more page
/// can share.
enum V4Style {
    /// Renders an integer as a plain Arabic number for UI display. Replaces the
    /// previous Roman-numeral styling so levels, counts, and tallies read as
    /// standard numbers throughout the app.
    static func displayNumber(_ value: Int) -> String {
        String(value)
    }
}

/// Small uppercase kicker with a leading mark and rule, e.g. "✦ — DASHBOARD".
/// Used as a page eyebrow on V4-styled views.
struct V4PageKicker: View {
    let title: String
    var symbol: String = "sparkle"
    var accent: Color = TrainingTheme.textPrimary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(accent.opacity(0.75))
            Rectangle()
                .fill(accent.opacity(0.35))
                .frame(width: 18, height: 1)
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(2.4)
                .foregroundStyle(accent.opacity(0.78))
        }
    }
}

/// Numbered section header used inside cards / between sections, e.g.
/// "VII — THE SEVEN SKILLS". Uses a serif Roman numeral up front.
struct V4SectionHeader: View {
    let number: Int
    let title: String
    var accent: Color = TrainingTheme.textMuted

    var body: some View {
        HStack(spacing: 10) {
            Text(V4Style.displayNumber(number))
                .font(.system(.title3, design: .serif).weight(.regular))
                .italic()
                .foregroundStyle(accent.opacity(0.55))
            Rectangle()
                .fill(accent.opacity(0.35))
                .frame(width: 18, height: 1)
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(2.0)
                .foregroundStyle(accent.opacity(0.78))
        }
    }
}

/// Capsule level badge used next to the big serif rank title, e.g. "LV III".
struct V4LevelBadge: View {
    let level: Int
    var tint: Color = TrainingTheme.textPrimary
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Text("LV")
                .font(.system(size: compact ? 9 : 10, weight: .black))
                .tracking(0.8)
                .foregroundStyle(tint.opacity(0.85))
            Text(V4Style.displayNumber(level))
                .font(.system(size: compact ? 12 : 14, design: .serif).weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
        )
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
        )
    }
}

/// Soft status pill used by Weekly Standing / Pace indicators. Dot color
/// follows the tint, background is a faded version of the tint.
struct V4StatusPill: View {
    let text: String
    var tint: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
    }
}

/// A column-of-stat tile used in the Goals strip and the More page header.
/// Renders the number in a serif face (Roman or Arabic depending on the
/// caller) over a small caption label.
struct V4StatTile: View {
    let value: String
    let label: String
    var tint: Color = TrainingTheme.textPrimary

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.title, design: .serif).weight(.regular))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// V4 card surface: cream background, fine inner border, very soft shadow.
struct V4Card<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 18
    var accent: Color = TrainingTheme.borderStrong
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.985, green: 0.975, blue: 0.955))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius - 4, style: .continuous)
                .strokeBorder(accent.opacity(0.10), lineWidth: 0.6)
                .padding(4)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

/// Diamond marker used for charge meters and day-of-week summaries in V4.
struct V4Diamond: View {
    var size: CGFloat = 10
    var filled: Bool = false
    var tint: Color = TrainingTheme.textMuted

    var body: some View {
        Rectangle()
            .fill(filled ? tint : Color.clear)
            .overlay(
                Rectangle()
                    .strokeBorder(tint.opacity(filled ? 0 : 0.55), lineWidth: 0.9)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(45))
    }
}

/// Small serif title text used for big rank/skill headlines, e.g. "Strength",
/// "Adept", "Centred". Keeps line breaking honest.
struct V4SerifTitle: View {
    let text: String
    var size: CGFloat = 34

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .regular, design: .serif))
            .foregroundStyle(TrainingTheme.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}
