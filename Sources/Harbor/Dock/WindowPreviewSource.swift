import AppKit
import ApplicationServices
import HarborCore
import ScreenCaptureKit

/// One window of an app, as the preview panel lists it.
struct PreviewWindow: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    var title: String
    /// Quartz coordinates (top-left origin), the same space Accessibility reports.
    let bounds: CGRect
    let onScreen: Bool
    let minimized: Bool
    let hidden: Bool
    /// Front-to-back position in the window server's list.
    let order: Int
}

/// Collects an app's windows and applies the preview filters and sort order.
@MainActor
enum WindowPreviewSource {
    static func windows(for app: RunningApp, settings: PreviewSettings) -> [PreviewWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let ax = WindowControl.windows(of: app.pid)
        let filters = settings.titleFilters.map { $0.lowercased() }.filter { !$0.isEmpty }
        var result: [PreviewWindow] = []
        for (order, entry) in info.enumerated() {
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) == app.pid,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width >= 60, bounds.height >= 40,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            let onScreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let cgTitle = entry[kCGWindowName as String] as? String ?? ""
            let axMatch = match(bounds: bounds, title: cgTitle, in: ax)
            let minimized = axMatch?.minimized ?? false
            let hidden = app.isHidden && !onScreen
            let title = !cgTitle.isEmpty ? cgTitle : (axMatch?.title ?? "")

            if minimized {
                guard settings.includeMinimized else { continue }
            } else if hidden {
                guard settings.includeHidden else { continue }
            } else if !onScreen {
                // Offscreen and neither minimized nor hidden: another Space, or an invisible helper window.
                guard !settings.currentSpaceOnly, !title.isEmpty else { continue }
            }
            if filters.contains(where: { title.lowercased().contains($0) }) { continue }
            result.append(PreviewWindow(id: number, pid: app.pid, title: title, bounds: bounds, onScreen: onScreen,
                                        minimized: minimized, hidden: hidden, order: order))
        }
        return sorted(result, by: settings.sort)
    }

    static func sorted(_ windows: [PreviewWindow], by sort: PreviewSort) -> [PreviewWindow] {
        switch sort {
        case .recent: windows.sorted { $0.order < $1.order }
        case .alphabetical: windows.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        // Window numbers grow as windows are created.
        case .creation: windows.sorted { $0.id < $1.id }
        case .screenPosition:
            windows.sorted { $0.bounds.minX != $1.bounds.minX ? $0.bounds.minX < $1.bounds.minX : $0.bounds.minY < $1.bounds.minY }
        }
    }

    /// Pairs a window-server window with its Accessibility element by frame, then by title.
    static func match(bounds: CGRect, title: String, in windows: [WindowControl.Window]) -> WindowControl.Window? {
        let byFrame = windows.first { window in
            guard let frame = WindowControl.frame(of: window.element) else { return false }
            return abs(frame.minX - bounds.minX) < 3 && abs(frame.minY - bounds.minY) < 3
                && abs(frame.width - bounds.width) < 3 && abs(frame.height - bounds.height) < 3
        }
        if let byFrame { return byFrame }
        return title.isEmpty ? nil : windows.first { $0.title == title }
    }

    static func axWindow(for window: PreviewWindow) -> WindowControl.Window? {
        match(bounds: window.bounds, title: window.title, in: WindowControl.windows(of: window.pid))
    }
}

/// Window thumbnails through ScreenCaptureKit. Every failure just yields no image.
@MainActor
enum WindowThumbnailer {
    static func capture(_ windows: [PreviewWindow], pixelWidth: Int,
                        deliver: (CGWindowID, CGImage) -> Void) async {
        guard CGPreflightScreenCaptureAccess(), !windows.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return }
        for window in windows {
            if Task.isCancelled { return }
            // The window number is exact; PID plus title covers the odd case where the ids disagree.
            let target = content.windows.first { $0.windowID == window.id }
                ?? content.windows.first { $0.owningApplication?.processID == window.pid && $0.title == window.title }
            guard let target, target.frame.width > 0, target.frame.height > 0 else { continue }
            let config = SCStreamConfiguration()
            config.width = pixelWidth
            config.height = max(Int(Double(pixelWidth) * target.frame.height / target.frame.width), 1)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: target)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                deliver(window.id, image)
            }
        }
    }
}
