import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @Query private var stats: [StatDomain]
    @Query(sort: \WeeklyResolution.weekStartDate, order: .reverse) private var resolutions: [WeeklyResolution]
    @Query private var settingsRecords: [AppSettings]
    @State private var detailWeekStart: Date?
    @State private var showExplainer = false
    @AppStorage("weeklyReview.hasSeenExplainer") private var hasSeenExplainer = false

    init() {}

    private var settings: AppSettings? { settingsRecords.first }

    private var activeStats: [StatDomain] {
        stats
            .filter(\.isActive)
            .sorted {
                if $0.sortOrder == $1.sortOrder { return $0.name < $1.name }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private var pendingWeek: WeekRange? {
        try? TrainingStore.pendingWeek(context: modelContext)
    }

    private var latestResolvedWeekStart: Date? {
        resolutions.first?.weekStartDate
    }

    private var resolvedWeekStarts: [Date] {
        Array(Set(resolutions.map(\.weekStartDate))).sorted(by: >)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TrainingTheme.background, TrainingTheme.backgroundSecondary],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    thisWeekSection
                    lastWeekSection
                    pastReviewsLink
                }
                .padding(16)
            }
        }
        .navigationTitle("Review")
        .navigationDestination(item: $detailWeekStart) { weekStart in
            WeeklyReviewDetailView(weekStart: weekStart)
        }
        .sheet(isPresented: $showExplainer) {
            NavigationStack {
                WeeklyReviewExplainerSheet()
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            if !hasSeenExplainer, pendingWeek != nil {
                showExplainer = true
                hasSeenExplainer = true
            }
        }
    }

    // MARK: - This Week

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIS WEEK")
                .font(.caption.weight(.black))
                .foregroundStyle(TrainingTheme.textMuted)

            if activeStats.isEmpty {
                SurfaceCard {
                    Text("No active skills yet. Start onboarding to begin a week.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            } else {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Live progress for the current week. These stats finalize when you lock in the week.")
                            .font(.caption)
                            .foregroundStyle(TrainingTheme.textSecondary)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(activeStats) { stat in
                                currentWeekRow(stat)
                            }
                        }
                    }
                }
            }
        }
    }

    private func currentWeekRow(_ stat: StatDomain) -> some View {
        let snapshot = TrainingStore.progressSnapshot(for: stat, settings: settings)
        let accent = TrainingArcConfig.color(for: stat.colorToken)
        let onPace = snapshot.pacingStatus != .behind

        return HStack(spacing: 12) {
            Image(systemName: stat.iconName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(accent.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(snapshot.weeklyCounterLabel + ": " + snapshot.weeklyCounterValueLabel)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }

            Spacer()

            Text(snapshot.pacingStatus.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(onPace ? TrainingTheme.positiveStrong : TrainingTheme.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill((onPace ? TrainingTheme.positiveStrong : TrainingTheme.warning).opacity(0.12))
                )
        }
    }

    // MARK: - Last Week

    @ViewBuilder
    private var lastWeekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("LAST WEEK")
                    .font(.caption.weight(.black))
                    .foregroundStyle(TrainingTheme.textMuted)
                Spacer()
                Button {
                    showExplainer = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
                .accessibilityLabel("How weekly review works")
            }

            if let pendingWeek {
                pendingWeekCard(pendingWeek)
            } else if let latestResolvedWeekStart {
                resolvedSummaryCard(weekStart: latestResolvedWeekStart)
            } else {
                SurfaceCard {
                    Text("No resolved weeks yet. After your first full week, a summary will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                }
            }
        }
    }

    private func pendingWeekCard(_ week: WeekRange) -> some View {
        SurfaceCard(accent: TrainingTheme.warning) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lock in last week")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("Apply your rank changes for \(week.displayTitle) and archive the week's stats. This is permanent.")
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)

                HStack(spacing: 10) {
                    Button("Lock In Week") {
                        let batch = try? TrainingStore.resolvePendingWeek(context: modelContext)
                        detailWeekStart = batch?.week.start
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrainingTheme.warning)

                    Button {
                        showExplainer = true
                    } label: {
                        Label("What does this do?", systemImage: "questionmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(TrainingTheme.warning)
                }
            }
        }
    }

    private func resolvedSummaryCard(weekStart: Date) -> some View {
        let weekResolutions = resolutions
            .filter { $0.weekStartDate == weekStart }
            .sorted { $0.statName < $1.statName }
        let verdict = computeVerdict(weekResolutions)
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let title = WeekRange(start: weekStart, end: end).displayTitle
        let levelUps = weekResolutions.filter(\.didLevelUp).count
        let regressed = weekResolutions.filter(\.didRegress).count

        return Button {
            detailWeekStart = weekStart
        } label: {
            SurfaceCard(accent: verdict.color) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verdict.rawValue)
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(TrainingTheme.textPrimary)
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TrainingTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TrainingTheme.textMuted)
                    }

                    Text(verdict.description)
                        .font(.subheadline)
                        .foregroundStyle(TrainingTheme.textSecondary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 10) {
                        summaryChip(label: "Skills", value: "\(weekResolutions.count)", color: TrainingTheme.textPrimary)
                        if levelUps > 0 {
                            summaryChip(label: "Rank ups", value: "\(levelUps)", color: TrainingTheme.positiveStrong)
                        }
                        if regressed > 0 {
                            summaryChip(label: "Drops", value: "\(regressed)", color: TrainingTheme.danger)
                        }
                    }

                    Text("Tap to see the full breakdown")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(verdict.color)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func summaryChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.black))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TrainingTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.82))
        )
    }

    // MARK: - Past Reviews

    @ViewBuilder
    private var pastReviewsLink: some View {
        if resolvedWeekStarts.count > 1 {
            NavigationLink {
                WeeklyReviewHistoryView(
                    weekStarts: resolvedWeekStarts,
                    resolutions: resolutions
                ) { weekStart in
                    detailWeekStart = weekStart
                }
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.bold))
                    Text("View past reviews")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(TrainingTheme.textSecondary)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(TrainingTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(TrainingTheme.borderStrong.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Verdict helper

    private struct VerdictDescriptor {
        let rawValue: String
        let color: Color
        let description: String
    }

    private func computeVerdict(_ resolutions: [WeeklyResolution]) -> VerdictDescriptor {
        guard !resolutions.isEmpty else {
            return VerdictDescriptor(rawValue: "Held Form", color: TrainingTheme.cold, description: "Baselines maintained across the board.")
        }
        let levelUps = resolutions.filter(\.didLevelUp).count
        let regressed = resolutions.filter(\.didRegress).count
        let belowBaseline = resolutions.filter { $0.weeklyDelta < 0 }.count
        let aboveBaseline = resolutions.filter { $0.weeklyDelta > 0 }.count

        if regressed > 0 {
            return VerdictDescriptor(rawValue: "Regression Risk", color: TrainingTheme.danger, description: "Skills ranked down or are close to dropping.")
        }
        if levelUps > 0, belowBaseline == 0 {
            return VerdictDescriptor(rawValue: "Advanced", color: TrainingTheme.positiveStrong, description: "Skills moved forward this week.")
        }
        if belowBaseline > resolutions.count / 2 {
            return VerdictDescriptor(rawValue: "Lost Momentum", color: TrainingTheme.warning, description: "Most skills landed below baseline.")
        }
        if aboveBaseline > 0, belowBaseline > 0 {
            return VerdictDescriptor(rawValue: "Mixed Week", color: TrainingTheme.warning, description: "Some skills advanced, others slipped.")
        }
        return VerdictDescriptor(rawValue: "Held Form", color: TrainingTheme.cold, description: "Baselines maintained across the board.")
    }
}

// MARK: - History list

struct WeeklyReviewHistoryView: View {
    let weekStarts: [Date]
    let resolutions: [WeeklyResolution]
    let onSelect: (Date) -> Void

    var body: some View {
        List {
            ForEach(weekStarts, id: \.self) { weekStart in
                Button {
                    onSelect(weekStart)
                } label: {
                    historyRow(for: weekStart)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Past Reviews")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyRow(for weekStart: Date) -> some View {
        let weekResolutions = resolutions.filter { $0.weekStartDate == weekStart }
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let title = WeekRange(start: weekStart, end: end).displayTitle
        let levelUps = weekResolutions.filter(\.didLevelUp).count
        let regressed = weekResolutions.filter(\.didRegress).count

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text("\(weekResolutions.count) skills · \(levelUps) up · \(regressed) down")
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TrainingTheme.textMuted)
        }
    }
}

// MARK: - Explainer

struct WeeklyReviewExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explainerSection(
                    icon: "calendar.badge.checkmark",
                    title: "How weekly review works",
                    body: "Each week your skill logs roll into a weekly stat. When the week ends, the app calculates whether each skill met its baseline and whether any ranks should change."
                )

                explainerSection(
                    icon: "lock.fill",
                    title: "Lock In Week",
                    body: "Applies rank changes for last week and archives the stats. Once locked in, you can't undo it — but the breakdown is saved here forever and you can always look back at it."
                )

                explainerSection(
                    icon: "clock",
                    title: "Until you lock in",
                    body: "Rank changes for last week are pending. Your current-week logs continue to count normally — only last week's rank effects are paused."
                )

                explainerSection(
                    icon: "list.bullet.rectangle",
                    title: "After you lock in",
                    body: "You'll see a verdict (Advanced, Held Form, Mixed Week, etc.), a recap of your best/worst skills, and a per-skill breakdown. Tap any past week to revisit it."
                )
            }
            .padding(20)
        }
        .navigationTitle("How review works")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func explainerSection(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(TrainingArcConfig.color(for: "focus"))
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(TrainingArcConfig.color(for: "focus").opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TrainingTheme.textPrimary)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(TrainingTheme.textSecondary)
            }
        }
    }
}
