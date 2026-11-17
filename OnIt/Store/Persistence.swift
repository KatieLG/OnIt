import Foundation

/// Owns `onit.json`: atomic writes, backups, corruption recovery, and watching for outside edits.
/// After launch, all file I/O runs on `queue`.
final class Persistence: @unchecked Sendable {
    let directory: URL
    var fileURL: URL { directory.appending(path: "onit.json") }
    func backupURL(_ n: Int) -> URL { directory.appending(path: "onit.backup-\(n).json") }

    private let queue = DispatchQueue(label: "onit.persistence", qos: .utility)
    // Confined to `queue`.
    private var lastKnownData: Data? // what we last wrote or read, so our own writes aren't "outside edits"
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingCheck: DispatchWorkItem?
    private var onChange: (@Sendable (Snapshot) -> Void)?

    init(directory: URL = .applicationSupportDirectory.appending(path: "OnIt")) {
        self.directory = directory
    }

    deinit { sources.forEach { $0.cancel() } }

    /// Loads the file, creating it from `seed` if missing, and rotates the three backups. A file that
    /// won't decode is copied aside (never lost) and the newest valid backup restored; `recovery`
    /// then explains what happened.
    func load(seed: () -> Snapshot) -> (snapshot: Snapshot, recovery: String?) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return (save(seed()), nil) }
        if let data = try? Data(contentsOf: fileURL), let snapshot = try? Snapshot.decode(data) {
            queue.sync { lastKnownData = data }
            rotateBackups()
            return (snapshot, nil)
        }
        let corrupt = copyAside("corrupt").lastPathComponent
        for n in 1...3 {
            if let data = try? Data(contentsOf: backupURL(n)), let snapshot = try? Snapshot.decode(data) {
                return (save(snapshot), "OnIt's data file couldn't be read, so it was restored from a backup. The unreadable file was kept as \(corrupt).")
            }
        }
        return (save(seed()), "OnIt's data file couldn't be read and there was no usable backup, so OnIt started fresh. The unreadable file was kept as \(corrupt).")
    }

    private func save(_ snapshot: Snapshot) -> Snapshot {
        if let data = try? snapshot.encoded() { write(data, sync: true) }
        return snapshot
    }

    private func rotateBackups() {
        let fm = FileManager.default
        try? fm.removeItem(at: backupURL(3))
        for n in [2, 1] { try? fm.moveItem(at: backupURL(n), to: backupURL(n + 1)) }
        try? fm.copyItem(at: fileURL, to: backupURL(1))
    }

    /// Copies the data file to `onit.<label>-<timestamp>.json`, e.g. before an import.
    @discardableResult
    func copyAside(_ label: String) -> URL {
        let url = directory.appending(path: "onit.\(label)-\(Int(Date().timeIntervalSince1970 * 1000)).json")
        queue.sync { _ = try? FileManager.default.copyItem(at: fileURL, to: url) }
        return url
    }

    /// Writes atomically (temp file, then rename). `sync` waits for it, and for any queued writes.
    func write(_ data: Data, sync: Bool = false) {
        let work: @Sendable () -> Void = { [self] in
            lastKnownData = data
            try? data.write(to: fileURL, options: .atomic)
        }
        sync ? queue.sync(execute: work) : queue.async(execute: work)
    }

    /// Calls `handler` when something other than OnIt changes the file (a text editor, a sync tool).
    func watch(_ handler: @escaping @Sendable (Snapshot) -> Void) {
        queue.async { [self] in
            onChange = handler
            rearm()
        }
    }

    /// Watches the folder (renames, new files) and the file itself (in-place edits). Atomic saves
    /// replace the file, so this re-arms after every check.
    private func rearm() {
        sources.forEach { $0.cancel() }
        sources = [directory.path, fileURL.path].compactMap { path in
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self] in self?.scheduleCheck() }
            source.setCancelHandler { close(fd) }
            source.resume()
            return source
        }
    }

    private func scheduleCheck() {
        pendingCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.check() }
        pendingCheck = item
        queue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    /// On `queue`. Skips our own writes and files that don't decode yet (half-saved edits).
    private func check() {
        rearm()
        guard let onChange, let data = try? Data(contentsOf: fileURL), data != lastKnownData,
              let snapshot = try? Snapshot.decode(data) else { return }
        lastKnownData = data
        onChange(snapshot)
    }

    /// For tests: run a check now, or wait for queued I/O.
    func checkNow() { queue.sync { check() } }
    func drain() { queue.sync {} }
}
