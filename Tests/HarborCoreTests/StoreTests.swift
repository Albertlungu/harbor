import Foundation
import Testing
@testable import HarborCore

@MainActor
@Suite struct StoreTests {
    @Test func createNamesSequentially() {
        let store = DockStore()
        #expect(store.createDock().name == "Dock 1")
        #expect(store.createDock().name == "Dock 2")
    }

    @Test func createUsesNewDockDefaults() {
        let store = DockStore()
        store.updateSettings {
            $0.newDocks.customizeStyle = true
            $0.newDocks.style.iconSizePreset = .large
        }
        #expect(store.createDock().style.iconSize == 64)
    }

    @Test func renameRejectsBlank() {
        let store = DockStore()
        let dock = store.createDock()
        #expect(!store.rename(dock.id, to: "   "))
        #expect(store.dock(dock.id)?.name == "Dock 1")
        #expect(store.rename(dock.id, to: " Media "))
        #expect(store.dock(dock.id)?.name == "Media")
    }

    @Test func duplicateGivesFreshIDsAndDropsScreens() throws {
        let store = DockStore()
        let dock = store.createDock()
        store.addItems([DockItem(kind: .app, path: "/A.app")], to: dock.id)
        store.updateDock(dock.id) { $0.screens.assignedScreenIDs = ["s1"] }
        let copy = try #require(store.duplicate(dock.id))
        #expect(copy.name == "Dock 1 Copy")
        #expect(copy.items.count == 1)
        #expect(copy.items[0].id != store.dock(dock.id)!.items[0].id)
        #expect(copy.screens.assignedScreenIDs.isEmpty)
        #expect(store.docks.map(\.id) == [dock.id, copy.id])
    }

    @Test func singleInstanceWidgets() {
        let store = DockStore()
        let dock = store.createDock()
        #expect(store.addWidget(.trash, to: dock.id) != nil)
        #expect(store.addWidget(.trash, to: dock.id) == nil)
        #expect(store.addWidget(.clock, to: dock.id) != nil)
        #expect(store.addWidget(.clock, to: dock.id) != nil)
    }

    @Test func monitorPresetSkipsPresent() {
        let store = DockStore()
        let dock = store.createDock()
        store.addWidget(.cpu, to: dock.id)
        store.addMonitorPreset(to: dock.id)
        let kinds = store.dock(dock.id)!.items.compactMap { $0.widget?.kind }
        #expect(kinds.filter { $0 == .cpu }.count == 1)
        #expect(kinds.count == WidgetCatalog.monitorPreset.count)
    }

    @Test func pasteKeepsTargetHotkeyAndItems() {
        let store = DockStore()
        let a = store.createDock()
        let b = store.createDock()
        store.updateDock(a.id) { $0.style.iconSizePreset = .small; $0.behavior.autoHide = true }
        store.updateDock(b.id) { $0.behavior.hotkey = Hotkey(keyCode: 1, modifiers: 1, display: "x") }
        store.addItems([DockItem(kind: .file, path: "/f")], to: b.id)
        store.copySettings(from: a.id)
        store.pasteSettings(to: b.id)
        let target = store.dock(b.id)!
        #expect(target.style.iconSize == 32)
        #expect(target.behavior.autoHide)
        #expect(target.behavior.hotkey?.display == "x")
        #expect(target.items.count == 1)
    }

    @Test func toggleEnablesDisabledDock() {
        let store = DockStore()
        let dock = store.createDock()
        store.setEnabled(dock.id, false)
        store.toggle(dock.id, source: .shortcut)
        #expect(store.isVisible(dock.id))
        store.toggle(dock.id, source: .shortcut)
        #expect(store.runtimeHidden[dock.id] == .shortcut)
        #expect(!store.isVisible(dock.id))
    }

    @Test func disabledDocksCannotBeEdited() {
        let store = DockStore()
        let dock = store.createDock()
        store.setEnabled(dock.id, false)
        store.setEditing(dock.id, true)
        #expect(store.editing.isEmpty)
    }

    @Test func forgetScreenClearsAssignments() {
        let store = DockStore()
        let dock = store.createDock()
        store.noteScreen(id: "s1", name: "Studio")
        store.updateDock(dock.id) {
            $0.screens.assignedScreenIDs = ["s1", "s2"]
            $0.perScreenPositions["s1"] = Position()
        }
        store.forgetScreen("s1")
        #expect(store.dock(dock.id)!.screens.assignedScreenIDs == ["s2"])
        #expect(store.dock(dock.id)!.perScreenPositions.isEmpty)
        #expect(store.config.knownScreens.isEmpty)
    }

    @Test func importReplacesSameIDAndAddsNew() {
        let store = DockStore()
        let existing = store.createDock()
        var backup = Config()
        var changed = existing
        changed.name = "From backup"
        backup.docks = [changed, Dock(name: "New")]
        backup.settings.magneticSnapping = false
        let result = store.importBackup(backup)
        #expect(result.added == 1 && result.replaced == 1)
        #expect(store.dock(existing.id)?.name == "From backup")
        #expect(!store.settings.magneticSnapping)
    }

    @Test func moveItemReorders() {
        let store = DockStore()
        let dock = store.createDock()
        let items = (0..<3).map { DockItem(kind: .file, path: "/\($0)") }
        store.addItems(items, to: dock.id)
        store.moveItem(items[0].id, in: dock.id, to: 2)
        #expect(store.dock(dock.id)!.items.map(\.path) == ["/1", "/2", "/0"])
    }

    @Test func themesApplyStyleOnly() throws {
        let store = DockStore()
        let a = store.createDock()
        let b = store.createDock()
        store.updateDock(a.id) { $0.style.background = .solid }
        store.saveTheme(named: "Plain", from: a.id)
        let theme = try #require(store.config.themes.first)
        store.addItems([DockItem(kind: .file, path: "/f")], to: b.id)
        store.applyTheme(theme.id, to: b.id)
        #expect(store.dock(b.id)!.style.background == .solid)
        #expect(store.dock(b.id)!.items.count == 1)
    }
}
