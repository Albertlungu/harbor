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
        .commands { EditCommands() }
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
        MainActor.assumeIsolated {
            if DevRender.runIfRequested() { NSApp.terminate(nil); return }
            model.start()
        }
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

/// SwiftUI leaves the Edit menu out of a menu-bar-only app, and text fields depend on it
/// for Select All, Cut, Copy, Paste and Undo.
struct EditCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                .keyboardShortcut("z")
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x")
            Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                .keyboardShortcut("c")
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v")
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a")
        }
    }
}
