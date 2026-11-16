import Foundation

public enum PositionMode: String, Codable, CaseIterable, Sendable { case pinned, floating }
public enum ScreenEdge: String, Codable, CaseIterable, Sendable { case bottom, top, left, right }
public enum EdgeAlignment: String, Codable, CaseIterable, Sendable { case start, center, end }
public enum EdgeGapPreset: String, Codable, CaseIterable, Sendable {
    case flush, small, medium, large, custom
    public var points: Double? {
        switch self {
        case .flush: 0
        case .small: 4
        case .medium: 10
        case .large: 20
        case .custom: nil
        }
    }
}
public enum DragHandleSide: String, Codable, CaseIterable, Sendable { case automatic, screenEdge, inward, start, end }

public struct Position: Codable, Hashable, Sendable {
    public var mode: PositionMode = .floating
    public var edge: ScreenEdge = .bottom
    public var alignment: EdgeAlignment = .center
    public var fullWidth = false
    public var gapPreset: EdgeGapPreset = .small
    public var customGap = 8.0
    /// Shift along the edge, positive moves away from the nearest corner.
    public var offsetAlongEdge = 0.0
    /// Inset from the pinned edge, and from both ends of the edge.
    public var edgePadding = 0.0
    public var endPadding = 0.0
    /// Floating dock center as a fraction of the screen's visible frame (0...1).
    public var floatingCenterX = 0.5
    public var floatingCenterY = 0.5
    public var alwaysShowDragHandle = false
    public var dragHandleSide: DragHandleSide = .automatic
    public var locked = false
    public var desktopWidgetMode = false

    public init() {}

    public var gap: Double { gapPreset.points ?? min(max(customGap, 0), 64) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        mode = c(.mode, d.mode)
        edge = c(.edge, d.edge)
        alignment = c(.alignment, d.alignment)
        fullWidth = c(.fullWidth, d.fullWidth)
        gapPreset = c(.gapPreset, d.gapPreset)
        customGap = c(.customGap, d.customGap)
        offsetAlongEdge = c(.offsetAlongEdge, d.offsetAlongEdge)
        edgePadding = c(.edgePadding, d.edgePadding)
        endPadding = c(.endPadding, d.endPadding)
        floatingCenterX = c(.floatingCenterX, d.floatingCenterX)
        floatingCenterY = c(.floatingCenterY, d.floatingCenterY)
        alwaysShowDragHandle = c(.alwaysShowDragHandle, d.alwaysShowDragHandle)
        dragHandleSide = c(.dragHandleSide, d.dragHandleSide)
        locked = c(.locked, d.locked)
        desktopWidgetMode = c(.desktopWidgetMode, d.desktopWidgetMode)
    }
}

public struct ScreenRules: Codable, Hashable, Sendable {
    public var showOnAllScreens = false
    public var assignedScreenIDs: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showOnAllScreens = c(.showOnAllScreens, false)
        assignedScreenIDs = c(.assignedScreenIDs, [])
    }
}

public enum RevealTrigger: String, Codable, CaseIterable, Sendable { case atEdge, nearEdge }
public enum SpacesVisibility: String, Codable, CaseIterable, Sendable { case allSpaces, activeSpace, pinnedSpace }
public enum ActiveAppClick: String, Codable, CaseIterable, Sendable { case none, minimize, hide, cycleWindows }
public enum DelayPreset: String, Codable, CaseIterable, Sendable { case fast, standard, slow, custom }

public struct Hotkey: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
    public var modifiers: UInt32
    public var display: String

    public init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }
}

public struct Behavior: Codable, Hashable, Sendable {
    public var autoHide = false
    public var revealTrigger: RevealTrigger = .atEdge
    public var revealDistance = 24.0
    public var hidePreset: DelayPreset = .standard
    public var customHideDelay = 0.6
    public var revealPreset: DelayPreset = .standard
    public var customRevealDelay = 0.15

    public var showOn: SpacesVisibility = .allSpaces
    public var hideInFullscreen = true
    public var hideOnWindowHover = false
    public var showAtEdgeWhileHidden = false
    public var reserveSpace = true

    public var activeAppClick: ActiveAppClick = .cycleWindows

    public var showBadges = false
    public var fullBadgeNumber = false
    public var badgeDisabledApps: [String] = []

    public var hotkey: Hotkey? = nil
    /// Seconds after a hotkey reveal before hiding again; 0 means never.
    public var hideAgainAfter = 0.0

    public init() {}

    public var hideDelay: Double {
        switch hidePreset {
        case .fast: 0.2
        case .standard: 0.6
        case .slow: 1.5
        case .custom: min(max(customHideDelay, 0), 5)
        }
    }

    public var revealDelay: Double {
        switch revealPreset {
        case .fast: 0
        case .standard: 0.15
        case .slow: 0.5
        case .custom: min(max(customRevealDelay, 0), 2)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        autoHide = c(.autoHide, d.autoHide)
        revealTrigger = c(.revealTrigger, d.revealTrigger)
        revealDistance = c(.revealDistance, d.revealDistance)
        hidePreset = c(.hidePreset, d.hidePreset)
        customHideDelay = c(.customHideDelay, d.customHideDelay)
        revealPreset = c(.revealPreset, d.revealPreset)
        customRevealDelay = c(.customRevealDelay, d.customRevealDelay)
        showOn = c(.showOn, d.showOn)
        hideInFullscreen = c(.hideInFullscreen, d.hideInFullscreen)
        hideOnWindowHover = c(.hideOnWindowHover, d.hideOnWindowHover)
        showAtEdgeWhileHidden = c(.showAtEdgeWhileHidden, d.showAtEdgeWhileHidden)
        reserveSpace = c(.reserveSpace, d.reserveSpace)
        activeAppClick = c(.activeAppClick, d.activeAppClick)
        showBadges = c(.showBadges, d.showBadges)
        fullBadgeNumber = c(.fullBadgeNumber, d.fullBadgeNumber)
        badgeDisabledApps = c(.badgeDisabledApps, d.badgeDisabledApps)
        hotkey = c(.hotkey, d.hotkey)
        hideAgainAfter = c(.hideAgainAfter, d.hideAgainAfter)
    }
}
