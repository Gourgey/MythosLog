import SwiftData
import SwiftUI

/// Skill Library — enable optional skills, archive/restore, and reorder the active
/// set. Archiving never deletes logs, goals, or history (see TrainingStore).
struct ManageSkillsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatDomain.sortOrder) private var stats: [StatDomain]

    private var activeStats: [StatDomain] {
        stats.filter { $0.isActive }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var inactiveStats: [StatDomain] {
        stats.filter { !$0.isActive }.sorted { lhs, rhs in
            if lhs.isCore != rhs.isCore { return rhs.isCore } // optional first
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(activeStats) { stat in
                    skillRow(stat, isActive: true)
                }
                .onMove(perform: moveActive)
            } header: {
                Text("ACTIVE SKILLS")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(TrainingTheme.textMuted)
            } footer: {
                Text("Drag to reorder. Swipe to archive — your logs, goals, and history are always kept.")
                    .font(.caption)
            }

            if !inactiveStats.isEmpty {
                Section {
                    ForEach(inactiveStats) { stat in
                        skillRow(stat, isActive: false)
                    }
                } header: {
                    Text("OPTIONAL & ARCHIVED")
                        .font(.caption.weight(.heavy))
                        .tracking(2.0)
                        .foregroundStyle(TrainingTheme.textMuted)
                } footer: {
                    Text("Enable an optional skill or restore an archived one anytime. Nothing here is deleted.")
                        .font(.caption)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.985, green: 0.975, blue: 0.955).ignoresSafeArea())
        .navigationTitle("Manage Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TrainingTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private func skillRow(_ stat: StatDomain, isActive: Bool) -> some View {
        let accent = TrainingArcConfig.color(for: stat.colorToken)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(isActive ? 0.16 : 0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: stat.iconName.isEmpty ? "circle" : stat.iconName)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stat.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isActive ? TrainingTheme.textPrimary : TrainingTheme.textSecondary)
                    if !stat.isCore {
                        Text("OPTIONAL")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(TrainingTheme.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TrainingTheme.border.opacity(0.4)))
                    }
                }
                Text(stat.descriptor)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !isActive {
                Button {
                    enable(stat)
                } label: {
                    Text(stat.isCore ? "Restore" : "Enable")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(accent.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isActive {
                Button(role: .destructive) {
                    archive(stat)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } else {
                Button {
                    enable(stat)
                } label: {
                    Label(stat.isCore ? "Restore" : "Enable", systemImage: "plus.circle")
                }
                .tint(TrainingTheme.positive)
            }
        }
    }

    private func moveActive(from source: IndexSet, to destination: Int) {
        var ids = activeStats.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        try? TrainingStore.setSkillOrder(ids, context: modelContext)
    }

    private func enable(_ stat: StatDomain) {
        try? TrainingStore.enableSkill(stat, context: modelContext)
    }

    private func archive(_ stat: StatDomain) {
        try? TrainingStore.archiveSkill(stat, context: modelContext)
    }
}
