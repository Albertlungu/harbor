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
        // Development aid for screenshots: open the Manager on a given section.
        if let raw = ProcessInfo.processInfo.environment["HARBOR_SECTION"], let section = ManagerSection(rawValue: raw) {
            managerSection = section
        }
    }

    func start() {
        applyPresentation()
        dockController.start()
        HotkeyCenter.shared.start(model: self)
        AssistantBridge.shared.start(model: self)
        if store.settings.deepHideNativeDock { _ = nativeDock.deepHide() }
        if !store.settings.onboardingDone {
            windows.showOnboarding()
        } else if store.settings.showManagerOnLaunch || store.docks.isEmpty {
            windows.showManager()
        }
    }

    func stop() {
        store.flush()
        if store.settings.deepHideNativeDock { _ = nativeDock.restore() }
    }

    // MARK: Commands used by several surfaces

    func newDock() {
        let dock = store.createDock()
        selectedDockID = dock.id
        managerSection = .items
        windows.showManager()
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

    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            store.updateSettings { $0.launchAtLogin = on }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}
