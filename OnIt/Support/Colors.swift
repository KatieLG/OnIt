import AppKit
import SwiftUI

extension Color {
    /// `#RRGGBB` or `RRGGBB` in sRGB.
    init?(hex: String) {
        guard let rgb = HexColor.components(hex) else { return nil }
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }

    /// `#RRGGBB` for the colour converted to sRGB.
    var hexString: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return HexColor.string(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
    }
}

enum HexColor {
    static func components(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    static func string(r: Double, g: Double, b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
