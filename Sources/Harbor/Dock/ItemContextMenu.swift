import AppKit
import HarborCore
import SwiftUI

/// Right-click menu for anything on a dock.
struct ItemContextMenu: View {
    @Environment(AppModel.self) private var model
    let slot: DockSlot
    let dock: Dock
    let editing: Bool

    var body: some View {
        switch slot {
        case .app(let owner, let path, _, let spacer):
            if !spacer {
                appSection(path: path)
                Divider()
                Button("Hide from This Widget") {
                    model.store.updateItem(owner, in: dock.id) { item in
                        var hidden = item.widget?.strings("hiddenApps") ?? []
                        hidden.append(path)
                        item.widget?.settings["hiddenApps"] = .array(hidden.map(JSONValue.string))
                    }
                }
                Button("Pin to \(dock.name)") {
                    model.store.addItems([DockItem(kind: .app, path: path)], to: dock.id)
                }
                dockSection
            } else {
                DockActions(dock: dock, editing: editing)
            }
        case .item(let item):
            // Dividers and spacers read as empty dock space, so they lead with the dock's own menu.
            if item.widget?.kind == .divider || item.widget?.kind == .spacer {
                DockActions(dock: dock, editing: editing)
                Divider()
                itemSection(item)
            } else {
                itemSection(item)
                dockSection
            }
        }
    }

    @ViewBuilder
    private func itemSection(_ item: DockItem) -> some View {
        if item.kind == .widget {
            Button("Widget Settings…") { model.openItemSettings(item.id, in: dock.id) }
            WidgetContextItems(item: item, dock: dock)
            Divider()
            Button("Remove Widget…") { model.confirmRemoveWidget(item, from: dock.id) }
        } else {
            if let url = item.url {
                Button("Open") { NSWorkspace.shared.open(url) }
                Button("Show in Finder") { ItemActions.reveal(url) }
                if item.kind == .app { appSection(path: url.path) }
                if item.kind == .folder {
                    Button("Open in New Finder Window") { ItemActions.openFolder(url, item: item, settings: model.store.settings) }
                }
            }
            Divider()
            Button("Item Options…") { model.openItemSettings(item.id, in: dock.id) }
            Button("Remove from Dock…") { model.confirmRemoveItem(item, from: dock.id) }
        }
    }

    @ViewBuilder
    private func appSection(path: String) -> some View {
        if let app = model.running.app(atPath: path) {
            let windows = WindowControl.windows(of: app.pid)
            if !windows.isEmpty {
                Section("Windows") {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                        Button((window.minimized ? "◦ " : "") + (window.title.isEmpty ? app.name : window.title)) {
                            WindowControl.raise(window, pid: app.pid)
                        }
                    }
                }
            }
            if ChromiumProfiles.isChromium(app.bundleID), let id = app.bundleID {
                let profiles = ChromiumProfiles.profiles(for: id)
                if !profiles.isEmpty {
                    Menu("New Window with Profile") {
                        ForEach(profiles, id: \.directory) { profile in
                            Button(profile.name) { ChromiumProfiles.open(profile, appPath: path) }
                        }
                    }
                }
            }
            Button(app.isHidden ? "Show" : "Hide") {
                let running = NSRunningApplication(processIdentifier: app.pid)
                if app.isHidden { running?.unhide() } else { running?.hide() }
            }
            Button("Quit") { NSRunningApplication(processIdentifier: app.pid)?.terminate() }
        }
    }

    @ViewBuilder
    private var dockSection: some View {
        Divider()
        Menu("Harbor") { DockActions(dock: dock, editing: editing) }
    }
}

/// Actions for a whole dock: the right-click menu on its empty space, and the Harbor submenu on its items.
struct DockActions: View {
    @Environment(AppModel.self) private var model
    let dock: Dock
    let editing: Bool

    var body: some View {
        if dock.layout == .dock {
            Toggle("Keep Dock Shown", isOn: Binding(
                get: { !dock.behavior.autoHide },
                set: { v in model.store.updateDock(dock.id) { $0.behavior.autoHide = !v } }))
        }
        Button(editing ? "Done Editing" : "Edit Dock") { model.store.setEditing(dock.id, !editing) }
        if dock.position.mode == .floating {
            Toggle("Lock Position", isOn: Binding(
                get: { dock.position.locked },
                set: { v in model.store.updateDock(dock.id) { $0.position.locked = v } }))
        }
        if dock.style.collapse.enabled {
            Button(dock.style.collapse.collapsed ? "Expand" : "Collapse") {
                model.store.updateDock(dock.id) { $0.style.collapse.collapsed.toggle() }
            }
        }
        Button("Hide Dock") { model.store.hide(dock.id, source: .menu) }
        Divider()
        Button("Dock Settings…") { model.openInManager(dock.id) }
        Button("Add Widget…") {
            model.openInManager(dock.id)
            model.showingLibraryFor = dock.id
        }
    }
}
