import AppKit
import HarborCore
import OSLog

let log = Logger(subsystem: "io.github.albertlungu.harbor", category: "app")

/// Support exports. Files are only written where the user chooses.
@MainActor
enum Diagnostics {
    static func exportScreens(model: AppModel) {
        let screens = DockController.connectedScreens().map { s -> [String: Any] in
            ["id": s.id, "name": s.name, "main": s.isMain,
             "frame": NSStringFromRect(s.geometry.frame), "visibleFrame": NSStringFromRect(s.geometry.visibleFrame)]
        }
        let known = model.store.config.knownScreens.map { ["id": $0.id, "name": $0.displayName, "lastSeen": $0.lastSeen.ISO8601Format()] }
        let placements = model.dockController.windows.map { key, c in
            ["window": key, "bar": NSStringFromRect(c.barFrame), "autoHidden": c.autoHidden, "fullscreenHidden": c.fullscreenHidden] as [String: Any]
        }
        save(json: ["connected": screens, "known": known, "placements": placements], name: "Harbor Screens.json")
    }

    /// Settings and runtime state of every dock, without item paths or custom names.
    static func exportDocks(model: AppModel, only id: UUID? = nil) {
        let docks = model.store.docks.filter { id == nil || $0.id == id }.map { dock -> [String: Any] in
            [
                "id": dock.id.uuidString,
                "name": dock.name,
                "enabled": dock.enabled,
                "hiddenBy": model.store.runtimeHidden[dock.id]?.rawValue ?? "",
                "layout": dock.layout.rawValue,
                "placement": dock.placementSummary,
                "items": dock.items.map { $0.widget?.type ?? $0.kind.rawValue },
                "screens": dock.screens.showOnAllScreens ? "all" : "\(dock.screens.assignedScreenIDs.count) assigned",
                "autoHide": dock.behavior.autoHide,
                "hideInFullscreen": dock.behavior.hideInFullscreen,
            ]
        }
        save(json: ["version": Bundle.main.shortVersion, "accessibility": WindowControl.isTrusted, "docks": docks],
             name: "Harbor Docks.json")
    }

    static func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Harbor Logs.txt"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var text = "Harbor \(Bundle.main.shortVersion) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"
        if let store = try? OSLogStore(scope: .currentProcessIdentifier) {
            let since = store.position(date: Date().addingTimeInterval(-86_400))
            let entries = (try? store.getEntries(at: since)) ?? AnySequence([])
            for case let entry as OSLogEntryLog in entries where entry.subsystem == "io.github.albertlungu.harbor" {
                text += "\(entry.date.ISO8601Format()) [\(entry.category)] \(entry.composedMessage)\n"
            }
        }
        // The home folder path is replaced so exports don't carry the user name.
        text = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func save(json: [String: Any], name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}
