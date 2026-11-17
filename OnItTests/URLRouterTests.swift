import Foundation
import Testing
@testable import OnIt

struct URLRouterTests {
    func route(_ string: String) -> URLAction { URLRouter.route(string) }
    func isInvalid(_ string: String) -> Bool { if case .invalid = route(string) { true } else { false } }

    @Test func add() {
        #expect(route("onit://add?text=Draft%20proposal%20%40c%20%21L%20%23sales") == .add("Draft proposal @c !L #sales"))
        #expect(route("onit://add?text=1+1%20is%202") == .add("1+1 is 2"), "+ is literal")
        #expect(route("onit://add?text=Caf%C3%A9%20%E2%98%95") == .add("Café ☕"))
        #expect(route("onit://add?text=") == .add(""), "the store rejects the empty title")
        #expect(route("onit://add?text=one&text=two&other=3") == .add("one"), "first parameter wins")
        let long = String(repeating: "a", count: 50_000)
        #expect(route("onit://add?text=\(long)") == .add(long))
        #expect(URLRouter.route(URL(string: "onit://add?text=Hello%20%23world")!) == .add("Hello #world"))
    }

    @Test func raycastScriptEncodingRoundTrips() {
        // Mirrors the script's perl: everything except [A-Za-z0-9_.~-] is %XX-encoded per UTF-8 byte.
        let input = "Draft Acme proposal @acme !L #sales & more = 100% ☕ + \\@x"
        let encoded = input.utf8.map { byte in
            let char = Character(Unicode.Scalar(byte))
            return byte < 0x80 && (char.isLetter || char.isNumber || "_.~-".contains(char)) ? String(char) : String(format: "%%%02X", byte)
        }.joined()
        #expect(route("onit://add?text=\(encoded)") == .add(input))
    }

    @Test func openAndToggle() {
        #expect(route("onit://open") == .open(board: nil))
        #expect(route("onit://open?board=acme") == .open(board: "acme"))
        #expect(route("onit://open?board=%40acme") == .open(board: "acme"))
        #expect(route("onit://open?board=") == .open(board: nil))
        #expect(route("onit://toggle") == .toggle)
        #expect(route("ONIT://ADD?text=x") == .add("x"))
        #expect(route("onit:toggle") == .toggle)
        #expect(route("onit:///open/") == .open(board: nil))
    }

    @Test func invalid() {
        for string in ["onit://add", "onit://add?text=%ZZoops", "onit://add?text=%C3", "onit://delete?id=1", "onit://",
                       "https://example.com/add?text=x", "nonsense"] {
            #expect(isInvalid(string), "\(string)")
        }
    }
}
