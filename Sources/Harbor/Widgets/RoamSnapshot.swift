import AppKit
import HarborCore

/// One read of the window server for the roaming pet, safe to run off the main thread.
enum RoamSnapshot {
    struct Result: Sendable {
        /// Normal windows of other apps, front to back, in AppKit coordinates.
        var windows: [RoamWindow]
        /// Screens showing a fullscreen app.
        var fullscreen: [CGRect]
    }

    /// `regularPIDs` are the apps with a Dock icon; system processes such as the Dock, Control Center
    /// and the window server own layer-0 windows too, and none of them are things to stand on.
    static func take(frontPID: pid_t?, ownPID: pid_t, regularPIDs: Set<pid_t>, screens: [CGRect]) -> Result {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]], let primaryHeight = screens.first?.maxY else { return Result(windows: [], fullscreen: []) }
        var windows: [RoamWindow] = []
        var fullscreen: [CGRect] = []
        var foundFront = false
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  regularPIDs.contains(pid) else { continue }
            let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            if pid == frontPID,
               let screen = screens.first(where: { abs(frame.width - $0.width) < 1 && abs(frame.height - $0.height) < 1
                   && frame.intersects($0) }) {
                fullscreen.append(screen)
                continue
            }
            guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  frame.width >= 80, frame.height >= 40 else { continue }
            let isFront = !foundFront && pid == frontPID
            if isFront { foundFront = true }
            windows.append(RoamWindow(frame: frame, isFront: isFront))
        }
        // A fullscreen app with the menu bar kept visible is shorter than its screen, so ask for the Space's type too.
        for frame in FullscreenSpaces.frames() where !fullscreen.contains(where: { $0.intersects(frame) }) {
            fullscreen.append(frame)
        }
        return Result(windows: windows, fullscreen: fullscreen)
    }
}
