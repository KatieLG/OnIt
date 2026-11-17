import Foundation
import Testing
@testable import OnIt

@MainActor
struct ArchiveTests {
    let clock = TestClock()
    let store: AppStore

    init() { store = emptyStore(clock: clock) }

    func done(_ title: String) -> TaskItem {
        let task = store.add(title)
        store.move(task.id, to: .done)
        return task
    }

    @Test func archivesDoneTasksOlderThanTheSetting() {
        let old = done("old")
        clock.advance(days: 1)
        let fresh = done("fresh")
        let todo = store.add("todo")
        clock.advance(days: 6)
        #expect(store.sweepArchive().isEmpty, "exactly 7 days isn't older than 7")

        clock.advance(days: 0.5)
        #expect(store.sweepArchive() == [old.id])
        #expect(store.task(id: old.id)?.archivedAt == clock.now)
        #expect(store.tasks(in: .done).map(\.id) == [fresh.id])
        #expect(store.archivedTasks.map(\.id) == [old.id])
        #expect(store.task(id: todo.id)?.isArchived == false)

        clock.advance(days: 30)
        #expect(store.sweepArchive() == [fresh.id], "already-archived tasks aren't touched")
        #expect(store.tasks.count == 3, "archived tasks are kept")
    }

    @Test func respectsConfiguredDays() {
        store.updateSettings { $0.archiveAfterDays = 2 }
        let task = done("x")
        clock.advance(days: 1)
        #expect(store.sweepArchive().isEmpty)
        clock.advance(days: 2)
        #expect(store.sweepArchive() == [task.id])
    }

    @Test func restoreBringsTaskBackToTodo() {
        let task = done("x")
        clock.advance(days: 10)
        store.sweepArchive()
        store.restore(task.id)
        let restored = store.task(id: task.id)!
        #expect(restored.column == .todo && restored.archivedAt == nil && restored.completedAt == nil)
        #expect(store.tasks(in: .todo).map(\.id) == [task.id])
    }
}
