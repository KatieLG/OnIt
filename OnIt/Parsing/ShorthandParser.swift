import Foundation

struct ParsedTask: Equatable, Sendable {
    var title = ""
    var boardId: UUID?
    var size: TaskSize?
    var tags: [String] = []
    /// An `@alias` that matched no board, reported only when no other board token matched.
    var unknownBoardAlias: String?
}

/// Pure shorthand parser: `Draft proposal @acme !L #sales`.
enum ShorthandParser {
    static let titleLimit = 280

    private enum Token { case board(UUID), size(TaskSize), tag(String) }

    /// What a word means as shorthand, or nil if it's plain title text.
    private static func token(_ word: Substring, boards: [Board]) -> Token? {
        let body = String(word.dropFirst())
        switch word.first {
        case "@": return resolveBoard(body, in: boards).map(Token.board)
        case "!": return TaskSize(rawValue: body.lowercased()).map(Token.size)
        case "#": return isWord(body) ? .tag(body.lowercased()) : nil
        default: return nil
        }
    }

    static func parse(_ input: String, boards: [Board]) -> ParsedTask {
        var result = ParsedTask(), words: [Substring] = [], unknown: String?
        for word in input.prefix(20_000).split(whereSeparator: \.isWhitespace) {
            // `\@acme` keeps the sigil literally.
            if word.first == "\\", let next = word.dropFirst().first, "@!#".contains(next) {
                words.append(word.dropFirst())
                continue
            }
            switch token(word, boards: boards) {
            case .board(let id): result.boardId = id
            case .size(let size): result.size = size
            case .tag(let tag): if !result.tags.contains(tag) { result.tags.append(tag) }
            case nil:
                words.append(word)
                if word.first == "@", isWord(word.dropFirst()) { unknown = String(word.dropFirst()) }
            }
        }
        result.title = String(words.joined(separator: " ").prefix(titleLimit)).trimmingCharacters(in: .whitespaces)
        result.unknownBoardAlias = result.boardId == nil ? unknown : nil
        return result
    }

    /// Aliases win over board names.
    static func resolveBoard(_ alias: String, in boards: [Board]) -> UUID? {
        let key = alias.lowercased()
        guard !key.isEmpty else { return nil }
        return (boards.first { $0.aliases.contains(key) } ?? boards.first { $0.nameSlug == key })?.id
    }

    /// "#Urgent, invoice" → ["urgent", "invoice"].
    static func normaliseTags(_ input: String) -> [String] {
        input.split { $0.isWhitespace || $0 == "," }.reduce(into: []) { tags, raw in
            let tag = raw.drop { $0 == "#" }.lowercased()
            if isWord(tag), !tags.contains(tag) { tags.append(tag) }
        }
    }

    /// Escapes words that would re-parse as tokens, so re-committing an unchanged title is lossless.
    static func escapeForEditing(_ title: String, boards: [Board]) -> String {
        title.split(separator: " ", omittingEmptySubsequences: false)
            .map { token($0, boards: boards) == nil ? String($0) : "\\" + $0 }
            .joined(separator: " ")
    }

    /// `[A-Za-z0-9_-]+`: what tags and aliases may contain.
    static func isWord(_ text: some StringProtocol) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}
