import Foundation

/// Board filters from the top bar. Empty sets mean "no restriction".
struct TaskFilter: Equatable, Sendable {
    var text: String = ""
    /// `nil` inside the set means "unsized".
    var sizes: Set<TaskSize?> = []
    var tags: Set<String> = []

    var isActive: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || !sizes.isEmpty || !tags.isEmpty
    }

    /// Text: every whitespace-separated term must appear in the title or a tag
    /// (case- and diacritic-insensitive; a leading `#` matches tags only).
    /// Sizes and tags: the task must match any one of the selected values.
    func matches(_ task: TaskItem) -> Bool {
        if !sizes.isEmpty, !sizes.contains(task.size) { return false }
        if !tags.isEmpty, tags.isDisjoint(with: task.tags) { return false }

        for term in text.split(whereSeparator: \.isWhitespace) {
            if term.hasPrefix("#") {
                let tagTerm = term.dropFirst()
                if tagTerm.isEmpty { continue }
                if !task.tags.contains(where: { Self.contains($0, String(tagTerm)) }) { return false }
            } else {
                let term = String(term)
                if !Self.contains(task.title, term), !task.tags.contains(where: { Self.contains($0, term) }) {
                    return false
                }
            }
        }
        return true
    }

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
