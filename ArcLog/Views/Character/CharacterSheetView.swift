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
