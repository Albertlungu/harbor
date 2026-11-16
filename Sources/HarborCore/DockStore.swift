import Foundation
import Observation

/// What temporarily hid an enabled dock. Runtime only; cleared on relaunch.
public enum HideSource: String, Sendable {
    case menu = "the menu"
    case shortcut = "a keyboard shortcut"
    case shortcutsApp = "Shortcuts"
    case focus = "a Focus filter"
    case assistant = "an AI assistant"
    case manager = "the Manager"
}

/// The single source of truth for docks and settings. Every UI surface mutates
/// the configuration through these commands.
@MainActor
@Observable
public final class DockStore {
    public private(set) var config: Config
    public private(set) var runtimeHidden: [UUID: HideSource] = [:]
    public private(set) var editing: Set<UUID> = []
    public private(set) var lastSaveError: String?
    public var recoveredFromDamage = false

    @ObservationIgnored public var file: ConfigFile?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored public var saveDelay: Duration = .milliseconds(400)
    @ObservationIgnored private var settingsClipboard: (DockStyle, Behavior)?

    public init(config: Config = Config(), file: ConfigFile? = nil) {
        self.config = config
        self.file = file
    }

    public static func load(from file: ConfigFile) -> DockStore {
        let (config, recovered) = file.load()
        let store = DockStore(config: config, file: file)
        store.recoveredFromDamage = recovered
        return store
    }

    // MARK: Lookup

    public var docks: [Dock] { config.docks }
    public var settings: AppSettings { config.settings }

    public func dock(_ id: UUID) -> Dock? { config.docks.first { $0.id == id } }

    public func isVisible(_ id: UUID) -> Bool {
        guard let dock = dock(id) else { return false }
        return dock.enabled && runtimeHidden[id] == nil
    }

    // MARK: Docks

    @discardableResult
    public func createDock(name: String? = nil) -> Dock {
        var dock = Dock(name: name ?? nextDockName())
        let defaults = config.settings.newDocks
        if defaults.customizeStyle { dock.style = defaults.style }
        if defaults.customizeBehavior { dock.behavior = defaults.behavior }
        config.docks.append(dock)
        changed()
        return dock
    }

    public func nextDockName() -> String {
        let used = Set(config.docks.map(\.name))
        var n = config.docks.count + 1
        while used.contains("Dock \(n)") { n += 1 }
        return "Dock \(n)"
    }

    public func updateDock(_ id: UUID, _ change: (inout Dock) -> Void) {
        guard let i = config.docks.firstIndex(where: { $0.id == id }) else { return }
        var dock = config.docks[i]
        change(&dock)
        guard dock != config.docks[i] else { return }
        config.docks[i] = dock
        changed()
    }

    /// Renames a dock. Empty or whitespace-only names are rejected.
    @discardableResult
    public func rename(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        updateDock(id) { $0.name = trimmed }
        return true
    }

    public func setEnabled(_ id: UUID, _ enabled: Bool) {
        updateDock(id) { $0.enabled = enabled }
        if !enabled { editing.remove(id) }
    }

    @discardableResult
    public func duplicate(_ id: UUID) -> Dock? {
        guard let i = config.docks.firstIndex(where: { $0.id == id }) else { return nil }
        let original = config.docks[i]
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " Copy"
        copy.items = original.items.map { $0.duplicated() }
        copy.screens = ScreenRules()
        copy.perScreenPositions = [:]
        config.docks.insert(copy, at: i + 1)
        changed()
        return copy
    }

    public func delete(_ id: UUID) {
        config.docks.removeAll { $0.id == id }
        runtimeHidden[id] = nil
        editing.remove(id)
        changed()
    }

    public func moveDocks(from source: IndexSet, to destination: Int) {
        config.docks.move(fromOffsets: source, toOffset: destination)
        changed()
    }

    public func copySettings(from id: UUID) {
        guard let dock = dock(id) else { return }
        settingsClipboard = (dock.style, dock.behavior)
    }

    public var canPasteSettings: Bool { settingsClipboard != nil }

    /// Applies copied style and behavior; keeps the target's identity, items, layout,
    /// position, screens and shortcut.
    public func pasteSettings(to id: UUID) {
        guard let (style, behavior) = settingsClipboard else { return }
        updateDock(id) { dock in
            let hotkey = dock.behavior.hotkey
            dock.style = style
            dock.behavior = behavior
            dock.behavior.hotkey = hotkey
        }
    }

    // MARK: Runtime visibility and edit mode

    public func hide(_ id: UUID, source: HideSource) {
        runtimeHidden[id] = source
        editing.remove(id)
    }

    public func show(_ id: UUID) {
        runtimeHidden[id] = nil
    }

    /// Toggles runtime visibility. A disabled dock is enabled instead.
    public func toggle(_ id: UUID, source: HideSource) {
        guard let dock = dock(id) else { return }
        if !dock.enabled {
            setEnabled(id, true)
            runtimeHidden[id] = nil
        } else if runtimeHidden[id] != nil {
            runtimeHidden[id] = nil
        } else {
            hide(id, source: source)
        }
    }

    public func setEditing(_ id: UUID, _ on: Bool) {
        guard let dock = dock(id), dock.enabled else { return }
        if on { editing.insert(id) } else { editing.remove(id) }
    }

    // MARK: Items

    public func addItems(_ items: [DockItem], to dockID: UUID, at index: Int? = nil) {
        updateDock(dockID) { dock in
            let i = min(index ?? dock.items.count, dock.items.count)
            dock.items.insert(contentsOf: items, at: i)
        }
    }

    /// Adds a widget unless it is single-instance and already present.
    @discardableResult
    public func addWidget(_ kind: WidgetKind, to dockID: UUID, settings: [String: JSONValue] = [:], at index: Int? = nil) -> DockItem? {
        guard let dock = dock(dockID) else { return nil }
        if kind.singleInstance && dock.hasWidget(kind) { return nil }
        let item = DockItem.widget(kind, settings: settings)
        addItems([item], to: dockID, at: index)
        return item
    }

    /// Adds the system monitor widgets that are not already in the dock.
    public func addMonitorPreset(to dockID: UUID) {
        guard let dock = dock(dockID) else { return }
        let missing = WidgetCatalog.monitorPreset.filter { !dock.hasWidget($0) }
        addItems(missing.map { DockItem.widget($0) }, to: dockID)
    }

    public func updateItem(_ itemID: UUID, in dockID: UUID, _ change: (inout DockItem) -> Void) {
        updateDock(dockID) { dock in
            guard let i = dock.items.firstIndex(where: { $0.id == itemID }) else { return }
            change(&dock.items[i])
        }
    }

    public func removeItem(_ itemID: UUID, from dockID: UUID) {
        updateDock(dockID) { $0.items.removeAll { $0.id == itemID } }
    }

    public func moveItems(in dockID: UUID, from source: IndexSet, to destination: Int) {
        updateDock(dockID) { $0.items.move(fromOffsets: source, toOffset: destination) }
    }

    /// Moves one item to a new index, used by drag-to-reorder on the dock.
    public func moveItem(_ itemID: UUID, in dockID: UUID, to index: Int) {
        updateDock(dockID) { dock in
            guard let from = dock.items.firstIndex(where: { $0.id == itemID }) else { return }
            let item = dock.items.remove(at: from)
            dock.items.insert(item, at: min(max(index, 0), dock.items.count))
        }
    }

    // MARK: Settings, screens, themes

    public func updateSettings(_ change: (inout AppSettings) -> Void) {
        var s = config.settings
        change(&s)
        guard s != config.settings else { return }
        config.settings = s
        changed()
    }

    /// Records a connected screen, refreshing its last-seen date.
    public func noteScreen(id: String, name: String, now: Date = Date()) {
        if let i = config.knownScreens.firstIndex(where: { $0.id == id }) {
            config.knownScreens[i].systemName = name
            config.knownScreens[i].lastSeen = now
        } else {
            config.knownScreens.append(KnownScreen(id: id, systemName: name, lastSeen: now))
            changed()
        }
    }

    public func renameScreen(_ id: String, to name: String) {
        guard let i = config.knownScreens.firstIndex(where: { $0.id == id }) else { return }
        config.knownScreens[i].customName = name
        changed()
    }

    /// Forgets a screen and removes it from every dock's assignments.
    public func forgetScreen(_ id: String) {
        config.knownScreens.removeAll { $0.id == id }
        for i in config.docks.indices {
            config.docks[i].screens.assignedScreenIDs.removeAll { $0 == id }
            config.docks[i].perScreenPositions[id] = nil
        }
        changed()
    }

    public func saveTheme(named name: String, from dockID: UUID) {
        guard let dock = dock(dockID) else { return }
        config.themes.append(Theme(name: name, style: dock.style))
        changed()
    }

    public func applyTheme(_ themeID: UUID, to dockID: UUID) {
        guard let theme = config.themes.first(where: { $0.id == themeID }) else { return }
        updateDock(dockID) { dock in
            let collapsed = dock.style.collapse.collapsed
            dock.style = theme.style
            dock.style.collapse.collapsed = collapsed
        }
    }

    public func updateThemes(_ change: (inout [Theme]) -> Void) {
        change(&config.themes)
        changed()
    }

    public func updateIcons(_ change: (inout [IconAsset]) -> Void) {
        change(&config.icons)
        changed()
    }

    public func updateShelf(_ change: (inout [ShelfEntry]) -> Void) {
        change(&config.shelf)
        changed()
    }

    // MARK: Whole-config replacement

    /// Replaces the configuration, used by restore and import.
    public func replaceConfig(_ new: Config) {
        config = new
        runtimeHidden = [:]
        editing = []
        changed()
    }

    /// Merges a backup: docks with the same ID are replaced, others are added; settings are overwritten.
    public func importBackup(_ backup: Config) -> (added: Int, replaced: Int) {
        var added = 0, replaced = 0
        for dock in backup.docks {
            if let i = config.docks.firstIndex(where: { $0.id == dock.id }) {
                config.docks[i] = dock
                replaced += 1
            } else {
                config.docks.append(dock)
                added += 1
            }
        }
        config.settings = backup.settings
        for icon in backup.icons where !config.icons.contains(where: { $0.id == icon.id }) {
            config.icons.append(icon)
        }
        changed()
        return (added, replaced)
    }

    // MARK: Persistence

    private func changed() {
        guard let file else { return }
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeNow(file)
        }
    }

    /// Writes pending changes immediately, e.g. on quit.
    public func flush() {
        saveTask?.cancel()
        if let file { writeNow(file) }
    }

    private func writeNow(_ file: ConfigFile) {
        do {
            try file.save(config)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }
}
