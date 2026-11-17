import Foundation

/// The four fixed columns every board has, in left-to-right order. Later sits first, before
/// Todo, because it's the backlog that work is picked up from.
enum Column: String, Codable, CaseIterable, Sendable, Identifiable {
    case later, todo, doing, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "Todo"
        case .doing: "In Progress"
        case .done: "Done"
        case .later: "Later"
        }
    }

    /// The column to the left, in board order.
    var previous: Column? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else { return nil }
        return Self.allCases[index - 1]
    }

    /// The column to the right, in board order.
    var next: Column? {
        guard let index = Self.allCases.firstIndex(of: self), index + 1 < Self.allCases.count else { return nil }
        return Self.allCases[index + 1]
    }
}
