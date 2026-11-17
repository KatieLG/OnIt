import Foundation
import Testing
@testable import OnIt

struct ParserTests {
    static let acme = UUID()
    static let internalBoard = UUID()

    static let boards = [
        BoardAliasEntry(boardId: internalBoard, nameSlug: "internal", aliases: ["int", "i"]),
        BoardAliasEntry(boardId: acme, nameSlug: "acme-co", aliases: ["acme", "a"]),
    ]

    func parse(_ input: String) -> ParsedTask {
        ShorthandParser.parse(input, knownBoards: Self.boards)
    }

    // MARK: Spec table (§4)

    struct Case: CustomTestStringConvertible, Sendable {
        let input: String
        let title: String
        let board: String?
        let size: TaskSize?
        let tags: [String]
        var unknown: String? = nil
        var testDescription: String { input }
    }

    static let table: [Case] = [
        Case(input: "Draft Acme proposal @acme !L", title: "Draft Acme proposal", board: "acme", size: .l, tags: []),
        Case(input: "!s fix invoice bug @int #billing #urgent", title: "fix invoice bug", board: "int", size: .s, tags: ["billing", "urgent"]),
        Case(input: "Email me@acme.com about thing", title: "Email me@acme.com about thing", board: nil, size: nil, tags: []),
        Case(input: "Call Sam \\@acme about lunch", title: "Call Sam @acme about lunch", board: nil, size: nil, tags: []),
        Case(input: "Ship it !XL !m", title: "Ship it", board: nil, size: .m, tags: []),
        Case(input: "Review PR @nobody", title: "Review PR @nobody", board: nil, size: nil, tags: [], unknown: "nobody"),
        Case(input: "Tidy desk #Home #home", title: "Tidy desk", board: nil, size: nil, tags: ["home"]),
        Case(input: "   !s   ", title: "", board: nil, size: .s, tags: []),
        Case(input: "Plan Q1 !huge", title: "Plan Q1 !huge", board: nil, size: nil, tags: []),
        Case(input: "Café ☕ run @int", title: "Café ☕ run", board: "int", size: nil, tags: []),
    ]

    @Test(arguments: table)
    func specTable(_ c: Case) {
        let result = parse(c.input)
        #expect(result.title == c.title)
        #expect(result.boardAlias == c.board)
        #expect(result.size == c.size)
        #expect(result.tags == c.tags)
        #expect(result.unknownBoardAlias == c.unknown)
    }

    @Test func emptyTitleIsEmpty() {
        #expect(parse("   !s   ").isEmpty)
        #expect(parse("").isEmpty)
        #expect(parse("#only #tags @acme").isEmpty)
    }

    // MARK: Boards

    @Test func boardResolvesToID() {
        #expect(parse("x @acme").boardId == Self.acme)
        #expect(parse("x @ACME").boardId == Self.acme)
        #expect(parse("x @a").boardId == Self.acme)
    }

    @Test func boardNameSlugMatches() {
        let result = parse("Thing @acme-co")
        #expect(result.boardId == Self.acme)
        #expect(result.title == "Thing")
    }

    @Test func lastValidBoardWins() {
        let result = parse("x @acme @int")
        #expect(result.boardId == Self.internalBoard)
        #expect(result.boardAlias == "int")
    }

    @Test func unknownBoardKeptButNotFlaggedWhenAValidOneExists() {
        let result = parse("Review @nobody @acme")
        #expect(result.title == "Review @nobody")
        #expect(result.boardId == Self.acme)
        #expect(result.unknownBoardAlias == nil)
    }

    @Test func aliasesWinOverNames() {
        let x = UUID(), y = UUID()
        let boards = [
            BoardAliasEntry(boardId: x, nameSlug: "ops", aliases: []),
            BoardAliasEntry(boardId: y, nameSlug: "other", aliases: ["ops"]),
        ]
        #expect(ShorthandParser.parse("t @ops", knownBoards: boards).boardId == y)
    }

    // MARK: Sigils and escapes

    @Test func bareSigilsStayInTitle() {
        #expect(parse("a @ b ! c #").title == "a @ b ! c #")
    }

    @Test func midWordSigilsArePlainText() {
        let result = parse("price!m and tag#x and a@acme")
        #expect(result.title == "price!m and tag#x and a@acme")
        #expect(result.size == nil)
        #expect(result.tags.isEmpty)
        #expect(result.boardId == nil)
    }

    @Test func escapesAllSigils() {
        let result = parse("\\!l \\#tag \\@acme")
        #expect(result.title == "!l #tag @acme")
        #expect(result.size == nil)
        #expect(result.tags.isEmpty)
        #expect(result.boardId == nil)
    }

    @Test func backslashWithoutSigilIsKept() {
        #expect(parse("path\\to \\n").title == "path\\to \\n")
    }

    @Test func invalidTagCharactersStayInTitle() {
        let result = parse("Go #urgent! #ok")
        #expect(result.title == "Go #urgent!")
        #expect(result.tags == ["ok"])
    }

    @Test func tagsPreserveOrderAndDedupe() {
        #expect(parse("x #b #A #b #a #c_d #e-f").tags == ["b", "a", "c_d", "e-f"])
    }

    @Test func sizeIsCaseInsensitiveAndLastWins() {
        #expect(parse("x !Xs").size == .xs)
        #expect(parse("x !l !s").size == .s)
        #expect(parse("x !l !nope").size == .l)
    }

    @Test func whitespaceCollapses() {
        #expect(parse("  a\t\tb \n c  ").title == "a b c")
    }

    @Test func titleCappedAt280WithoutEllipsis() {
        let long = String(repeating: "abcd ", count: 100) + "@acme !xl"
        let result = parse(long)
        #expect(result.title.count <= 280)
        #expect(!result.title.hasSuffix("…"))
        #expect(result.boardId == Self.acme)
        #expect(result.size == .xl)

        let exact = String(repeating: "x", count: 400)
        #expect(parse(exact).title.count == 280)
    }

    @Test func unicodeTitlesSurvive() {
        #expect(parse("日本語 タスク 🎉 #tag").title == "日本語 タスク 🎉")
    }

    // MARK: Helpers

    @Test func escapeForEditingRoundTrips() {
        let titles = ["Call Sam @acme about lunch", "Plan !l now", "Use #hash", "Review PR @nobody", "Plain"]
        for title in titles {
            let escaped = ShorthandParser.escapeForEditing(title, knownBoards: Self.boards)
            let reparsed = parse(escaped)
            #expect(reparsed.title == title, "\(title) → \(escaped) → \(reparsed.title)")
            #expect(reparsed.boardId == nil)
            #expect(reparsed.size == nil)
            #expect(reparsed.tags.isEmpty)
        }
    }

    @Test func normaliseTags() {
        #expect(ShorthandParser.normaliseTags("#Urgent, invoice  #urgent bad! x") == ["urgent", "invoice", "x"])
    }
}
