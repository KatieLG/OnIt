import AppKit
import SwiftUI

enum FocusField: Hashable { case filter, add, edit }

enum FocusRequest: Equatable {
    case field(FocusField)
    /// Leave any text field so the board gets keyboard navigation.
    case board
}

/// One board surface's transient state: selection, filters, editing. The panel and the main window
/// each have their own; the selected board and Later state are shared settings in the store.
@MainActor @Observable
final class BoardUIState {
    let store: AppStore
    var filter = TaskFilter()
    var selectedTaskId: UUID?
    var editingTaskId: UUID?
    var editText = ""
    var addText = ""
    var addFeedback: String?
    var tagEditingTaskId: UUID?
    var tagEditText = ""
    /// Mirrors the view's `@FocusState`, kept in sync by `RootView`.
    var focus: FocusField?
    /// Asks `RootView` to move focus; cleared once handled.
    var focusRequest: FocusRequest?
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?

    init(store: AppStore) { self.store = store }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var cardAnimation: Animation? { reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.15) }
    func animate(_ change: () -> Void) { withAnimation(Self.cardAnimation, change) }

    // MARK: Boards and cards

    /// nil means All.
    var selectedBoardId: UUID? { store.board(id: store.settings.lastSelectedBoardId)?.id }
    var visibleColumns: [Column] { Column.allCases.filter { $0 != .later || store.settings.laterExpanded } }
    var selectedTask: TaskItem? { store.task(id: selectedTaskId).flatMap { $0.isArchived ? nil : $0 } }

    func visibleTasks(in column: Column) -> [TaskItem] {
        store.tasks(in: column, boardId: selectedBoardId, filter: filter)
    }

    func selectBoard(_ id: UUID?) {
        store.selectBoard(id)
        if let task = selectedTask, position(of: task) == nil { selectedTaskId = nil }
    }

    /// ⌘1 is All, ⌘2… the boards in order.
    func selectBoard(atShortcutIndex index: Int) {
        if index == 1 { selectBoard(nil) } else if store.boards.indices.contains(index - 2) { selectBoard(store.boards[index - 2].id) }
    }

    private func position(of task: TaskItem) -> (list: [TaskItem], index: Int)? {
        let list = visibleTasks(in: task.column)
        return list.firstIndex { $0.id == task.id }.map { (list, $0) }
    }

    /// Handles a card dropped on a column (or the Later strip). Strings that aren't card IDs are ignored.
    func drop(_ items: [String], in column: Column, at position: InsertPosition = .end) -> Bool {
        guard let id = items.lazy.compactMap(UUID.init(uuidString:)).first, store.task(id: id) != nil else { return false }
        animate { store.move(id, to: column, position: position) }
        selectedTaskId = id
        return true
    }

    // MARK: Adding and editing

    func submitAdd() {
        guard !addText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let added = try withAnimation(Self.cardAnimation) { try store.add(text: addText, preferredBoardId: selectedBoardId) }
            addText = ""
            selectedTaskId = added.task.id
            showFeedback(added.warning)
        } catch {
            showFeedback(error.localizedDescription)
        }
    }

    private func showFeedback(_ message: String?) {
        addFeedback = message
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { addFeedback = nil }
        }
    }

    func beginEdit(_ id: UUID) {
        guard let task = store.task(id: id) else { return }
        (selectedTaskId, editingTaskId) = (id, id)
        editText = ShorthandParser.escapeForEditing(task.title, boards: store.boards)
        focusRequest = .field(.edit)
    }

    /// Saves the inline edit if the text changed.
    func commitEdit() {
        guard let id = editingTaskId else { return }
        editingTaskId = nil
        if let task = store.task(id: id), editText != ShorthandParser.escapeForEditing(task.title, boards: store.boards) {
            store.edit(id, shorthand: editText)
        }
        focusRequest = .board
    }

    func cancelEdit() {
        editingTaskId = nil
        focusRequest = .board
    }

    func beginTagEdit(_ id: UUID) {
        tagEditText = store.task(id: id)?.tags.map { "#\($0)" }.joined(separator: " ") ?? ""
        tagEditingTaskId = id
    }

    func commitTagEdit() {
        let tags = ShorthandParser.normaliseTags(tagEditText)
        if let id = tagEditingTaskId { store.update(id) { $0.tags = tags } }
        tagEditingTaskId = nil
    }

    // MARK: Keyboard actions

    func toggleLater() {
        store.updateSettings { $0.laterExpanded.toggle() }
        if !store.settings.laterExpanded, selectedTask?.column == .later { selectedTaskId = nil }
    }

    /// ↑ / ↓ within the column.
    func moveSelection(by delta: Int) {
        guard let task = selectedTask, let pos = position(of: task) else { return selectFirst() }
        selectedTaskId = pos.list[(pos.index + delta).clamped(to: 0...pos.list.count - 1)].id
    }

    /// ← / →: the nearest non-empty column that way, keeping the row where possible.
    func moveSelectionToAdjacentColumn(_ delta: Int) {
        guard let task = selectedTask, let pos = position(of: task), var c = visibleColumns.firstIndex(of: task.column) else {
            return selectFirst()
        }
        while visibleColumns.indices.contains(c + delta) {
            c += delta
            let list = visibleTasks(in: visibleColumns[c])
            if !list.isEmpty { return selectedTaskId = list[min(pos.index, list.count - 1)].id }
        }
    }

    private func selectFirst() {
        selectedTaskId = visibleColumns.lazy.compactMap { self.visibleTasks(in: $0).first }.first?.id
    }

    /// ⌘← / ⌘→
    func moveSelectedToAdjacentColumn(_ delta: Int) {
        guard let task = selectedTask, let target = delta < 0 ? task.column.previous : task.column.next else { return }
        animate { store.move(task.id, to: target) }
    }

    /// ⌘↑ / ⌘↓, past the neighbouring visible card.
    func reorderSelected(_ delta: Int) {
        guard let task = selectedTask, let pos = position(of: task), pos.list.indices.contains(pos.index + delta) else { return }
        let neighbour = pos.list[pos.index + delta].id
        animate { store.move(task.id, to: task.column, position: delta < 0 ? .before(neighbour) : .after(neighbour)) }
    }

    func setSizeOnSelected(_ size: TaskSize?) {
        if let id = selectedTask?.id { store.update(id) { $0.size = size } }
    }

    func editSelected() {
        if let id = selectedTask?.id { beginEdit(id) }
    }

    func deleteSelected() {
        guard let task = selectedTask, let pos = position(of: task) else { return }
        animate { store.delete(task.id) }
        let rest = visibleTasks(in: task.column)
        selectedTaskId = rest.isEmpty ? nil : rest[min(pos.index, rest.count - 1)].id
    }

    func undo() { animate(store.undo) }
    func redo() { animate(store.redo) }

    /// Esc clears filters, else cancels an edit, else leaves the text field. False if there was nothing to do.
    func handleEscape() -> Bool {
        if filter.isActive {
            filter = TaskFilter()
        } else if editingTaskId != nil {
            cancelEdit()
        } else if let focus {
            if focus == .add { addText = "" }
            focusRequest = .board
        } else {
            return false
        }
        return true
    }
}
