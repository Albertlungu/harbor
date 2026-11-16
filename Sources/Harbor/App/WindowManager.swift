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
            manager?.minSize = NSSize(width: 720, height: 460)
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
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.delegate = self
        if let autosave { window.setFrameAutosaveName(autosave) }
        if autosave == nil || !window.setFrameUsingName(autosave!) { window.center() }
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
