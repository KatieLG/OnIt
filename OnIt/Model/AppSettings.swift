import Foundation

enum BadgeMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case doing, todo, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doing: "In Progress"
        case .todo: "Todo"
        case .off: "Off"
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var defaultSize: TaskSize? = nil
    var archiveAfterDays: Int = 7
    var badgeMode: BadgeMode = .doing
    var notifyOnAdd: Bool = false
    var launchAtLogin: Bool = false
    var laterExpanded: Bool = false
    /// `nil` means the All view.
    var lastSelectedBoardId: UUID? = nil

    static let archiveDaysRange = 1...60

    init() {}

    private enum CodingKeys: String, CodingKey {
        case defaultSize, archiveAfterDays, badgeMode, notifyOnAdd, launchAtLogin, laterExpanded, lastSelectedBoardId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultSize = (try c.decodeIfPresent(String.self, forKey: .defaultSize)).flatMap(TaskSize.init(shorthand:))
        let days = try c.decodeIfPresent(Int.self, forKey: .archiveAfterDays) ?? 7
        archiveAfterDays = min(max(days, Self.archiveDaysRange.lowerBound), Self.archiveDaysRange.upperBound)
        badgeMode = (try c.decodeIfPresent(String.self, forKey: .badgeMode)).flatMap(BadgeMode.init(rawValue:)) ?? .doing
        notifyOnAdd = try c.decodeIfPresent(Bool.self, forKey: .notifyOnAdd) ?? false
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        laterExpanded = try c.decodeIfPresent(Bool.self, forKey: .laterExpanded) ?? false
        lastSelectedBoardId = try c.decodeIfPresent(UUID.self, forKey: .lastSelectedBoardId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(defaultSize, forKey: .defaultSize)
        try c.encode(archiveAfterDays, forKey: .archiveAfterDays)
        try c.encode(badgeMode, forKey: .badgeMode)
        try c.encode(notifyOnAdd, forKey: .notifyOnAdd)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(laterExpanded, forKey: .laterExpanded)
        try c.encode(lastSelectedBoardId, forKey: .lastSelectedBoardId)
    }
}
