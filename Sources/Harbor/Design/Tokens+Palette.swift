import AppKit
import HarborCore
import Observation
import SwiftUI

/// The live look: the chosen palette and the switches that decide how much of it shows.
/// A shared instance because Tokens are read from plain static contexts; AppModel keeps it
/// in step with the settings, and views that read it re-render when it changes.
@MainActor
@Observable
final class Appearance {
    static let shared = Appearance()

    private(set) var palette: Palette = .pastel
    private(set) var categoryColors = true
    private(set) var paletteGlass = false
    private(set) var roundedType = true

    func sync(_ settings: AppSettings) {
        if palette != settings.palette { palette = settings.palette }
        if categoryColors != settings.categoryColors { categoryColors = settings.categoryColors }
        if paletteGlass != settings.paletteGlass { paletteGlass = settings.paletteGlass }
        if roundedType != settings.roundedType { roundedType = settings.roundedType }
    }

    var accent: Color { Self.accent(of: palette) }

    var onAccent: Color {
        let spec = palette.spec.accent
        return Tokens.dynamic(Self.readable(on: spec.light), Self.readable(on: spec.dark))
    }

    /// Category hue, or a neutral grey when category colours are off.
    func hue(for category: WidgetCategory) -> Color {
        guard categoryColors else { return Tokens.textMuted }
        if category == .all { return accent }
        return Self.color(palette.spec.hue(for: category))
    }

    var fontDesign: Font.Design? { roundedType ? .rounded : nil }

    // MARK: Palette previews, independent of the active palette

    static func accent(of palette: Palette) -> Color {
        palette == .system ? Color(nsColor: .controlAccentColor) : color(palette.spec.accent)
    }

    static func color(_ pair: HexPair) -> Color { Tokens.dynamic(pair.light, pair.dark) }

    private static func readable(on background: UInt32) -> UInt32 {
        let light: UInt32 = 0xFFFFFF, dark: UInt32 = 0x10131C
        return Contrast.ratio(light, background) >= Contrast.ratio(dark, background) ? light : dark
    }
}

extension Tokens {
    @MainActor static var accent: Color { Appearance.shared.accent }
    @MainActor static var onAccent: Color { Appearance.shared.onAccent }

    /// Soft wash laid over glass when the palette is allowed to tint docks.
    static let paletteWash = 0.12
}

private struct HarborLook: ViewModifier {
    func body(content: Content) -> some View {
        let look = Appearance.shared
        content
            .tint(look.accent)
            .fontDesign(look.fontDesign)
    }
}

extension View {
    /// Applies the palette accent and type design at a window root.
    @MainActor func harborLook() -> some View { modifier(HarborLook()) }
}
