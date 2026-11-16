import AppKit
import HarborCore

/// One rendered position on a dock: a stored item, or an app contributed by a
/// Live Dock / Running Apps / Space Apps widget.
enum DockSlot: Identifiable, Equatable {
    case item(DockItem)
    case app(owner: UUID, path: String, name: String, spacer: Bool)

    var id: String {
        switch self {
        case .item(let item): item.id.uuidString
        case .app(let owner, let path, _, let spacer): spacer ? "\(owner)-spacer-\(path)" : "\(owner)-\(path)"
        }
    }

    var item: DockItem? { if case .item(let i) = self { i } else { nil } }

    /// Size along the dock axis in icon cells.
    var cells: Double {
        switch self {
        case .app(_, _, _, let spacer): return spacer ? 0.5 : 1
        case .item(let item):
            guard let widget = item.widget else { return 1 }
            guard let kind = widget.kind else { return 1 }
            switch kind {
            case .spacer:
                return widget.double("cells", 0.25)
            case .divider:
                return 0.25
            case .label:
                return widget.double("length", 96) / 48
            case .clock:
                return widget.bool("showDate", false) ? 2.5 : 2
            case .pet:
                return widget.double("cells", 1)
            default:
                return kind.defaultCells
            }
        }
    }

    /// Whether hover magnification applies.
    var magnifies: Bool {
        switch self {
        case .app(_, _, _, let spacer): return !spacer
        case .item(let item): return item.kind != .widget
        }
    }
}

/// Expands a dock's items into slots, inserting live app lists for app-list widgets.
@MainActor
enum SlotBuilder {
    static func slots(for dock: Dock, running: RunningApps, nativeDock: NativeDock, settings: AppSettings) -> [DockSlot] {
        var result: [DockSlot] = []
        var pinnedPaths = Set(dock.items.compactMap { $0.kind == .app ? $0.path.map(RunningApps.normalize) : nil })
        // A Finder widget already stands for Finder, so app lists shouldn't show it again.
        if dock.hasWidget(.finder) { pinnedPaths.insert("/System/Library/CoreServices/Finder.app") }
        let excluded = Set(settings.excludedApps)
        for item in dock.items where !item.hidden {
            switch item.widget?.kind {
            case .liveDock?:
                let hidden = Set(item.widget?.strings("hiddenApps") ?? [])
                var seen = Set<String>()
                for entry in nativeDock.entries() {
                    switch entry {
                    case .spacer(let i):
                        result.append(.app(owner: item.id, path: "\(i)", name: "", spacer: true))
                    case .app(let path):
                        let p = RunningApps.normalize(path)
                        guard !hidden.contains(p), FileManager.default.fileExists(atPath: p), seen.insert(p).inserted
                        else { continue }
                        result.append(.app(owner: item.id, path: p, name: appName(p), spacer: false))
                    }
                }
                for app in running.apps {
                    guard let p = app.path, !hidden.contains(p), !excluded.contains(p), seen.insert(p).inserted
                    else { continue }
                    result.append(.app(owner: item.id, path: p, name: app.name, spacer: false))
                }
            case .runningApps?:
                let hidden = Set(item.widget?.strings("hiddenApps") ?? [])
                for app in running.apps {
                    guard let p = app.path, !pinnedPaths.contains(p), !hidden.contains(p), !excluded.contains(p)
                    else { continue }
                    if !(item.widget?.bool("showWindowless", true) ?? true),
                       WindowControl.isTrusted, WindowControl.windows(of: app.pid).isEmpty { continue }
                    result.append(.app(owner: item.id, path: p, name: app.name, spacer: false))
                }
            case .spaceAwareness?:
                if item.widget?.string("mode", "apps") == "apps" {
                    for app in SpaceApps.appsOnCurrentSpace(running: running) {
                        guard let p = app.path else { continue }
                        result.append(.app(owner: item.id, path: p, name: app.name, spacer: false))
                    }
                } else {
                    result.append(.item(item))
                }
            default:
                result.append(.item(item))
            }
        }
        return result
    }

    static func appName(_ path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }
}
