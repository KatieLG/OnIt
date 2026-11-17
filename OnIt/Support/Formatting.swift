import Foundation

enum Formatting {
    /// Time in progress: "5m", "3h", "2d".
    static func elapsed(since start: Date, now: Date = .now) -> String {
        let s = max(0, now.timeIntervalSince(start))
        return s < 3600 ? "\(max(1, Int(s / 60)))m" : s < 86400 ? "\(Int(s / 3600))h" : "\(Int(s / 86400))d"
    }

    /// When a card was done: "today", "yesterday", a weekday this week, else "12 Nov".
    static func completion(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        return switch calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0 {
        case 0: "today"
        case 1: "yesterday"
        case 2..<7: date.formatted(.dateTime.weekday(.abbreviated))
        default: date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    static func points(_ n: Int) -> String { n == 1 ? "1 pt" : "\(n) pts" }
}
