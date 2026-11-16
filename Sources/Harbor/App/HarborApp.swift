import AppKit
import HarborCore
import SwiftUI

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { delegate.model.store.settings.presentation != .dockApp },
            set: { _ in }
        )) {
            MenuBarMenu()
                .environment(delegate.model)
        } label: {
            if let glyph = Self.menuBarGlyph {
                Image(nsImage: glyph)
            } else {
                Image(systemName: "dock.rectangle")
            }
        }
        .menuBarExtraStyle(.menu)
    }

    /// Template glyph from the app bundle; nil under `swift run`, where resources are absent.
    private static let menuBarGlyph: NSImage? = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor lazy var model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { model.start() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { URLCommands.handle(urls, model: model) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model.stop() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { model.windows.showManager() }
        return false
    }
}
