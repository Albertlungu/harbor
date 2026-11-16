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

    func showManager() {
        guard let model else { return }
        if manager == nil {
            manager = makeWindow(title: "Harbor", size: NSSize(width: 860, height: 600),
                                 content: ManagerView().environment(model), autosave: "Manager")
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
                                  content: SettingsView().environment(model), autosave: "Settings")
        }
        present(settings)
    }

    func showOnboarding() {
        guard let model else { return }
        if onboarding == nil {
            onboarding = makeWindow(title: "Welcome to Harbor", size: NSSize(width: 560, height: 460),
                                    content: OnboardingView().environment(model), autosave: nil)
            onboarding?.styleMask.remove(.resizable)
        }
        present(onboarding)
    }

    func closeOnboarding() {
        onboarding?.close()
        onboarding = nil
    }

    private func makeWindow(title: String, size: NSSize, content: some View, autosave: String?) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        // A hosting view with no size constraints at all: grouped forms report their full,
        // unscrolled height, and any constraint taken from it made the window taller than
        // the screen and impossible to move or shrink.
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        window.contentView = host
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
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
