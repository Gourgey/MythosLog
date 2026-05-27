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
                Text("Active Skills")
            } footer: {
                Text("Drag to reorder. Swipe to archive — your logs, goals, and history are always kept.")
            }

            if !inactiveStats.isEmpty {
                Section {
                    ForEach(inactiveStats) { stat in
                        skillRow(stat, isActive: false)
                    }
                } header: {
                    Text("Optional & Archived")
                } footer: {
                    Text("Enable an optional skill or restore an archived one anytime. Nothing here is deleted.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TrainingTheme.background.ignoresSafeArea())
        .navigationTitle("Manage Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private func skillRow(_ stat: StatDomain, isActive: Bool) -> some View {
        let accent = TrainingArcConfig.color(for: stat.colorToken)
        return HStack(spacing: 12) {
            Image(systemName: stat.iconName.isEmpty ? "circle" : stat.iconName)
                .font(.headline)
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stat.name)
                        .font(.headline)
                        .foregroundStyle(TrainingTheme.textPrimary)
                    if !stat.isCore {
                        Text("Optional")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TrainingTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TrainingTheme.backgroundTertiary))
                    }
                }
                Text(stat.descriptor)
                    .font(.caption)
                    .foregroundStyle(TrainingTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !isActive {
                Button(stat.isCore ? "Restore" : "Enable") {
                    enable(stat)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(accent)
            }
        }
        .padding(.vertical, 4)
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
