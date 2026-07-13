import SwiftData
import SwiftUI

struct MoreView: View {
    @Query private var allStats: [StatDomain]
    @Query private var resolutions: [WeeklyResolution]
    @Query private var settingsRecords: [AppSettings]

    let onSettingsMutated: () -> Void

    private var activeStats: [StatDomain] {
        allStats.filter(\.isActive)
    }

    private var totalRanksEarned: Int {
        activeStats.reduce(0) { $0 + max($1.rankLevel, 0) }
    }

    private var totalCharge: Int {
        activeStats.reduce(0) { $0 + max($1.chargeValue, 0) }
    }

    private var resolvedThisWeekCount: Int {
        let weekStartsOnMonday = settingsRecords.first?.weekStartsOnMonday ?? true
        let lastCompletedWeek = WeekMath.lastCompletedWeek(before: .now, weekStartsOnMonday: weekStartsOnMonday)
        return resolutions.filter { $0.weekStartDate == lastCompletedWeek.start }.count
    }

    private var atBaselineCount: Int {
        let count = activeStats.filter { $0.chargeValue == 0 }.count
        return count
    }

    private var overallLevel: Int {
        let active = activeStats
        guard !active.isEmpty else { return 1 }
        let avg = Double(totalRanksEarned) / Double(active.count)
        return max(1, Int(avg.rounded()))
    }

    private var overallTitle: String {
        switch overallLevel {
        case ...2: return "Initiate"
        case 3...4: return "Apprentice"
        case 5...6: return "Skilled"
        case 7...8: return "Adept"
        case 9...10: return "Master"
        default: return "Adept"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    morePageHeader

                    overallStandingCard

                    NavigationLink {
                        ManageSkillsView()
                    } label: {
                        destinationCard(
                            title: "Manage Skills",
                            detail: "Enable optional skills, archive ones you don't track, reorder your set.",
                            icon: "square.stack.3d.up.fill",
                            accent: TrainingArcConfig.color(for: "strength")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        HistoryView()
                    } label: {
                        destinationCard(
                            title: "History",
                            detail: "Resolved weeks, baselines, and long-term movement for each skill.",
                            icon: "chart.xyaxis.line",
                            accent: TrainingArcConfig.color(for: "intellect")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SettingsView {
                            onSettingsMutated()
                        }
                    } label: {
                        destinationCard(
                            title: "Settings",
                            detail: "Notifications, theme, exports, and progression preferences.",
                            icon: "gearshape.fill",
                            accent: TrainingArcConfig.color(for: "curiosity")
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var morePageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            V4PageKicker(title: "Profile & Controls")
        }
    }

    private var overallStandingCard: some View {
        let accent = TrainingArcConfig.color(for: "focus")
        return V4Card(accent: accent) {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(TrainingTheme.border.opacity(0.5), lineWidth: 2)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: ringTrim)
                            .stroke(TrainingTheme.textPrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 72, height: 72)
                        Text(V4Style.displayNumber(overallLevel))
                            .font(.system(.title2, design: .serif).weight(.regular))
                            .foregroundStyle(TrainingTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("OVERALL STANDING")
                            .font(.caption.weight(.heavy))
                            .tracking(2.0)
                            .foregroundStyle(TrainingTheme.textMuted)
                        V4SerifTitle(text: overallTitle, size: 30)
                        Text("\(activeStats.count) skills tracked · \(totalRanksEarned) ranks earned")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textSecondary)
                    }

                    Spacer(minLength: 0)
                }

                Divider()
                    .overlay(TrainingTheme.border.opacity(0.5))

                HStack(alignment: .top, spacing: 0) {
                    V4StatTile(value: V4Style.displayNumber(totalCharge), label: "Charge")
                    V4StatTile(value: V4Style.displayNumber(resolvedThisWeekCount), label: "This week")
                    V4StatTile(value: V4Style.displayNumber(atBaselineCount), label: "At baseline")
                }
            }
        }
    }

    private var ringTrim: Double {
        let maxLevel = Double(TrainingArcConfig.maximumRankLevel)
        return min(max(Double(overallLevel) / maxLevel, 0.05), 1.0)
    }

    private func destinationCard(title: String, detail: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .serif).weight(.regular))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TrainingTheme.textMuted)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.985, green: 0.975, blue: 0.955))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TrainingTheme.border.opacity(0.5), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

struct SkillCharacterRosterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allStats: [StatDomain]

    let stat: StatDomain
    @State private var activeStatID: UUID
    @State private var focusedLevel: Int
    @State private var entries: [CharacterRosterEntry]

    init(stat: StatDomain) {
        self.stat = stat
        _activeStatID = State(initialValue: stat.id)
        _focusedLevel = State(initialValue: stat.rankLevel)
        _entries = State(initialValue: TrainingArcConfig.characterRosterEntries(for: stat.statKey ?? .strength, currentLevel: stat.rankLevel))
    }

    private var activeStats: [StatDomain] {
        allStats
            .filter { $0.isActive }
            .sorted {
                if $0.sortOrder == $1.sortOrder { return $0.name < $1.name }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private var activeStat: StatDomain {
        activeStats.first(where: { $0.id == activeStatID }) ?? stat
    }

    private var statKey: StatKey {
        activeStat.statKey ?? .strength
    }

    private var accent: Color {
        TrainingArcConfig.color(for: activeStat.colorToken)
    }

    private var currentLevel: Int {
        activeStat.rankLevel
    }

    private var focusedEntry: CharacterRosterEntry {
        entries.first(where: { $0.level == focusedLevel }) ?? entries.first(where: { $0.level == currentLevel }) ?? entries[0]
    }

    private var unlockedCount: Int {
        entries.filter { !$0.isLocked }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                skillSwitcher
                heroBlock
                progressionList
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .background(
            LinearGradient(
                colors: [
                    TrainingTheme.background,
                    TrainingTheme.backgroundSecondary,
                    accent.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Roster")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                V4PageKicker(title: "Roster")
            }
        }
        .onChange(of: activeStatID) { _, _ in
            focusedLevel = currentLevel
            entries = TrainingArcConfig.characterRosterEntries(for: statKey, currentLevel: currentLevel)
        }
    }

    private var skillSwitcher: some View {
        VStack(alignment: .leading, spacing: 10) {
            V4PageKicker(title: "Your Skills", symbol: "sparkle", accent: TrainingTheme.textMuted)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(activeStats) { other in
                        skillChip(for: other)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private func skillChip(for other: StatDomain) -> some View {
        let isActive = other.id == activeStatID
        let chipAccent = TrainingArcConfig.color(for: other.colorToken)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                activeStatID = other.id
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: other.iconName)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(chipAccent)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(chipAccent.opacity(isActive ? 0.22 : 0.14)))
                Text(other.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? chipAccent.opacity(0.12) : Color(red: 0.97, green: 0.96, blue: 0.94))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? chipAccent.opacity(0.45) : TrainingTheme.border.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                V4SerifTitle(text: activeStat.name)
                Spacer()
                V4LevelBadge(level: focusedEntry.level, tint: accent)
            }

            (Text(focusPrefix).foregroundStyle(TrainingTheme.textSecondary)
             + Text(focusedEntry.title).foregroundStyle(accent).fontWeight(.semibold)
             + Text(" · \(unlockedCount) of \(entries.count) ranks unlocked").foregroundStyle(TrainingTheme.textSecondary))
                .font(.subheadline)

            progressBar
                .padding(.top, 4)

            CharacterRosterCarousel(
                entries: entries,
                activeStatName: activeStat.name,
                focusedLevel: $focusedLevel,
                currentLevel: currentLevel,
                accent: accent
            )
            .padding(.vertical, 4)
        }
    }

    private var focusPrefix: String {
        if focusedEntry.level == currentLevel {
            return "Currently "
        }
        if focusedEntry.isLocked {
            return "Previewing locked "
        }
        return "Previewing "
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                ForEach(entries) { entry in
                    Capsule()
                        .fill(entry.isLocked ? TrainingTheme.border.opacity(0.5) : accent.opacity(entry.level == focusedEntry.level ? 1.0 : 0.5))
                        .frame(width: max((proxy.size.width - CGFloat((entries.count - 1) * 4)) / CGFloat(entries.count), 8), height: 6)
                }
            }
        }
        .frame(height: 6)
    }

    private var progressionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            V4SectionHeader(number: entries.count, title: "Rank Progression")
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(entries) { entry in
                    rankRow(entry)
                }
            }
        }
    }

    private func rankRow(_ entry: CharacterRosterEntry) -> some View {
        let isCurrent = entry.level == focusedEntry.level
        let isActualCurrent = entry.level == currentLevel
        let statusLabel: String
        let statusTint: Color
        if isActualCurrent {
            statusLabel = "Current"
            statusTint = accent
        } else if isCurrent {
            statusLabel = "Preview"
            statusTint = accent
        } else if entry.isLocked {
            statusLabel = "Locked"
            statusTint = TrainingTheme.textMuted
        } else {
            statusLabel = "Unlocked"
            statusTint = TrainingTheme.positiveStrong
        }

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(entry.isLocked ? 0.06 : 0.14))
                    .frame(width: 56, height: 56)
                if let image = entry.image {
                    rosterThumbnail(for: image)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: entry.isLocked ? "lock.fill" : "person.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(entry.isLocked ? TrainingTheme.textMuted : accent)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("LV \(V4Style.displayNumber(entry.level)) · \(statusLabel.uppercased())")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(statusTint)
                Text(entry.title)
                    .font(.system(.title3, design: .serif).weight(.regular))
                    .foregroundStyle(entry.isLocked ? TrainingTheme.textSecondary : TrainingTheme.textPrimary)
                    .lineLimit(2)
            }

            Spacer()

            if isActualCurrent {
                Text("YOU ARE HERE")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(accent)
                    )
            } else if entry.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TrainingTheme.textMuted)
            } else {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.985, green: 0.975, blue: 0.955))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isCurrent ? accent.opacity(0.55) : TrainingTheme.border.opacity(0.45), lineWidth: isCurrent ? 1.4 : 0.8)
        )
        .shadow(color: Color.black.opacity(isCurrent ? 0.06 : 0.02), radius: isCurrent ? 6 : 3, x: 0, y: 2)
    }

    @ViewBuilder
    private func rosterThumbnail(for reference: RankImageReference) -> some View {
        switch reference {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFill()
        }
    }
}

private struct CharacterRosterCarousel: View {
    let entries: [CharacterRosterEntry]
    let activeStatName: String
    @Binding var focusedLevel: Int
    let currentLevel: Int
    let accent: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(entries) { entry in
                    rosterCard(entry)
                        .id(entry.level)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.84)
                                .opacity(phase.isIdentity ? 1.0 : 0.64)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: 326)
        .contentMargins(.horizontal, 54, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: focusedLevelBinding)
        .onAppear {
            focusedLevel = min(max(focusedLevel, TrainingArcConfig.minimumRankLevel), TrainingArcConfig.maximumRankLevel)
        }
    }

    private var focusedLevelBinding: Binding<Int?> {
        Binding<Int?>(
            get: { focusedLevel },
            set: { newValue in
                guard let newValue else { return }
                focusedLevel = newValue
            }
        )
    }

    private func rosterCard(_ entry: CharacterRosterEntry) -> some View {
        let isCurrent = entry.level == currentLevel
        return VStack(spacing: 12) {
            HStack {
                V4LevelBadge(level: entry.level, tint: accent, compact: true)
                Spacer()
                Text(statusText(for: entry))
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(statusTint(for: entry))
            }

            ZStack(alignment: .topTrailing) {
                RankArtworkView(
                    habitName: activeStatName,
                    level: entry.level,
                    title: entry.title,
                    image: entry.image,
                    accent: accent,
                    style: .dashboardTile
                )

                if entry.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textMuted)
                        .padding(8)
                        .background(Circle().fill(.white.opacity(0.86)))
                        .padding(10)
                }
            }

            Text(entry.title)
                .font(.system(.headline, design: .serif).weight(.regular))
                .foregroundStyle(entry.isLocked ? TrainingTheme.textSecondary : TrainingTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(width: 224, height: 310)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TrainingTheme.card,
                            .white.opacity(0.92),
                            accent.opacity(isCurrent ? 0.14 : 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(isCurrent ? accent.opacity(0.46) : TrainingTheme.borderStrong.opacity(0.18), lineWidth: isCurrent ? 1.3 : 0.9)
        )
        .shadow(color: accent.opacity(isCurrent ? 0.18 : 0.08), radius: isCurrent ? 14 : 8, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(entry.level), \(entry.title), \(statusText(for: entry))")
    }

    private func statusText(for entry: CharacterRosterEntry) -> String {
        if entry.level == currentLevel { return "CURRENT" }
        if entry.isLocked { return "LOCKED" }
        return "UNLOCKED"
    }

    private func statusTint(for entry: CharacterRosterEntry) -> Color {
        if entry.level == currentLevel { return accent }
        if entry.isLocked { return TrainingTheme.textMuted }
        return TrainingTheme.positiveStrong
    }
}
