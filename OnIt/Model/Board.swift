import Foundation

struct Board: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Lowercase, `[a-z0-9_-]+`, unique across all boards.
    var aliases: [String]
    var colorHex: String
    var isDefault: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        colorHex: String,
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }

    /// The board's name as usable in shorthand: lowercased, whitespace runs replaced by `-`.
    /// "Acme Co" → "acme-co".
    var nameSlug: String { Board.slug(for: name) }

    static func slug(for name: String) -> String {
        name.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "-")
    }

    /// A short label for card footers in All view.
    var shortName: String {
        name.count <= 12 ? name : String(name.prefix(11)) + "…"
    }

    // Lenient decoding so hand-edited files with missing optional keys still load.
    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, colorHex, isDefault, sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = (try c.decodeIfPresent([String].self, forKey: .aliases) ?? []).map { $0.lowercased() }
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#8E8E93"
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}
