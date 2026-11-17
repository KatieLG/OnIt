import Foundation

/// T-shirt size of a task. `nil` (no size) is modelled as `TaskSize?` throughout.
enum TaskSize: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case xs, s, m, l, xl

    var id: String { rawValue }

    /// Upper-case label used on chips and in menus ("XS"…"XL").
    var label: String { rawValue.uppercased() }

    /// Parses the body of a `!size` token, case-insensitively.
    init?(shorthand: String) {
        self.init(rawValue: shorthand.lowercased())
    }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: TaskSize, rhs: TaskSize) -> Bool { lhs.rank < rhs.rank }
}
