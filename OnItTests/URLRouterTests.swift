import Foundation
import Testing
@testable import OnIt

struct URLRouterTests {
    @Test func addDecodesText() {
        #expect(URLRouter.route("onit://add?text=Draft%20proposal%20%40c%20%21L%20%23sales")
                == .add(text: "Draft proposal @c !L #sales"))
    }

    @Test func plusIsLiteral() {
        #expect(URLRouter.route("onit://add?text=1+1%20is%202") == .add(text: "1+1 is 2"))
    }

    @Test func utf8IsDecoded() {
        #expect(URLRouter.route("onit://add?text=Caf%C3%A9%20%E2%98%95") == .add(text: "Café ☕"))
    }

    @Test func raycastScriptEncodingRoundTrips() {
        // Mirrors the perl one-liner: everything except [A-Za-z0-9_.~-] is %XX-encoded per UTF-8 byte.
        let input = "Draft Acme proposal @acme !L #sales & more = 100% ☕ + \\@x"
        let encoded = input.utf8.map { byte -> String in
            let scalar = Unicode.Scalar(byte)
            let safe = (byte < 0x80) && (CharacterSet.alphanumerics.contains(scalar) || "_.~-".unicodeScalars.contains(scalar))
            return safe ? String(Character(scalar)) : String(format: "%%%02X", byte)
        }.joined()
        #expect(URLRouter.route("onit://add?text=\(encoded)") == .add(text: input))
    }

    @Test func emptyTextIsAnAddWithEmptyText() {
        // The store rejects it (empty title) and reports the failure.
        #expect(URLRouter.route("onit://add?text=") == .add(text: ""))
    }

    @Test func missingTextIsInvalid() {
        guard case .invalid = URLRouter.route("onit://add") else {
            Issue.record("expected invalid")
            return
        }
    }

    @Test func malformedPercentEncodingIsInvalid() {
        guard case .invalid = URLRouter.route("onit://add?text=%ZZoops") else {
            Issue.record("expected invalid")
            return
        }
        guard case .invalid = URLRouter.route("onit://add?text=%C3") else {
            Issue.record("expected invalid for truncated UTF-8")
            return
        }
    }

    @Test func veryLongTextIsAccepted() {
        let long = String(repeating: "a", count: 50_000)
        #expect(URLRouter.route("onit://add?text=\(long)") == .add(text: long))
    }

    @Test func openToggleAndBoard() {
        #expect(URLRouter.route("onit://open") == .open(board: nil))
        #expect(URLRouter.route("onit://open?board=acme") == .open(board: "acme"))
        #expect(URLRouter.route("onit://open?board=%40acme") == .open(board: "acme"))
        #expect(URLRouter.route("onit://open?board=") == .open(board: nil))
        #expect(URLRouter.route("onit://toggle") == .toggle)
    }

    @Test func commandsAreCaseInsensitiveAndToleratePathForms() {
        #expect(URLRouter.route("ONIT://ADD?text=x") == .add(text: "x"))
        #expect(URLRouter.route("onit:toggle") == .toggle)
        #expect(URLRouter.route("onit:///open/") == .open(board: nil))
    }

    @Test func firstParameterWins() {
        #expect(URLRouter.route("onit://add?text=one&text=two&other=3") == .add(text: "one"))
    }

    @Test func unknownCommandOrSchemeIsInvalid() {
        for string in ["onit://delete?id=1", "onit://", "https://example.com/add?text=x", "nonsense"] {
            guard case .invalid = URLRouter.route(string) else {
                Issue.record("expected invalid for \(string)")
                continue
            }
        }
    }

    @Test func routesURLObjects() throws {
        let url = try #require(URL(string: "onit://add?text=Hello%20%23world"))
        #expect(URLRouter.route(url) == .add(text: "Hello #world"))
    }
}
