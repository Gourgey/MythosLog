import SwiftUI

enum DashboardChargeDots {
    static let maximumDots = 4

    static func filledDots(from progress: Double) -> Int {
        let clampedProgress = min(max(progress, 0), 1)
        if clampedProgress >= 1 { return maximumDots }
        return Int(floor(clampedProgress * Double(maximumDots)))
    }
}

struct StatCard: View {
    let stat: StatDomain
    let snapshot: SkillProgressSnapshot
    let trend: Double
    let habits: [Habit]
    let isFocusTarget: Bool
    let showLogFeedback: Bool
    let onOpenDetail: () -> Void
    let onQuickLogTap: (Habit, Double) -> Void

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var primaryHabit: Habit? {
        habits.first
    }

    private var extraHabitCount: Int {
        max(habits.count - 1, 0)
    }

    private var trendIcon: String {
        if trend > 0.15 { return "arrow.up.right" }
        if trend < -0.15 { return "arrow.down.right" }
        return "minus"
    }

    private var filledChargeDots: Int {
        DashboardChargeDots.filledDots(from: snapshot.rank.progressToNextLevel)
    }

    private var stateAccent: Color {
        if let pending = snapshot.pendingRankChange {
            return pending.direction == .up ? .orange : TrainingTheme.cold
        }

        switch snapshot.focusState {
        case .nearCharge:
            return TrainingTheme.positiveStrong
        case .aheadOfTarget:
            return accent
        case .behindTarget:
            return TrainingTheme.warning
        case .pendingRankChange:
            return .orange
        case .neutral:
            return accent
        }
    }

    private var stateLabel: String? {
        if let pending = snapshot.pendingRankChange {
            return pending.direction == .up ? "Rank Ready" : "Rank Drop"
        }

        switch snapshot.focusState {
        case .nearCharge:
            return "Near Charge"
        case .aheadOfTarget:
            return "Hot Streak"
        case .behindTarget:
            return "Fading"
        case .pendingRankChange:
            return "Rank Shift"
        case .neutral:
            return isFocusTarget ? "Focus Target" : nil
        }
    }

    private var footerTint: Color {
        switch snapshot.pacingStatus {
        case .ahead:
            return TrainingTheme.positiveStrong
        case .behind:
            return TrainingTheme.warning
        case .onPace:
            return accent
        }
    }

    private var trendTint: Color {
        if trend > 0.15 { return TrainingTheme.positiveStrong }
        if trend < -0.15 { return TrainingTheme.warning }
        return TrainingTheme.textMuted
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TrainingTheme.card,
                            .white.opacity(0.92),
                            TrainingTheme.elevatedCard
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(TrainingTheme.borderStrong.opacity(0.28), lineWidth: 1.15)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                        .padding(2)
                )
                .overlay {
                    if isFocusTarget || snapshot.pendingRankChange != nil {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(stateAccent.opacity(snapshot.pendingRankChange == nil ? 0.18 : 0.30), lineWidth: snapshot.pendingRankChange == nil ? 1 : 1.2)
                            .padding(3)
                    }
                }
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 14) {
                Button(action: onOpenDetail) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        mainContent
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                footer
            }
            .padding(20)

            if showLogFeedback {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.24), stateAccent.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(stateAccent.opacity(0.38), lineWidth: 1.4)
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .scaleEffect(showLogFeedback ? 1.015 : (isFocusTarget ? 1.005 : 1))
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: showLogFeedback)
        .animation(.easeInOut(duration: 0.22), value: isFocusTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(stat.name), \(snapshot.rank.title), level \(snapshot.rank.level) of \(snapshot.rank.maximumLevel), " +
            "\(snapshot.weeklyCounterLabel) \(snapshot.weeklyCounterValueLabel), " +
            "\(filledChargeDots) of \(DashboardChargeDots.maximumDots) charge dots filled, " +
            "\(snapshot.nextActionLabel)"
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: stat.iconName)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(accent.opacity(0.16), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.name)
                        .font(.system(.headline, design: .rounded).weight(.black))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text("Level \(snapshot.rank.level) / \(snapshot.rank.maximumLevel)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textMuted)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let stateLabel {
                    badge(text: stateLabel, tint: stateAccent)
                }

                Image(systemName: trendIcon)
                    .font(.caption.weight(.black))
                    .foregroundStyle(trendTint)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(TrainingTheme.actionSurface)
                    )
            }
        }
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.rank.title)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .lineLimit(2)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.weeklyCounterLabel + ":")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textMuted)
                    Text(snapshot.weeklyCounterValueLabel)
                        .font(.system(.title3, design: .rounded).weight(.black))
                        .foregroundStyle(TrainingTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    chargeMeter

                    HStack(spacing: 8) {
                        compactInfoPill(text: snapshot.pacingStatus.label, tint: footerTint)
                        compactInfoPill(text: snapshot.bankCountdownLabel, tint: TrainingTheme.cold)
                    }
                }
            }

            Spacer(minLength: 8)

            RankArtworkView(
                habitName: stat.name,
                level: snapshot.rank.level,
                title: snapshot.rank.title,
                image: snapshot.rank.image,
                accent: stateAccent,
                style: .dashboardCompact
            )
            .overlay(alignment: .bottom) {
                if isFocusTarget {
                    Text("NEXT WIN")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(TrainingTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.94))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(TrainingTheme.borderStrong.opacity(0.20), lineWidth: 0.9)
                        )
                        .offset(y: 8)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryHabit?.name ?? "Skill Actions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text(snapshot.nextActionLabel)
                        .font(.caption)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 10)

                if extraHabitCount > 0 {
                    Text(extraHabitCount == 1 ? "1 more action" : "\(extraHabitCount) more actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }

            if let primaryHabit {
                HabitQuickActionButtons(habit: primaryHabit, accent: accent) { value in
                    onQuickLogTap(primaryHabit, value)
                }
            } else {
                Button("Open Skill") {
                    onOpenDetail()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(TrainingTheme.borderStrong.opacity(0.14), lineWidth: 1)
        )
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.black))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.16), lineWidth: 0.8)
            )
    }

    private func jewelDot(filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(filled ? TrainingTheme.positiveStrong.opacity(0.18) : TrainingTheme.socketInner)
                .overlay(
                    Circle()
                        .stroke(filled ? TrainingTheme.positiveStrong.opacity(0.28) : TrainingTheme.socketOuter, lineWidth: filled ? 1 : 1.4)
                )

            Circle()
                .fill(filled ? TrainingTheme.positiveStrong : .clear)
                .frame(width: 10, height: 10)
                .shadow(color: filled ? TrainingTheme.positiveStrong.opacity(0.36) : .clear, radius: 5, x: 0, y: 0)
        }
        .frame(width: 18, height: 18)
    }

    private var chargeMeter: some View {
        HStack(spacing: 8) {
            ForEach(0..<DashboardChargeDots.maximumDots, id: \.self) { index in
                jewelDot(filled: index < filledChargeDots)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.white.opacity(0.86))
        )
        .overlay(
            Capsule()
                .strokeBorder(TrainingTheme.borderStrong.opacity(0.14), lineWidth: 1)
        )
    }

    private func compactInfoPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(TrainingTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.white.opacity(0.90))
            )
            .overlay(
                Capsule()
                    .strokeBorder(TrainingTheme.borderStrong.opacity(0.12), lineWidth: 0.8)
            )
    }
}

struct DashboardGridTile: View {
    let stat: StatDomain
    let snapshot: SkillProgressSnapshot
    let onOpenDetail: () -> Void

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var filledChargeDots: Int {
        DashboardChargeDots.filledDots(from: snapshot.rank.progressToNextLevel)
    }

    private var stateAccent: Color {
        if let pending = snapshot.pendingRankChange {
            return pending.direction == .up ? .orange : TrainingTheme.cold
        }
        return accent
    }

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: stat.iconName)
                        .font(.caption.weight(.black))
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(accent.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(accent.opacity(0.16), lineWidth: 0.9)
                        )
                    Spacer()
                    lvlChip
                }

                RankArtworkView(
                    habitName: stat.name,
                    level: snapshot.rank.level,
                    title: snapshot.rank.title,
                    image: snapshot.rank.image,
                    accent: stateAccent,
                    style: .dashboardTile
                )

                Text(stat.name)
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundStyle(TrainingTheme.textPrimary)
                    .lineLimit(1)

                Text(snapshot.rank.title.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 6) {
                    ForEach(0..<DashboardChargeDots.maximumDots, id: \.self) { index in
                        jewelTileDot(filled: index < filledChargeDots)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.88))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(TrainingTheme.borderStrong.opacity(0.12), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                TrainingTheme.card,
                                .white.opacity(0.92),
                                TrainingTheme.elevatedCard
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(TrainingTheme.borderStrong.opacity(0.24), lineWidth: 1.1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                    .padding(2)
            )
            .overlay {
                if snapshot.pendingRankChange != nil {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(stateAccent.opacity(0.24), lineWidth: 1.1)
                        .padding(3)
                }
            }
            .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stat.name), level \(snapshot.rank.level), \(filledChargeDots) charge dots filled")
    }

    private var lvlChip: some View {
        Text("Lvl \(snapshot.rank.level)")
            .font(.caption2.weight(.black))
            .foregroundStyle(accent.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.white.opacity(0.92))
            )
            .overlay(
                Capsule()
                    .strokeBorder(accent.opacity(0.16), lineWidth: 0.8)
            )
    }

    private func jewelTileDot(filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(filled ? TrainingTheme.positiveStrong.opacity(0.16) : TrainingTheme.socketInner)
                .overlay(
                    Circle()
                        .stroke(
                            filled ? TrainingTheme.positiveStrong.opacity(0.32) : TrainingTheme.socketOuter.opacity(0.70),
                            lineWidth: filled ? 1.1 : 1
                        )
                )

            Circle()
                .fill(filled ? TrainingTheme.positiveStrong : .clear)
                .frame(width: 5, height: 5)
                .shadow(color: filled ? TrainingTheme.positiveStrong.opacity(0.36) : .clear, radius: 4, x: 0, y: 0)
        }
        .frame(width: 11, height: 11)
    }
}
