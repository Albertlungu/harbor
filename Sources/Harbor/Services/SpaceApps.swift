import AppKit
import CoreGraphics

/// Apps with windows on the current Space, from the window server's on-screen list.
@MainActor
enum SpaceApps {
    static func appsOnCurrentSpace(running: RunningApps) -> [RunningApp] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var pids: [pid_t] = []
        for window in info where (window[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = window[kCGWindowOwnerPID as String] as? pid_t, !pids.contains(pid) { pids.append(pid) }
        }
        return pids.compactMap { pid in running.apps.first { $0.pid == pid } }
    }

    /// Current Space number and Space count for the main display. There is no public
    /// API for this, so it reads Mission Control's preferences, which can lag a switch.
    static func spaceIndicator() -> (current: Int, total: Int)? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let config = plist["SpacesDisplayConfiguration"] as? [String: Any],
              let mgmt = config["Management Data"] as? [String: Any],
              let monitors = mgmt["Monitors"] as? [[String: Any]],
              let first = monitors.first(where: { $0["Spaces"] != nil }),
              let spaces = first["Spaces"] as? [[String: Any]] else { return nil }
        let currentID = (first["Current Space"] as? [String: Any])?["uuid"] as? String
        let index = spaces.firstIndex { ($0["uuid"] as? String) == currentID } ?? 0
        return (index + 1, spaces.count)
    }
}
