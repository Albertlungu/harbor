import AppKit
import HarborCore
import SwiftUI

/// Non-activating panel that holds the preview cards.
final class WindowPreviewPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Opens window previews beside a dock when the pointer rests on a running app.
@MainActor
final class WindowPreviewController {
    private unowned let model: AppModel
    private let panel = WindowPreviewPanel()
    private let content = WindowPreviewModel()
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var presentedPath: String?
    private var anchorPoint = CGPoint.zero
    private weak var anchor: DockWindowController?
    private var pointerInPanel = false

    init(model: AppModel) {
        self.model = model
        panel.contentView = FirstClickHostingView(rootView: WindowPreviewView(model: content))
        content.onHover = { [weak self] inside in self?.panelHovered(inside) }
        content.onRaise = { [weak self] window in self?.raise(window) }
        content.onClose = { [weak self] window in self?.close(window) }
    }

    // MARK: Hover events from dock slots

    func hoverBegan(path: String, from controller: DockWindowController?) {
        let settings = model.store.settings.previews
        guard settings.enabled, let controller, let app = model.running.app(atPath: path),
              !settings.excludedApps.contains(where: { $0.caseInsensitiveCompare(app.name) == .orderedSame })
        else { return }
        hideTask?.cancel()
        showTask?.cancel()
        if panel.isVisible, presentedPath == RunningApps.normalize(path) { return }
        showTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(min(max(settings.showDelay, 0), 2)))
            guard !Task.isCancelled else { return }
            self?.present(app: app, path: path, from: controller)
        }
    }

    func hoverEnded() {
        showTask?.cancel()
        scheduleHide()
    }

    private func panelHovered(_ inside: Bool) {
        pointerInPanel = inside
        if inside { hideTask?.cancel() } else { scheduleHide() }
    }

    private func scheduleHide() {
        guard panel.isVisible else { return }
        hideTask?.cancel()
        let delay = max(model.store.settings.previews.hideDelay, 0)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.pointerInPanel else { return }
            self.dismiss()
        }
    }

    // MARK: Presenting

    private func present(app: RunningApp, path: String, from controller: DockWindowController) {
        let settings = model.store.settings.previews
        // Refresh in case the app quit while the delay ran.
        guard let live = model.running.app(atPath: path) else { return }
        let windows = WindowPreviewSource.windows(for: live, settings: settings)
        guard !windows.isEmpty else { dismiss(); return }
        let access = CGPreflightScreenCaptureAccess()

        captureTask?.cancel()
        if let old = anchor, old !== controller { old.state.menuOpen = false }
        anchor = controller
        presentedPath = RunningApps.normalize(path)
        anchorPoint = NSEvent.mouseLocation
        content.settings = settings
        content.appName = live.name
        content.icon = IconProvider.icon(forPath: path)
        content.hasScreenAccess = access
        content.canClose = WindowControl.isTrusted
        content.windows = windows
        content.images = [:]
        apply(windows: windows, settings: settings, access: access)

        controller.state.menuOpen = true
        if !panel.isVisible {
            content.animate = model.store.settings.openAnimation
            content.appearCount += 1
        }
        panel.orderFrontRegardless()

        guard access, !content.layout.compact else { return }
        let pixelWidth = Int(content.layout.cardWidth * 2)
        captureTask = Task { @MainActor [weak self] in
            await WindowThumbnailer.capture(windows, pixelWidth: pixelWidth) { id, image in
                self?.content.images[id] = image
            }
        }
    }

    /// Sizes the panel to the current window list and puts it on the dock's inward side.
    private func apply(windows: [PreviewWindow], settings: PreviewSettings, access: Bool) {
        guard let anchor else { return }
        let compact = PreviewLayout.isCompact(count: windows.count, settings: settings, hasScreenAccess: access)
        content.layout = PreviewLayout.make(count: windows.count, settings: settings, compact: compact)
        let frame = Self.placement(size: content.layout.size, pointer: anchorPoint, edge: anchor.state.hugEdge,
                                   dockFrame: anchor.panelFrame, screen: anchor.screen.geometry.frame)
        panel.setFrame(frame, display: true)
    }

    /// Where the preview panel sits: against the dock's inward edge, centered on the pointer along the axis.
    static func placement(size: CGSize, pointer: CGPoint, edge: ScreenEdge, dockFrame: CGRect, screen: CGRect) -> CGRect {
        var origin = CGPoint.zero
        switch edge {
        case .bottom: origin = CGPoint(x: pointer.x - size.width / 2, y: dockFrame.maxY)
        case .top: origin = CGPoint(x: pointer.x - size.width / 2, y: dockFrame.minY - size.height)
        case .left: origin = CGPoint(x: dockFrame.maxX, y: pointer.y - size.height / 2)
        case .right: origin = CGPoint(x: dockFrame.minX - size.width, y: pointer.y - size.height / 2)
        }
        origin.x = min(max(origin.x, screen.minX + 4), max(screen.maxX - size.width - 4, screen.minX + 4))
        origin.y = min(max(origin.y, screen.minY + 4), max(screen.maxY - size.height - 4, screen.minY + 4))
        return CGRect(origin: origin, size: size)
    }

    func dismiss() {
        showTask?.cancel()
        hideTask?.cancel()
        captureTask?.cancel()
        pointerInPanel = false
        presentedPath = nil
        anchor?.state.menuOpen = false
        anchor = nil
        panel.orderOut(nil)
    }

    // MARK: Card actions

    private func raise(_ window: PreviewWindow) {
        let pid = window.pid
        if let ax = WindowPreviewSource.axWindow(for: window) {
            WindowControl.raise(ax, pid: pid)
        } else if let app = NSRunningApplication(processIdentifier: pid) {
            // Without Accessibility, or for a window on another Space, activating the app is the best available.
            app.unhide()
            app.activate()
        }
        dismiss()
    }

    private func close(_ window: PreviewWindow) {
        guard let ax = WindowPreviewSource.axWindow(for: window) else { return }
        WindowControl.close(ax)
        content.windows.removeAll { $0.id == window.id }
        if content.windows.isEmpty {
            dismiss()
        } else {
            apply(windows: content.windows, settings: content.settings, access: content.hasScreenAccess)
        }
    }
}
