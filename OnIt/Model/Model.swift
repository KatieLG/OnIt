import Foundation

/// T-shirt size of a task; `nil` means unsized.
enum TaskSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case xs, s, m, l, xl
    var id: Self { self }
    var label: String { rawValue.uppercased() }
}

/// Columns in left-to-right order. Later comes first: it's the backlog work is picked up from.
enum Column: String, Codable, CaseIterable, Identifiable, Sendable {
    case later, todo, doing, done
    var id: Self { self }
    var title: String { self == .doing ? "In Progress" : rawValue.capitalized }
    var previous: Column? { offset(-1) }
    var next: Column? { offset(1) }

    private func offset(_ delta: Int) -> Column? {
        let all = Self.allCases, index = all.firstIndex(of: self)! + delta
        return all.indices.contains(index) ? all[index] : nil
    }
}

struct Board: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Lowercase `[a-z0-9_-]+`, unique across boards.
    var aliases: [String] = []
    var colorHex: String
    var isDefault = false
    var sortOrder = 0
    /// Off hides size chips, colours and points on this board's cards; sizes are kept, just not shown.
    var showsSizes = true

    /// The name as a shorthand alias: "Acme Co" → `acme-co`.
    var nameSlug: String { name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-") }
}

extension Board {
    private enum CodingKeys: String, CodingKey { case id, name, aliases, colorHex, isDefault, sortOrder, showsSizes }

    /// Spelled out so files from before `showsSizes` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  aliases: try c.decode([String].self, forKey: .aliases), colorHex: try c.decode(String.self, forKey: .colorHex),
                  isDefault: try c.decode(Bool.self, forKey: .isDefault), sortOrder: try c.decode(Int.self, forKey: .sortOrder),
                  showsSizes: try c.decodeIfPresent(Bool.self, forKey: .showsSizes) ?? true)
    }
}

/// A card. Not `Task`, which would clash with Swift concurrency.
struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var boardId: UUID
    var title: String
    var size: TaskSize?
    var column = Column.todo
    var tags: [String] = []
    /// Fractional position within the column; lower sorts first.
    var order = 0.0
    var createdAt: Date
    /// Set the first time the card enters In Progress.
    var startedAt: Date?
    /// Set on entering Done, cleared on leaving it.
    var completedAt: Date?
    /// Set by the auto-archive sweep; archived cards are hidden from the board.
    var archivedAt: Date?

    var isArchived: Bool { archivedAt != nil }
}

enum BadgeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case doing, todo, off
    var id: Self { self }
    var title: String { self == .doing ? "In Progress" : rawValue.capitalized }
}

struct AppSettings: Codable, Equatable, Sendable {
    static let archiveDaysRange = 1...60

    var defaultSize: TaskSize?
    var archiveAfterDays = 7
    var badgeMode = BadgeMode.doing
    var notifyOnAdd = false
    var launchAtLogin = false
    var laterExpanded = false
    /// `nil` means the All view.
    var lastSelectedBoardId: UUID?
}
