import Foundation
import Testing
@testable import OnIt

@MainActor
struct ArchiveTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    func makeStore(now: Date) -> AppStore {
        let snapshot = Snapshot.seed(now: base)
        return AppStore(snapshot: Snapshot(boards: snapshot.boards, tasks: []), clock: { now })
    }

    func doneTask(boardId: UUID, completedDaysAgo days: Double, now: Date) -> TaskItem {
        TaskItem(boardId: boardId, title: "Done \(days)", column: .done, order: 1,
                 createdAt: base, completedAt: now.addingTimeInterval(-days * day))
    }

    @Test func pureSweepArchivesOnlyOldDoneTasks() {
        let now = base.addingTimeInterval(30 * day)
        let board = UUID()
        let old = doneTask(boardId: board, completedDaysAgo: 8, now: now)
        let fresh = doneTask(boardId: board, completedDaysAgo: 6, now: now)
        let exactlySeven = doneTask(boardId: board, completedDaysAgo: 7, now: now)
        var todo = TaskItem(boardId: board, title: "Todo", column: .todo, createdAt: base)
        todo.completedAt = now.addingTimeInterval(-20 * day) // stale field shouldn't matter outside Done

        let result = ArchiveSweeper.sweep([old, fresh, exactlySeven, todo], now: now, archiveAfterDays: 7)
        #expect(result.archived == [old.id])
        #expect(result.tasks.first { $0.id == old.id }?.archivedAt == now)
        #expect(result.tasks.first { $0.id == fresh.id }?.archivedAt == nil)
        #expect(result.tasks.first { $0.id == exactlySeven.id }?.archivedAt == nil)
        #expect(result.tasks.first { $0.id == todo.id }?.archivedAt == nil)
    }

    @Test func alreadyArchivedTasksAreNotTouched() {
        let now = base.addingTimeInterval(30 * day)
        var task = doneTask(boardId: UUID(), completedDaysAgo: 20, now: now)
        task.archivedAt = base
        let result = ArchiveSweeper.sweep([task], now: now, archiveAfterDays: 7)
        #expect(result.archived.isEmpty)
        #expect(result.tasks[0].archivedAt == base)
    }

    @Test func storeSweepUsesInjectedClockAndHidesTasks() {
        let clock = TestClock(base)
        let store = AppStore(snapshot: Snapshot(boards: Snapshot.seed().boards, tasks: []), clock: clock.closure)
        let task = store.add(text: "Ship it").task!
        store.move(task.id, to: .done)
        #expect(store.task(id: task.id)?.completedAt == base)

        clock.advance(days: 6)
        #expect(store.sweepArchive().isEmpty)

        clock.advance(days: 2)
        let archived = store.sweepArchive()
        #expect(archived == [task.id])
        #expect(store.task(id: task.id)?.archivedAt == clock.now)
        #expect(store.tasks(in: .done).isEmpty)
        #expect(store.archivedTasks.map(\.id) == [task.id])
    }

    @Test func respectsConfiguredDays() {
        let now = base.addingTimeInterval(3 * day)
        let store = makeStore(now: base)
        store.updateSettings { $0.archiveAfterDays = 2 }
        let task = store.add(text: "x").task!
        store.move(task.id, to: .done)
        #expect(store.sweepArchive(now: base.addingTimeInterval(1 * day)).isEmpty)
        #expect(store.sweepArchive(now: now) == [task.id])
    }

    @Test func restoreBringsTaskBackToTodo() {
        let store = makeStore(now: base)
        let task = store.add(text: "x").task!
        store.move(task.id, to: .done)
        store.sweepArchive(now: base.addingTimeInterval(10 * day))
        #expect(store.task(id: task.id)?.isArchived == true)

        store.restore(task.id)
        let restored = store.task(id: task.id)!
        #expect(restored.column == .todo)
        #expect(restored.archivedAt == nil)
        #expect(restored.completedAt == nil)
        #expect(store.tasks(in: .todo).map(\.id) == [task.id])
    }

    @Test func archivedTasksAreKeptNotDeleted() {
        let store = makeStore(now: base)
        let task = store.add(text: "x").task!
        store.move(task.id, to: .done)
        store.sweepArchive(now: base.addingTimeInterval(10 * day))
        #expect(store.tasks.count == 1)
    }
}
