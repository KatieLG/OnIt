import Foundation

enum URLAction: Equatable, Sendable {
    case add(String), open(board: String?), toggle, invalid(String)
}

/// Turns `onit://` links into actions. Parsed by hand so `+` stays a literal plus and bad
/// percent-escapes are reported rather than dropped.
enum URLRouter {
    static func route(_ url: URL) -> URLAction { route(url.absoluteString) }

    static func route(_ string: String) -> URLAction {
        let parts = string.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "onit" else { return .invalid("That isn't an onit:// link.") }
        let link = parts[1].drop { $0 == "/" }.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let pathAndQuery = link.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var params: [String: String] = [:]
        for pair in pathAndQuery.dropFirst().first?.split(separator: "&") ?? [] {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = kv[0].removingPercentEncoding?.lowercased(),
                  let value = (kv.count > 1 ? kv[1] : "").removingPercentEncoding
            else { return .invalid("The link wasn't valid percent-encoded UTF-8.") }
            params[key] = params[key] ?? value // first one wins
        }
        switch pathAndQuery[0].split(separator: "/").first?.lowercased() ?? "" {
        case "add": return params["text"].map(URLAction.add) ?? .invalid("The add link had no text.")
        case "toggle": return .toggle
        case "open":
            let board = params["board"].map { String($0.drop { $0 == "@" }) }
            return .open(board: board?.isEmpty == false ? board : nil)
        case let command: return .invalid("Unknown link “\(command)”. Expected add, open or toggle.")
        }
    }
}
