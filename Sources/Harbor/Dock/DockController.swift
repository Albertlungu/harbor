import AppKit
import HarborCore
import Observation

/// Creates, places and removes dock panels as docks, screens and running apps change.
@MainActor
final class DockController {
    private unowned let model: AppModel
    private(set) var windows: [String: DockWindowController] = [:]
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var fullscreenTimer: Timer?
    private var reconcileScheduled = false
    let previews: WindowPreviewController

    init(model: AppModel) {
        self.model = model
        previews = WindowPreviewController(model: model)
    }

    func start() {
        noteScreens()
        observeModel()
        reconcile()

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.noteScreens()
                self?.reconcile()
            }
        })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reconcile()
                    self?.checkFullscreen()
                }
            })
        }
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFullscreen() }
        })

        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in handler(event); return event }) {
            monitors.append(local)
        }
        // Fullscreen apps and delayed auto-hide need a clock even when the pointer is still.
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pointerMoved()
                self?.checkFullscreen()
            }
        }
    }

    // MARK: Screens

    static func connectedScreens() -> [ConnectedScreen] {
        var slots: [String: Int] = [:]
        return NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = CGDirectDisplayID(number?.uint32Value ?? 0)
            let vendor = CGDisplayVendorNumber(displayID)
            let modelNumber = CGDisplayModelNumber(displayID)
            let key = "\(vendor)-\(modelNumber)"
            let slot = slots[key, default: 0]
            slots[key] = slot + 1
            let id = ScreenResolver.identity(vendor: vendor, model: modelNumber, serial: CGDisplaySerialNumber(displayID),
                                             name: screen.localizedName, slot: slot)
            return ConnectedScreen(id: id, name: screen.localizedName,
                                   geometry: ScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame),
                                   isMain: index == 0)
        }
    }

    private func noteScreens() {
        for screen in Self.connectedScreens() {
            model.store.noteScreen(id: screen.id, name: screen.name)
        }
    }

    // MARK: Reconcile

    private func observeModel() {
        withObservationTracking {
            _ = model.store.config
            _ = model.store.runtimeHidden
            _ = model.store.editing
            _ = model.running.apps
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleReconcile()
                self?.observeModel()
            }
        }
    }

    private func scheduleReconcile() {
        guard !reconcileScheduled else { return }
        reconcileScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.reconcileScheduled = false
            self?.reconcile()
        }
    }

    func reconcile() {
        let screens = Self.connectedScreens()
        let store = model.store
        var wanted: Set<String> = []
        for dock in store.docks where store.isVisible(dock.id) {
            let slots = SlotBuilder.slots(for: dock, running: model.running, nativeDock: model.nativeDock,
                                          settings: store.settings)
            for screen in ScreenResolver.screens(for: dock, connected: screens) {
                let key = "\(dock.id)|\(screen.id)"
                wanted.insert(key)
                let controller = windows[key] ?? {
                    let c = DockWindowController(dock: dock, screen: screen, model: model)
                    windows[key] = c
                    return c
                }()
                controller.update(dock: dock, screen: screen, slots: slots, settings: store.settings,
                                  editing: store.editing.contains(dock.id))
            }
        }
        for (key, controller) in windows where !wanted.contains(key) {
            controller.close()
            windows[key] = nil
        }
    }

    func controllers(for dockID: UUID) -> [DockWindowController] {
        windows.values.filter { $0.dockID == dockID }
    }

    // MARK: Pointer and fullscreen

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        for controller in windows.values { controller.pointerMoved(to: point) }
    }

    private func checkFullscreen() {
        let fullscreenFrames = FullscreenDetector.fullscreenScreenFrames()
        for controller in windows.values {
            guard let dock = model.store.dock(controller.dockID) else { continue }
            let hide = dock.behavior.hideInFullscreen
                && fullscreenFrames.contains { $0.intersects(controller.screen.geometry.frame.insetBy(dx: 1, dy: 1)) }
            controller.setFullscreenHidden(hide)
        }
    }
}

/// Finds screens where the frontmost app has a window covering the whole display,
/// menu bar included, which is how fullscreen windows look to the window server.
@MainActor
enum FullscreenDetector {
    static func fullscreenScreenFrames() -> [CGRect] {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.maxY else { return [] }
        var result: [CGRect] = []
        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let appKit = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            for screen in NSScreen.screens where abs(appKit.width - screen.frame.width) < 1
                && abs(appKit.height - screen.frame.height) < 1 && appKit.intersects(screen.frame) {
                result.append(screen.frame)
            }
        }
        return result
    }
}
