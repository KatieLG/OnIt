import SwiftUI

struct ArchiveView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var pendingDelete: TaskItem?

    private struct WeekGroup: Identifiable {
        let weekStart: Date
        let tasks: [TaskItem]
        var id: Date { weekStart }
    }

    private var groups: [WeekGroup] {
        let calendar = Calendar.current
        let filter = TaskFilter(text: search)
        let matching = store.archivedTasks.filter { task in
            filter.matches(task) || (store.board(id: task.boardId)?.name.localizedCaseInsensitiveContains(search) ?? false)
        }
        let grouped = Dictionary(grouping: matching) { task in
            calendar.dateInterval(of: .weekOfYear, for: task.completedAt ?? task.updatedAt)?.start ?? .distantPast
        }
        return grouped
            .map { WeekGroup(weekStart: $0.key, tasks: $0.value) }
            .sorted { $0.weekStart > $1.weekStart }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search archive", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .padding(10)

            let groups = groups
            if groups.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No archived tasks" : "No matches",
                    systemImage: "archivebox",
                    description: Text(search.isEmpty
                        ? "Done tasks are archived automatically after \(store.settings.archiveAfterDays) days."
                        : "Try a different search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section("Week of \(group.weekStart.formatted(.dateTime.day().month(.wide).year()))") {
                            ForEach(group.tasks) { task in
                                ArchiveRow(task: task, onDelete: { pendingDelete = task })
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 480)
        .confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")” permanently?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let task = pendingDelete { store.delete(task.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }
}

private struct ArchiveRow: View {
    @Environment(AppStore.self) private var store
    let task: TaskItem
    let onDelete: () -> Void

    var body: some View {
        let board = store.board(id: task.boardId)
        HStack(spacing: 10) {
            SizeChip(size: task.size)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(2)
                HStack(spacing: 4) {
                    if let board {
                        Circle().fill(Color(hex: board.colorHex) ?? .gray).frame(width: 6, height: 6)
                        Text(board.name)
                    }
                    if let completed = task.completedAt {
                        Text("· completed \(completed.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore to Todo") { store.restore(task.id) }
                .controlSize(.small)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .help("Delete permanently")
            .accessibilityLabel("Delete \(task.title) permanently")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Restore to Todo") { store.restore(task.id) }
            Button("Delete Permanently…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
    }
}
