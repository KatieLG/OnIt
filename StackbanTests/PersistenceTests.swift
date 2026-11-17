import Foundation
import Testing
@testable import Stackban

@MainActor
struct PersistenceTests {
    let directory = makeTempDirectory()
    var persistence: Persistence { Persistence(directory: directory) }

    func fileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    @Test func createsSeedFileWhenMissing() throws {
        let p = persistence
        // Whole-second date: the file stores ISO8601 without fractional seconds.
        let outcome = p.load(seed: { Snapshot.seed(now: Date(timeIntervalSince1970: 1_800_000_000)) })
        guard case .created(let snapshot) = outcome else {
            Issue.record("expected .created")
            return
        }
        let onDisk = try Snapshot.decode(Data(contentsOf: p.fileURL))
        #expect(onDisk == snapshot)
        #expect(fileNames() == ["stackban.json"])
    }

    @Test func roundTrip() throws {
        let p = persistence
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = Snapshot.seed(now: date)
        snapshot.tasks.append(TaskItem(
            boardId: snapshot.boards[1].id, title: "Café ☕ \"quoted\"", size: .xl, column: .doing,
            tags: ["a", "b"], order: 1536.5, createdAt: date, startedAt: date
        ))
        snapshot.settings.badgeMode = .todo
        snapshot.settings.defaultSize = .s
        snapshot.settings.lastSelectedBoardId = snapshot.boards[1].id
        p.writeSync(try snapshot.encoded())

        guard case .loaded(let loaded) = persistence.load(seed: { Snapshot.seed() }) else {
            Issue.record("expected .loaded")
            return
        }
        #expect(loaded == snapshot)
    }

    @Test func fileMatchesDocumentedSchema() throws {
        let data = try Snapshot.seed(now: Date(timeIntervalSince1970: 0)).encoded()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
        let task = try #require((json["tasks"] as? [[String: Any]])?.first)
        #expect(task["size"] is NSNull)
        #expect(task["startedAt"] is NSNull)
        #expect(task["column"] as? String == "todo")
        #expect(task["createdAt"] as? String == "1970-01-01T00:00:00Z")
        let settings = try #require(json["settings"] as? [String: Any])
        #expect(settings["defaultSize"] is NSNull)
        #expect(settings["archiveAfterDays"] as? Int == 7)
        #expect(settings["badgeMode"] as? String == "doing")
        #expect(settings["lastSelectedBoardId"] is NSNull)
    }

    @Test func decodesLenientHandEdits() throws {
        let board = UUID(), task = UUID()
        let json = """
        {
          "boards": [{ "id": "\(board)", "name": "Solo" }],
          "tasks": [{ "id": "\(task)", "boardId": "\(board)", "title": "Hand made",
                      "size": "HUGE", "column": "doing", "createdAt": "2026-01-02T03:04:05.678Z" }]
        }
        """
        let snapshot = try Snapshot.decode(Data(json.utf8))
        #expect(snapshot.boards[0].colorHex == "#8E8E93")
        #expect(snapshot.tasks[0].size == nil)
        #expect(snapshot.tasks[0].column == .doing)
        #expect(snapshot.tasks[0].tags.isEmpty)
        #expect(snapshot.settings == AppSettings())
    }

    @Test func rejectsFutureSchema() {
        let json = #"{ "schemaVersion": 99, "boards": [] }"#
        #expect(throws: Migrations.MigrationError.unsupportedVersion(99)) {
            try Snapshot.decode(Data(json.utf8))
        }
    }

    @Test func backupsRotateOncePerLaunchAndKeepThree() throws {
        let p = persistence
        _ = p.load(seed: { Snapshot.seed() }) // creates file, no rotation
        #expect(!FileManager.default.fileExists(atPath: p.backupURL(1).path))

        for launch in 1...5 {
            var snapshot = try Snapshot.decode(Data(contentsOf: p.fileURL))
            snapshot.tasks[0].title = "launch \(launch)"
            p.writeSync(try snapshot.encoded())
            _ = persistence.load(seed: { Snapshot.seed() })
        }
        #expect(fileNames() == ["stackban.backup-1.json", "stackban.backup-2.json", "stackban.backup-3.json", "stackban.json"])
        let newest = try Snapshot.decode(Data(contentsOf: p.backupURL(1)))
        let oldest = try Snapshot.decode(Data(contentsOf: p.backupURL(3)))
        #expect(newest.tasks[0].title == "launch 5")
        #expect(oldest.tasks[0].title == "launch 3")
    }

    @Test func corruptFileIsMovedAsideAndRecoveredFromBackup() throws {
        let p = persistence
        var good = Snapshot.seed()
        good.tasks[0].title = "precious"
        p.writeSync(try good.encoded())
        _ = persistence.load(seed: { Snapshot.seed() }) // rotates: backup-1 = good

        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: p.fileURL)

        let outcome = persistence.load(seed: { Snapshot.seed() })
        guard case .recovered(let snapshot, let corruptURL, let backup) = outcome else {
            Issue.record("expected .recovered, got \(outcome)")
            return
        }
        #expect(snapshot.tasks[0].title == "precious")
        #expect(backup?.lastPathComponent == "stackban.backup-1.json")
        #expect(corruptURL.lastPathComponent.hasPrefix("stackban.corrupt-"))
        // The corrupt bytes are preserved, never overwritten.
        #expect(try Data(contentsOf: corruptURL) == garbage)
        // The main file now holds the recovered data.
        #expect(try Snapshot.decode(Data(contentsOf: p.fileURL)).tasks[0].title == "precious")
    }

    @Test func recoverySkipsInvalidBackups() throws {
        let p = persistence
        var good = Snapshot.seed()
        good.tasks[0].title = "from backup 2"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: p.backupURL(1))
        try good.encoded().write(to: p.backupURL(2))
        try Data("also corrupt".utf8).write(to: p.fileURL)

        guard case .recovered(let snapshot, _, let backup) = p.load(seed: { Snapshot.seed() }) else {
            Issue.record("expected .recovered")
            return
        }
        #expect(snapshot.tasks[0].title == "from backup 2")
        #expect(backup == p.backupURL(2))
    }

    @Test func corruptWithNoBackupStartsFromSeedButKeepsFile() throws {
        let p = persistence
        try Data("corrupt".utf8).write(to: p.fileURL)
        guard case .recovered(_, let corrupt, let backup) = p.load(seed: { Snapshot.seed() }) else {
            Issue.record("expected .recovered")
            return
        }
        #expect(backup == nil)
        #expect(try String(contentsOf: corrupt, encoding: .utf8) == "corrupt")
    }

    @Test func storeReportsRecoveryAndSavesThroughDebounce() async throws {
        let p = persistence
        try Data("corrupt".utf8).write(to: p.fileURL)
        let store = AppStore(persistence: p)
        #expect(store.launchIssue != nil)

        _ = store.add(text: "persist me")
        store.flush(synchronously: true)
        let onDisk = try Snapshot.decode(Data(contentsOf: p.fileURL))
        #expect(onDisk.tasks.contains { $0.title == "persist me" })

        _ = store.add(text: "debounced")
        try await Task.sleep(for: .milliseconds(700))
        p.drain()
        let later = try Snapshot.decode(Data(contentsOf: p.fileURL))
        #expect(later.tasks.contains { $0.title == "debounced" })
    }

    @Test func dataSurvivesRelaunch() throws {
        let first = AppStore(persistence: persistence)
        _ = first.add(text: "survivor @c !m #keep")
        first.flush(synchronously: true)

        let second = AppStore(persistence: persistence)
        let task = try #require(second.tasks.first { $0.title == "survivor" })
        #expect(task.size == .m)
        #expect(task.tags == ["keep"])
        #expect(second.board(id: task.boardId)?.name == "Client")
    }

    @Test func externalEditsAreDetectedButOwnWritesIgnored() async throws {
        let p = persistence
        _ = p.load(seed: { Snapshot.seed() })

        let received = Received()
        p.startWatching { snapshot in received.append(snapshot) }
        p.drain()

        // Our own write: ignored.
        var snapshot = try Snapshot.decode(Data(contentsOf: p.fileURL))
        snapshot.tasks[0].title = "ours"
        p.writeSync(try snapshot.encoded())
        p.checkForExternalChangeNow()
        #expect(received.count == 0)

        // Someone else's write (in place, like a text editor): picked up.
        snapshot.tasks[0].title = "theirs"
        try snapshot.encoded().write(to: p.fileURL)
        p.checkForExternalChangeNow()
        #expect(received.count == 1)
        #expect(received.last?.tasks[0].title == "theirs")

        // Half-written garbage: ignored until valid.
        try Data("{".utf8).write(to: p.fileURL)
        p.checkForExternalChangeNow()
        #expect(received.count == 1)
        p.stopWatching()
    }

    @Test func watcherFiresOnRealFileSystemEvents() async throws {
        let p = persistence
        _ = p.load(seed: { Snapshot.seed() })
        let received = Received()
        p.startWatching { snapshot in received.append(snapshot) }
        p.drain()

        var snapshot = try Snapshot.decode(Data(contentsOf: p.fileURL))
        snapshot.tasks[0].title = "external"
        try snapshot.encoded().write(to: p.fileURL, options: .atomic)

        for _ in 0..<40 where received.count == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(received.last?.tasks[0].title == "external")
        p.stopWatching()
    }

    @Test func preImportBackup() throws {
        let p = persistence
        _ = p.load(seed: { Snapshot.seed() })
        let url = try #require(p.writePreImportBackup())
        #expect(try Data(contentsOf: url) == Data(contentsOf: p.fileURL))
    }
}

final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Snapshot] = []

    func append(_ snapshot: Snapshot) { lock.withLock { items.append(snapshot) } }
    var count: Int { lock.withLock { items.count } }
    var last: Snapshot? { lock.withLock { items.last } }
}
