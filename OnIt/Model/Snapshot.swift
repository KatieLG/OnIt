import Foundation

/// The entire persisted state: what lives in `onit.json`.
struct Snapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Snapshot.currentSchemaVersion
    var boards: [Board]
    var tasks: [TaskItem]
    var settings: AppSettings

    init(boards: [Board], tasks: [TaskItem], settings: AppSettings = AppSettings()) {
        self.boards = boards
        self.tasks = tasks
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, boards, tasks, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Snapshot.currentSchemaVersion
        boards = try c.decode([Board].self, forKey: .boards)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }

    // MARK: Seed

    /// First-launch boards: Home and Work, with Work as the default (tasks without an `@board`),
    /// and one plain example task on each.
    static func seed(now: Date = Date()) -> Snapshot {
        let home = Board(
            name: "Home", aliases: ["home", "h"], colorHex: "#4CAF7A", isDefault: false, sortOrder: 0
        )
        let work = Board(
            name: "Work", aliases: ["work", "w"], colorHex: "#5B8DEF", isDefault: true, sortOrder: 1
        )
        let homeTask = TaskItem(
            boardId: home.id, title: "Pick up dry cleaning", column: .todo, order: 1024, createdAt: now
        )
        let workTask = TaskItem(
            boardId: work.id, title: "Reply to the project update email", column: .todo, order: 2048, createdAt: now
        )
        return Snapshot(boards: [home, work], tasks: [homeTask, workTask])
    }

    // MARK: Coding

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601Parsing.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid ISO8601 date: \(string)"
            )
        }
        return decoder
    }

    func encoded() throws -> Data {
        try Snapshot.makeEncoder().encode(self)
    }

    /// Decodes data of any supported schema version, running migrations first.
    static func decode(_ data: Data) throws -> Snapshot {
        try Migrations.decodeSnapshot(from: data)
    }
}

/// Accepts ISO8601 timestamps with or without fractional seconds (hand edits vary).
enum ISO8601Parsing {
    static func date(from string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601) { return date }
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? withFraction.parse(string)
    }
}
