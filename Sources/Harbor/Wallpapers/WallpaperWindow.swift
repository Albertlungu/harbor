import AppKit
import SwiftUI

/// The wallpaper browser's window. Built when opened and torn down when closed, so a
/// closed browser holds no thumbnails and runs no tasks.
@MainActor
final class WallpaperWindow: NSObject, NSWindowDelegate {
    static let shared = WallpaperWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let size = NSSize(width: 1040, height: 680)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Wallpapers"
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentViewController = NSHostingController(rootView: WallpaperBrowserView().harborLook())
            window.setContentSize(size)
            window.contentMinSize = NSSize(width: 760, height: 460)
            window.delegate = self
            window.setFrameAutosaveName("Wallpapers")
            if !window.setFrameUsingName("Wallpapers") { window.center() }
            WindowManager.keepOnScreen(window, defaultSize: size)
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Dropping the hosting controller ends the browser's view tasks and frees its state.
        window?.contentViewController = nil
        window = nil
    }
}
