import Foundation

enum Formatting {
    /// Compact elapsed time for In Progress cards: "5m", "3h", "2d".
    static func elapsed(since start: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(start))
        switch seconds {
        case ..<3_600: return "\(max(1, Int(seconds / 60)))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }

    /// Friendly completion time for Done cards: "today", "yesterday", "Mon", "12 Nov".
    static func completion(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days >= 0, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func pointsLabel(_ points: Int) -> String {
        points == 1 ? "1 pt" : "\(points) pts"
    }
}
