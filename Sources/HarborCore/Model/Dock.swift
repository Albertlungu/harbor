import Foundation

public enum WidgetKind: String, Codable, CaseIterable, Sendable {
    case clock, link, finder, ipAddress, spacer, divider, label
    case folderStack, appStack, shelf, fileShelf
    case liveDock, runningApps, spaceAwareness, trash
    case battery, cpu, memory, gpu, bluetoothBattery
    case clicker, timer, metronome, pet

    /// Widgets limited to one instance per dock.
    public var singleInstance: Bool { self == .liveDock || self == .trash }

    /// Widgets that open a setup sheet before they are added.
    public var needsSetup: Bool {
        switch self {
        case .link, .folderStack, .appStack, .bluetoothBattery: true
        default: false
        }
    }

    /// Default size along the dock axis, in icon cells.
    public var defaultCells: Double {
        switch self {
        case .clock: 2
        case .spacer: 0.25
        case .divider: 0.25
        case .ipAddress: 2.5
        case .label: 2
        case .bluetoothBattery: 2
        default: 1
        }
    }
}

public struct WidgetConfig: Codable, Hashable, Sendable {
    /// Raw type name, kept as a string so unknown widgets from newer builds survive a round trip.
    public var type: String
    public var settings: [String: JSONValue]
    public var state: [String: JSONValue]

    public init(kind: WidgetKind, settings: [String: JSONValue] = [:]) {
        self.type = kind.rawValue
        self.settings = settings
        self.state = [:]
    }

    public var kind: WidgetKind? { WidgetKind(rawValue: type) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c(.type, "unknown")
        settings = c(.settings, [:])
        state = c(.state, [:])
    }

    public func string(_ key: String, _ fallback: String) -> String { settings[key]?.stringValue ?? fallback }
    public func double(_ key: String, _ fallback: Double) -> Double { settings[key]?.doubleValue ?? fallback }
    public func bool(_ key: String, _ fallback: Bool) -> Bool { settings[key]?.boolValue ?? fallback }
    public func strings(_ key: String) -> [String] { settings[key]?.arrayValue?.compactMap(\.stringValue) ?? [] }
}

public enum ItemKind: String, Codable, CaseIterable, Sendable { case app, file, folder, widget }
public enum FolderClick: String, Codable, CaseIterable, Sendable { case inherit, browse, openInFinder }
/// `grid` is Finder's icon view; the raw values predate the column and gallery views.
public enum FolderLayout: String, Codable, CaseIterable, Sendable { case grid, list, columns, gallery, fan }
public enum FolderSort: String, Codable, CaseIterable, Sendable {
    case name, kind, dateLastOpened, dateAdded, dateModified, dateCreated, size
}

public struct FolderOptions: Codable, Hashable, Sendable {
    public var onClick: FolderClick = .inherit
    public var layout: FolderLayout = .grid
    public var iconSize = 48.0
    public var columns = 5
    public var showNames = true
    public var sort: FolderSort = .name
    public var reverse = false
    public var foldersFirst = true
    public var showHidden = false
    public var showPreviews = true
    public var closeAfterDragOut = false
    public var openWithApp: String? = nil

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        onClick = c(.onClick, d.onClick)
        layout = c(.layout, d.layout)
        iconSize = c(.iconSize, d.iconSize)
        columns = c(.columns, d.columns)
        showNames = c(.showNames, d.showNames)
        sort = c(.sort, d.sort)
        reverse = c(.reverse, d.reverse)
        foldersFirst = c(.foldersFirst, d.foldersFirst)
        showHidden = c(.showHidden, d.showHidden)
        showPreviews = c(.showPreviews, d.showPreviews)
        closeAfterDragOut = c(.closeAfterDragOut, d.closeAfterDragOut)
        openWithApp = c(.openWithApp, d.openWithApp)
    }
}

public struct DockItem: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: ItemKind
    /// File system path for apps, files and folders.
    public var path: String?
    public var customName: String?
    public var alwaysShowLabel = false
    public var hideExtension = false
    public var hidden = false
    public var customIconID: UUID?
    public var folder = FolderOptions()
    public var widget: WidgetConfig?

    public init(kind: ItemKind, path: String? = nil, widget: WidgetConfig? = nil) {
        self.kind = kind
        self.path = path
        self.widget = widget
    }

    public static func file(at url: URL) -> DockItem {
        let kind: ItemKind
        if url.pathExtension == "app" {
            kind = .app
        } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true {
            kind = .folder
        } else {
            kind = .file
        }
        return DockItem(kind: kind, path: url.path)
    }

    public static func widget(_ kind: WidgetKind, settings: [String: JSONValue] = [:]) -> DockItem {
        DockItem(kind: .widget, widget: WidgetConfig(kind: kind, settings: settings))
    }

    public var url: URL? { path.map { URL(fileURLWithPath: $0) } }

    /// Name shown in labels and lists.
    public var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        if let widget { return widget.kind.map(WidgetCatalog.name(for:)) ?? "Unsupported widget" }
        guard let url else { return "Item" }
        if kind == .app || hideExtension { return url.deletingPathExtension().lastPathComponent }
        return url.lastPathComponent
    }

    /// Copy with fresh identity, used when duplicating docks.
    public func duplicated() -> DockItem {
        var copy = self
        copy.id = UUID()
        return copy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c(.id, UUID())
        kind = c(.kind, .file)
        path = c(.path, nil)
        customName = c(.customName, nil)
        alwaysShowLabel = c(.alwaysShowLabel, false)
        hideExtension = c(.hideExtension, false)
        hidden = c(.hidden, false)
        customIconID = c(.customIconID, nil)
        folder = c(.folder, FolderOptions())
        widget = c(.widget, nil)
    }
}

public struct Dock: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var enabled = true
    public var layout: DockLayout = .dock
    public var style = DockStyle()
    public var position = Position()
    public var screens = ScreenRules()
    public var behavior = Behavior()
    public var items: [DockItem] = []
    /// Screen-specific placement overrides keyed by screen ID.
    public var perScreenPositions: [String: Position] = [:]

    public init(name: String) {
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c(.id, UUID())
        name = c(.name, "Dock")
        enabled = c(.enabled, true)
        layout = c(.layout, .dock)
        style = c(.style, DockStyle())
        position = c(.position, Position())
        screens = c(.screens, ScreenRules())
        behavior = c(.behavior, Behavior())
        items = c(.items, [])
        perScreenPositions = c(.perScreenPositions, [:])
    }

    /// One-line placement summary for the sidebar, e.g. "Pinned · Bottom".
    public var placementSummary: String {
        if layout == .notch { return "Notch · \(position.edge.rawValue.capitalized)" }
        switch position.mode {
        case .pinned: return "Pinned · \(position.edge.rawValue.capitalized)"
        case .floating: return "Floating · \(style.orientation.rawValue.capitalized)"
        }
    }

    /// Effective orientation: pinned docks follow their edge.
    public var effectiveOrientation: Orientation {
        guard position.mode == .pinned || layout == .notch else { return style.orientation }
        switch position.edge {
        case .bottom, .top: return .horizontal
        case .left, .right: return .vertical
        }
    }

    public func hasWidget(_ kind: WidgetKind) -> Bool {
        items.contains { $0.widget?.kind == kind }
    }
}
