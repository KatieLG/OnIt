import SwiftUI

struct CardView: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    let task: TaskItem
    var focus: FocusState<FocusField?>.Binding

    @State private var isHovering = false

    private var isSelected: Bool { ui.selectedTaskId == task.id }
    private var isEditing: Bool { ui.editingTaskId == task.id }
    private var board: Board? { store.board(id: task.boardId) }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(SizeStyle.color(for: task.size))
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                titleView
                footer
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(isHovering ? 0.16 : 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering, !isEditing {
                Menu {
                    CardMenuContent(task: task)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .frame(width: 18, height: 14)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(4)
                .accessibilityLabel("Actions for \(task.title)")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { ui.beginEdit(task.id) }
        .onTapGesture {
            ui.selectedTaskId = task.id
            if ui.editingTaskId != task.id { ui.focusRequest = .board }
        }
        .contextMenu { CardMenuContent(task: task) }
        .draggable(task.id.uuidString) {
            CardDragPreview(task: task)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Edit title") { ui.beginEdit(task.id) }
        .accessibilityAction(named: "Move to next column") {
            if let next = task.column.next { store.move(task.id, to: next) }
        }
        .accessibilityAction(named: "Move to previous column") {
            if let previous = task.column.previous { store.move(task.id, to: previous) }
        }
        .accessibilityAction(named: "Delete") { store.delete(task.id) }
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditing {
            @Bindable var ui = ui
            TextField("Title", text: $ui.editText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused(focus, equals: .edit)
                .onSubmit { ui.commitEdit() }
                .accessibilityLabel("Edit title")
        } else {
            Text(task.title)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, isHovering ? 18 : 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            SizeChip(size: task.size)
            ForEach(task.tags.prefix(2), id: \.self) { tag in
                TagPill(text: "#\(tag)")
            }
            if task.tags.count > 2 {
                TagPill(text: "+\(task.tags.count - 2)")
            }
            Spacer(minLength: 4)
            if ui.isAllView, let board {
                HStack(spacing: 3) {
                    Circle().fill(Color(hex: board.colorHex) ?? .gray).frame(width: 6, height: 6)
                    Text(board.shortName)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            timeLabel
        }
    }

    @ViewBuilder
    private var timeLabel: some View {
        if task.column == .doing, let started = task.startedAt {
            TimelineView(.everyMinute) { context in
                Text(Formatting.elapsed(since: started, now: context.date))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .help("Started \(started.formatted(date: .abbreviated, time: .shortened))")
        } else if task.column == .done, let completed = task.completedAt {
            Text(Formatting.completion(completed))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("Completed \(completed.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    private var accessibilityLabel: String {
        var parts = [task.title, SizeStyle.accessibilityName(for: task.size)]
        if let board { parts.append("\(board.name) board") }
        parts.append("in \(task.column.title)")
        if !task.tags.isEmpty { parts.append("tags " + task.tags.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}

struct CardDragPreview: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 6) {
            SizeChip(size: task.size)
            Text(task.title).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SizeChip: View {
    let size: TaskSize?

    var body: some View {
        Text(SizeStyle.label(for: size))
            .font(.caption2.weight(.bold))
            .monospaced()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 22)
            .foregroundStyle(SizeStyle.chipText(for: size))
            .background(SizeStyle.chipBackground(for: size), in: Capsule())
            .accessibilityLabel(SizeStyle.accessibilityName(for: size))
    }
}

struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(.secondary)
            .background(Color.secondary.opacity(0.14), in: Capsule())
    }
}

/// Shared by the context menu and the hover "…" button.
struct CardMenuContent: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    let task: TaskItem

    var body: some View {
        Button("Edit Title") { ui.beginEdit(task.id) }
        Menu("Set Size") {
            ForEach(TaskSize.allCases) { size in
                Button {
                    store.setSize(task.id, size)
                } label: {
                    if task.size == size { Label(size.label, systemImage: "checkmark") } else { Text(size.label) }
                }
            }
            Divider()
            Button {
                store.setSize(task.id, nil)
            } label: {
                if task.size == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
            }
        }
        Menu("Move To") {
            ForEach(Column.allCases) { column in
                Button(column.title) {
                    withAnimation(BoardUIState.cardAnimation) { store.move(task.id, to: column) }
                }
                .disabled(column == task.column)
            }
        }
        Menu("Change Board") {
            ForEach(store.boards) { board in
                Button(board.name) { store.setBoard(task.id, boardId: board.id) }
                    .disabled(board.id == task.boardId)
            }
        }
        Button("Edit Tags…") { ui.beginTagEdit(task.id) }
        Divider()
        Button("Delete", role: .destructive) {
            withAnimation(BoardUIState.cardAnimation) { store.delete(task.id) }
        }
    }
}
