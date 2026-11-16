import AppKit
import HarborCore
import SwiftUI

/// The status item menu: app actions, then one submenu per dock.
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Open Harbor") { model.windows.showManager() }
        // The quickest way back to the macOS Dock, and to hide it again.
        Toggle("Hide macOS Dock", isOn: Binding(
            get: { model.store.settings.deepHideNativeDock },
            set: { model.setReplaceNativeDock($0) }))
        Divider()
        Button("Settings…") { model.windows.showSettings() }
            .keyboardShortcut(",")
        Button("New Dock") { model.newDock() }
        Toggle("Window Previews", isOn: Binding(
            get: { model.store.settings.previews.enabled },
            set: { v in model.store.updateSettings { $0.previews.enabled = v } }))
        MediaSubmenu()
        Divider()

        if model.store.docks.isEmpty {
            Text("No Docks")
        } else {
            ForEach(model.store.docks) { dock in
                DockSubmenu(dock: dock)
            }
        }
        Divider()

        if !WindowControl.isTrusted {
            Button("Accessibility Permission Needed…") { WindowControl.requestTrust() }
        }
        Button("About Harbor") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        Button("Quit Harbor") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct MediaSubmenu: View {
    var body: some View {
        let media = MediaControl.shared
        let tracks = media.tracks()
        Menu("Media") {
            if tracks.isEmpty {
                Text("Nothing Playing")
            }
            ForEach(tracks, id: \.player) { track in
                Text(track.title)
                Text(track.artist.isEmpty ? track.player.rawValue : "\(track.artist) - \(track.player.rawValue)")
                Button(track.playing ? "Pause" : "Play") { media.togglePlayPause(track.player) }
                Button("Next") { media.next(track.player) }
                Button("Previous") { media.previous(track.player) }
                Divider()
            }
        }
    }
}

private struct DockSubmenu: View {
    @Environment(AppModel.self) private var model
    let dock: Dock

    var body: some View {
        let store = model.store
        let hidden = store.runtimeHidden[dock.id] != nil
        Menu(dock.name) {
            if let source = store.runtimeHidden[dock.id] {
                Text("Hidden by \(source.rawValue)")
            }
            Button(hidden ? "Show Dock" : "Hide Dock") {
                if hidden { store.show(dock.id) } else { store.hide(dock.id, source: .menu) }
            }
            .disabled(!dock.enabled)
            Toggle("Enabled", isOn: Binding(get: { dock.enabled }, set: { store.setEnabled(dock.id, $0) }))
            Button(store.editing.contains(dock.id) ? "Done Editing" : "Edit Dock") {
                store.setEditing(dock.id, !store.editing.contains(dock.id))
            }
            .disabled(!dock.enabled)
            Divider()
            Menu("Position") {
                Button("Floating, Horizontal") { set(.floating, orientation: .horizontal) }
                Button("Floating, Vertical") { set(.floating, orientation: .vertical) }
                Divider()
                ForEach(ScreenEdge.allCases, id: \.self) { edge in
                    Button("Pinned, \(edge.rawValue.capitalized)") {
                        store.updateDock(dock.id) {
                            $0.position.mode = .pinned
                            $0.position.edge = edge
                        }
                    }
                }
            }
            if dock.position.mode == .floating {
                Toggle("Lock Position", isOn: Binding(
                    get: { dock.position.locked },
                    set: { v in store.updateDock(dock.id) { $0.position.locked = v } }))
            }
            Menu("Size") {
                ForEach([IconSizePreset.small, .medium, .large], id: \.self) { preset in
                    Button("\(preset.rawValue.capitalized) (\(Int(preset.points!)) pt)") {
                        store.updateDock(dock.id) { $0.style.iconSizePreset = preset }
                    }
                }
                Button("Match macOS Dock") {
                    let size = NativeDockSize.current()
                    store.updateDock(dock.id) {
                        $0.style.iconSizePreset = .custom
                        $0.style.customIconSize = size
                    }
                }
            }
            Divider()
            Button("Open in Harbor…") { model.openInManager(dock.id) }
        }
    }

    private func set(_ mode: PositionMode, orientation: Orientation) {
        model.store.updateDock(dock.id) {
            $0.position.mode = mode
            $0.style.orientation = orientation
        }
    }
}

enum NativeDockSize {
    /// The native Dock's icon size, or 48 when it can't be read.
    static func current() -> Double {
        UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize").nonZero ?? 48
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
