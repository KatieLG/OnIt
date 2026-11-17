import Foundation
import Testing
@testable import OnIt

@MainActor
struct StoreTests {
    let clock = TestClock()
    let store: AppStore
    let internalBoard: Board
    let client: Board

    init() {
        let seed = Snapshot.seed(now: clock.now)
        store = AppStore(snapshot: Snapshot(boards: seed.boards, tasks: []), clock: clock.closure)
        internalBoard = store.boards[0]
        client = store.boards[1]
    }

    @discardableResult
    func add(_ text: String) -> TaskItem {
        store.add(text: text).task!
    }

    func todoTitles(_ column: Column = .todo) -> [String] {
        store.tasks(in: column).map(\.title)
    }

    // MARK: Seed

    @Test func seedHasTwoBoardsAndWelcomeCard() {
        let seed = Snapshot.seed()
        #expect(seed.boards.map(\.name) == ["Internal", "Client"])
        #expect(seed.boards[0].isDefault)
        #expect(seed.boards[0].aliases == ["int", "i"])
        #expect(seed.boards[1].aliases == ["client", "c"])
        #expect(seed.tasks.count == 1)
        #expect(seed.tasks[0].column == .todo)
        #expect(seed.tasks[0].boardId == seed.boards[0].id)
    }

    // MARK: Adding

    @Test func addParsesShorthand() {
        let result = store.add(text: "Draft proposal @c !L #sales")
        guard case .added(let task, let board) = result else {
            Issue.record("expected .added, got \(result)")
            return
        }
        #expect(board.id == client.id)
        #expect(task.title == "Draft proposal")
        #expect(task.size == .l)
        #expect(task.tags == ["sales"])
        #expect(task.column == .todo)
        #expect(task.createdAt == clock.now)
    }

    @Test func addWithoutBoardUsesDefaultOrPreferred() {
        #expect(store.add(text: "a").task?.boardId == internalBoard.id)
        #expect(store.add(text: "b", preferredBoardId: client.id).task?.boardId == client.id)
        #expect(store.add(text: "c @int", preferredBoardId: client.id).task?.boardId == internalBoard.id)
    }

    @Test func unknownBoardWarns() {
        let result = store.add(text: "Review PR @nobody")
        guard case .addedWithWarning(let task, let board, let message) = result else {
            Issue.record("expected warning, got \(result)")
            return
        }
        #expect(task.title == "Review PR @nobody")
        #expect(board.id == internalBoard.id)
        #expect(message.contains("No board '@nobody'"))
        #expect(message.contains("Internal"))
    }

    @Test func emptyTitleRejected() {
        #expect(store.add(text: "   !s   ") == .rejected(.emptyTitle))
        #expect(store.tasks.isEmpty)
    }

    @Test func defaultSizeApplies() {
        store.updateSettings { $0.defaultSize = .m }
        #expect(add("x").size == .m)
        #expect(add("y !xs").size == .xs)
    }

    @Test func newTasksGoToBottom() {
        add("one")
        add("two")
        add("three")
        #expect(todoTitles() == ["one", "two", "three"])
    }

    @Test func boardRenameIsPickedUpImmediately() {
        store.renameBoard(client.id, to: "Acme Co")
        #expect(add("x @acme-co").boardId == client.id)
        store.addAlias("acme", to: client.id)
        #expect(add("y @acme").boardId == client.id)
    }

    // MARK: Moving and ordering

    @Test func moveSetsTimestamps() {
        let task = add("x")
        clock.advance(days: 1)
        store.move(task.id, to: .doing)
        let started = store.task(id: task.id)!.startedAt
        #expect(started == clock.now)

        clock.advance(days: 1)
        store.move(task.id, to: .done)
        #expect(store.task(id: task.id)!.completedAt == clock.now)

        clock.advance(days: 1)
        store.move(task.id, to: .doing)
        let back = store.task(id: task.id)!
        #expect(back.completedAt == nil)
        #expect(back.archivedAt == nil)
        #expect(back.startedAt == started, "startedAt is only set the first time")
    }

    @Test func moveBeforeAndAfter() {
        let a = add("a"), b = add("b"), c = add("c")
        store.move(c.id, to: .todo, position: .before(a.id))
        #expect(todoTitles() == ["c", "a", "b"])
        store.move(c.id, to: .todo, position: .after(b.id))
        #expect(todoTitles() == ["a", "b", "c"])
        store.move(a.id, to: .todo, position: .after(b.id))
        #expect(todoTitles() == ["b", "a", "c"])
        store.move(c.id, to: .todo, position: .start)
        #expect(todoTitles() == ["c", "b", "a"])
    }

    @Test func moveAcrossColumnsInsertsAtPosition() {
        let a = add("a"), b = add("b"), c = add("c")
        store.move(a.id, to: .doing)
        store.move(b.id, to: .doing)
        store.move(c.id, to: .doing, position: .before(b.id))
        #expect(todoTitles(.doing) == ["a", "c", "b"])
        #expect(todoTitles(.todo).isEmpty)
    }

    @Test func droppingInPlaceIsNoOp() {
        let a = add("a"), b = add("b")
        let before = store.tasks
        store.move(a.id, to: .todo, position: .before(b.id))
        store.move(a.id, to: .todo, position: .before(a.id))
        store.move(b.id, to: .todo, position: .end)
        #expect(store.tasks == before)
    }

    @Test func midpointOrderingAndRenormalisation() {
        let a = add("a"), b = add("b")
        // Repeatedly insert between a and the card after it until gaps would collapse.
        var last = b
        for index in 0..<80 {
            let t = add("n\(index)")
            store.move(t.id, to: .todo, position: .before(last.id))
            last = t
        }
        let titles = todoTitles()
        #expect(titles.first == "a")
        #expect(titles.last == "b")
        #expect(titles.count == 82)
        // Every order is distinct and strictly increasing.
        let orders = store.tasks(in: .todo).map(\.order)
        #expect(zip(orders, orders.dropFirst()).allSatisfy { $0 < $1 })
        _ = a
    }

    @Test func orderingIsConsistentAcrossBoardViews() {
        let a = add("a @int"), b = add("b @c"), c = add("c @int")
        store.move(c.id, to: .todo, position: .before(b.id))
        #expect(todoTitles() == ["a", "c", "b"])
        #expect(store.tasks(in: .todo, boardId: internalBoard.id).map(\.title) == ["a", "c"])
        _ = a
    }

    // MARK: Editing

    @Test func editTitleAppliesShorthand() {
        let task = add("Old title #one")
        store.editTitle(task.id, shorthand: "New title !l #two @c")
        let edited = store.task(id: task.id)!
        #expect(edited.title == "New title")
        #expect(edited.size == .l)
        #expect(edited.tags == ["one", "two"])
        #expect(edited.boardId == client.id)
    }

    @Test func editWithOnlyTokensKeepsTitle() {
        let task = add("Keep me")
        store.editTitle(task.id, shorthand: "!xs")
        #expect(store.task(id: task.id)?.title == "Keep me")
        #expect(store.task(id: task.id)?.size == .xs)
    }

    @Test func setSizeBoardTagsAndDelete() {
        let task = add("x")
        store.setSize(task.id, .xl)
        store.setBoard(task.id, boardId: client.id)
        store.setTags(task.id, ["#A", "b", "a"])
        let t = store.task(id: task.id)!
        #expect(t.size == .xl)
        #expect(t.boardId == client.id)
        #expect(t.tags == ["a", "b"])
        store.delete(task.id)
        #expect(store.task(id: task.id) == nil)
    }

    @Test func updatedAtChangesOnlyWhenSomethingChanges() {
        let task = add("x !s")
        clock.advance(days: 1)
        store.setSize(task.id, .s)
        #expect(store.task(id: task.id)?.updatedAt == task.updatedAt)
        store.setSize(task.id, .m)
        #expect(store.task(id: task.id)?.updatedAt == clock.now)
    }

    // MARK: Undo / redo

    @Test func undoRedoAddMoveEditDeleteSize() {
        let task = add("x")
        store.move(task.id, to: .doing)
        store.editTitle(task.id, shorthand: "y")
        store.setSize(task.id, .l)
        store.delete(task.id)
        #expect(store.task(id: task.id) == nil)

        store.undo()
        #expect(store.task(id: task.id)?.size == .l)
        store.undo()
        #expect(store.task(id: task.id)?.size == nil)
        store.undo()
        #expect(store.task(id: task.id)?.title == "x")
        store.undo()
        #expect(store.task(id: task.id)?.column == .todo)
        store.undo()
        #expect(store.tasks.isEmpty)
        #expect(!store.canUndo)

        store.redo()
        store.redo()
        #expect(store.task(id: task.id)?.column == .doing)
        #expect(store.canRedo)

        store.setSize(task.id, .s) // a new change clears redo
        #expect(!store.canRedo)
    }

    @Test func undoIsCappedAt50() {
        for index in 0..<60 { add("t\(index)") }
        var undone = 0
        while store.canUndo {
            store.undo()
            undone += 1
        }
        #expect(undone == 50)
        #expect(store.tasks.count == 10)
    }

    // MARK: Boards

    @Test func aliasValidation() {
        #expect(store.validateAlias("", for: client.id) == .empty)
        #expect(store.validateAlias("Bad Alias", for: client.id) == .invalidCharacters)
        #expect(store.validateAlias("café", for: client.id) == .invalidCharacters)
        #expect(store.validateAlias("int", for: client.id) == .duplicate(boardName: "Internal"))
        #expect(store.validateAlias("INT", for: client.id) == .duplicate(boardName: "Internal"))
        #expect(store.validateAlias("internal", for: client.id) == .duplicate(boardName: "Internal"))
        #expect(store.validateAlias("ok_alias-2", for: client.id) == nil)
        #expect(store.addAlias("i", to: client.id) == .duplicate(boardName: "Internal"))
        #expect(store.addAlias("CL", to: client.id) == nil)
        #expect(store.board(id: client.id)?.aliases.contains("cl") == true)
    }

    @Test func exactlyOneDefault() {
        store.setDefaultBoard(client.id)
        #expect(store.boards.filter(\.isDefault).map(\.id) == [client.id])
        #expect(add("x").boardId == client.id)
    }

    @Test func cannotDeleteDefaultBoard() {
        #expect(throws: BoardError.cannotDeleteDefault) {
            try store.deleteBoard(internalBoard.id, tasks: .deleteTasks)
        }
    }

    @Test func deleteBoardMovingTasks() throws {
        let task = add("x @c")
        try store.deleteBoard(client.id, tasks: .moveTasks(to: internalBoard.id))
        #expect(store.boards.map(\.id) == [internalBoard.id])
        #expect(store.task(id: task.id)?.boardId == internalBoard.id)

        store.undo()
        #expect(store.boards.count == 2)
        #expect(store.task(id: task.id)?.boardId == client.id)
    }

    @Test func deleteBoardDeletingTasksIsUndoable() throws {
        let task = add("x @c")
        let entry = try store.deleteBoard(client.id, tasks: .deleteTasks)
        #expect(store.task(id: task.id) == nil)
        #expect(store.undo(ifTop: try #require(entry)))
        #expect(store.task(id: task.id) != nil)
    }

    @Test func undoIfTopIgnoresStaleEntries() throws {
        let entry = try #require(try store.deleteBoard(client.id, tasks: .deleteTasks))
        add("later change")
        #expect(!store.undo(ifTop: entry))
        #expect(store.boards.count == 1)
    }

    @Test func deleteBoardRejectsBadTarget() {
        #expect(throws: BoardError.invalidTarget) {
            try store.deleteBoard(client.id, tasks: .moveTasks(to: client.id))
        }
    }

    @Test func reorderBoards() {
        store.moveBoards(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(store.boards.map(\.name) == ["Client", "Internal"])
        #expect(store.boards.map(\.sortOrder) == [0, 1])
    }

    @Test func addBoardPicksUnusedColour() {
        let board = store.addBoard(name: "Globex")
        #expect(!board.isDefault)
        #expect(board.colorHex != internalBoard.colorHex)
        #expect(board.colorHex != client.colorHex)
        #expect(store.boards.last?.id == board.id)
    }

    @Test func normalisationFixesDefaultsAndOrphans() {
        var a = Board(name: "A", colorHex: "#000000", isDefault: true)
        var b = Board(name: "B", colorHex: "#000000", isDefault: true)
        a.sortOrder = 1
        b.sortOrder = 0
        let orphan = TaskItem(boardId: UUID(), title: "orphan", createdAt: clock.now)
        let store = AppStore(snapshot: Snapshot(boards: [a, b], tasks: [orphan]))
        #expect(store.boards.map(\.name) == ["B", "A"])
        #expect(store.boards.filter(\.isDefault).count == 1)
        #expect(store.task(id: orphan.id)?.boardId == store.defaultBoard?.id)
    }

    // MARK: Derived data

    @Test func loadPointsAndCounts() {
        add("a !xs"); add("b !s"); add("c !m"); add("d !l"); add("e !xl"); add("f")
        let todo = store.tasks(in: .todo)
        #expect(AppStore.loadPoints(todo) == 1 + 2 + 3 + 5 + 8)
        #expect(store.activeCount(in: .todo) == 6)
    }

    @Test func filtersWorkInAllAndSingleBoardViews() {
        add("Invoice Acme @c #billing !s")
        add("Fix invoice bug @int #billing #urgent")
        add("Lunch @int")

        var filter = TaskFilter(text: "invoice")
        #expect(store.tasks(in: .todo, filter: filter).count == 2)
        #expect(store.tasks(in: .todo, boardId: internalBoard.id, filter: filter).count == 1)

        filter = TaskFilter(tags: ["urgent"])
        #expect(store.tasks(in: .todo, filter: filter).map(\.title) == ["Fix invoice bug"])

        filter = TaskFilter(text: "#bill")
        #expect(store.tasks(in: .todo, filter: filter).count == 2)

        filter = TaskFilter(sizes: [nil])
        #expect(store.tasks(in: .todo, filter: filter).count == 2)

        filter = TaskFilter(sizes: [.s])
        #expect(store.tasks(in: .todo, boardId: client.id, filter: filter).count == 1)

        #expect(store.allTags == ["billing", "urgent"])
    }

    @Test func externalChangeReplacesStateAndClearsUndo() {
        add("x")
        #expect(store.canUndo)
        var snapshot = store.snapshot()
        snapshot.tasks[0].title = "edited by hand"
        store.applyExternalChange(snapshot)
        #expect(store.tasks[0].title == "edited by hand")
        #expect(!store.canUndo)
    }
}
