import Foundation
import Testing
@testable import OnIt

struct ParserTests {
    static let internalBoard = Board(name: "Internal", aliases: ["int", "i"], colorHex: "#000000")
    static let acme = Board(name: "Acme Co", aliases: ["acme", "a"], colorHex: "#000000")
    static let boards = [internalBoard, acme]

    func parse(_ input: String) -> ParsedTask { ShorthandParser.parse(input, boards: Self.boards) }

    struct Case: CustomTestStringConvertible, Sendable {
        let input: String, title: String, board: Board?, size: TaskSize?, tags: [String]
        var unknown: String? = nil
        var testDescription: String { input }
    }

    static let table: [Case] = [
        Case(input: "Draft Acme proposal @acme !L", title: "Draft Acme proposal", board: acme, size: .l, tags: []),
        Case(input: "!s fix invoice bug @int #billing #urgent", title: "fix invoice bug", board: internalBoard, size: .s, tags: ["billing", "urgent"]),
        Case(input: "Email me@acme.com about thing", title: "Email me@acme.com about thing", board: nil, size: nil, tags: []),
        Case(input: "Call Sam \\@acme about lunch", title: "Call Sam @acme about lunch", board: nil, size: nil, tags: []),
        Case(input: "Ship it !XL !m", title: "Ship it", board: nil, size: .m, tags: []),
        Case(input: "Review PR @nobody", title: "Review PR @nobody", board: nil, size: nil, tags: [], unknown: "nobody"),
        Case(input: "Tidy desk #Home #home", title: "Tidy desk", board: nil, size: nil, tags: ["home"]),
        Case(input: "   !s   ", title: "", board: nil, size: .s, tags: []),
        Case(input: "Plan Q1 !huge", title: "Plan Q1 !huge", board: nil, size: nil, tags: []),
        Case(input: "Café ☕ run @int", title: "Café ☕ run", board: internalBoard, size: nil, tags: []),
    ]

    @Test(arguments: table)
    func specTable(_ c: Case) {
        let result = parse(c.input)
        #expect(result == ParsedTask(title: c.title, boardId: c.board?.id, size: c.size, tags: c.tags, unknownBoardAlias: c.unknown))
    }

    @Test func boards() {
        #expect(parse("x @ACME").boardId == Self.acme.id)
        #expect(parse("x @a").boardId == Self.acme.id)
        #expect(parse("Thing @acme-co") == ParsedTask(title: "Thing", boardId: Self.acme.id))
        #expect(parse("x @acme @int").boardId == Self.internalBoard.id, "last valid board wins")
        #expect(parse("Review @nobody @acme") == ParsedTask(title: "Review @nobody", boardId: Self.acme.id), "no warning when another board matched")
        #expect(parse("#only #tags @acme").title.isEmpty)
    }

    @Test func aliasesWinOverNames() {
        let named = Board(name: "Ops", colorHex: "#000000"), aliased = Board(name: "Other", aliases: ["ops"], colorHex: "#000000")
        #expect(ShorthandParser.parse("t @ops", boards: [named, aliased]).boardId == aliased.id)
    }

    @Test func plainTextIsLeftAlone() {
        #expect(parse("a @ b ! c #").title == "a @ b ! c #")
        #expect(parse("price!m and tag#x and a@acme") == ParsedTask(title: "price!m and tag#x and a@acme"))
        #expect(parse("\\!l \\#tag \\@acme") == ParsedTask(title: "!l #tag @acme"))
        #expect(parse("path\\to \\n").title == "path\\to \\n")
        #expect(parse("Go #urgent! #ok") == ParsedTask(title: "Go #urgent!", tags: ["ok"]))
        #expect(parse("  a\t\tb \n c  ").title == "a b c")
        #expect(parse("日本語 タスク 🎉 #tag").title == "日本語 タスク 🎉")
    }

    @Test func tagsAndSizes() {
        #expect(parse("x #b #A #b #a #c_d #e-f").tags == ["b", "a", "c_d", "e-f"])
        #expect(parse("x !Xs").size == .xs)
        #expect(parse("x !l !nope").size == .l)
    }

    @Test func titleCappedAt280WithoutEllipsis() {
        let result = parse(String(repeating: "abcd ", count: 100) + "@acme !xl")
        #expect(result.title.count <= 280 && !result.title.hasSuffix("…"))
        #expect(result.boardId == Self.acme.id && result.size == .xl)
        #expect(parse(String(repeating: "x", count: 400)).title.count == 280)
    }

    @Test func escapeForEditingRoundTrips() {
        for title in ["Call Sam @acme about lunch", "Plan !l now", "Use #hash", "Review PR @nobody", "Plain"] {
            let reparsed = parse(ShorthandParser.escapeForEditing(title, boards: Self.boards))
            #expect(reparsed.title == title && reparsed.boardId == nil && reparsed.size == nil && reparsed.tags.isEmpty)
        }
    }

    @Test func normaliseTags() {
        #expect(ShorthandParser.normaliseTags("#Urgent, invoice  #urgent bad! x") == ["urgent", "invoice", "x"])
    }
}
