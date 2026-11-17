import Foundation
import os

/// Owns `stackban.json`: atomic writes, backup rotation, corruption recovery and
/// external-change watching. All file I/O after launch happens on `ioQueue`.
final class Persistence: @unchecked Sendable {
    enum LoadOutcome: Equatable, Sendable {
        /// The file existed and decoded.
        case loaded(Snapshot)
        /// No file existed; seed data was written.
        case created(Snapshot)
        /// The file failed to decode. It was moved to `corruptFile`, and data was restored from
        /// `backup` (or seed data if no valid backup existed).
        case recovered(Snapshot, corruptFile: URL, backup: URL?)

        var snapshot: Snapshot {
            switch self {
            case .loaded(let s), .created(let s), .recovered(let s, _, _): s
            }
        }
    }

    static let fileName = "stackban.json"
    static let backupCount = 3

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Stackban", directoryHint: .isDirectory)
    }

    let directory: URL
    var fileURL: URL { directory.appending(path: Self.fileName) }

    func backupURL(_ index: Int) -> URL {
        directory.appending(path: "stackban.backup-\(index).json")
    }

    private let ioQueue = DispatchQueue(label: "com.example.stackban.persistence", qos: .utility)
    private let logger = Logger(subsystem: "com.example.stackban", category: "persistence")

    // Guarded by `lock`: the bytes most recently written by us or read from disk.
    private let lock = NSLock()
    private var lastKnownData: Data?

    // Confined to `ioQueue`.
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pendingCheck: DispatchWorkItem?
    private var changeHandler: (@Sendable (Snapshot) -> Void)?

    init(directory: URL = Persistence.defaultDirectory) {
        self.directory = directory
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
    }

    // MARK: Loading

    /// Loads (or creates) the data file. Synchronous: called once at launch before any UI exists.
    func load(seed: () -> Snapshot) -> LoadOutcome {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        guard fm.fileExists(atPath: fileURL.path) else {
            let snapshot = seed()
            writeNow(snapshot)
            return .created(snapshot)
        }

        if let data = try? Data(contentsOf: fileURL), let snapshot = try? Snapshot.decode(data) {
            setLastKnown(data)
            rotateBackups()
            return .loaded(snapshot)
        }

        // Corrupt or unreadable: never overwrite it. Move it aside and recover.
        let corruptURL = uniqueURL(base: "stackban.corrupt-\(Self.timestamp())")
        do {
            try fm.moveItem(at: fileURL, to: corruptURL)
        } catch {
            logger.error("Could not move corrupt data file aside: \(error.localizedDescription)")
            // Fall back to a copy so the original bytes survive the rewrite below.
            try? fm.copyItem(at: fileURL, to: corruptURL)
        }

        for index in 1...Self.backupCount {
            let url = backupURL(index)
            if let data = try? Data(contentsOf: url), let snapshot = try? Snapshot.decode(data) {
                logger.notice("Recovered data from \(url.lastPathComponent)")
                writeNow(snapshot)
                return .recovered(snapshot, corruptFile: corruptURL, backup: url)
            }
        }

        logger.error("No valid backup found; starting from seed data")
        let snapshot = seed()
        writeNow(snapshot)
        return .recovered(snapshot, corruptFile: corruptURL, backup: nil)
    }

    /// Shifts `backup-1…-2` up one slot and copies the current file into `backup-1`.
    /// Called at most once per launch (from `load`).
    func rotateBackups() {
        let fm = FileManager.default
        try? fm.removeItem(at: backupURL(Self.backupCount))
        for index in stride(from: Self.backupCount - 1, through: 1, by: -1) {
            let from = backupURL(index)
            if fm.fileExists(atPath: from.path) {
                try? fm.moveItem(at: from, to: backupURL(index + 1))
            }
        }
        do {
            try fm.copyItem(at: fileURL, to: backupURL(1))
        } catch {
            logger.error("Backup rotation failed: \(error.localizedDescription)")
        }
    }

    /// Saves a copy of the current file before a destructive import.
    @discardableResult
    func writePreImportBackup() -> URL? {
        let url = uniqueURL(base: "stackban.pre-import-\(Self.timestamp())")
        return ioQueue.sync {
            do {
                try FileManager.default.copyItem(at: fileURL, to: url)
                return url
            } catch {
                logger.error("Pre-import backup failed: \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: Writing

    /// Queues an atomic write on the I/O queue.
    func write(_ data: Data) {
        ioQueue.async { [self] in
            writeAtomically(data)
        }
    }

    /// Writes synchronously (termination, launch). Waits for any queued writes first.
    func writeSync(_ data: Data) {
        ioQueue.sync {
            writeAtomically(data)
        }
    }

    private func writeNow(_ snapshot: Snapshot) {
        guard let data = try? snapshot.encoded() else { return }
        writeSync(data)
    }

    /// Writes to a temporary file in the same directory, then renames it over the real file.
    private func writeAtomically(_ data: Data) {
        let tempURL = directory.appending(path: ".stackban.json.\(UUID().uuidString).tmp")
        do {
            try data.write(to: tempURL)
            // Record before the rename so the watcher recognises its own write.
            setLastKnown(data)
            if rename(tempURL.path, fileURL.path) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            logger.error("Write failed: \(error.localizedDescription)")
        }
    }

    // MARK: Watching

    /// Watches for changes made by anything other than this app (hand edits, sync tools)
    /// and calls `handler` with the newly decoded snapshot. Our own writes are ignored.
    func startWatching(_ handler: @escaping @Sendable (Snapshot) -> Void) {
        ioQueue.async { [self] in
            changeHandler = handler
            armDirectorySource()
            armFileSource()
        }
    }

    func stopWatching() {
        ioQueue.sync {
            directorySource?.cancel()
            directorySource = nil
            fileSource?.cancel()
            fileSource = nil
            changeHandler = nil
        }
    }

    private func armDirectorySource() {
        directorySource?.cancel()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: ioQueue
        )
        source.setEventHandler { [weak self] in self?.scheduleCheck() }
        source.setCancelHandler { close(fd) }
        source.resume()
        directorySource = source
    }

    /// The file's inode changes on every atomic rename, so this is re-armed after each check.
    private func armFileSource() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: ioQueue
        )
        source.setEventHandler { [weak self] in self?.scheduleCheck() }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    private func scheduleCheck() {
        pendingCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.checkForExternalChange() }
        pendingCheck = item
        ioQueue.asyncAfter(deadline: .now() + .milliseconds(250), execute: item)
    }

    private func checkForExternalChange() {
        guard changeHandler != nil else { return }
        armFileSource()
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard data != currentLastKnown() else { return }
        guard let snapshot = try? Snapshot.decode(data) else {
            // Possibly a half-written edit; the next event will try again.
            logger.notice("External change did not decode; ignoring for now")
            return
        }
        setLastKnown(data)
        logger.info("Reloading after external change")
        changeHandler?(snapshot)
    }

    /// Exposed for tests: runs a check immediately on the I/O queue.
    func checkForExternalChangeNow() {
        ioQueue.sync { checkForExternalChange() }
    }

    /// Blocks until all queued I/O has finished. Used by tests and termination.
    func drain() {
        ioQueue.sync {}
    }

    // MARK: Helpers

    private func setLastKnown(_ data: Data) {
        lock.withLock { lastKnownData = data }
    }

    private func currentLastKnown() -> Data? {
        lock.withLock { lastKnownData }
    }

    /// `<base>.json`, or `<base>-2.json`, `-3`… if that name is taken.
    private func uniqueURL(base: String) -> URL {
        var candidate = directory.appending(path: "\(base).json")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base)-\(suffix).json")
            suffix += 1
        }
        return candidate
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
