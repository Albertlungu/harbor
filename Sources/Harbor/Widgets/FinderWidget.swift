import AppKit
import HarborCore
import SwiftUI

/// Where a Finder widget opens its window.
enum FinderLocation {
    static func url(for widget: WidgetConfig?) -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func directory(_ d: FileManager.SearchPathDirectory) -> URL { fm.urls(for: d, in: .userDomainMask).first ?? home }
        switch widget?.string("location", "home") {
        case "documents": return directory(.documentDirectory)
        case "downloads": return directory(.downloadsDirectory)
        case "desktop": return directory(.desktopDirectory)
        case "applications": return URL(fileURLWithPath: "/Applications")
        case "custom":
            let path = (widget?.string("path", "") ?? "").trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? home : URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        default: return home
        }
    }

    static let finderID = "com.apple.finder"

    /// Finder keeps the desktop in a window below layer zero, so layer zero means a real window.
    private static var hasWindow: Bool {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return info?.contains { ($0["kCGWindowOwnerName"] as? String) == "Finder" && ($0["kCGWindowLayer"] as? Int) == 0 } ?? false
    }

    @MainActor
    static func activate(opening location: URL) {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: finderID).first else {
            NSWorkspace.shared.open(location)
            return
        }
        finder.activate()
        if !hasWindow { NSWorkspace.shared.open(location) }
    }
}

/// Stands in for the native Dock's Finder icon.
struct FinderWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    var body: some View {
        let side = min(size.width, size.height)
        let running = model.running.apps.contains { $0.bundleID == FinderLocation.finderID }
        Image(nsImage: IconProvider.icon(forPath: "/System/Library/CoreServices/Finder.app"))
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .overlay(alignment: .bottom) {
                if widget.bool("showRunningDot", true) && running {
                    Circle()
                        .fill(model.store.settings.indicatorColor?.color ?? Tokens.indicator)
                        .frame(width: Tokens.Dock.indicatorSize, height: Tokens.Dock.indicatorSize)
                        .offset(y: Tokens.Dock.indicatorSize + 2)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { FinderLocation.activate(opening: FinderLocation.url(for: widget)) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Finder")
            .accessibilityHint("Opens \(FinderLocation.url(for: widget).lastPathComponent)")
            .accessibilityAddTraits(.isButton)
    }
}
