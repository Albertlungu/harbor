import AppKit
import SwiftUI

/// Opens and reuses the app's regular windows. Managed by hand rather than as
/// SwiftUI scenes so they can be opened from dock panels and menus alike.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    weak var model: AppModel?
    private var manager: NSWindow?
    private var settings: NSWindow?
    private var onboarding: NSWindow?
    private var permissions: NSWindow?

    var managerWindow: NSWindow? { manager }

    func showManager() {
        guard let model else { return }
        if manager == nil {
            manager = makeWindow(title: "Harbor", size: NSSize(width: 860, height: 600),
                                 content: ManagerView().environment(model).harborLook(), autosave: "Manager")
            manager?.contentMinSize = NSSize(width: 720, height: 440)
            // The dock name field in the toolbar already says what this window is.
            manager?.titleVisibility = .hidden
        }
        present(manager)
    }

    func showSettings() {
        guard let model else { return }
        if settings == nil {
            settings = makeWindow(title: "Harbor Settings", size: NSSize(width: 720, height: 540),
                                  content: SettingsView().environment(model).harborLook(), autosave: "Settings")
        }
        present(settings)
    }

    func showOnboarding() {
        guard let model else { return }
        if onboarding == nil {
            onboarding = makeWindow(title: "Welcome to Harbor", size: NSSize(width: 560, height: 520),
                                    content: OnboardingView().environment(model).harborLook(), autosave: nil)
            onboarding?.styleMask.remove(.resizable)
        }
        present(onboarding)
    }

    /// `intro` explains why the window opened by itself after an install or update.
    func showPermissions(intro: Bool = false) {
        guard let model else { return }
        if permissions == nil {
            permissions = makeWindow(title: "Harbor Permissions", size: NSSize(width: 640, height: 560),
                                     content: PermissionsView(showsIntro: intro).environment(model).harborLook(), autosave: nil)
        }
        present(permissions)
    }

    func closeOnboarding() {
        onboarding?.close()
        onboarding = nil
    }

    private func makeWindow(title: String, size: NSSize, content: some View, autosave: String?) -> NSWindow {
        becomeRegularApp()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        // macOS state restoration would re-apply an old frame after launch, undoing keepOnScreen.
        window.isRestorable = false
        // The content declares its own size range: an ideal of the default window size and a
        // small minimum. Left to itself it reported a form's full, unscrolled height, which
        // pushed the window past the screen. The controller only enforces that minimum.
        let host = NSHostingController(rootView: content.frame(
            minWidth: min(size.width, 640), idealWidth: size.width, maxWidth: .infinity,
            minHeight: 420, idealHeight: size.height, maxHeight: .infinity))
        host.sizingOptions = [.minSize]
        window.contentViewController = host
        window.setContentSize(size)
        window.delegate = self
        window.contentMinSize = NSSize(width: min(size.width, 640), height: 420)
        if let autosave { window.setFrameAutosaveName(autosave) }
        if autosave == nil || !window.setFrameUsingName(autosave!) { window.center() }
        Self.keepOnScreen(window, defaultSize: size)
        return window
    }

    /// Pulls a window back onto its screen and shrinks it to fit, so a frame saved by an
    /// older build (or on a larger display) can't leave the window out of reach.
    static func keepOnScreen(_ window: NSWindow, defaultSize: NSSize) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        // AppKit already trims an oversized saved frame to exactly the screen, so treat a full-height frame as stale too.
        if frame.height >= visible.height - 1 || frame.width >= visible.width - 1 {
            frame.size = NSSize(width: min(defaultSize.width, visible.width - 40),
                                height: min(defaultSize.height, visible.height - 40))
            frame.origin = CGPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        }
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: false)
    }

    private func present(_ window: NSWindow?) {
        // Presenting resets the minimum size, so it is restored right after.
        let minimum = window?.contentMinSize ?? .zero
        defer { DispatchQueue.main.async { window?.contentMinSize = minimum } }
        becomeRegularApp()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// A menu-bar-only app's windows open on whatever Space is showing, even on top of another
    /// app's fullscreen window. While one of these windows is open Harbor is a regular app instead,
    /// so macOS opens it on a desktop and switches there. The switch has to happen before the
    /// window is created: a window made while Harbor was menu-bar-only keeps joining fullscreen Spaces.
    private func becomeRegularApp() {
        if NSApp.activationPolicy() == .accessory { NSApp.setActivationPolicy(.regular) }
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let open = [manager, settings, onboarding, permissions].contains { $0 != nil && $0 !== closing && $0!.isVisible }
        if !open { model?.applyPresentation() }
    }
}
