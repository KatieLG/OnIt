import Foundation

/// Top bar filters. Empty sets mean no restriction; `nil` in `sizes` means unsized.
struct TaskFilter: Equatable, Sendable {
    var text = ""
    var sizes: Set<TaskSize?> = []
    var tags: Set<String> = []

    var isActive: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty || !sizes.isEmpty || !tags.isEmpty }

    /// Every text term must appear in the title or a tag (`#term`: tags only). Sizes and tags match any.
    func matches(_ task: TaskItem) -> Bool {
        guard sizes.isEmpty || sizes.contains(task.size), tags.isEmpty || !tags.isDisjoint(with: task.tags) else { return false }
        return text.split(whereSeparator: \.isWhitespace).allSatisfy { term in
            let tagOnly = term.hasPrefix("#"), needle = tagOnly ? term.dropFirst() : term
            func has(_ text: String) -> Bool { text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return needle.isEmpty || task.tags.contains(where: has) || (!tagOnly && has(task.title))
        }
    }
}
