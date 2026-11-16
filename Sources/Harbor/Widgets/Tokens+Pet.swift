import AppKit
import SwiftUI

extension Tokens {
    /// Colors for the seal pup. They are fixed warm tones rather than UI roles, so the pet keeps its look in both appearances.
    enum Pet {
        private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }

        static let furTop = dynamic(0xEDE8E0, 0xC4BFB7)
        static let furBottom = dynamic(0xCDC7BE, 0x9F9A93)
        static let bellyTop = dynamic(0xFAF7F1, 0xDAD5CC)
        static let bellyBottom = dynamic(0xEEE9E0, 0xC3BEB5)
        static let flipper = dynamic(0xC2BBB1, 0x8F8A83)
        static let outline = dynamic(0xA39D93, 0x7A766F)
        static let eye = Color(red: 0.12, green: 0.10, blue: 0.14)
        static let blush = dynamic(0xF28C9F, 0xF28C9F)
        static let nose = dynamic(0x6B5F66, 0x3E363B)
        static let whisker = dynamic(0x8E877D, 0x6A655E)
    }
}
