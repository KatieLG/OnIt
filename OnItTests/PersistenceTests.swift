import Foundation
import Testing
@testable import OnIt

@MainActor
struct PersistenceTests {
    let directory = makeTempDirectory()
    var persistence: Persistence { Persistence(directory: directory) }
    // Whole seconds: the file stores ISO8601 without fractions.
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    func onDisk(_ url: URL? = nil) throws -> Snapshot { try Snapshot.decode(Data(contentsOf: url ?? persistence.fileURL)) }

    func write(_ title: String, to url: URL? = nil) throws {
        var snapshot = Snapshot.seed(now: date)
        snapshot.tasks[0].title = title
        try snapshot.encoded().write(to: url ?? persistence.fileURL)
    }

    @Test func createsSeedFileWhenMissing() throws {
        let (snapshot, recovery) = persistence.load { Snapshot.seed(now: date) }
        #expect(recovery == nil && files() == ["onit.json"])
        #expect(try onDisk() == snapshot)
    }

    @Test func roundTrip() throws {
        var snapshot = Snapshot.seed(now: date)
        snapshot.tasks.append(TaskItem(boardId: snapshot.boards[1].id, title: "Café ☕ \"quoted\"", size: .xl, column: .doing,
                                       tags: ["a", "b"], order: 1536.5, createdAt: date, startedAt: date))
        snapshot.settings = AppSettings(defaultSize: .s, badgeMode: .todo, lastSelectedBoardId: snapshot.boards[1].id)
        persistence.write(try snapshot.encoded(), sync: true)
        #expect(persistence.load { Snapshot.seed() } == (snapshot, nil))
    }

    @Test func rejectsFutureSchema() {
        #expect(throws: (any Error).self) { try Snapshot.decode(Data(#"{ "schemaVersion": 99, "boards": [], "tasks": [], "settings": {} }"#.utf8)) }
    }

    @Test func backupsRotateOncePerLaunchAndKeepThree() throws {
        _ = persistence.load { Snapshot.seed() }
        #expect(files() == ["onit.json"], "a new file isn't backed up")
        for launch in 1...5 {
            try write("launch \(launch)")
            _ = persistence.load { Snapshot.seed() }
        }
        #expect(files() == ["onit.backup-1.json", "onit.backup-2.json", "onit.backup-3.json", "onit.json"])
        #expect(try onDisk(persistence.backupURL(1)).tasks[0].title == "launch 5")
        #expect(try onDisk(persistence.backupURL(3)).tasks[0].title == "launch 3")
    }

    @Test func corruptFileIsKeptAndRecoveredFromNewestValidBackup() throws {
        try Data("nope".utf8).write(to: persistence.backupURL(1))
        try write("from backup 2", to: persistence.backupURL(2))
        try Data("{ not json".utf8).write(to: persistence.fileURL)

        let (snapshot, recovery) = persistence.load { Snapshot.seed() }
        #expect(snapshot.tasks[0].title == "from backup 2" && recovery?.contains("restored from a backup") == true)
        #expect(try onDisk().tasks[0].title == "from backup 2")
        let corrupt = try #require(files().first { $0.hasPrefix("onit.corrupt-") })
        #expect(try String(contentsOf: directory.appending(path: corrupt), encoding: .utf8) == "{ not json", "never overwritten")
    }

    @Test func corruptWithNoBackupStartsFresh() throws {
        try Data("corrupt".utf8).write(to: persistence.fileURL)
        #expect(persistence.load { Snapshot.seed() }.recovery?.contains("started fresh") == true)
        #expect(files().contains { $0.hasPrefix("onit.corrupt-") })
    }

    @Test func storeSavesAndSurvivesRelaunch() async throws {
        let p = persistence
        try Data("corrupt".utf8).write(to: p.fileURL)
        let first = AppStore(persistence: p)
        #expect(first.launchIssue != nil)
        first.add("survivor @h !m #keep")
        first.flush(synchronously: true)
        let task = try #require(AppStore(persistence: persistence).tasks.first { $0.title == "survivor" })
        #expect(task.size == .m && task.tags == ["keep"])

        first.add("debounced")
        try await Task.sleep(for: .milliseconds(700))
        p.drain()
        #expect(try onDisk().tasks.contains { $0.title == "debounced" })
    }

    @Test func outsideEditsAreReportedButOwnWritesIgnored() throws {
        let p = persistence, received = Received()
        _ = p.load { Snapshot.seed() }
        p.watch { received.append($0) }
        p.drain()

        var snapshot = try onDisk()
        snapshot.tasks[0].title = "ours"
        p.write(try snapshot.encoded(), sync: true)
        p.checkNow()
        #expect(received.count == 0)

        try write("theirs")
        p.checkNow()
        #expect(received.count == 1 && received.last?.tasks[0].title == "theirs")

        try Data("{".utf8).write(to: p.fileURL) // half-saved: ignored
        p.checkNow()
        #expect(received.count == 1)
    }

    @Test func watcherFiresOnRealFileSystemEvents() async throws {
        let p = persistence, received = Received()
        _ = p.load { Snapshot.seed() }
        p.watch { received.append($0) }
        p.drain()
        var snapshot = try onDisk()
        snapshot.tasks[0].title = "external"
        try snapshot.encoded().write(to: p.fileURL, options: .atomic)
        for _ in 0..<40 where received.count == 0 { try await Task.sleep(for: .milliseconds(100)) }
        #expect(received.last?.tasks[0].title == "external")
    }

    @Test func copyAside() throws {
        _ = persistence.load { Snapshot.seed() }
        let url = persistence.copyAside("pre-import")
        #expect(try Data(contentsOf: url) == Data(contentsOf: persistence.fileURL))
    }
}
