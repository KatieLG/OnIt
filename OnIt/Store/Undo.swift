import Foundation

/// The part of the state that undo/redo covers. Settings are deliberately excluded.
struct UndoState: Equatable, Sendable {
    var boards: [Board]
    var tasks: [TaskItem]
}

/// One undoable change, stored as the states either side of it. Applying `before` is the
/// inverse operation; applying `after` redoes it.
struct UndoEntry: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let before: UndoState
    let after: UndoState
}

/// In-memory undo/redo history, capped at `limit` entries.
struct UndoStack: Sendable {
    static let limit = 50

    private(set) var undoEntries: [UndoEntry] = []
    private(set) var redoEntries: [UndoEntry] = []

    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }
    var topUndoID: UUID? { undoEntries.last?.id }

    mutating func record(_ entry: UndoEntry) {
        undoEntries.append(entry)
        if undoEntries.count > Self.limit {
            undoEntries.removeFirst(undoEntries.count - Self.limit)
        }
        redoEntries.removeAll()
    }

    mutating func popUndo() -> UndoEntry? {
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(entry)
        return entry
    }

    mutating func popRedo() -> UndoEntry? {
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(entry)
        return entry
    }

    mutating func clear() {
        undoEntries.removeAll()
        redoEntries.removeAll()
    }
}
