import AppKit
import SwiftUI

/// Size colours and load points, in one place. Sizes are relative: what an M means is up to you.
enum SizeStyle {
    /// Over this many points, In Progress is tinted as a gentle warning.
    static let doingWarning = 13

    private static let table: [TaskSize: (hex: String, points: Int)] = [
        .xs: ("#34C3A0", 1), .s: ("#8BC34A", 2), .m: ("#F2C14E", 3), .l: ("#F28C38", 5), .xl: ("#E5484D", 8),
    ]

    static func points(_ size: TaskSize?) -> Int { size.flatMap { table[$0]?.points } ?? 0 }
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
