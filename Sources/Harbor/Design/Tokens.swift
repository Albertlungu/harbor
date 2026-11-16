import AppKit
import HarborCore
import SwiftUI

/// Color roles from replica/design/tokens.json (light) and tokens.dark.json (dark).
enum Tokens {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    static let surface = dynamic(0xF2F2F4, 0x2A2A2D)
    static let dockSolid = dynamic(0xE9E9EE, 0x323236)
    static let border = dynamic(0xD9D9DE, 0x3D3D42)
    static let text = dynamic(0x1D1D1F, 0xF2F2F5)
    static let textMuted = dynamic(0x5F5F66, 0xA8A8B0)
    static let labelBackground = dynamic(0x2B2B30, 0xF0F0F3)
    static let onLabel = dynamic(0xFFFFFF, 0x1D1D1F)
    static let accent = dynamic(0x3A5CCC, 0x7D9CFF)
    static let onAccent = dynamic(0xFFFFFF, 0x10131C)
    static let indicator = dynamic(0x3C3C43, 0xD6D6DC)
    static let badge = dynamic(0xD93A2F, 0xFF5F52)
    static let onBadge = dynamic(0xFFFFFF, 0x1D0302)
    static let danger = dynamic(0xC62F2F, 0xFF7B72)
    static let success = dynamic(0x1F7A4D, 0x5FD39A)
    static let warning = dynamic(0x8A5A00, 0xF0B44C)

    enum Radius {
        static let card: CGFloat = 10
        static let popover: CGFloat = 14
        static let pill: CGFloat = 6
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
    }

    enum Motion {
        static let reveal = 0.18
        static let base = 0.22
    }

    enum Dock {
        static let indicatorSize: CGFloat = 4
        static let labelHeadroom: CGFloat = 30
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension RGBA {
    /// Relative luminance above the point where dark text reads better than light.
    var isLight: Bool { 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.55 }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
    }
}

extension Binding where Value == RGBA {
    /// Bridges a stored RGBA to SwiftUI's ColorPicker.
    var color: Binding<Color> {
        Binding<Color>(get: { wrappedValue.color }, set: { wrappedValue = RGBA($0) })
    }
}
