import SwiftUI

/// The single place that maps sizes to colours, load points and chip styling (spec §7).
enum SizeStyle {
    struct Style: Sendable {
        let hex: String?
        let points: Int
        let meaning: String
        /// Chip text colour chosen for contrast against `hex`. Identical in light and dark mode,
        /// because the chip background is a solid colour in both.
        let darkText: Bool
    }

    /// Soft load warning for the In Progress column (cosmetic only).
    static let doingLoadWarningThreshold = 13

    static func style(for size: TaskSize?) -> Style {
        switch size {
        case .xs: Style(hex: "#34C3A0", points: 1, meaning: "A few minutes", darkText: true)
        case .s: Style(hex: "#8BC34A", points: 2, meaning: "Under an hour", darkText: true)
        case .m: Style(hex: "#F2C14E", points: 3, meaning: "Half a day", darkText: true)
        case .l: Style(hex: "#F28C38", points: 5, meaning: "Most of a day", darkText: true)
        case .xl: Style(hex: "#E5484D", points: 8, meaning: "Multi-day", darkText: false)
        case nil: Style(hex: nil, points: 0, meaning: "Not yet sized", darkText: false)
        }
    }

    static func points(for size: TaskSize?) -> Int { style(for: size).points }

    static func color(for size: TaskSize?) -> Color {
        guard let hex = style(for: size).hex, let color = Color(hex: hex) else {
            return Color.secondary.opacity(0.45)
        }
        return color
    }

    static func chipText(for size: TaskSize?) -> Color {
        guard size != nil else { return .primary }
        return style(for: size).darkText ? Color.black.opacity(0.82) : .white
    }

    static func chipBackground(for size: TaskSize?) -> Color {
        size == nil ? Color.secondary.opacity(0.18) : color(for: size)
    }

    static func label(for size: TaskSize?) -> String { size?.label ?? "–" }

    static func accessibilityName(for size: TaskSize?) -> String {
        size.map { "size \($0.label)" } ?? "no size"
    }

    /// Load threshold above which a column's points figure is tinted.
    static func warningThreshold(for column: Column) -> Int? {
        column == .doing ? doingLoadWarningThreshold : nil
    }
}
