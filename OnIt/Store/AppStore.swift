import Foundation
import Observation

/// Where a moved card lands within its column.
enum InsertPosition: Equatable, Sendable {
    case start, end, before(UUID), after(UUID)
}

enum StoreError: Error, Equatable, LocalizedError {
    case emptyTitle, cannotDeleteDefault, invalidTarget, invalidAlias(String), duplicateAlias(String, board: String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "The task title was empty, so nothing was added."
        case .cannotDeleteDefault: "Make another board the default before deleting this one."
        case .invalidTarget: "Choose a different board to move the tasks to."
        case .invalidAlias(let alias): "“\(alias)” can only use a–z, 0–9, _ and -."
        case .duplicateAlias(let alias, let board): "“\(alias)” is already used by \(board)."
        }
    }
}

/// Owns all data. Every change goes through here, which records undo and schedules a save.
@MainActor @Observable
final class AppStore {
    static let orderStep = 1024.0
    static let boardPalette = ["#5B8DEF", "#A970FF", "#FF6FB1", "#2FB5D2", "#4CAF7A", "#F2A93B", "#8E8E93", "#C0392B"]

    /// Sorted by `sortOrder`.
    private(set) var boards: [Board] = []
    private(set) var tasks: [TaskItem] = []
    private(set) var settings = AppSettings()
    /// Why the data file had to be recovered at launch, shown once.
    var launchIssue: String?

    private struct UndoState: Equatable { var boards: [Board], tasks: [TaskItem] }
    private var undoStack: [UndoState] = []
    private var redoStack: [UndoState] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @ObservationIgnored let persistence: Persistence?
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isDirty = false

    init(snapshot: Snapshot, persistence: Persistence? = nil, clock: @escaping @Sendable () -> Date = { .now }) {
        self.persistence = persistence
        self.clock = clock
        apply(snapshot)
    }

    /// Loads from disk, creating or recovering the file as needed.
    convenience init(persistence: Persistence, clock: @escaping @Sendable () -> Date = { .now }) {
        let (snapshot, recovery) = persistence.load { Snapshot.seed(now: clock()) }
        self.init(snapshot: snapshot, persistence: persistence, clock: clock)
        launchIssue = recovery
        if self.snapshot() != snapshot { markDirty() } // normalising changed something
    }

    func snapshot() -> Snapshot { Snapshot(boards: boards, tasks: tasks, settings: settings) }

    /// Replaces all state, enforcing exactly one default board and no orphaned tasks.
    private func apply(_ snapshot: Snapshot) {
        var boards = snapshot.boards.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        if boards.isEmpty { boards = [Board(name: "Work", aliases: ["work", "w"], colorHex: Self.boardPalette[0])] }
        let defaultID = (boards.first(where: \.isDefault) ?? boards[0]).id
        for index in boards.indices {
            boards[index].isDefault = boards[index].id == defaultID
            boards[index].sortOrder = index
        }
        let ids = Set(boards.map(\.id))
        self.boards = boards
        tasks = snapshot.tasks.map { task in
            var task = task
            if !ids.contains(task.boardId) { task.boardId = defaultID }
            return task
        }
        settings = snapshot.settings
        if let selected = settings.lastSelectedBoardId, !ids.contains(selected) { settings.lastSelectedBoardId = nil }
    }

    // MARK: Queries

    var defaultBoard: Board { boards.first(where: \.isDefault) ?? boards[0] }
    func board(id: UUID?) -> Board? { boards.first { $0.id == id } }
    func task(id: UUID?) -> TaskItem? { tasks.first { $0.id == id } }

    var archivedTasks: [TaskItem] {
        tasks.filter(\.isArchived).sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    /// Non-archived tasks in `column`, optionally limited to one board and a filter, in display order.
    func tasks(in column: Column, boardId: UUID? = nil, filter: TaskFilter = TaskFilter()) -> [TaskItem] {
        tasks.filter { !$0.isArchived && $0.column == column && (boardId == nil || $0.boardId == boardId) && filter.matches($0) }
            .sorted(by: Self.displayOrder)
    }

    static func displayOrder(_ a: TaskItem, _ b: TaskItem) -> Bool { (a.order, a.createdAt) < (b.order, b.createdAt) }

    /// Whether sizes show for a board's cards, or for nil (All), whether any board shows them.
    func showsSizes(boardId: UUID?) -> Bool { boardId.map { board(id: $0)?.showsSizes ?? true } ?? boards.contains(where: \.showsSizes) }
    /// Total size points, skipping tasks on boards with sizes hidden.
    func loadPoints(_ tasks: [TaskItem]) -> Int { tasks.reduce(0) { $0 + (showsSizes(boardId: $1.boardId) ? SizeStyle.points($1.size) : 0) } }

    var allTags: [String] { Set(tasks.filter { !$0.isArchived }.flatMap(\.tags)).sorted() }
    func activeCount(in column: Column) -> Int { tasks.count(where: { !$0.isArchived && $0.column == column }) }

    // MARK: Tasks

    /// Adds a task to the bottom of Todo. Without an `@board` it goes to `preferredBoardId`
    /// (the board being viewed) or the default board. Returns a warning for an unknown `@board`.
    @discardableResult
    func add(text: String, preferredBoardId: UUID? = nil) throws -> (task: TaskItem, board: Board, warning: String?) {
        let parsed = ShorthandParser.parse(text, boards: boards)
        guard !parsed.title.isEmpty else { throw StoreError.emptyTitle }
        let board = board(id: parsed.boardId) ?? board(id: preferredBoardId) ?? defaultBoard
        let task = TaskItem(boardId: board.id, title: parsed.title, size: parsed.size ?? settings.defaultSize,
                            tags: parsed.tags, order: endOrder(in: .todo), createdAt: clock())
        perform { tasks.append(task) }
        return (task, board, parsed.unknownBoardAlias.map { "No board '@\($0)'. Added to \(board.name)." })
    }

    /// Applies shorthand to a task: any remaining text replaces the title, `!size` resizes,
    /// `#tags` are added and `@board` moves it.
    func edit(_ id: UUID, shorthand: String) {
        let parsed = ShorthandParser.parse(shorthand, boards: boards)
        update(id) { task in
            if !parsed.title.isEmpty { task.title = parsed.title }
            task.size = parsed.size ?? task.size
            task.boardId = parsed.boardId ?? task.boardId
            task.tags += parsed.tags.filter { !task.tags.contains($0) }
        }
    }

    /// An undoable change to one task.
    func update(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        perform { change(&tasks[index]) }
    }

    func delete(_ id: UUID) { perform { tasks.removeAll { $0.id == id } } }

    /// Moves a card, keeping fractional orders between its new neighbours.
    func move(_ id: UUID, to column: Column, position: InsertPosition = .end) {
        guard task(id: id) != nil, position != .before(id), position != .after(id) else { return }
        var list = tasks(in: column)
        let currentIndex = list.firstIndex { $0.id == id }
        list.removeAll { $0.id == id }
        let index = switch position {
        case .start: 0
        case .end: list.count
        case .before(let anchor): list.firstIndex { $0.id == anchor } ?? list.count
        case .after(let anchor): list.firstIndex { $0.id == anchor }.map { $0 + 1 } ?? list.count
        }
        guard index != currentIndex else { return } // already there

        let prev = index > 0 ? list[index - 1].order : nil, next = index < list.count ? list[index].order : nil
        let order = switch (prev, next) {
        case let (p?, n?): (p + n) / 2
        case let (p?, nil): p + Self.orderStep
        case let (nil, n?): n - Self.orderStep
        case (nil, nil): Self.orderStep
        }
        let now = clock()
        perform {
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
            Self.applyColumnChange(&tasks[i], to: column, now: now)
            tasks[i].order = order
            // Midpoints eventually run out of precision: respace the column.
            if let p = prev, let n = next, n - p < 1e-6 {
                list.insert(tasks[i], at: index)
                for (offset, task) in list.enumerated() {
                    tasks[tasks.firstIndex { $0.id == task.id }!].order = Double(offset + 1) * Self.orderStep
                }
            }
        }
    }

    static func applyColumnChange(_ task: inout TaskItem, to column: Column, now: Date) {
        if task.column == .done, column != .done { (task.completedAt, task.archivedAt) = (nil, nil) }
        guard task.column != column else { return }
        if column == .doing, task.startedAt == nil { task.startedAt = now }
        if column == .done { task.completedAt = now }
        task.column = column
    }

    /// Restores an archived task to the bottom of Todo.
    func restore(_ id: UUID) { move(id, to: .todo) }

    private func endOrder(in column: Column) -> Double {
        (tasks(in: column).last?.order ?? 0) + Self.orderStep
    }

    /// Archives Done tasks completed more than `archiveAfterDays` ago. Housekeeping, so not undoable.
    @discardableResult
    func sweepArchive(now: Date? = nil) -> [UUID] {
        let now = now ?? clock(), cutoff = now.addingTimeInterval(-Double(settings.archiveAfterDays) * 86_400)
        var archived: [UUID] = []
        for i in tasks.indices where tasks[i].column == .done && !tasks[i].isArchived && (tasks[i].completedAt ?? now) < cutoff {
            tasks[i].archivedAt = now
            archived.append(tasks[i].id)
        }
        if !archived.isEmpty { markDirty() }
        return archived
    }

    // MARK: Boards

    @discardableResult
    func addBoard(name: String = "New Board") -> Board {
        let used = Set(boards.map(\.colorHex))
        let board = Board(name: name, colorHex: Self.boardPalette.first { !used.contains($0) } ?? Self.boardPalette[0],
                          sortOrder: boards.count)
        perform { boards.append(board) }
        return board
    }

    /// A non-undoable board edit (renames happen per keystroke).
    func updateBoard(_ id: UUID, _ change: (inout Board) -> Void) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        perform(undoable: false) { change(&boards[index]) }
    }

    /// Sets a board's aliases from text like "work, w @job". Aliases must be unique across boards,
    /// including other boards' names, since `@name` works too.
    func setAliases(_ text: String, for id: UUID) throws {
        let words = text.split { $0.isWhitespace || $0 == "," }.map { $0.drop { $0 == "@" }.lowercased() }
        if let bad = words.first(where: { !ShorthandParser.isWord($0) }) { throw StoreError.invalidAlias(bad) }
        let aliases = words.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for alias in aliases {
            if let owner = boards.first(where: { $0.id != id && ($0.aliases.contains(alias) || $0.nameSlug == alias) }) {
                throw StoreError.duplicateAlias(alias, board: owner.name)
            }
        }
        updateBoard(id) { $0.aliases = aliases }
    }

    /// Shows or hides sizes on one board, or on every board for nil (All).
    func setShowsSizes(_ on: Bool, boardId: UUID?) {
        perform(undoable: false) { for i in boards.indices where boardId == nil || boards[i].id == boardId { boards[i].showsSizes = on } }
    }

    func setDefaultBoard(_ id: UUID) {
        perform(undoable: false) { for i in boards.indices { boards[i].isDefault = boards[i].id == id } }
    }

    func moveBoards(fromOffsets source: IndexSet, toOffset destination: Int) {
        perform(undoable: false) {
            boards.move(fromOffsets: source, toOffset: destination)
            for i in boards.indices { boards[i].sortOrder = i }
        }
    }

    /// Deletes a board, moving its tasks to `target` or deleting them with it. Undoable.
    func deleteBoard(_ id: UUID, moveTasksTo target: UUID?) throws {
        guard board(id: id)?.isDefault == false else { throw StoreError.cannotDeleteDefault }
        if let target, target == id || board(id: target) == nil { throw StoreError.invalidTarget }
        perform {
            if let target {
                for i in tasks.indices where tasks[i].boardId == id { tasks[i].boardId = target }
            } else {
                tasks.removeAll { $0.boardId == id }
            }
            boards.removeAll { $0.id == id }
            for i in boards.indices { boards[i].sortOrder = i }
        }
        if settings.lastSelectedBoardId == id { updateSettings { $0.lastSelectedBoardId = nil } }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var new = settings
        change(&new)
        new.archiveAfterDays = new.archiveAfterDays.clamped(to: AppSettings.archiveDaysRange)
        guard new != settings else { return }
        let resweep = new.archiveAfterDays != settings.archiveAfterDays
        settings = new
        markDirty()
        if resweep { sweepArchive() }
    }

    func selectBoard(_ id: UUID?) { updateSettings { $0.lastSelectedBoardId = board(id: id)?.id } }

    // MARK: Undo

    func undo() { step(from: &undoStack, to: &redoStack) }
    func redo() { step(from: &redoStack, to: &undoStack) }

    private func step(from source: inout [UndoState], to destination: inout [UndoState]) {
        guard let state = source.popLast() else { return }
        destination.append(UndoState(boards: boards, tasks: tasks))
        (boards, tasks) = (state.boards, state.tasks)
        markDirty()
    }

    /// Runs a change, recording the previous state for undo (capped at 50) if anything changed.
    private func perform(undoable: Bool = true, _ change: () -> Void) {
        let before = UndoState(boards: boards, tasks: tasks)
        change()
        guard before != UndoState(boards: boards, tasks: tasks) else { return }
        if undoable {
            undoStack = Array((undoStack + [before]).suffix(50))
            redoStack = []
        }
        markDirty()
    }

    // MARK: Saving

    private func markDirty() {
        isDirty = true
        guard persistence != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { self?.flush() }
        }
    }

    /// Writes pending changes; `synchronously` waits for the bytes to hit disk (used at quit).
    func flush(synchronously: Bool = false) {
        saveTask?.cancel()
        guard isDirty, let persistence, let data = try? snapshot().encoded() else { return }
        isDirty = false
        persistence.write(data, sync: synchronously)
    }

    func startWatchingFile() {
        persistence?.watch { [weak self] snapshot in Task { @MainActor in self?.replaceAll(with: snapshot, save: false) } }
    }

    /// Replaces everything (an outside edit to the file, or an import). Undo history no longer applies.
    func replaceAll(with snapshot: Snapshot, save: Bool = true) {
        saveTask?.cancel()
        isDirty = false
        apply(snapshot)
        (undoStack, redoStack) = ([], [])
        if save { markDirty() }
        sweepArchive()
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
