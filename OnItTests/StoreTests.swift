import Foundation
import Testing
@testable import OnIt

@MainActor
struct StoreTests {
    let clock = TestClock()
    let store: AppStore
    let home: Board, work: Board

    init() {
        store = emptyStore(clock: clock)
        (home, work) = (store.boards[0], store.boards[1])
    }

    func titles(_ column: Column = .todo) -> [String] { store.tasks(in: column).map(\.title) }

    @Test func seedHasHomeAndWorkWithAPlainTaskEach() {
        let seed = Snapshot.seed()
        #expect(seed.boards.map(\.name) == ["Home", "Work"])
        #expect(seed.boards.filter(\.isDefault).map(\.name) == ["Work"])
        #expect(seed.boards.map(\.aliases) == [["home", "h"], ["work", "w"]])
        #expect(seed.tasks.map(\.boardId) == seed.boards.map(\.id))
        #expect(seed.tasks.map(\.size) == [.m, .s])
        #expect(seed.tasks.allSatisfy { ShorthandParser.parse($0.title, boards: seed.boards).title == $0.title }, "no shorthand in titles")
    }

    // MARK: Adding

    @Test func addParsesShorthand() throws {
        let (task, board, warning) = try store.add(text: "Draft proposal @h !L #sales")
        #expect(board.id == home.id && warning == nil)
        #expect(task.title == "Draft proposal" && task.size == .l && task.tags == ["sales"] && task.column == .todo)
        #expect(task.createdAt == clock.now)
    }

    @Test func addChoosesBoards() throws {
        #expect(store.add("a").boardId == work.id, "default board")
        #expect(try store.add(text: "b", preferredBoardId: home.id).task.boardId == home.id)
        #expect(try store.add(text: "c @work", preferredBoardId: home.id).task.boardId == work.id)
        let (task, board, warning) = try store.add(text: "Review PR @nobody")
        #expect(task.title == "Review PR @nobody" && board.id == work.id)
        #expect(warning == "No board '@nobody'. Added to Work.")
    }

    @Test func emptyTitleRejected() {
        #expect(throws: StoreError.emptyTitle) { try store.add(text: "   !s   ") }
        #expect(store.tasks.isEmpty)
    }

    @Test func defaultSizeAndBottomOfTodo() {
        store.updateSettings { $0.defaultSize = .m }
        #expect(store.add("one").size == .m)
        #expect(store.add("two !xs").size == .xs)
        store.add("three")
        #expect(titles() == ["one", "two", "three"])
    }

    @Test func renamesAndAliasesApplyImmediately() throws {
        store.updateBoard(home.id) { $0.name = "Acme Co" }
        #expect(store.add("x @acme-co").boardId == home.id)
        try store.setAliases("acme", for: home.id)
        #expect(store.add("y @acme").boardId == home.id)
    }

    // MARK: Moving

    @Test func columnOrder() {
        #expect(Column.allCases == [.later, .todo, .doing, .done])
        #expect(Column.todo.previous == .later && Column.later.previous == nil && Column.done.next == nil)
    }

    @Test func moveSetsTimestamps() {
        let task = store.add("x")
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
        #expect(back.completedAt == nil && back.archivedAt == nil)
        #expect(back.startedAt == started, "only set the first time")
    }

    @Test func moveToPositions() {
        let a = store.add("a"), b = store.add("b"), c = store.add("c")
        store.move(c.id, to: .todo, position: .before(a.id))
        #expect(titles() == ["c", "a", "b"])
        store.move(c.id, to: .todo, position: .after(b.id))
        #expect(titles() == ["a", "b", "c"])
        store.move(c.id, to: .todo, position: .start)
        #expect(titles() == ["c", "a", "b"])
        store.move(a.id, to: .doing)
        store.move(b.id, to: .doing, position: .before(a.id))
        #expect(titles(.doing) == ["b", "a"])
    }

    @Test func droppingInPlaceIsNoOp() {
        let a = store.add("a"), b = store.add("b")
        let before = store.tasks
        store.move(a.id, to: .todo, position: .before(b.id))
        store.move(a.id, to: .todo, position: .before(a.id))
        store.move(b.id, to: .todo)
        #expect(store.tasks == before)
        store.undo()
        #expect(titles() == ["a"], "no-ops don't add undo steps")
    }

    @Test func midpointsRespaceWhenPrecisionRunsOut() {
        store.add("a")
        var last = store.add("b")
        for i in 0..<80 {
            let task = store.add("n\(i)")
            store.move(task.id, to: .todo, position: .before(last.id))
            last = task
        }
        #expect(titles().first == "a" && titles().last == "b" && titles().count == 82)
        let orders = store.tasks(in: .todo).map(\.order)
        #expect(zip(orders, orders.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func orderIsSharedAcrossBoardViews() {
        store.add("a @work")
        let b = store.add("b @h"), c = store.add("c @work")
        store.move(c.id, to: .todo, position: .before(b.id))
        #expect(titles() == ["a", "c", "b"])
        #expect(store.tasks(in: .todo, boardId: work.id).map(\.title) == ["a", "c"])
    }

    // MARK: Editing and undo

    @Test func editAppliesShorthand() {
        let task = store.add("Old title #one")
        store.edit(task.id, shorthand: "New title !l #two @h")
        #expect(store.task(id: task.id) == TaskItem(id: task.id, boardId: home.id, title: "New title", size: .l, tags: ["one", "two"],
                                                     order: task.order, createdAt: task.createdAt))
        store.edit(task.id, shorthand: "!xs")
        #expect(store.task(id: task.id)?.title == "New title", "tokens alone keep the title")
    }

    @Test func undoRedo() {
        let task = store.add("x")
        store.move(task.id, to: .doing)
        store.edit(task.id, shorthand: "y")
        store.update(task.id) { $0.size = .l }
        store.delete(task.id)

        for check in [{ store.task(id: task.id)?.size == .l }, { store.task(id: task.id)?.size == nil },
                      { store.task(id: task.id)?.title == "x" }, { store.task(id: task.id)?.column == .todo }, { store.tasks.isEmpty }] {
            store.undo()
            #expect(check())
        }
        #expect(!store.canUndo)
        store.redo()
        store.redo()
        #expect(store.task(id: task.id)?.column == .doing && store.canRedo)
        store.update(task.id) { $0.size = .s }
        #expect(!store.canRedo, "a new change clears redo")
    }

    @Test func undoIsCappedAt50() {
        for i in 0..<60 { store.add("t\(i)") }
        var undone = 0
        while store.canUndo { store.undo(); undone += 1 }
        #expect(undone == 50 && store.tasks.count == 10)
    }

    // MARK: Boards

    @Test func aliases() throws {
        #expect(throws: StoreError.invalidAlias("bad!")) { try store.setAliases("ok, bad!", for: home.id) }
        #expect(throws: StoreError.duplicateAlias("work", board: "Work")) { try store.setAliases("WORK", for: home.id) }
        #expect(throws: StoreError.duplicateAlias("w", board: "Work")) { try store.setAliases("@w", for: home.id) }
        try store.setAliases("@home, hm hm, ok_alias-2", for: home.id)
        #expect(store.board(id: home.id)?.aliases == ["home", "hm", "ok_alias-2"])
        store.updateBoard(work.id) { $0.name = "Day Job" }
        #expect(throws: StoreError.duplicateAlias("day-job", board: "Day Job"), "names are reserved too") {
            try store.setAliases("day-job", for: home.id)
        }
    }

    @Test func defaultBoard() {
        store.setDefaultBoard(home.id)
        #expect(store.boards.filter(\.isDefault).map(\.id) == [home.id])
        #expect(store.add("x").boardId == home.id)
        #expect(throws: StoreError.cannotDeleteDefault) { try store.deleteBoard(home.id, moveTasksTo: nil) }
    }

    @Test func deleteBoard() throws {
        let task = store.add("x @h")
        #expect(throws: StoreError.invalidTarget) { try store.deleteBoard(home.id, moveTasksTo: home.id) }
        try store.deleteBoard(home.id, moveTasksTo: work.id)
        #expect(store.boards.map(\.id) == [work.id] && store.task(id: task.id)?.boardId == work.id)
        store.undo()
        #expect(store.boards.count == 2 && store.task(id: task.id)?.boardId == home.id)
        try store.deleteBoard(home.id, moveTasksTo: nil)
        #expect(store.task(id: task.id) == nil)
    }

    @Test func reorderAndAddBoards() {
        store.moveBoards(fromOffsets: [1], toOffset: 0)
        #expect(store.boards.map(\.name) == ["Work", "Home"] && store.boards.map(\.sortOrder) == [0, 1])
        let board = store.addBoard(name: "Globex")
        #expect(!board.isDefault && ![work.colorHex, home.colorHex].contains(board.colorHex) && store.boards.last == board)
    }

    @Test func normalisesDefaultsAndOrphans() {
        let a = Board(name: "A", colorHex: "#000000", isDefault: true, sortOrder: 1)
        let b = Board(name: "B", colorHex: "#000000", isDefault: true, sortOrder: 0)
        let orphan = TaskItem(boardId: UUID(), title: "orphan", createdAt: clock.now)
        let store = AppStore(snapshot: Snapshot(boards: [a, b], tasks: [orphan]))
        #expect(store.boards.map(\.name) == ["B", "A"] && store.boards.filter(\.isDefault).count == 1)
        #expect(store.task(id: orphan.id)?.boardId == store.defaultBoard.id)
    }

    // MARK: Derived data

    @Test func loadPointsAndFilters() {
        ["a !xs", "b !s", "c !m", "d !l", "e !xl", "f"].forEach { store.add($0) }
        #expect(AppStore.loadPoints(store.tasks(in: .todo)) == 19 && store.activeCount(in: .todo) == 6)
    }

    @Test func filters() {
        store.add("Invoice Acme @h #billing !s")
        store.add("Fix invoice bug @work #billing #urgent")
        store.add("Lunch @work")
        func count(_ filter: TaskFilter, board: UUID? = nil) -> Int { store.tasks(in: .todo, boardId: board, filter: filter).count }
        #expect(count(TaskFilter(text: "invoice")) == 2)
        #expect(count(TaskFilter(text: "invoice"), board: work.id) == 1)
        #expect(count(TaskFilter(tags: ["urgent"])) == 1)
        #expect(count(TaskFilter(text: "#bill")) == 2)
        #expect(count(TaskFilter(sizes: [nil])) == 2)
        #expect(count(TaskFilter(sizes: [.s]), board: home.id) == 1)
        #expect(store.allTags == ["billing", "urgent"])
    }

    @Test func replacingEverythingClearsUndo() {
        store.add("x")
        var snapshot = store.snapshot()
        snapshot.tasks[0].title = "edited by hand"
        store.replaceAll(with: snapshot, save: false)
        #expect(store.tasks[0].title == "edited by hand" && !store.canUndo)
    }
}
