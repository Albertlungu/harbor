import Foundation

public enum Palette: String, Codable, CaseIterable, Sendable { case system, pastel, ocean, sunset, forest, mono }

/// One colour for each appearance, as 0xRRGGBB.
public struct HexPair: Hashable, Sendable {
    public var light: UInt32
    public var dark: UInt32

    public init(_ light: UInt32, _ dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    public func value(dark isDark: Bool) -> UInt32 { isDark ? dark : light }
}

/// An accent plus one hue per widget category.
public struct PaletteSpec: Hashable, Sendable {
    public var accent: HexPair
    public var apps: HexPair
    public var folders: HexPair
    public var clocks: HexPair
    public var tasks: HexPair
    public var system: HexPair

    public var categories: [HexPair] { [apps, folders, clocks, tasks, system] }

    public func hue(for category: WidgetCategory) -> HexPair {
        switch category {
        case .apps: apps
        case .folders: folders
        case .clocks: clocks
        case .tasks: tasks
        case .system: system
        case .all: accent
        }
    }
}

/// The surfaces a palette colour has to stay legible on, mirroring the design tokens.
public enum PaletteSurfaces {
    public static let bg = HexPair(0xFFFFFF, 0x1E1E20)
    public static let surface = HexPair(0xF2F2F4, 0x2A2A2D)
    public static let dockSolid = HexPair(0xE9E9EE, 0x323236)
    public static let all: [HexPair] = [bg, surface, dockSolid]
}

extension Palette {
    public var title: String { rawValue.capitalized }

    /// The system palette's accent is the macOS accent colour at runtime; this spec's accent
    /// is only the fallback, and its hues are the classic system ones.
    public var spec: PaletteSpec {
        switch self {
        case .system:
            PaletteSpec(accent: HexPair(0x425DCD, 0x889ADF), apps: HexPair(0x457FD1, 0x93B5E4),
                        folders: HexPair(0x238B8B, 0x31C6C6), clocks: HexPair(0xB66D2D, 0xDDA778),
                        tasks: HexPair(0xAC5AD6, 0xD0A1E8), system: HexPair(0x249148, 0x33CC66))
        case .pastel:
            PaletteSpec(accent: HexPair(0x6E51C5, 0xA694DB), apps: HexPair(0x5780BA, 0x9BB4D6),
                        folders: HexPair(0x398B80, 0x67C1B5), clocks: HexPair(0xAE7047, 0xD2AB91),
                        tasks: HexPair(0xA863BF, 0xCDA4DA), system: HexPair(0x3A8F57, 0x6EC48B))
        case .ocean:
            PaletteSpec(accent: HexPair(0x116C9A, 0x27A7E7), apps: HexPair(0x3A7DDC, 0x8EB5EB),
                        folders: HexPair(0x1A8B96, 0x25C4D2), clocks: HexPair(0x198F72, 0x24CAA0),
                        tasks: HexPair(0x786EE5, 0xB2ADF0), system: HexPair(0x1E88AB, 0x58BFE2))
        case .sunset:
            PaletteSpec(accent: HexPair(0xBE311B, 0xEA7F6E), apps: HexPair(0xE1455F, 0xEF9CAA),
                        folders: HexPair(0xCA5F21, 0xE9A279), clocks: HexPair(0xA9751B, 0xE1A847),
                        tasks: HexPair(0xDF37A7, 0xEE96D0), system: HexPair(0xDD502C, 0xECA08D))
        case .forest:
            PaletteSpec(accent: HexPair(0x26734C, 0x3BB277), apps: HexPair(0x298E75, 0x3DC7A4),
                        folders: HexPair(0x5B8C29, 0x80C639), clocks: HexPair(0x9A792D, 0xD1AE5F),
                        tasks: HexPair(0x2A9233, 0x4BCB56), system: HexPair(0x298C8C, 0x39C6C6))
        case .mono:
            PaletteSpec(accent: HexPair(0x4A4A50, 0xCFCFD6), apps: HexPair(0x55555A, 0xB0B0B8),
                        folders: HexPair(0x65656B, 0xA0A0A8), clocks: HexPair(0x75757B, 0xC0C0C8),
                        tasks: HexPair(0x5F5F66, 0xB8B8C0), system: HexPair(0x70707A, 0xA8A8B0))
        }
    }
}
