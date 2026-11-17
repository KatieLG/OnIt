import Foundation
@testable import OnIt

/// A controllable clock for injecting into `AppStore`.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_800_000_000)) { _now = now }

    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }

    func advance(days: Double) { now = now.addingTimeInterval(days * 86_400) }
    var closure: @Sendable () -> Date { { [self] in now } }
}

/// Collects snapshots delivered on another queue.
final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Snapshot] = []
    func append(_ snapshot: Snapshot) { lock.withLock { items.append(snapshot) } }
    var last: Snapshot? { lock.withLock { items.last } }
    var count: Int { lock.withLock { items.count } }
}

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "OnItTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
func emptyStore(clock: TestClock = TestClock()) -> AppStore {
    AppStore(snapshot: Snapshot(boards: Snapshot.seed().boards, tasks: []), clock: clock.closure)
}

extension AppStore {
    @discardableResult
    func add(_ text: String) -> TaskItem { try! add(text: text).task }
}
