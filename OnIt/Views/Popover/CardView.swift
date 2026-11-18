import SwiftUI

struct CardView: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    let task: TaskItem
    var focus: FocusState<FocusField?>.Binding
    @State private var isHovering = false

    var body: some View {
        let selected = ui.selectedTaskId == task.id, editing = ui.editingTaskId == task.id
        let board = store.board(id: task.boardId), sized = board?.showsSizes ?? true
        HStack(spacing: 0) {
            if sized { Rectangle().fill(SizeStyle.color(task.size)).frame(width: 4) }
            VStack(alignment: .leading, spacing: 6) {
                if editing {
                    @Bindable var ui = ui
                    TextField("Title", text: $ui.editText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused(focus, equals: .edit)
                        .onSubmit(ui.commitEdit)
                } else {
                    Text(task.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, isHovering ? 18 : 0)
                }
                HStack(spacing: 4) {
                    if sized { SizeMenu(task: task) }
                    ForEach(task.tags.prefix(2), id: \.self) { Pill(text: "#\($0)") }
                    if task.tags.count > 2 { Pill(text: "+\(task.tags.count - 2)") }
                    Spacer(minLength: 4)
                    Group {
                        if ui.selectedBoardId == nil, let board {
                            HStack(spacing: 3) {
                                Circle().fill(Color(hex: board.colorHex)).frame(width: 6, height: 6)
                                Text(board.name)
                            }
                        }
                        timeLabel
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(.secondary.opacity(isHovering ? 0.16 : 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            if isHovering, !editing {
                Menu { CardMenu(task: task) } label: { Image(systemName: "ellipsis").font(.caption.weight(.bold)).frame(width: 18, height: 14) }
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
            if !editing { ui.focusRequest = .board }
        }
        .contextMenu { CardMenu(task: task) }
        .draggable(task.id.uuidString) {
            HStack(spacing: 6) { if sized { SizeChip(size: task.size) }; Text(task.title).lineLimit(1) }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([task.title, sized ? SizeStyle.spoken(task.size) : nil, board.map { "\($0.name) board" }, "in \(task.column.title)",
                             task.tags.isEmpty ? nil : "tags " + task.tags.joined(separator: ", ")].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Edit title") { ui.beginEdit(task.id) }
        .accessibilityAction(named: "Move to next column") { if let next = task.column.next { store.move(task.id, to: next) } }
        .accessibilityAction(named: "Move to previous column") { if let previous = task.column.previous { store.move(task.id, to: previous) } }
        .accessibilityAction(named: "Delete") { store.delete(task.id) }
    }

    @ViewBuilder private var timeLabel: some View {
        if task.column == .doing, let started = task.startedAt {
            TimelineView(.everyMinute) { Text(Formatting.elapsed(since: started, now: $0.date)) }
                .help("Started \(started.formatted(date: .abbreviated, time: .shortened))")
        } else if task.column == .done, let completed = task.completedAt {
            Text(Formatting.completion(completed)).help("Completed \(completed.formatted(date: .abbreviated, time: .shortened))")
        }
    }
}

/// The card's actions, shared by its context menu and hover "…" button.
private struct CardMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    let task: TaskItem

    var body: some View {
        Button("Edit Title") { ui.beginEdit(task.id) }
        if store.showsSizes(boardId: task.boardId) { SizePicker(task: task) }
        Picker("Move To", selection: Binding(get: { task.column }, set: { column in ui.animate { store.move(task.id, to: column) } })) {
            ForEach(Column.allCases) { Text($0.title).tag($0) }
        }
        Picker("Board", selection: binding(\.boardId)) {
            ForEach(store.boards) { Text($0.name).tag($0.id) }
        }
        Button("Edit Tags…") { ui.beginTagEdit(task.id) }
        Divider()
        Button("Delete", role: .destructive) { ui.animate { store.delete(task.id) } }
    }

    private func binding<Value>(_ path: WritableKeyPath<TaskItem, Value>) -> Binding<Value> {
        Binding(get: { task[keyPath: path] }, set: { value in store.update(task.id) { $0[keyPath: path] = value } })
    }
}

/// The size choices, as a submenu in the card menu or inline in the chip's menu.
private struct SizePicker: View {
    @Environment(AppStore.self) private var store
    let task: TaskItem

    var body: some View {
        Picker("Size", selection: Binding(get: { task.size }, set: { size in store.update(task.id) { $0.size = size } })) {
            ForEach(TaskSize.allCases) { Text($0.label).tag(Optional($0)) }
            Text("None").tag(TaskSize?.none)
        }
    }
}

/// The card's size chip; click it to change the size.
private struct SizeMenu: View {
    let task: TaskItem

    var body: some View {
        Menu { SizePicker(task: task).pickerStyle(.inline).labelsHidden() } label: { SizeChip(size: task.size) }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change size")
    }
}

/// The size label on a card: dark text on the lighter colours, white on XL, so it reads the same in light and dark mode.
struct SizeChip: View {
    let size: TaskSize?

    var body: some View {
        Pill(text: size?.label ?? "–", bold: true,
             foreground: size == nil ? .primary : size == .xl ? .white : .black.opacity(0.82),
             background: size == nil ? .secondary.opacity(0.18) : SizeStyle.color(size))
            .accessibilityLabel(SizeStyle.spoken(size))
    }
}

/// A small capsule label: tags, and the size chip.
struct Pill: View {
    let text: String
    var bold = false
    var foreground = Color.secondary
    var background = Color.secondary.opacity(0.14)

    var body: some View {
        Text(text)
            .font(.caption2.weight(bold ? .bold : .regular))
            .monospaced(bold)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: bold ? 22 : nil)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }
}
