import AppKit
import HarborCore

/// Runs harbor:// URLs. These work from the Shortcuts "Open URL" action, Focus
/// automations, scripts and links, without needing App Intents.
@MainActor
enum URLCommands {
    static func handle(_ urls: [URL], model: AppModel) {
        for url in urls {
            guard let command = URLCommand.parse(url) else { continue }
            run(command, model: model)
        }
    }

    private static func run(_ command: URLCommand, model: AppModel) {
        let store = model.store
        switch command {
        case .show(let name):
            for dock in DockMatching.matches(name, in: store.docks) {
                // A disabled dock stays off unless the user asked for it by name.
                if !dock.enabled { store.setEnabled(dock.id, true) }
                store.show(dock.id)
            }
        case .hide(let name):
            for dock in DockMatching.matches(name, in: store.docks) where dock.enabled {
                store.hide(dock.id, source: .shortcutsApp)
            }
        case .toggle(let name):
            for dock in DockMatching.matches(name, in: store.docks) {
                store.toggle(dock.id, source: .shortcutsApp)
            }
        case .new(let name):
            let dock = store.createDock(name: name)
            model.openInManager(dock.id)
        case .manager:
            model.windows.showManager()
        }
    }
}
