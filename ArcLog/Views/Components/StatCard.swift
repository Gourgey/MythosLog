import SwiftUI

struct StatCard: View {
    let stat: StatDomain
    let snapshot: SkillProgressSnapshot
    let trend: Double

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var trendIcon: String {
        if trend > 0.15 { return "arrow.up.right" }
        if trend < -0.15 { return "arrow.down.right" }
        return "minus"
    }

    var body: some View {
        SurfaceCard(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: stat.iconName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(width: 26)
                        Text(stat.name)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(TrainingTheme.textPrimary)
                        Spacer()
                        Image(systemName: trendIcon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(trend >= 0 ? TrainingTheme.positive : TrainingTheme.warning)
                    }

                    Text("Level \(snapshot.rank.level) / \(snapshot.rank.maximumLevel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textSecondary)

                    Text(snapshot.rank.title)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(TrainingTheme.textPrimary)

                    Text("\(MetricFormatting.shortMetric(snapshot.currentWeekActual)) / \(snapshot.baseline)")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(TrainingTheme.textPrimary)

                    Text("This week")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                HStack {
                    progressPill(
                        title: snapshot.charge.label,
                        value: "\(snapshot.charge.current)/\(snapshot.charge.maximum)",
                        tint: accent
                    )
                    progressPill(
                        title: "Next Rank",
                        value: snapshot.rank.isAtMaximumRank
                            ? "Max"
                            : "\(snapshot.rank.progressUnits)/\(snapshot.rank.progressRequired)",
                        tint: TrainingTheme.backgroundTertiary
                    )
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(TrainingTheme.backgroundSecondary.opacity(0.65))
                        Capsule()
                            .fill(accent.gradient)
                            .frame(width: max(10, proxy.size.width * min(max(snapshot.rank.progressToNextLevel, 0), 1)))
                    }
                }
                .frame(height: 10)

                Text(snapshot.rank.isAtMaximumRank
                     ? "Maximum rank reached"
                     : "Rank progress: \(Int(min(max(snapshot.rank.progressToNextLevel, 0), 1) * 100))%")
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)

                if snapshot.earnedRankProgressThisWeek > 0 {
                    Text("+\(snapshot.earnedRankProgressThisWeek) rank progress banked this week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.name), \(snapshot.rank.title), level \(snapshot.rank.level) of \(snapshot.rank.maximumLevel), charge \(snapshot.charge.current) of \(snapshot.charge.maximum)")
    }

    private func progressPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrainingTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}
