import SwiftUI

/// Summary page reached from the dashboard "Rank changes to review" banner.
/// Lists every skill that currently has an unseen rank up/down with the
/// from→to transition and last week's stats. Tapping a row opens the skill,
/// which plays the full reveal animation and acknowledges the change.
struct RankChangesReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let stats: [StatDomain]
    let onOpenSkill: (StatDomain) -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if stats.isEmpty {
                ContentUnavailableView(
                    "No rank changes",
                    systemImage: "rosette",
                    description: Text("You're all caught up.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Open a skill to see its full reveal. Each card summarises last week's change.")
                            .font(.subheadline)
                            .foregroundStyle(TrainingTheme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        ForEach(stats) { stat in
                            rankChangeRow(stat)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Rank Changes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func rankChangeRow(_ stat: StatDomain) -> some View {
        if let pending = stat.pendingRankChange {
            let accent = TrainingArcConfig.color(for: stat.colorToken)
            let isUp = pending.direction == .up
            let tint = isUp ? TrainingTheme.positiveStrong : TrainingTheme.danger
            let resolution = TrainingStore.latestRankChangeResolution(for: stat)
            let unit = TrainingStore.weeklyUnitLabel(for: stat)

            Button {
                onOpenSkill(stat)
            } label: {
                SurfaceCard(accent: accent) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(stat.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(TrainingTheme.textPrimary)
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: isUp ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                Text(isUp ? "Rank Up" : "Rank Down")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                        }

                        HStack(spacing: 10) {
                            transitionPill(level: pending.fromLevel, title: pending.fromTitle, tint: TrainingTheme.textMuted)
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.black))
                                .foregroundStyle(tint)
                            transitionPill(level: pending.toLevel, title: pending.toTitle, tint: tint)
                        }

                        if let resolution {
                            Text("\(MetricFormatting.shortMetric(resolution.actualCompletedValue)) \(unit) logged · target \(MetricFormatting.shortMetric(resolution.expectedTotal)) \(unit)")
                                .font(.caption)
                                .foregroundStyle(TrainingTheme.textSecondary)
                                .monospacedDigit()
                            if !resolution.summaryText.isEmpty {
                                Text(resolution.summaryText)
                                    .font(.caption)
                                    .foregroundStyle(TrainingTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(spacing: 6) {
                            Text("Open skill to reveal")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(accent)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    private func transitionPill(level: Int, title: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("LV \(V4Style.displayNumber(level))")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(TrainingTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
        )
    }
}
