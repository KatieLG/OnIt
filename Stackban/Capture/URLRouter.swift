import Foundation

enum URLAction: Equatable, Sendable {
    case add(text: String)
    /// `board` is the raw alias from `?board=`, if any.
    case open(board: String?)
    case toggle
    case invalid(reason: String)
}

/// Turns `stackban://` URLs into actions. Pure; no side effects.
enum URLRouter {
    static let scheme = "stackban"

    static func route(_ url: URL) -> URLAction {
        route(url.absoluteString)
    }

    /// Parses the URL string by hand so that `+` stays a literal plus and malformed
    /// percent-escapes are reported rather than silently dropped.
    static func route(_ string: String) -> URLAction {
        guard let colon = string.firstIndex(of: ":") else {
            return .invalid(reason: "Not a stackban:// link.")
        }
        guard string[..<colon].lowercased() == scheme else {
            return .invalid(reason: "Not a stackban:// link.")
        }

        var rest = string[string.index(after: colon)...]
        while rest.hasPrefix("/") { rest = rest.dropFirst() }

        let (pathPart, queryPart): (Substring, Substring?) = {
            if let q = rest.firstIndex(of: "?") {
                return (rest[..<q], rest[rest.index(after: q)...])
            }
            return (rest, nil)
        }()

        // Drop any fragment from the query.
        let query = queryPart.map { part -> Substring in
            if let hash = part.firstIndex(of: "#") { return part[..<hash] }
            return part
        }

        let command = pathPart
            .split(separator: "/", omittingEmptySubsequences: true)
            .first.map { String($0).lowercased() } ?? ""

        let params: [String: String]
        switch parseQuery(query) {
        case .success(let parsed): params = parsed
        case .failure(let reason): return .invalid(reason: reason)
        }

        switch command {
        case "add":
            guard let text = params["text"] else {
                return .invalid(reason: "The add link had no text parameter.")
            }
            return .add(text: text)
        case "open":
            let board = params["board"].map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
            return .open(board: board?.isEmpty == true ? nil : board)
        case "toggle":
            return .toggle
        case "":
            return .invalid(reason: "The link had no command (expected add, open or toggle).")
        default:
            return .invalid(reason: "Unknown command '\(command)'.")
        }
    }

    private enum QueryResult {
        case success([String: String])
        case failure(String)
    }

    /// First occurrence of each key wins. `+` is literal.
    private static func parseQuery(_ query: Substring?) -> QueryResult {
        guard let query, !query.isEmpty else { return .success([:]) }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first, let key = String(rawKey).removingPercentEncoding else {
                return .failure("The link contained a malformed parameter name.")
            }
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            guard let value = rawValue.removingPercentEncoding else {
                return .failure("The '\(key)' parameter was not valid percent-encoded UTF-8.")
            }
            if result[key.lowercased()] == nil {
                result[key.lowercased()] = value
            }
        }
        return .success(result)
    }
}
