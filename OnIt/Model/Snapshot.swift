import Foundation

/// Everything in `onit.json`.
struct Snapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var schemaVersion = currentVersion
    var boards: [Board]
    var tasks: [TaskItem]
    var settings = AppSettings()

    /// First launch: Home and Work boards (Work is the default) with an example card on each.
    static func seed(now: Date = .now) -> Snapshot {
        let home = Board(name: "Home", aliases: ["home", "h"], colorHex: "#4CAF7A")
        let work = Board(name: "Work", aliases: ["work", "w"], colorHex: "#5B8DEF", isDefault: true, sortOrder: 1)
        return Snapshot(boards: [home, work], tasks: [
            TaskItem(boardId: home.id, title: "Pick up dry cleaning", size: .m, order: 1024, createdAt: now),
            TaskItem(boardId: work.id, title: "Reply to the project update email", size: .s, order: 2048, createdAt: now),
        ])
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decodes the file. When the schema changes, migrate older `schemaVersion`s here.
    static func decode(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        guard snapshot.schemaVersion == currentVersion else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Unsupported schema version \(snapshot.schemaVersion)."])
        }
        return snapshot
    }
}
