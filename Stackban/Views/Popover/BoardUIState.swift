import AppKit
import SwiftUI

/// Which text field in the popover has focus.
enum FocusField: Hashable {
    case filter
    case add
    case edit
}

enum FocusRequest: Equatable {
    case field(FocusField)
    /// Resign any text field so the board receives keyboard navigation.
    case board
}

/// Transient UI state for the popover (selection, filters, editing). Not persisted, except the
/// selected board and Later state, which live in `AppSettings` via the store.
@MainActor
@Observable
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

    /// Mirror of the view's `@FocusState`, kept in sync by `RootView`.
    var focus: FocusField?
    /// Set to ask `RootView` to move focus; it clears this once handled.
    var focusRequest: FocusRequest?

    @ObservationIgnored var closePanel: () -> Void = {}
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?

    init(store: AppStore) {
        self.store = store
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The standard card animation, or none when Reduce Motion is on.
    static var cardAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.15)
    }

    // MARK: Board selection

    /// nil = All boards.
    var selectedBoardId: UUID? {
        store.board(id: store.settings.lastSelectedBoardId)?.id
    }

    var isAllView: Bool { selectedBoardId == nil }

    func selectBoard(_ id: UUID?) {
        store.selectBoard(id)
        if let selected = selectedTaskId, !visibleTasks(in: store.task(id: selected)?.column ?? .todo).contains(where: { $0.id == selected }) {
            selectedTaskId = nil
        }
    }

    /// ⌘1 = All, ⌘2… = boards in order.
    func selectBoard(atShortcutIndex index: Int) {
        if index == 1 {
            selectBoard(nil)
        } else if index - 2 < store.boards.count {
            selectBoard(store.boards[index - 2].id)
        }
    }

    // MARK: Visible data

    var visibleColumns: [Column] {
        store.settings.laterExpanded ? Column.allCases : [.todo, .doing, .done]
    }

    func visibleTasks(in column: Column) -> [TaskItem] {
        store.tasks(in: column, boardId: selectedBoardId, filter: filter)
    }

    var selectedTask: TaskItem? {
        guard let task = store.task(id: selectedTaskId), !task.isArchived else { return nil }
        return task
    }

    // MARK: Filters

    func clearFilters() {
        filter = TaskFilter()
    }

    func toggleSizeFilter(_ size: TaskSize?) {
        if filter.sizes.contains(size) { filter.sizes.remove(size) } else { filter.sizes.insert(size) }
    }

    func toggleTagFilter(_ tag: String) {
        if filter.tags.contains(tag) { filter.tags.remove(tag) } else { filter.tags.insert(tag) }
    }

    // MARK: Adding

    func submitAdd() {
        let text = addText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let result = withAnimation(Self.cardAnimation) {
            store.add(text: text, preferredBoardId: selectedBoardId)
        }
        switch result {
        case .added(let task, _):
            addText = ""
            selectedTaskId = task.id
            showAddFeedback(nil)
        case .addedWithWarning(let task, _, let message):
            addText = ""
            selectedTaskId = task.id
            showAddFeedback(message)
        case .rejected(let reason):
            showAddFeedback(reason.message)
        }
    }

    private func showAddFeedback(_ message: String?) {
        feedbackTask?.cancel()
        addFeedback = message
        guard message != nil else { return }
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.addFeedback = nil
        }
    }

    // MARK: Editing

    func beginEdit(_ id: UUID) {
        guard let task = store.task(id: id) else { return }
        selectedTaskId = id
        editText = ShorthandParser.escapeForEditing(task.title, knownBoards: store.aliasEntries)
        editingTaskId = id
        focusRequest = .field(.edit)
    }

    func commitEdit() {
        guard let id = editingTaskId else { return }
        editingTaskId = nil
        let text = editText
        if let task = store.task(id: id),
           text != ShorthandParser.escapeForEditing(task.title, knownBoards: store.aliasEntries) {
            store.editTitle(id, shorthand: text)
        }
        focusRequest = .board
    }

    func cancelEdit() {
        editingTaskId = nil
        focusRequest = .board
    }

    func beginTagEdit(_ id: UUID) {
        guard let task = store.task(id: id) else { return }
        tagEditText = task.tags.map { "#\($0)" }.joined(separator: " ")
        tagEditingTaskId = id
    }

    func commitTagEdit() {
        guard let id = tagEditingTaskId else { return }
        store.setTags(id, ShorthandParser.normaliseTags(tagEditText))
        tagEditingTaskId = nil
    }

    // MARK: Keyboard actions

    func toggleLater() {
        store.updateSettings { $0.laterExpanded.toggle() }
        if !store.settings.laterExpanded, selectedTask?.column == .later {
            selectedTaskId = nil
        }
    }

    /// ↑ / ↓
    func moveSelection(by delta: Int) {
        guard let task = selectedTask else {
            selectFirstAvailable()
            return
        }
        let list = visibleTasks(in: task.column)
        guard let index = list.firstIndex(where: { $0.id == task.id }) else {
            selectFirstAvailable()
            return
        }
        let target = min(max(index + delta, 0), list.count - 1)
        selectedTaskId = list[target].id
    }

    /// ← / →: jumps to the nearest non-empty column in that direction, keeping the row if possible.
    func moveSelectionToAdjacentColumn(_ delta: Int) {
        guard let task = selectedTask else {
            selectFirstAvailable()
            return
        }
        let columns = visibleColumns
        guard var columnIndex = columns.firstIndex(of: task.column) else { return }
        let row = visibleTasks(in: task.column).firstIndex(where: { $0.id == task.id }) ?? 0
        while true {
            columnIndex += delta
            guard columns.indices.contains(columnIndex) else { return }
            let list = visibleTasks(in: columns[columnIndex])
            if !list.isEmpty {
                selectedTaskId = list[min(row, list.count - 1)].id
                return
            }
        }
    }

    private func selectFirstAvailable() {
        for column in visibleColumns {
            if let first = visibleTasks(in: column).first {
                selectedTaskId = first.id
                return
            }
        }
    }

    /// ⌘← / ⌘→
    func moveSelectedToAdjacentColumn(_ delta: Int) {
        guard let task = selectedTask else { return }
        let target = delta < 0 ? task.column.previous : task.column.next
        guard let target else { return }
        withAnimation(Self.cardAnimation) {
            store.move(task.id, to: target, position: .end)
        }
    }

    /// ⌘↑ / ⌘↓, relative to the visible (filtered) neighbours.
    func reorderSelected(_ delta: Int) {
        guard let task = selectedTask else { return }
        let list = visibleTasks(in: task.column)
        guard let index = list.firstIndex(where: { $0.id == task.id }) else { return }
        let targetIndex = index + delta
        guard list.indices.contains(targetIndex) else { return }
        let neighbour = list[targetIndex].id
        withAnimation(Self.cardAnimation) {
            store.move(task.id, to: task.column, position: delta < 0 ? .before(neighbour) : .after(neighbour))
        }
    }

    func setSizeOnSelected(_ size: TaskSize?) {
        guard let task = selectedTask else { return }
        store.setSize(task.id, size)
    }

    func editSelected() {
        guard let task = selectedTask else { return }
        beginEdit(task.id)
    }

    func deleteSelected() {
        guard let task = selectedTask else { return }
        let column = task.column
        let list = visibleTasks(in: column)
        let index = list.firstIndex(where: { $0.id == task.id }) ?? 0
        withAnimation(Self.cardAnimation) {
            store.delete(task.id)
        }
        let remaining = visibleTasks(in: column)
        selectedTaskId = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    func undo() {
        withAnimation(Self.cardAnimation) { store.undo() }
    }

    func redo() {
        withAnimation(Self.cardAnimation) { store.redo() }
    }

    /// Esc priority: clear filter → cancel edit → leave a text field → close the popover.
    /// Returns false when the popover should close.
    func handleEscape() -> Bool {
        if filter.isActive {
            clearFilters()
            return true
        }
        if editingTaskId != nil {
            cancelEdit()
            return true
        }
        if focus != nil {
            if focus == .add { addText = "" }
            focusRequest = .board
            return true
        }
        return false
    }
}
