import Foundation

/// What the parser needs to know about one board to resolve `@alias` tokens.
struct BoardAliasEntry: Equatable, Sendable {
    var boardId: UUID
    /// The board name in slug form ("Acme Co" → "acme-co").
    var nameSlug: String
    /// Lowercase aliases.
    var aliases: [String]

    init(boardId: UUID, nameSlug: String, aliases: [String]) {
        self.boardId = boardId
        self.nameSlug = nameSlug.lowercased()
        self.aliases = aliases.map { $0.lowercased() }
    }

    init(board: Board) {
        self.init(boardId: board.id, nameSlug: board.nameSlug, aliases: board.aliases)
    }
}

struct ParsedTask: Equatable, Sendable {
    var title: String
    /// Raw alias as typed (without `@`), nil if no board token resolved.
    var boardAlias: String?
    /// The resolved board, nil if absent or unknown.
    var boardId: UUID?
    /// nil if no `!size` token was given.
    var size: TaskSize?
    var tags: [String]
    /// Set when an `@alias` was given but did not resolve and no other board token did.
    var unknownBoardAlias: String?

    var isEmpty: Bool { title.isEmpty }
}

/// Pure shorthand parser: `Draft proposal @acme !L #sales`.
enum ShorthandParser {
    static let titleLimit = 280
    /// Inputs beyond this are cut before tokenising, as a guard against pathological input.
    static let inputLimit = 20_000

    private static let sigils: Set<Character> = ["@", "!", "#"]

    static func parse(_ input: String, knownBoards: [BoardAliasEntry]) -> ParsedTask {
        let input = input.count > inputLimit ? String(input.prefix(inputLimit)) : input

        var titleWords: [Substring] = []
        var boardAlias: String?
        var boardId: UUID?
        var unknownAlias: String?
        var size: TaskSize?
        var tags: [String] = []

        for word in input.split(whereSeparator: { $0.isWhitespace }) {
            guard let first = word.first else { continue }

            // `\@acme` → literal `@acme`.
            if first == "\\", word.count > 1, sigils.contains(word[word.index(after: word.startIndex)]) {
                titleWords.append(word.dropFirst())
                continue
            }

            let body = String(word.dropFirst())
            switch first {
            case "@":
                if !body.isEmpty, let id = resolveBoard(body, in: knownBoards) {
                    boardAlias = body
                    boardId = id
                } else {
                    titleWords.append(word)
                    if isAliasSyntax(body) { unknownAlias = body }
                }
            case "!":
                if let parsed = TaskSize(shorthand: body) {
                    size = parsed
                } else {
                    titleWords.append(word)
                }
            case "#":
                if isTagSyntax(body) {
                    let tag = body.lowercased()
                    if !tags.contains(tag) { tags.append(tag) }
                } else {
                    titleWords.append(word)
                }
            default:
                titleWords.append(word)
            }
        }

        var title = titleWords.joined(separator: " ")
        if title.count > titleLimit {
            title = String(title.prefix(titleLimit))
            title = title.trimmingCharacters(in: .whitespaces)
        }

        return ParsedTask(
            title: title,
            boardAlias: boardAlias,
            boardId: boardId,
            size: size,
            tags: tags,
            unknownBoardAlias: boardId == nil ? unknownAlias : nil
        )
    }

    /// Aliases are matched before board names so an explicit alias always wins.
    static func resolveBoard(_ alias: String, in boards: [BoardAliasEntry]) -> UUID? {
        let key = alias.lowercased()
        if let match = boards.first(where: { $0.aliases.contains(key) }) { return match.boardId }
        if let match = boards.first(where: { $0.nameSlug == key }) { return match.boardId }
        return nil
    }

    /// Normalises free-form tag input ("#Urgent, invoice") into stored tags.
    static func normaliseTags(_ input: String) -> [String] {
        var result: [String] = []
        for raw in input.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            let body = raw.hasPrefix("#") ? String(raw.dropFirst()) : String(raw)
            guard isTagSyntax(body) else { continue }
            let tag = body.lowercased()
            if !result.contains(tag) { result.append(tag) }
        }
        return result
    }

    /// Prepares an existing title for the inline editor: words that would otherwise be
    /// re-interpreted as tokens get a backslash, so committing an unchanged title is lossless.
    static func escapeForEditing(_ title: String, knownBoards: [BoardAliasEntry]) -> String {
        title.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            guard let first = word.first else { return String(word) }
            let body = String(word.dropFirst())
            let wouldParse: Bool
            switch first {
            case "@": wouldParse = !body.isEmpty && resolveBoard(body, in: knownBoards) != nil
            case "!": wouldParse = TaskSize(shorthand: body) != nil
            case "#": wouldParse = isTagSyntax(body)
            default: wouldParse = false
            }
            return wouldParse ? "\\" + word : String(word)
        }.joined(separator: " ")
    }

    // MARK: Character classes

    static func isTagSyntax(_ body: String) -> Bool {
        !body.isEmpty && body.unicodeScalars.allSatisfy(isWordScalar)
    }

    static func isAliasSyntax(_ body: String) -> Bool {
        isTagSyntax(body)
    }

    /// `[a-z0-9_-]+` after lowercasing: what a stored alias may contain.
    static func isValidStoredAlias(_ alias: String) -> Bool {
        alias == alias.lowercased() && isTagSyntax(alias)
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "_", "-": true
        default: false
        }
    }
}
