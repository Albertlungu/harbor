import Foundation

public enum Presentation: String, Codable, CaseIterable, Sendable { case menuBar, dockApp, both }
public enum AttentionStyle: String, Codable, CaseIterable, Sendable { case bounce, flashOnce, badgeOnly, off }
public enum GestureAction: String, Codable, CaseIterable, Sendable {
    case nothing, revealInFinder, toggleHidden, showOnlyThis, quit, minimizeFront
}
public enum ClickModifier: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable { case command, option, optionCommand, shift, middle }
public enum ScrollAction: String, Codable, CaseIterable, Sendable { case cycleWindows, showHide }
public enum PreviewSort: String, Codable, CaseIterable, Sendable { case recent, alphabetical, creation, screenPosition }

public struct PreviewSettings: Codable, Hashable, Sendable {
    public var enabled = false
    public var currentSpaceOnly = false
    public var includeMinimized = true
    public var includeHidden = true
    public var excludedApps: [String] = []
    public var titleFilters: [String] = []
    public var sort: PreviewSort = .recent
    public var showDelay = 0.25
    public var hideDelay = 0.3
    public var cardWidth = 220.0
    public var maxRows = 3
    public var maxColumns = 3
    public var showAppName = true
    public var showWindowTitle = true
    public var compactAt = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = c(.enabled, d.enabled)
        currentSpaceOnly = c(.currentSpaceOnly, d.currentSpaceOnly)
        includeMinimized = c(.includeMinimized, d.includeMinimized)
        includeHidden = c(.includeHidden, d.includeHidden)
        excludedApps = c(.excludedApps, d.excludedApps)
        titleFilters = c(.titleFilters, d.titleFilters)
        sort = c(.sort, d.sort)
        showDelay = c(.showDelay, d.showDelay)
        hideDelay = c(.hideDelay, d.hideDelay)
        cardWidth = c(.cardWidth, d.cardWidth)
        maxRows = c(.maxRows, d.maxRows)
        maxColumns = c(.maxColumns, d.maxColumns)
        showAppName = c(.showAppName, d.showAppName)
        showWindowTitle = c(.showWindowTitle, d.showWindowTitle)
        compactAt = c(.compactAt, d.compactAt)
    }
}

public struct NewDockDefaults: Codable, Hashable, Sendable {
    public var customizeStyle = false
    public var style = DockStyle()
    public var customizeBehavior = false
    public var behavior = Behavior()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customizeStyle = c(.customizeStyle, false)
        style = c(.style, DockStyle())
        customizeBehavior = c(.customizeBehavior, false)
        behavior = c(.behavior, Behavior())
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    // General
    public var launchAtLogin = false
    public var showManagerOnLaunch = false
    public var presentation: Presentation = .menuBar
    public var deepHideNativeDock = false
    public var opaqueBackgrounds = false
    public var checkForUpdates = true
    public var onboardingDone = false

    // Behavior
    public var folderClick: FolderClick = .browse
    public var folderApp: String? = nil
    public var showMoveToTrash = true
    public var magneticSnapping = true
    public var reserveDockSpace = false
    public var reserveOnDrag = false
    public var showRunningIndicators = true
    public var indicatorColor: RGBA? = nil
    public var excludedApps: [String] = []
    public var attentionStyle: AttentionStyle = .bounce
    public var clickGestures = false
    public var clickGestureActions: [ClickModifier: GestureAction] = [
        .command: .revealInFinder, .option: .toggleHidden, .optionCommand: .showOnlyThis,
        .shift: .nothing, .middle: .quit,
    ]
    public var scrollGestures = false
    public var scrollAction: ScrollAction = .cycleWindows
    public var hideFromScreenSharing = false

    public var newDocks = NewDockDefaults()
    public var previews = PreviewSettings()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        launchAtLogin = c(.launchAtLogin, d.launchAtLogin)
        showManagerOnLaunch = c(.showManagerOnLaunch, d.showManagerOnLaunch)
        presentation = c(.presentation, d.presentation)
        deepHideNativeDock = c(.deepHideNativeDock, d.deepHideNativeDock)
        opaqueBackgrounds = c(.opaqueBackgrounds, d.opaqueBackgrounds)
        checkForUpdates = c(.checkForUpdates, d.checkForUpdates)
        onboardingDone = c(.onboardingDone, d.onboardingDone)
        folderClick = c(.folderClick, d.folderClick)
        folderApp = c(.folderApp, d.folderApp)
        showMoveToTrash = c(.showMoveToTrash, d.showMoveToTrash)
        magneticSnapping = c(.magneticSnapping, d.magneticSnapping)
        reserveDockSpace = c(.reserveDockSpace, d.reserveDockSpace)
        reserveOnDrag = c(.reserveOnDrag, d.reserveOnDrag)
        showRunningIndicators = c(.showRunningIndicators, d.showRunningIndicators)
        indicatorColor = c(.indicatorColor, d.indicatorColor)
        excludedApps = c(.excludedApps, d.excludedApps)
        attentionStyle = c(.attentionStyle, d.attentionStyle)
        clickGestures = c(.clickGestures, d.clickGestures)
        clickGestureActions = c(.clickGestureActions, d.clickGestureActions)
        scrollGestures = c(.scrollGestures, d.scrollGestures)
        scrollAction = c(.scrollAction, d.scrollAction)
        hideFromScreenSharing = c(.hideFromScreenSharing, d.hideFromScreenSharing)
        newDocks = c(.newDocks, d.newDocks)
        previews = c(.previews, d.previews)
    }
}

public struct KnownScreen: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var systemName: String
    public var customName: String?
    public var lastSeen: Date

    public init(id: String, systemName: String, lastSeen: Date = Date()) {
        self.id = id
        self.systemName = systemName
        self.lastSeen = lastSeen
    }

    public var displayName: String { customName?.isEmpty == false ? customName! : systemName }
}

public struct Theme: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var style: DockStyle

    public init(name: String, style: DockStyle) {
        self.name = name
        self.style = style
    }
}

public struct IconAsset: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    /// File name inside the app's Icons folder.
    public var fileName: String
    public var sourceURL: String?

    public init(fileName: String, sourceURL: String? = nil) {
        self.fileName = fileName
        self.sourceURL = sourceURL
    }
}

public struct ShelfEntry: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var path: String
    public var added = Date()

    public init(path: String) {
        self.path = path
    }
}

/// The whole persisted configuration.
public struct Config: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Config.currentSchemaVersion
    public var docks: [Dock] = []
    public var settings = AppSettings()
    public var knownScreens: [KnownScreen] = []
    public var themes: [Theme] = []
    public var icons: [IconAsset] = []
    /// Copies held by Shelf widgets; one collection shared by every Shelf.
    public var shelf: [ShelfEntry] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c(.schemaVersion, 1)
        docks = c(.docks, [])
        settings = c(.settings, AppSettings())
        knownScreens = c(.knownScreens, [])
        themes = c(.themes, [])
        icons = c(.icons, [])
        shelf = c(.shelf, [])
    }
}
