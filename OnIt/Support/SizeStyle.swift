import AppKit
import SwiftUI

/// Size colours, load points and meanings, in one place.
enum SizeStyle {
    /// Over this many points, In Progress is tinted as a gentle warning.
    static let doingWarning = 13

    private static let table: [TaskSize: (hex: String, points: Int, meaning: String)] = [
        .xs: ("#34C3A0", 1, "A few minutes"), .s: ("#8BC34A", 2, "Under an hour"), .m: ("#F2C14E", 3, "Half a day"),
        .l: ("#F28C38", 5, "Most of a day"), .xl: ("#E5484D", 8, "Multi-day"),
    ]

    static func points(_ size: TaskSize?) -> Int { size.flatMap { table[$0]?.points } ?? 0 }
    static func meaning(_ size: TaskSize?) -> String { size.flatMap { table[$0]?.meaning } ?? "Not yet sized" }
    static func color(_ size: TaskSize?) -> Color { size.flatMap { table[$0] }.map { Color(hex: $0.hex) } ?? .secondary.opacity(0.45) }
    static func spoken(_ size: TaskSize?) -> String { size.map { "size \($0.label)" } ?? "no size" }
}

extension Color {
    /// `#RRGGBB` in sRGB; grey if malformed.
    init(hex: String) {
        let v = UInt32(hex.trimmingPrefix("#"), radix: 16) ?? 0x8E8E93
        self.init(.sRGB, red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hex: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255 + 0.5), Int(c.greenComponent * 255 + 0.5), Int(c.blueComponent * 255 + 0.5))
    }
}
