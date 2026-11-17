import Foundation

/// A task card. Named `TaskItem` to avoid clashing with Swift concurrency's `Task`.
struct TaskItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var boardId: UUID
    var title: String
    var size: TaskSize?
    var column: Column
    var tags: [String]
    /// Fractional index; lower sorts first.
    var order: Double
    var createdAt: Date
    var updatedAt: Date
    /// Set the first time the task moves to `doing`.
    var startedAt: Date?
    /// Set on entering `done`; cleared when moved out.
    var completedAt: Date?
    /// Set by the auto-archive sweep. Archived tasks are hidden from the board.
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        boardId: UUID,
        title: String,
        size: TaskSize? = nil,
        column: Column = .todo,
        tags: [String] = [],
        order: Double = 0,
        createdAt: Date,
        updatedAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.boardId = boardId
        self.title = title
        self.size = size
        self.column = column
        self.tags = tags
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
    }

    var isArchived: Bool { archivedAt != nil }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, boardId, title, size, column, tags, order
        case createdAt, updatedAt, startedAt, completedAt, archivedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        boardId = try c.decode(UUID.self, forKey: .boardId)
        title = try c.decode(String.self, forKey: .title)
        // Unknown size strings decode as "no size" rather than failing the whole file.
        size = (try c.decodeIfPresent(String.self, forKey: .size)).flatMap(TaskSize.init(shorthand:))
        column = (try c.decodeIfPresent(String.self, forKey: .column)).flatMap(Column.init(rawValue:)) ?? .todo
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
        let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        createdAt = created
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    /// Encodes absent optionals as explicit `null`s so the file matches the documented schema.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(boardId, forKey: .boardId)
        try c.encode(title, forKey: .title)
        try c.encode(size, forKey: .size)
        try c.encode(column, forKey: .column)
        try c.encode(tags, forKey: .tags)
        try c.encode(order, forKey: .order)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(archivedAt, forKey: .archivedAt)
    }
}
