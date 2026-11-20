import AppKit
import HarborCore
import SwiftUI

/// Changes to the app-wide shelf of copied files.
@MainActor
enum ShelfOps {
    /// Copies (or moves) files into the shelf folder under a name that never overwrites anything.
    static func add(_ urls: [URL], model: AppModel, move: Bool) {
        let directory = model.file.shelfDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var added: [ShelfEntry] = []
        for url in urls where !url.path.hasPrefix(directory.path + "/") {
            let target = ItemActions.uniqueDestination(for: url.lastPathComponent, in: directory)
            do {
                if move { try FileManager.default.moveItem(at: url, to: target) } else { try FileManager.default.copyItem(at: url, to: target) }
                added.append(ShelfEntry(path: target.path))
            } catch {
                model.flashHint("Couldn't add \(url.lastPathComponent) to the shelf")
            }
        }
        guard !added.isEmpty else { return }
        model.store.updateShelf { $0.append(contentsOf: added) }
    }

    /// `afterDelay` leaves the copy in place long enough for a drop target to finish reading it.
    static func remove(_ urls: [URL], model: AppModel, afterDelay delay: Duration = .zero) {
        let paths = Set(urls.map(\.standardizedFileURL.path))
        model.store.updateShelf { $0.removeAll { paths.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path) } }
        Task { @MainActor in
            if delay > .zero { try? await Task.sleep(for: delay) }
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Empties the shelf folder, including anything added to it from the browser.
    static func clear(model: AppModel) {
        let directory = model.file.shelfDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? FileManager.default.removeItem(at: url) }
        model.store.updateShelf { $0.removeAll() }
    }

    /// Matches the saved list to what the shelf folder holds, since the browser can paste, drop, rename and
    /// delete there directly. Entries still present keep their identity and date.
    static func sync(_ urls: [URL], model: AppModel) {
        let present = urls.filter { !$0.lastPathComponent.hasPrefix(".") }
        let presentPaths = Set(present.map(\.standardizedFileURL.path))
        let current = model.store.config.shelf
        let kept = current.filter { presentPaths.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path) }
        let known = Set(kept.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        let next = kept + present.filter { !known.contains($0.standardizedFileURL.path) }.map { ShelfEntry(path: $0.path) }
        if next != current { model.store.updateShelf { $0 = next } }
    }
}

/// Parks copies of files in a collection shared by every shelf, shown in a Finder-style browser.
struct ShelfWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var open = false
    @State private var dropTargeted = false
    @State private var springTask: Task<Void, Never>?

    var body: some View {
        let count = model.store.config.shelf.count
        StorageGlyph(symbol: count > 0 ? "tray.full" : "tray", color: colorSetting(widget, "iconColor"), size: size)
            .overlay(alignment: .topTrailing) {
                if widget.bool("showCount", false) && count > 0 { CountBadge(count: count) }
            }
            .contentShape(Rectangle())
            .onTapGesture { open.toggle() }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                StorageWidgetDrop.handle(providers, item: item, dock: dock, model: model)
            }
            // Springs open while files are held over it, so they can be dropped straight into the browser.
            .onChange(of: dropTargeted) { _, over in
                springTask?.cancel()
                guard over, !open else { return }
                springTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if !Task.isCancelled { open = true }
                }
            }
            .storagePopover(isPresented: $open, state: state, sized: false) {
                FolderBrowser(folder: shelfFolder, options: item.folder, role: role, arrowEdge: state.popoverEdge,
                              save: { options in model.store.updateItem(item.id, in: dock.id) { $0.folder = options } },
                              onClose: { open = false })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shelf")
            .accessibilityValue(count == 0 ? "Empty" : "\(count) items")
            .accessibilityAddTraits(.isButton)
    }

    private var shelfFolder: URL {
        let directory = model.file.shelfDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var role: FolderBrowserRole {
        let model = model
        let removeAfterDrag = widget.string("afterDrag", "keep") == "remove"
        let empty = Copy.emptyShelf(model.playful)
        return FolderBrowserRole(
            kind: .shelf, dropsMove: widget.string("dropAction", "copy") == "move",
            emptyTitle: empty.title, emptyHint: empty.detail, emptySymbol: "tray",
            onRootRead: { ShelfOps.sync($0, model: model) },
            onDraggedOut: { urls in
                guard removeAfterDrag else { return }
                let shelf = model.file.shelfDirectory.standardizedFileURL.path + "/"
                ShelfOps.remove(urls.filter { $0.standardizedFileURL.path.hasPrefix(shelf) }, model: model,
                                afterDelay: .seconds(10))
            },
            clear: ("Clear All", { ShelfOps.clear(model: model) }))
    }
}

/// Holds references to files in place, with a separate list per widget.
struct FileShelfWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var open = false

    var body: some View {
        let count = widget.strings("refs").count
        StorageGlyph(symbol: count > 0 ? "tray.2.fill" : "tray.2", color: colorSetting(widget, "iconColor"), size: size)
            .overlay(alignment: .topTrailing) {
                if widget.bool("showCount", false) && count > 0 { CountBadge(count: count) }
            }
            .contentShape(Rectangle())
            .onTapGesture { open.toggle() }
            .storagePopover(isPresented: $open, state: state) {
                FileShelfPanel(item: item, dockID: dock.id, onClose: { open = false })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pinned Files")
            .accessibilityValue(count == 0 ? "Empty" : "\(count) files")
            .accessibilityAddTraits(.isButton)
    }
}

enum FileShelfOps {
    @MainActor
    static func add(_ urls: [URL], fields: WidgetFields) {
        var refs = fields.current.strings("refs")
        for url in urls where !refs.contains(url.path) { refs.append(url.path) }
        fields.set("refs", .array(refs.map(JSONValue.string)))
    }
}

private struct FileShelfPanel: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID
    let onClose: () -> Void

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dockID) }

    var body: some View {
        FilePanel(
            labels: .init(title: "Pinned Files", clearButton: "Clear All", clearTitle: "Remove all pinned files?",
                          clearMessage: "Only the shelf's list is cleared. The files stay where they are.",
                          removeItem: "Remove from Shelf", emptyTitle: Copy.pinnedFiles(model.playful).title,
                          emptyHint: Copy.pinnedFiles(model.playful).detail,
                          emptySymbol: "tray.2"),
            entries: fields.current.strings("refs").map { FilePanelEntry(id: $0, url: URL(fileURLWithPath: $0)) },
            searchable: true,
            showsCopy: true,
            onRemove: { remove($0.id) },
            onClear: { fields.set("refs", .array([])) },
            onAdd: { FileShelfOps.add($0, fields: fields) },
            onDragEnd: { entry, inside in
                guard !inside else { return }
                switch fields.current.string("afterDrag", "keep") {
                case "remove": remove(entry.id)
                case "ask":
                    if StorageDialogs.confirm("Remove \(entry.url.lastPathComponent) from the shelf?",
                                              message: "The file itself stays where it is.", action: "Remove",
                                              destructive: false) { remove(entry.id) }
                default: break
                }
            },
            onClose: onClose)
    }

    private func remove(_ path: String) {
        fields.set("refs", .array(fields.current.strings("refs").filter { $0 != path }.map(JSONValue.string)))
    }
}
