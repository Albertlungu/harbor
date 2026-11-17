import Foundation

public enum DockLayout: String, Codable, CaseIterable, Sendable { case dock, notch }
public enum Orientation: String, Codable, CaseIterable, Sendable { case horizontal, vertical }

public enum IconSizePreset: String, Codable, CaseIterable, Sendable {
    case small, medium, large, custom
    public var points: Double? {
        switch self {
        case .small: 32
        case .medium: 48
        case .large: 64
        case .custom: nil
        }
    }
}

public enum ThicknessPreset: String, Codable, CaseIterable, Sendable { case auto, thin, standard, thick, custom }
public enum SpacingPreset: String, Codable, CaseIterable, Sendable {
    case tight, normal, roomy, spacious
    public var points: Double {
        switch self {
        case .tight: 2
        case .normal: 6
        case .roomy: 12
        case .spacious: 20
        }
    }
}
public enum CornerStyle: String, Codable, CaseIterable, Sendable {
    case standard, soft, round
    /// Corner radius as a fraction of bar thickness.
    public var fraction: Double {
        switch self {
        case .standard: 0.28
        case .soft: 0.4
        case .round: 0.5
        }
    }
}
public enum BackgroundKind: String, Codable, CaseIterable, Sendable { case glass, blur, solid, none }
public enum OpacityPreset: String, Codable, CaseIterable, Sendable {
    case subtle, medium, solid, opaque
    public var value: Double {
        switch self {
        case .subtle: 0.35
        case .medium: 0.6
        case .solid: 0.85
        case .opaque: 1
        }
    }
}
public enum EffectKind: String, Codable, CaseIterable, Sendable {
    case snow, rays, fireworks
    case fireflies, leaves, petals, rain, bubbles, aurora, stars, hearts, sparkles, waves, sky, ripples, trail, seasonal
}

public enum CollapseButtonPosition: String, Codable, CaseIterable, Sendable { case auto, start, center, end }
public enum CollapseButtonStyle: String, Codable, CaseIterable, Sendable { case arrow, symbol, text, none }
public enum ExpandTrigger: String, Codable, CaseIterable, Sendable { case click, handleHover, dockHover, automatic }

public struct CollapseSettings: Codable, Hashable, Sendable {
    public var enabled = false
    public var collapsed = false
    public var buttonPosition: CollapseButtonPosition = .auto
    public var buttonStyle: CollapseButtonStyle = .arrow
    public var symbolName = "square.grid.2x2"
    public var text = "H"
    public var buttonColor: RGBA? = nil
    public var expandUsing: ExpandTrigger = .click
    public var expandAfter = 0.2
    public var collapseAfter = 0.8

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = c(.enabled, d.enabled)
        collapsed = c(.collapsed, d.collapsed)
        buttonPosition = c(.buttonPosition, d.buttonPosition)
        buttonStyle = c(.buttonStyle, d.buttonStyle)
        symbolName = c(.symbolName, d.symbolName)
        text = c(.text, d.text)
        buttonColor = c(.buttonColor, d.buttonColor)
        expandUsing = c(.expandUsing, d.expandUsing)
        expandAfter = c(.expandAfter, d.expandAfter)
        collapseAfter = c(.collapseAfter, d.collapseAfter)
    }
}

public enum NotchIdleMode: String, Codable, CaseIterable, Sendable { case show, pill, hidden }
public enum NotchBackground: String, Codable, CaseIterable, Sendable { case black, color, blur, glass }

public struct NotchSettings: Codable, Hashable, Sendable {
    public var idleMode: NotchIdleMode = .pill
    public var background: NotchBackground = .black
    public var color = RGBA(0.1, 0.1, 0.12)
    public var expandAfter = 0.1
    public var foldAfter = 0.6

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        idleMode = c(.idleMode, d.idleMode)
        background = c(.background, d.background)
        color = c(.color, d.color)
        expandAfter = c(.expandAfter, d.expandAfter)
        foldAfter = c(.foldAfter, d.foldAfter)
    }
}

public struct DockStyle: Codable, Hashable, Sendable {
    public var orientation: Orientation = .horizontal
    public var iconSizePreset: IconSizePreset = .medium
    public var customIconSize = 48.0
    public var thicknessPreset: ThicknessPreset = .auto
    public var customThickness = 64.0
    public var spacing: SpacingPreset = .normal
    public var alwaysShowNames = false
    public var cornerStyle: CornerStyle = .standard
    public var sidePadding = 8.0

    public var tintIcons = false
    public var tintColor = RGBA.accent
    public var tintIntensity = 0.5

    public var background: BackgroundKind = .glass
    public var darkGlass = false
    public var glassTint: RGBA? = nil
    public var blurDarkness = 0.5
    public var opacity: OpacityPreset = .medium
    public var solidColor = RGBA(0.91, 0.91, 0.93)

    public var showBorder = false
    public var borderWidth = 1.0
    public var borderColor = RGBA(0.5, 0.5, 0.55, 0.6)

    public var effects: Set<EffectKind> = []
    public var effectIntensity = 0.5

    public var magnify = true
    public var maxScale = 1.6
    /// How many icon widths the magnification spreads to either side.
    public var falloff = 2.5

    public var collapse = CollapseSettings()
    public var notch = NotchSettings()

    public init() {}

    public var iconSize: Double {
        iconSizePreset.points ?? min(max(customIconSize, 20), 128)
    }

    /// Bar thickness in points, measured across the dock.
    public var thickness: Double {
        let icon = iconSize
        switch thicknessPreset {
        case .auto: return icon + 16
        case .thin: return icon + 8
        case .standard: return icon + 16
        case .thick: return icon + 28
        case .custom: return min(max(customThickness, 24), 200)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        orientation = c(.orientation, d.orientation)
        iconSizePreset = c(.iconSizePreset, d.iconSizePreset)
        customIconSize = c(.customIconSize, d.customIconSize)
        thicknessPreset = c(.thicknessPreset, d.thicknessPreset)
        customThickness = c(.customThickness, d.customThickness)
        spacing = c(.spacing, d.spacing)
        alwaysShowNames = c(.alwaysShowNames, d.alwaysShowNames)
        cornerStyle = c(.cornerStyle, d.cornerStyle)
        sidePadding = c(.sidePadding, d.sidePadding)
        tintIcons = c(.tintIcons, d.tintIcons)
        tintColor = c(.tintColor, d.tintColor)
        tintIntensity = c(.tintIntensity, d.tintIntensity)
        background = c(.background, d.background)
        darkGlass = c(.darkGlass, d.darkGlass)
        glassTint = c(.glassTint, d.glassTint)
        blurDarkness = c(.blurDarkness, d.blurDarkness)
        opacity = c(.opacity, d.opacity)
        solidColor = c(.solidColor, d.solidColor)
        showBorder = c(.showBorder, d.showBorder)
        borderWidth = c(.borderWidth, d.borderWidth)
        borderColor = c(.borderColor, d.borderColor)
        // Decoded leniently so an effect from a newer build drops out instead of clearing them all.
        effects = Set(c(.effects, [String]()).compactMap(EffectKind.init(rawValue:)))
        effectIntensity = c(.effectIntensity, d.effectIntensity)
        magnify = c(.magnify, d.magnify)
        maxScale = c(.maxScale, d.maxScale)
        falloff = c(.falloff, d.falloff)
        collapse = c(.collapse, d.collapse)
        notch = c(.notch, d.notch)
    }
}
