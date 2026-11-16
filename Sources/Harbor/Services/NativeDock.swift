import AppKit
import HarborCore

/// Reads (and for deep-hide, adjusts) the native macOS Dock's preferences.
@MainActor
final class NativeDock {
    enum Entry: Equatable {
        case app(String)
        case spacer(Int)
    }

    private var cached: (date: Date, entries: [Entry])?

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
    }

    private func readPlist() -> [String: Any]? {
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    var isReadable: Bool { readPlist() != nil }

    /// Pinned apps and spacers in order; refreshed when the plist changes.
    func entries() -> [Entry] {
        let modified = (try? plistURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached, let modified, cached.date == modified { return cached.entries }
        var result: [Entry] = []
        let apps = readPlist()?["persistent-apps"] as? [[String: Any]] ?? []
        for (i, tile) in apps.enumerated() {
            let type = tile["tile-type"] as? String ?? ""
            if type.contains("spacer") {
                result.append(.spacer(i))
            } else if let path = Self.path(of: tile) {
                result.append(.app(path))
            }
        }
        cached = modified.map { ($0, result) }
        return result
    }

    /// Pinned folders and files from the right side of the native Dock.
    func others() -> [String] {
        let tiles = readPlist()?["persistent-others"] as? [[String: Any]] ?? []
        return tiles.compactMap(Self.path(of:))
    }

    private static func path(of tile: [String: Any]) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let urlString = file["_CFURLString"] as? String else { return nil }
        if let url = URL(string: urlString), url.isFileURL { return url.path }
        return urlString.hasPrefix("/") ? urlString : nil
    }

    // MARK: Deep hide

    private static let savedKey = "nativeDockSaved"

    /// Pushes the native Dock off screen with an extreme auto-hide delay, saving prior values.
    func deepHide() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.dictionary(forKey: Self.savedKey) == nil {
            let current = readPlist() ?? [:]
            var saved: [String: Any] = [:]
            saved["autohide"] = current["autohide"] as? Bool ?? false
            if let delay = current["autohide-delay"] { saved["autohide-delay"] = delay }
            defaults.set(saved, forKey: Self.savedKey)
        }
        return run(["write", "com.apple.dock", "autohide", "-bool", "true"])
            && run(["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
            && restartDock()
    }

    /// Restores what `deepHide` saved.
    func restore() -> Bool {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.savedKey) else { return true }
        var ok = run(["write", "com.apple.dock", "autohide", "-bool", (saved["autohide"] as? Bool ?? false) ? "true" : "false"])
        if let delay = saved["autohide-delay"] as? Double {
            ok = ok && run(["write", "com.apple.dock", "autohide-delay", "-float", String(delay)])
        } else {
            ok = ok && run(["delete", "com.apple.dock", "autohide-delay"])
        }
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        return ok && restartDock()
    }

    private func restartDock() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        return (try? task.run()) != nil
    }

    private func run(_ args: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = args
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0 || args.first == "delete"
    }
}
