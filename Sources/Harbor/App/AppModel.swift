import AppKit
import HarborCore
import Observation
import ServiceManagement

enum ManagerSection: String, CaseIterable, Identifiable {
    case items, style, position, screens, behavior
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .items: "square.grid.2x2"
        case .style: "paintbrush"
        case .position: "rectangle.bottomhalf.inset.filled"
        case .screens: "display.2"
        case .behavior: "gearshape.2"
        }
    }
}

/// App-wide state shared by docks, the Manager, Settings and the menu bar.
@MainActor
@Observable
final class AppModel {
    let file: ConfigFile
    let store: DockStore
    let running = RunningApps()
    let nativeDock = NativeDock()

    var selectedDockID: UUID?
    var managerSection: ManagerSection = .items
    var showingLibraryFor: UUID?
    var itemSheet: ItemRef?
    var showingRestore = false

    @ObservationIgnored private(set) var dockController: DockController!
    @ObservationIgnored let windows = WindowManager()

    /// HARBOR_HOME points the app at another config folder, for development and screenshots.
    static var configDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["HARBOR_HOME"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return ConfigFile.defaultDirectory
    }

    init(file: ConfigFile = ConfigFile(directory: AppModel.configDirectory)) {
        self.file = file
        store = DockStore.load(from: file)
        dockController = DockController(model: self)
        windows.model = self
        Appearance.shared.sync(store.settings)
        Celebration.shared.model = self
        observeAppearance()
        // Development aid for screenshots: open the Manager on a given section.
        if let raw = ProcessInfo.processInfo.environment["HARBOR_SECTION"], let section = ManagerSection(rawValue: raw) {
            managerSection = section
        }
    }

    /// Keeps the shared palette in step with the settings so every window recolours live.
    private func observeAppearance() {
        withObservationTracking {
            _ = store.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                Appearance.shared.sync(self.store.settings)
                self.observeAppearance()
            }
        }
    }

    func start() {
        applyPresentation()
        dockController.start()
        HotkeyCenter.shared.start(model: self)
        // Roaming pets come back at launch even if no dock showing a pet has drawn yet.
        RoamCoordinator.shared.start(model: self)
        WeatherController.shared.start(model: self)
        ScreenCorners.shared.start(model: self)
        AssistantBridge.shared.start(model: self)
        if store.settings.deepHideNativeDock {
            _ = nativeDock.deepHide()
        } else if nativeDock.isHiddenByHarbor {
            // A previous session ended without restoring the macOS Dock.
            _ = nativeDock.restore()
        }
        if store.settings.onboardingDone && PermissionsGate.shouldShow(model: self) {
            windows.showPermissions(intro: true)
        }
        if !store.settings.onboardingDone {
            windows.showOnboarding()
        } else if store.settings.showManagerOnLaunch || store.docks.isEmpty {
            windows.showManager()
        }
        if ProcessInfo.processInfo.environment["HARBOR_SETTINGS"] != nil { windows.showSettings() }
        WallpaperStore.shared.startSeasonalChanges()
        // HARBOR_WALLPAPERS opens the wallpaper browser, searching for its value when that isn't "1";
        // a development aid for screenshots.
        if ProcessInfo.processInfo.environment["HARBOR_WALLPAPERS"] != nil { WallpaperWindow.shared.show() }
    }

    func stop() {
        store.flush()
        if store.settings.deepHideNativeDock { _ = nativeDock.restore() }
    }

    // MARK: Commands used by several surfaces

    func newDock() {
        let first = store.docks.isEmpty
        let dock = store.createDock()
        selectedDockID = dock.id
        managerSection = .items
        windows.showManager()
        if first { celebrateFirstDock() }
    }

    func celebrateFirstDock() {
        Celebration.shared.play(window: windows.managerWindow)
    }

    func openInManager(_ id: UUID, section: ManagerSection = .items) {
        selectedDockID = id
        managerSection = section
        windows.showManager()
    }

    func applyPresentation() {
        let policy: NSApplication.ActivationPolicy = store.settings.presentation == .menuBar ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    /// Hides or restores the macOS Dock right away. Turning it on with no visible dock
    /// first creates one from the macOS Dock's contents so the Mac is never left without one.
    @discardableResult
    func setReplaceNativeDock(_ on: Bool) -> String? {
        if on && !store.docks.contains(where: { $0.enabled }) {
            let dock = store.createDock(name: "Dock")
            store.updateDock(dock.id) {
                $0.position.mode = .pinned
                $0.position.edge = .bottom
            }
            addNativeDockCopy(to: dock.id)
            selectedDockID = dock.id
        }
        store.updateSettings { $0.deepHideNativeDock = on }
        let ok = on ? nativeDock.deepHide() : nativeDock.restore()
        return ok ? nil : "macOS didn't accept the change. Try again, or restart your Mac if it keeps failing."
    }

    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            store.updateSettings { $0.launchAtLogin = on }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Whether copy should use its playful variant.
    var playful: Bool { store.settings.playfulCopy }

    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}
