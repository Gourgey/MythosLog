import SwiftUI

// Rendering vocabulary for the charge meter. The underlying game-balance
// numbers live in ChargeMath (domain layer); this only adds presentation.
enum DashboardChargeDots {
    static let slotsPerSide = ChargeMath.slotsPerSide
    static let totalDots = ChargeMath.totalSlots

    static func clampedCharge(_ charge: Int) -> Int {
        ChargeMath.clampedCharge(charge)
    }

    static func positiveDots(from charge: Int) -> Int {
        max(0, min(clampedCharge(charge), slotsPerSide))
    }

    static func negativeDots(from charge: Int) -> Int {
        max(0, min(-clampedCharge(charge), slotsPerSide))
    }

    static func summaryLabel(for charge: Int) -> String {
        let clamped = clampedCharge(charge)
        switch clamped {
        case let value where value > 0:
            return "Charge +\(value)"
        case let value where value < 0:
            return "Charge \(value)"
        default:
            return "Charge 0"
        }
    }
}

struct SignedChargeMeter: View {
    let charge: Int
    var pendingProgress: Double = 0
    var socketSize: CGFloat = 14
    var spacing: CGFloat = 8

    private var positiveDots: Int {
        DashboardChargeDots.positiveDots(from: charge)
    }

    private var negativeDots: Int {
        DashboardChargeDots.negativeDots(from: charge)
    }

    private var clampedPending: Double {
        min(max(pendingProgress, 0), 1)
    }

    private var pendingPositiveIndex: Int? {
        guard charge >= 0, positiveDots < DashboardChargeDots.slotsPerSide, clampedPending > 0.001 else { return nil }
        return positiveDots
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<DashboardChargeDots.slotsPerSide, id: \.self) { index in
                chargeSocket(
                    filled: negativeDots > (DashboardChargeDots.slotsPerSide - index - 1),
                    pendingFraction: 0,
                    tint: TrainingTheme.warning
                )
            }

            Capsule()
                .fill(TrainingTheme.borderStrong.opacity(0.30))
                .frame(width: max(socketSize * 0.3, 4), height: socketSize * 1.3)
                .padding(.horizontal, 2)

            ForEach(0..<DashboardChargeDots.slotsPerSide, id: \.self) { index in
                chargeSocket(
                    filled: positiveDots > index,
                    pendingFraction: pendingPositiveIndex == index ? clampedPending : 0,
                    tint: TrainingTheme.positiveStrong
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DashboardChargeDots.summaryLabel(for: charge))
    }

    private func chargeSocket(filled: Bool, pendingFraction: Double, tint: Color) -> some View {
        let isPending = !filled && pendingFraction > 0
        return ZStack {
            Circle()
                .fill(filled ? tint.opacity(0.18) : TrainingTheme.socketInner)
                .overlay(
                    Circle()
                        .stroke(
                            filled ? tint.opacity(0.34) : (isPending ? tint.opacity(0.55) : TrainingTheme.socketOuter.opacity(0.72)),
                            lineWidth: filled ? 1.1 : (isPending ? 1.3 : 1)
                        )
                )

            if isPending {
                Circle()
                    .fill(tint.opacity(0.75))
                    .frame(width: socketSize * 0.42, height: socketSize * 0.42)
                    .scaleEffect(pendingFraction)
                    .shadow(color: tint.opacity(0.28), radius: 3, x: 0, y: 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: pendingFraction)
            }

            Circle()
                .fill(filled ? tint : .clear)
                .frame(width: socketSize * 0.42, height: socketSize * 0.42)
                .shadow(color: filled ? tint.opacity(0.32) : .clear, radius: 4, x: 0, y: 0)
        }
        .frame(width: socketSize, height: socketSize)
    }
}

struct DirectionalChargeMeter: View {
    let charge: Int
    var socketSize: CGFloat = 10
    var spacing: CGFloat = 5

    private var clampedCharge: Int {
        DashboardChargeDots.clampedCharge(charge)
    }

    private var filledSlots: Int {
        abs(clampedCharge)
    }

    private var tint: Color {
        clampedCharge < 0 ? TrainingTheme.danger : TrainingTheme.positiveStrong
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<DashboardChargeDots.slotsPerSide, id: \.self) { index in
                chargeSocket(filled: isFilled(index))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DashboardChargeDots.summaryLabel(for: charge))
    }

    private func isFilled(_ index: Int) -> Bool {
        if clampedCharge < 0 {
            return index >= DashboardChargeDots.slotsPerSide - filledSlots
        }

        return index < filledSlots
    }

    private func chargeSocket(filled: Bool) -> some View {
        Circle()
            .fill(filled ? tint : TrainingTheme.socketInner.opacity(0.58))
            .overlay(
                Circle()
                    .stroke(filled ? tint.opacity(0.45) : TrainingTheme.socketOuter.opacity(0.20), lineWidth: 0.8)
            )
            .shadow(color: filled ? tint.opacity(0.22) : .clear, radius: 3, x: 0, y: 0)
            .frame(width: socketSize, height: socketSize)
    }
}

struct StatCard: View {
    let stat: StatDomain
    let snapshot: SkillProgressSnapshot
    let trend: Double
    let habits: [Habit]
    let isFocusTarget: Bool
    let showLogFeedback: Bool
    let needsAttention: Bool
    let hasUnmatchedImports: Bool
    let onOpenDetail: () -> Void
    let onQuickLogTap: (Habit, Double) -> Void
    let onShowUnmatched: () -> Void

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

    private var indicatorActive: Bool {
        snapshot.rankChangeIndicatorVisible
    }

    private var stateAccent: Color {
        if indicatorActive, let pending = snapshot.pendingRankChange {
            return pending.direction == .up ? TrainingTheme.positiveStrong : TrainingTheme.danger
        }

        switch snapshot.focusState {
        case .nearCharge:
            return TrainingTheme.positiveStrong
        case .aheadOfTarget:
            return accent
        case .behindTarget:
            return TrainingTheme.warning
        case .pendingRankChange:
            return accent
        case .neutral:
            return accent
        }
    }

    private var stateLabel: String? {
        if indicatorActive, let pending = snapshot.pendingRankChange {
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
            return nil
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
                .overlay {
                    if isFocusTarget || indicatorActive {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(stateAccent.opacity(indicatorActive ? 0.36 : 0.18), lineWidth: indicatorActive ? 1.4 : 1)
                            .padding(3)
                    }
                }
                .shadow(color: indicatorActive ? stateAccent.opacity(0.32) : Color.black.opacity(0.06), radius: indicatorActive ? 12 : 8, x: 0, y: 4)

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
        .overlay(alignment: .topTrailing) {
            if indicatorActive, let direction = snapshot.pendingRankChange?.direction {
                Image(systemName: direction == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(stateAccent)
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.85), lineWidth: 1.6)
                    )
                    .shadow(color: stateAccent.opacity(0.5), radius: 8, x: 0, y: 0)
                    .padding(10)
                    .accessibilityLabel(direction == .up ? "Rank up available" : "Rank drop pending")
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if hasUnmatchedImports {
                UnmatchedBadge(accent: accent, action: onShowUnmatched)
                    .padding(12)
            } else if needsAttention {
                AttentionDot(accent: accent)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(showLogFeedback ? 1.015 : (isFocusTarget ? 1.005 : 1))
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: showLogFeedback)
        .animation(.easeInOut(duration: 0.22), value: isFocusTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detailedAccessibilityLabel)
    }

    private var detailedAccessibilityLabel: String {
        var base = "\(stat.name), \(snapshot.rank.title), level \(snapshot.rank.level) of \(snapshot.rank.maximumLevel), " +
            "\(snapshot.weeklyCounterLabel) \(snapshot.weeklyCounterValueLabel), " +
            "\(DashboardChargeDots.summaryLabel(for: snapshot.charge.current)), " +
            "\(snapshot.nextActionLabel)"
        if hasUnmatchedImports { base += ", unmatched workouts to review" }
        else if needsAttention { base += ", needs attention this week" }
        return base
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

    private var chargeMeter: some View {
        SignedChargeMeter(charge: snapshot.charge.current, pendingProgress: snapshot.weeklyTargetProgress, socketSize: 16, spacing: 7)
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
    let preview: DashboardCardPreview
    let quickLogTitle: String
    let isReordering: Bool
    let needsAttention: Bool
    let hasUnmatchedImports: Bool
    let onOpenDetail: () -> Void
    let onQuickLog: () -> Void
    let onShowUnmatched: () -> Void

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var stateAccent: Color {
        if snapshot.rankChangeIndicatorVisible, let pending = snapshot.pendingRankChange {
            return pending.direction == .up ? TrainingTheme.positiveStrong : TrainingTheme.danger
        }
        return accent
    }

    @ViewBuilder
    var body: some View {
        if isReordering {
            tileBody
        } else {
            tileBody
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .onEnded { _ in onQuickLog() }
                        .exclusively(before: TapGesture().onEnded { onOpenDetail() })
                )
        }
    }

    private var tileBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(stat.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: stat.iconName)
                    .font(.caption.weight(.black))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(accent.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                    )

                Spacer(minLength: 8)

                levelBadge
            }

            Text(snapshot.rank.title)
                .font(.system(.headline, design: .rounded).weight(.black))
                .foregroundStyle(TrainingTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

            RankArtworkView(
                habitName: stat.name,
                level: snapshot.rank.level,
                title: snapshot.rank.title,
                image: snapshot.rank.image,
                accent: stateAccent,
                style: .dashboardTile
            )
            .frame(maxWidth: .infinity)

            Text(snapshot.weeklyTargetFractionLabel)
                .font(.caption.weight(.black))
                .foregroundStyle(TrainingTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .center)

            SignedChargeMeter(charge: snapshot.charge.current, pendingProgress: snapshot.weeklyTargetProgress, socketSize: 11, spacing: 6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TrainingTheme.borderStrong.opacity(0.12), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TrainingTheme.card,
                            .white.opacity(0.95),
                            TrainingTheme.elevatedCard,
                            accent.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(TrainingTheme.borderStrong.opacity(0.24), lineWidth: 1.1)
        )
        .overlay {
            if snapshot.rankChangeIndicatorVisible {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(stateAccent.opacity(0.42), lineWidth: 1.4)
                    .padding(3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if snapshot.rankChangeIndicatorVisible, let direction = snapshot.pendingRankChange?.direction {
                Image(systemName: direction == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(stateAccent)
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.85), lineWidth: 1.4)
                    )
                    .shadow(color: stateAccent.opacity(0.45), radius: 6, x: 0, y: 0)
                    .padding(8)
                    .accessibilityLabel(direction == .up ? "Rank up available" : "Rank drop pending")
            }
        }
        .overlay(alignment: .topLeading) {
            if hasUnmatchedImports {
                UnmatchedBadge(accent: accent, action: onShowUnmatched)
                    .padding(10)
            } else if needsAttention {
                AttentionDot(accent: accent)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: snapshot.rankChangeIndicatorVisible ? stateAccent.opacity(0.28) : accent.opacity(0.08), radius: snapshot.rankChangeIndicatorVisible ? 14 : 10, x: 0, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["\(stat.name)", "level \(snapshot.rank.level)", DashboardChargeDots.summaryLabel(for: snapshot.charge.current)]
        if hasUnmatchedImports { parts.append("unmatched workouts to review") }
        else if needsAttention { parts.append("needs attention this week") }
        return parts.joined(separator: ", ")
    }

    private var levelBadge: some View {
        Text("LV \(snapshot.rank.level)")
            .font(.caption.weight(.black))
            .foregroundStyle(accent.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.white.opacity(0.94))
            )
            .overlay(
                Capsule()
                    .strokeBorder(accent.opacity(0.18), lineWidth: 0.9)
            )
    }
}
