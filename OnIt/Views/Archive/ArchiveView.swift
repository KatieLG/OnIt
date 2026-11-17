import SwiftUI

struct ArchiveView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var deleting: TaskItem?

    var body: some View {
        let matches = store.archivedTasks.filter {
            TaskFilter(text: search).matches($0) || store.board(id: $0.boardId)?.name.localizedCaseInsensitiveContains(search) == true
        }
        let weeks = Dictionary(grouping: matches) {
            Calendar.current.dateInterval(of: .weekOfYear, for: $0.completedAt ?? $0.createdAt)?.start ?? .distantPast
        }
        VStack(spacing: 0) {
            TextField("Search archive", text: $search).textFieldStyle(.roundedBorder).padding(10)
            if weeks.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No archived tasks" : "No matches", systemImage: "archivebox", description: Text(
                    search.isEmpty ? "Done tasks are archived automatically after \(store.settings.archiveAfterDays) days." : "Try a different search."
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(weeks.keys.sorted(by: >), id: \.self) { week in
                    Section("Week of \(week.formatted(.dateTime.day().month(.wide).year()))") {
                        ForEach(weeks[week] ?? []) { task in ArchiveRow(task: task) { deleting = task } }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 480)
        .confirmationDialog("Delete “\(deleting?.title ?? "")” permanently?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) { if let deleting { store.delete(deleting.id) } }
        }
    }
}

private struct ArchiveRow: View {
    @Environment(AppStore.self) private var store
    let task: TaskItem
    let onDelete: () -> Void

    var body: some View {
        let completed = task.completedAt.map { "completed \($0.formatted(date: .abbreviated, time: .omitted))" }
        HStack(spacing: 10) {
            SizeChip(size: task.size)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(2)
                Text([store.board(id: task.boardId)?.name, completed].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore to Todo") { store.restore(task.id) }.controlSize(.small)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .controlSize(.small)
                .help("Delete permanently")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Restore to Todo") { store.restore(task.id) }
            Button("Delete Permanently…", role: .destructive, action: onDelete)
        }
    }
}
