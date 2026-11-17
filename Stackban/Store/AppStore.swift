import Foundation
import Observation
import os

/// Where a moved card lands within its column.
enum InsertPosition: Equatable, Sendable {
    case end
    case start
    case before(UUID)
    case after(UUID)
}

enum AddRejection: Equatable, Sendable {
    case emptyTitle
    case noBoard

    var message: String {
        switch self {
        case .emptyTitle: "The task title was empty, so nothing was added."
        case .noBoard: "There is no board to add the task to."
        }
    }
}

enum AddResult: Equatable, Sendable {
    case added(TaskItem, Board)
    case addedWithWarning(TaskItem, Board, String)
    case rejected(AddRejection)

    var task: TaskItem? {
        switch self {
        case .added(let task, _), .addedWithWarning(let task, _, _): task
        case .rejected: nil
        }
    }
}

enum BoardDeletion: Equatable, Sendable {
    case moveTasks(to: UUID)
    case deleteTasks
}

enum BoardError: Error, Equatable, LocalizedError {
    case notFound
    case cannotDeleteDefault
    case invalidTarget

    var errorDescription: String? {
        switch self {
        case .notFound: "That board no longer exists."
        case .cannotDeleteDefault: "Make another board the default before deleting this one."
        case .invalidTarget: "Choose a different board to move the tasks to."
        }
    }
}

enum AliasError: Error, Equatable, LocalizedError {
    case empty
    case invalidCharacters
    case duplicate(boardName: String)

    var errorDescription: String? {
        switch self {
        case .empty: "Aliases can't be empty."
        case .invalidCharacters: "Aliases may only contain a–z, 0–9, _ and -."
        case .duplicate(let name): "That alias is already used by \(name)."
        }
    }
}

/// Owns all app data. Every mutation goes through here; it schedules the debounced save.
@MainActor
@Observable
final class AppStore {
    static let orderStep: Double = 1024
    static let orderEpsilon: Double = 1e-6
    static let saveDebounce: Duration = .milliseconds(300)

    static let boardPalette: [String] = [
        "#5B8DEF", "#A970FF", "#FF6FB1", "#2FB5D2", "#4CAF7A", "#F2A93B", "#8E8E93", "#C0392B",
    ]

    /// Sorted by `sortOrder`.
    private(set) var boards: [Board] = []
    private(set) var tasks: [TaskItem] = []
    private(set) var settings = AppSettings()
    /// A problem found while loading (for example a corrupt file), shown once at launch.
    var launchIssue: String?

    private var undoStack = UndoStack()
    var canUndo: Bool { undoStack.canUndo }
    var canRedo: Bool { undoStack.canRedo }

    @ObservationIgnored let persistence: Persistence?
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private(set) var isDirty = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.example.stackban", category: "store")

    init(snapshot: Snapshot, persistence: Persistence? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.persistence = persistence
        self.clock = clock
        apply(snapshot)
    }

    /// Loads from disk (creating or recovering the file as needed).
    convenience init(persistence: Persistence, clock: @escaping @Sendable () -> Date = { Date() }) {
        let outcome = persistence.load(seed: { Snapshot.seed(now: clock()) })
        self.init(snapshot: outcome.snapshot, persistence: persistence, clock: clock)
        if case .recovered(_, let corrupt, let backup) = outcome {
            if let backup {
                launchIssue = """
                Stackban's data file couldn't be read, so it was restored from \(backup.lastPathComponent). \
                The unreadable file was kept as \(corrupt.lastPathComponent) in the same folder.
                """
            } else {
                launchIssue = """
                Stackban's data file couldn't be read and no valid backup was found, so Stackban started fresh. \
                The unreadable file was kept as \(corrupt.lastPathComponent) in the same folder.
                """
            }
        }
        // A recovered or normalised snapshot may differ from the file; make sure it's written.
        if (try? snapshot().encoded()) != (try? outcome.snapshot.encoded()) {
            markDirty()
        }
    }

    // MARK: Snapshot

    func snapshot() -> Snapshot {
        Snapshot(boards: boards, tasks: tasks, settings: settings)
    }

    /// Replaces all state, normalising invariants (exactly one default board, no orphan tasks).
    private func apply(_ snapshot: Snapshot) {
        var boards = snapshot.boards.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        if boards.isEmpty {
            boards = [Board(name: "Internal", aliases: ["int", "i"], colorHex: Self.boardPalette[0], isDefault: true)]
        }
        let defaults = boards.indices.filter { boards[$0].isDefault }
        if defaults.isEmpty {
            boards[0].isDefault = true
        } else {
            for index in defaults.dropFirst() { boards[index].isDefault = false }
        }
        for index in boards.indices { boards[index].sortOrder = index }

        let boardIDs = Set(boards.map(\.id))
        let fallbackID = boards.first(where: \.isDefault)!.id
        let tasks = snapshot.tasks.map { task -> TaskItem in
            guard !boardIDs.contains(task.boardId) else { return task }
            var task = task
            task.boardId = fallbackID
            return task
        }

        self.boards = boards
        self.tasks = tasks
        var settings = snapshot.settings
        if let selected = settings.lastSelectedBoardId, !boardIDs.contains(selected) {
            settings.lastSelectedBoardId = nil
        }
        self.settings = settings
    }

    // MARK: Lookup and derived data

    var defaultBoard: Board? { boards.first(where: \.isDefault) ?? boards.first }

    func board(id: UUID?) -> Board? {
        guard let id else { return nil }
        return boards.first { $0.id == id }
    }

    func task(id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    var aliasEntries: [BoardAliasEntry] { boards.map(BoardAliasEntry.init(board:)) }

    var archivedTasks: [TaskItem] {
        tasks.filter(\.isArchived).sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    /// Non-archived tasks in `column`, optionally restricted to one board and a filter, in display order.
    func tasks(in column: Column, boardId: UUID? = nil, filter: TaskFilter = TaskFilter()) -> [TaskItem] {
        tasks.filter { task in
            !task.isArchived
                && task.column == column
                && (boardId == nil || task.boardId == boardId)
                && filter.matches(task)
        }
        .sorted(by: Self.displayOrder)
    }

    static func displayOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.order != b.order { return a.order < b.order }
        return a.createdAt < b.createdAt
    }

    static func loadPoints(_ tasks: [TaskItem]) -> Int {
        tasks.reduce(0) { $0 + SizeStyle.points(for: $1.size) }
    }

    /// Every tag on a non-archived task, sorted.
    var allTags: [String] {
        Array(Set(tasks.lazy.filter { !$0.isArchived }.flatMap(\.tags))).sorted()
    }

    func activeCount(in column: Column) -> Int {
        tasks.reduce(0) { $0 + ((!$1.isArchived && $1.column == column) ? 1 : 0) }
    }

    func taskCount(onBoard boardId: UUID) -> Int {
        tasks.reduce(0) { $0 + ($1.boardId == boardId ? 1 : 0) }
    }

    // MARK: Adding

    func add(text: String, preferredBoardId: UUID? = nil) -> AddResult {
        add(parsed: ShorthandParser.parse(text, knownBoards: aliasEntries), preferredBoardId: preferredBoardId)
    }

    /// Adds a parsed task at the bottom of Todo. Without an `@board`, it goes to
    /// `preferredBoardId` (the board being viewed) or the default board.
    func add(parsed: ParsedTask, preferredBoardId: UUID? = nil) -> AddResult {
        guard !parsed.title.isEmpty else { return .rejected(.emptyTitle) }
        guard let fallback = board(id: preferredBoardId) ?? defaultBoard else { return .rejected(.noBoard) }
        let target = board(id: parsed.boardId) ?? fallback

        let task = TaskItem(
            boardId: target.id,
            title: parsed.title,
            size: parsed.size ?? settings.defaultSize,
            column: .todo,
            tags: parsed.tags,
            order: endOrder(in: .todo),
            createdAt: clock()
        )
        perform("Add Task") { tasks.append(task) }

        if let unknown = parsed.unknownBoardAlias {
            return .addedWithWarning(task, target, "No board '@\(unknown)'. Added to \(target.name).")
        }
        return .added(task, target)
    }

    // MARK: Editing tasks

    /// Applies shorthand to an existing task: the remaining text replaces the title (if any),
    /// `!size` sets the size, `#tags` are added and `@board` moves it.
    /// Returns a warning message if an `@alias` was unknown.
    @discardableResult
    func editTitle(_ id: UUID, shorthand text: String) -> String? {
        let parsed = ShorthandParser.parse(text, knownBoards: aliasEntries)
        perform("Edit Task") {
            updateTask(id) { task in
                if !parsed.title.isEmpty { task.title = parsed.title }
                if let size = parsed.size { task.size = size }
                for tag in parsed.tags where !task.tags.contains(tag) { task.tags.append(tag) }
                if let boardId = parsed.boardId { task.boardId = boardId }
            }
        }
        return parsed.unknownBoardAlias.map { "No board '@\($0)'." }
    }

    func setSize(_ id: UUID, _ size: TaskSize?) {
        perform("Set Size") { updateTask(id) { $0.size = size } }
    }

    func setBoard(_ id: UUID, boardId: UUID) {
        guard board(id: boardId) != nil else { return }
        perform("Change Board") { updateTask(id) { $0.boardId = boardId } }
    }

    func setTags(_ id: UUID, _ tags: [String]) {
        let normalised = ShorthandParser.normaliseTags(tags.joined(separator: " "))
        perform("Edit Tags") { updateTask(id) { $0.tags = normalised } }
    }

    func delete(_ id: UUID) {
        perform("Delete Task") { tasks.removeAll { $0.id == id } }
    }

    /// Restores an archived task to the bottom of Todo.
    func restore(_ id: UUID) {
        move(id, to: .todo, position: .end)
    }

    // MARK: Moving

    func move(_ id: UUID, to column: Column, position: InsertPosition = .end) {
        guard let current = task(id: id) else { return }
        if case .before(let anchor) = position, anchor == id { return }
        if case .after(let anchor) = position, anchor == id { return }

        let others = tasks
            .filter { !$0.isArchived && $0.column == column && $0.id != id }
            .sorted(by: Self.displayOrder)

        let insertIndex: Int
        switch position {
        case .end:
            insertIndex = others.count
        case .start:
            insertIndex = 0
        case .before(let anchor):
            insertIndex = others.firstIndex { $0.id == anchor } ?? others.count
        case .after(let anchor):
            insertIndex = others.firstIndex { $0.id == anchor }.map { $0 + 1 } ?? others.count
        }

        // Dropping a card where it already is: nothing to do.
        if current.column == column, !current.isArchived {
            let full = tasks.filter { !$0.isArchived && $0.column == column }.sorted(by: Self.displayOrder)
            if full.firstIndex(where: { $0.id == id }) == insertIndex { return }
        }

        let prev = insertIndex > 0 ? others[insertIndex - 1].order : nil
        let next = insertIndex < others.count ? others[insertIndex].order : nil
        let newOrder: Double
        var needsRenormalise = false
        switch (prev, next) {
        case (nil, nil): newOrder = Self.orderStep
        case (let p?, nil): newOrder = p + Self.orderStep
        case (nil, let n?): newOrder = n - Self.orderStep
        case (let p?, let n?):
            newOrder = (p + n) / 2
            needsRenormalise = (n - p) < Self.orderEpsilon * 2
        }

        let now = clock()
        perform(current.column == column ? "Reorder" : "Move to \(column.title)") {
            updateTask(id) { task in
                Self.applyColumnChange(&task, to: column, now: now)
                task.order = newOrder
            }
            if needsRenormalise {
                var ordered = others
                if let moved = self.task(id: id) { ordered.insert(moved, at: insertIndex) }
                renormalise(ordered.map(\.id))
            }
        }
    }

    /// Timestamp rules for column transitions (spec §6).
    static func applyColumnChange(_ task: inout TaskItem, to column: Column, now: Date) {
        if task.column == .done, column != .done {
            task.completedAt = nil
            task.archivedAt = nil
        }
        guard task.column != column else { return }
        if column == .doing, task.startedAt == nil { task.startedAt = now }
        if column == .done { task.completedAt = now }
        task.column = column
    }

    /// Reassigns evenly spaced orders to the given IDs, in sequence.
    private func renormalise(_ ids: [UUID]) {
        for (offset, id) in ids.enumerated() {
            if let index = tasks.firstIndex(where: { $0.id == id }) {
                tasks[index].order = Double(offset + 1) * Self.orderStep
            }
        }
    }

    private func endOrder(in column: Column) -> Double {
        let maxOrder = tasks.lazy.filter { !$0.isArchived && $0.column == column }.map(\.order).max()
        return (maxOrder ?? 0) + Self.orderStep
    }

    // MARK: Archive

    /// Archives Done tasks older than `archiveAfterDays`. Not undoable (it's housekeeping).
    @discardableResult
    func sweepArchive(now: Date? = nil) -> [UUID] {
        let result = ArchiveSweeper.sweep(tasks, now: now ?? clock(), archiveAfterDays: settings.archiveAfterDays)
        guard !result.archived.isEmpty else { return [] }
        tasks = result.tasks
        markDirty()
        return result.archived
    }

    // MARK: Boards

    @discardableResult
    func addBoard(name: String = "New Board") -> Board {
        let used = Set(boards.map(\.colorHex))
        let color = Self.boardPalette.first { !used.contains($0) } ?? Self.boardPalette[boards.count % Self.boardPalette.count]
        let board = Board(name: name, aliases: [], colorHex: color, isDefault: boards.isEmpty, sortOrder: boards.count)
        perform("Add Board") { boards.append(board) }
        return board
    }

    func renameBoard(_ id: UUID, to name: String) {
        perform("Rename Board", undoable: false) { updateBoard(id) { $0.name = name } }
    }

    func setBoardColor(_ id: UUID, hex: String) {
        perform("Board Colour", undoable: false) { updateBoard(id) { $0.colorHex = hex } }
    }

    /// Returns nil if `alias` may be added to the board, otherwise why not.
    func validateAlias(_ alias: String, for boardId: UUID) -> AliasError? {
        let alias = alias.trimmingCharacters(in: .whitespaces).lowercased()
        guard !alias.isEmpty else { return .empty }
        guard ShorthandParser.isValidStoredAlias(alias) else { return .invalidCharacters }
        if let owner = boards.first(where: { $0.id != boardId && ($0.aliases.contains(alias) || $0.nameSlug == alias) }) {
            return .duplicate(boardName: owner.name)
        }
        return nil
    }

    @discardableResult
    func addAlias(_ alias: String, to boardId: UUID) -> AliasError? {
        if let error = validateAlias(alias, for: boardId) { return error }
        let alias = alias.trimmingCharacters(in: .whitespaces).lowercased()
        perform("Add Alias", undoable: false) {
            updateBoard(boardId) { board in
                if !board.aliases.contains(alias) { board.aliases.append(alias) }
            }
        }
        return nil
    }

    func removeAlias(_ alias: String, from boardId: UUID) {
        perform("Remove Alias", undoable: false) {
            updateBoard(boardId) { $0.aliases.removeAll { $0 == alias } }
        }
    }

    func setDefaultBoard(_ id: UUID) {
        guard board(id: id) != nil else { return }
        perform("Default Board", undoable: false) {
            for index in boards.indices { boards[index].isDefault = boards[index].id == id }
        }
    }

    func moveBoards(fromOffsets source: IndexSet, toOffset destination: Int) {
        perform("Reorder Boards", undoable: false) {
            boards.move(fromOffsets: source, toOffset: destination)
            for index in boards.indices { boards[index].sortOrder = index }
        }
    }

    /// Deletes a board, moving or deleting its tasks. Undoable.
    /// Returns the undo entry ID so a caller can offer a scoped "Undo" button.
    @discardableResult
    func deleteBoard(_ id: UUID, tasks disposition: BoardDeletion) throws -> UUID? {
        guard let board = board(id: id) else { throw BoardError.notFound }
        guard !board.isDefault else { throw BoardError.cannotDeleteDefault }
        if case .moveTasks(let target) = disposition, target == id || self.board(id: target) == nil {
            throw BoardError.invalidTarget
        }
        let now = clock()
        perform("Delete Board") {
            switch disposition {
            case .moveTasks(let target):
                for index in tasks.indices where tasks[index].boardId == id {
                    tasks[index].boardId = target
                    tasks[index].updatedAt = now
                }
            case .deleteTasks:
                tasks.removeAll { $0.boardId == id }
            }
            boards.removeAll { $0.id == id }
            for index in boards.indices { boards[index].sortOrder = index }
        }
        if settings.lastSelectedBoardId == id {
            updateSettings { $0.lastSelectedBoardId = nil }
        }
        return undoStack.topUndoID
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        copy.archiveAfterDays = min(max(copy.archiveAfterDays, AppSettings.archiveDaysRange.lowerBound),
                                    AppSettings.archiveDaysRange.upperBound)
        guard copy != settings else { return }
        let archiveChanged = copy.archiveAfterDays != settings.archiveAfterDays
        settings = copy
        markDirty()
        if archiveChanged { sweepArchive() }
    }

    func selectBoard(_ id: UUID?) {
        updateSettings { $0.lastSelectedBoardId = board(id: id)?.id }
    }

    // MARK: Undo

    func undo() {
        guard let entry = undoStack.popUndo() else { return }
        restore(entry.before)
    }

    func redo() {
        guard let entry = undoStack.popRedo() else { return }
        restore(entry.after)
    }

    /// Undoes only if `entryID` is still the most recent change (used by "Undo" banners).
    func undo(ifTop entryID: UUID) -> Bool {
        guard undoStack.topUndoID == entryID else { return false }
        undo()
        return true
    }

    var undoLabel: String? { undoStack.undoEntries.last?.label }
    var redoLabel: String? { undoStack.redoEntries.last?.label }

    private func restore(_ state: UndoState) {
        boards = state.boards
        tasks = state.tasks
        markDirty()
    }

    // MARK: Mutation plumbing

    private func perform(_ label: String, undoable: Bool = true, _ change: () -> Void) {
        let before = UndoState(boards: boards, tasks: tasks)
        change()
        let after = UndoState(boards: boards, tasks: tasks)
        guard before != after else { return }
        if undoable {
            undoStack.record(UndoEntry(label: label, before: before, after: after))
        }
        markDirty()
    }

    private func updateTask(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = tasks[index]
        change(&task)
        guard task != tasks[index] else { return }
        task.updatedAt = clock()
        tasks[index] = task
    }

    private func updateBoard(_ id: UUID, _ change: (inout Board) -> Void) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        change(&boards[index])
    }

    // MARK: Persistence

    private func markDirty() {
        isDirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        guard persistence != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes pending changes now. `synchronously` blocks until the bytes are on disk (termination).
    func flush(synchronously: Bool = false) {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, let persistence else { return }
        do {
            let data = try snapshot().encoded()
            isDirty = false
            if synchronously {
                persistence.writeSync(data)
            } else {
                persistence.write(data)
            }
        } catch {
            logger.error("Encoding failed: \(error.localizedDescription)")
        }
    }

    /// Starts watching the data file for external edits.
    func startWatchingFile() {
        persistence?.startWatching { [weak self] snapshot in
            Task { @MainActor in self?.applyExternalChange(snapshot) }
        }
    }

    /// External edits win over any unsaved in-app change; undo history no longer applies.
    func applyExternalChange(_ snapshot: Snapshot) {
        saveTask?.cancel()
        saveTask = nil
        isDirty = false
        apply(snapshot)
        undoStack.clear()
        sweepArchive()
    }

    /// Replaces everything with imported data (after the caller has made a backup).
    func replaceAll(with snapshot: Snapshot) {
        apply(snapshot)
        undoStack.clear()
        markDirty()
        flush()
    }

    func exportData() throws -> Data {
        try snapshot().encoded()
    }
}
