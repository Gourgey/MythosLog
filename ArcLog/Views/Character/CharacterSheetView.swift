import SwiftUI

struct MoreView: View {
    let onSettingsMutated: () -> Void

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
                    SurfaceCard(accent: TrainingArcConfig.color(for: "focus")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("More")
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .foregroundStyle(TrainingTheme.textPrimary)
                            Text("History, settings, and the extra controls that no longer need their own tab.")
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                    }

                    NavigationLink {
                        HistoryView()
                    } label: {
                        destinationCard(
                            title: "History",
                            detail: "Review resolved weeks, baselines, and long-term movement for each skill.",
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
                            detail: "Notifications, theme, exports, sample data, and progression preferences.",
                            icon: "gearshape.fill",
                            accent: TrainingArcConfig.color(for: "curiosity")
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .navigationTitle("More")
    }

    private func destinationCard(title: String, detail: String, icon: String, accent: Color) -> some View {
        SurfaceCard(accent: accent) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(TrainingTheme.textPrimary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }
}

struct SkillCharacterRosterView: View {
    let stat: StatDomain

    @State private var centeredLevel: Int?
    @State private var didCenterInitialLevel = false

    private var statKey: StatKey {
        stat.statKey ?? .strength
    }

    private var accent: Color {
        TrainingArcConfig.color(for: stat.colorToken)
    }

    private var currentLevel: Int {
        stat.rankLevel
    }

    private var entries: [CharacterRosterEntry] {
        TrainingArcConfig.characterRosterEntries(for: statKey, currentLevel: currentLevel)
    }

    private var focusedEntry: CharacterRosterEntry {
        entries.first(where: { $0.level == (centeredLevel ?? currentLevel) }) ?? entries[0]
    }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(max(geometry.size.width * 0.72, 260), 380)
            let carouselHeight = max(geometry.size.height * 0.66, 420)
            let horizontalInset = max((geometry.size.width - cardWidth) / 2, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(stat.name)
                            .font(.system(.largeTitle, design: .rounded).weight(.black))
                            .foregroundStyle(TrainingTheme.textPrimary)

                        HStack(spacing: 10) {
                            Text(focusedEntry.title)
                                .font(.system(.title3, design: .rounded).weight(.heavy))
                                .foregroundStyle(TrainingTheme.textPrimary)
                                .lineLimit(2)

                            Spacer(minLength: 8)

                            Text("LV \(focusedEntry.level)")
                                .font(.caption.weight(.black))
                                .foregroundStyle(focusedEntry.isLocked ? TrainingTheme.warning : accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.92))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder((focusedEntry.isLocked ? TrainingTheme.warning : accent).opacity(0.18), lineWidth: 0.9)
                                )

                            if focusedEntry.isLocked {
                                Label("Locked", systemImage: "lock.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TrainingTheme.warning)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(TrainingTheme.warning.opacity(0.10))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 18) {
                                ForEach(entries) { entry in
                                    SkillCharacterRosterCard(
                                        entry: entry,
                                        statName: stat.name,
                                        accent: accent
                                    )
                                    .frame(width: cardWidth, height: carouselHeight)
                                    .id(entry.level)
                                    .visualEffect { content, proxy in
                                        let frame = proxy.frame(in: .scrollView(axis: .horizontal))
                                        let distance = abs(frame.midX - geometry.size.width / 2)
                                        let progress = min(distance / (geometry.size.width * 0.72), 1)
                                        let scale = 1 - (progress * 0.22)
                                        let opacity = 1 - (progress * 0.38)

                                        return content
                                            .scaleEffect(scale)
                                            .opacity(opacity)
                                    }
                                }
                            }
                            .padding(.horizontal, horizontalInset)
                            .scrollTargetLayout()
                        }
                        .frame(height: carouselHeight)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $centeredLevel, anchor: .center)
                        .onAppear {
                            guard !didCenterInitialLevel else { return }
                            didCenterInitialLevel = true
                            centeredLevel = currentLevel

                            DispatchQueue.main.async {
                                proxy.scrollTo(currentLevel, anchor: .center)
                                centeredLevel = currentLevel
                            }
                        }
                    }
                }
                .padding(.vertical, 18)
            }
            .background(
                LinearGradient(
                    colors: [
                        TrainingTheme.background,
                        TrainingTheme.backgroundSecondary,
                        accent.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
        .navigationTitle("Character Roster")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            centeredLevel = currentLevel
        }
    }
}

private struct SkillCharacterRosterCard: View {
    let entry: CharacterRosterEntry
    let statName: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(statName.uppercased())
                    .font(.caption.weight(.black))
                    .foregroundStyle(TrainingTheme.textMuted)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(TrainingTheme.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text("LV \(entry.level)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(entry.isLocked ? TrainingTheme.warning : accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.92))
                        )
                }
            }

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.96),
                                TrainingTheme.card,
                                accent.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(TrainingTheme.borderStrong.opacity(0.20), lineWidth: 1.2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(.white.opacity(0.24), lineWidth: 0.8)
                            .padding(2)
                    )

                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 220, height: 220)
                    .blur(radius: 10)
                    .offset(x: 72, y: -68)

                cardArtwork

                if entry.isLocked {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.44))
                        )
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TrainingTheme.card,
                            .white.opacity(0.98),
                            TrainingTheme.elevatedCard.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(accent.opacity(0.14), lineWidth: 1.1)
        )
        .shadow(color: accent.opacity(0.16), radius: 20, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 5)
    }

    @ViewBuilder
    private var cardArtwork: some View {
        if let image = entry.image {
            rosterImage(for: image)
                .padding(.horizontal, 2)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else {
            rosterFallbackArtwork
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func rosterImage(for reference: RankImageReference) -> some View {
        switch reference {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .scaleEffect(1.22, anchor: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var rosterFallbackArtwork: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.20), .white.opacity(0.94)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(accent.opacity(0.16), lineWidth: 1)
                    )

                if entry.isLocked {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(TrainingTheme.warning)
                } else {
                    Text(String(statName.prefix(1)).uppercased())
                        .font(.system(size: 58, design: .rounded).weight(.black))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: 170, height: 230)

            Text(entry.isLocked ? "Unknown Form" : "Prototype Form")
                .font(.caption.weight(.bold))
                .foregroundStyle(TrainingTheme.textSecondary)
        }
    }
}
