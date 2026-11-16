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
    static func remove(_ entry: ShelfEntry, model: AppModel, afterDelay delay: Duration = .zero) {
        model.store.updateShelf { $0.removeAll { $0.id == entry.id } }
        let url = URL(fileURLWithPath: entry.path)
        Task { @MainActor in
            if delay > .zero { try? await Task.sleep(for: delay) }
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func clear(model: AppModel) {
        let entries = model.store.config.shelf
        model.store.updateShelf { $0.removeAll() }
        for entry in entries { try? FileManager.default.removeItem(atPath: entry.path) }
    }
}

/// Parks copies of files in a collection shared by every shelf.
struct ShelfWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var open = false

    var body: some View {
        let count = model.store.config.shelf.count
        StorageGlyph(symbol: count > 0 ? "tray.full" : "tray", color: colorSetting(widget, "iconColor"), size: size)
            .overlay(alignment: .topTrailing) {
                if widget.bool("showCount", false) && count > 0 { CountBadge(count: count) }
            }
            .contentShape(Rectangle())
            .onTapGesture { open.toggle() }
            .storagePopover(isPresented: $open, state: state) {
                ShelfPanel(item: item, dockID: dock.id, onClose: { open = false })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shelf")
            .accessibilityValue(count == 0 ? "Empty" : "\(count) items")
            .accessibilityAddTraits(.isButton)
    }
}

private struct ShelfPanel: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID
    let onClose: () -> Void

    private var settings: WidgetConfig { WidgetFields(model: model, itemID: item.id, dockID: dockID).current }

    var body: some View {
        FilePanel(
            labels: .init(title: "Shelf", clearButton: "Clear All", clearTitle: "Clear the shelf?",
                          clearMessage: "Every copy on the shelf is deleted. Your originals are not touched.",
                          removeItem: "Remove from Shelf", emptyTitle: "Nothing on the shelf",
                          emptyHint: "Drop files on the shelf icon or here to keep a copy.", emptySymbol: "tray"),
            entries: model.store.config.shelf.map { FilePanelEntry(id: $0.id.uuidString, url: URL(fileURLWithPath: $0.path)) },
            searchable: false,
            showsCopy: false,
            onRemove: { entry in
                if let shelfEntry = model.store.config.shelf.first(where: { $0.id.uuidString == entry.id }) {
                    ShelfOps.remove(shelfEntry, model: model)
                }
            },
            onClear: { ShelfOps.clear(model: model) },
            onAdd: { ShelfOps.add($0, model: model, move: settings.string("dropAction", "copy") == "move") },
            onDragEnd: { entry, inside in
                guard !inside, settings.string("afterDrag", "keep") == "remove",
                      let shelfEntry = model.store.config.shelf.first(where: { $0.id.uuidString == entry.id }) else { return }
                ShelfOps.remove(shelfEntry, model: model, afterDelay: .seconds(10))
            },
            onClose: onClose)
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
                          removeItem: "Remove from Shelf", emptyTitle: "Nothing on the shelf",
                          emptyHint: "Drop files or folders here to keep them close without moving them.",
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
