import AppKit
import HarborCore
import SwiftUI

/// Widget-specific right-click entries for the storage widgets.
struct StorageWidgetMenu: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dock: Dock

    var body: some View {
        switch item.widget?.kind {
        case .finder?:
            Button("New Finder Window") { NSWorkspace.shared.open(FinderLocation.url(for: item.widget)) }
        case .link?:
            if let url = StorageLogic.normalizedURL(item.widget?.string("url", "") ?? "") {
                Button("Open Link") { NSWorkspace.shared.open(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        case .shelf?:
            Button("Clear Shelf") { ShelfOps.clear(model: model) }
        case .fileShelf?:
            Button("Clear Shelf…") {
                if StorageDialogs.confirm("Clear the file shelf?", message: "Only the list is cleared. The files stay where they are.",
                                          action: "Clear Shelf") {
                    WidgetFields(model: model, itemID: item.id, dockID: dock.id).set("refs", .array([]))
                }
            }
        case .trash?:
            Button("Open Trash in Finder") { NSWorkspace.shared.open(TrashService.url) }
            Button("Empty Trash…") { TrashService.emptyWithDialogs(confirm: !NSEvent.modifierFlags.contains(.command)) }
        default:
            EmptyView()
        }
    }
}

/// Files dropped on a storage widget.
@MainActor
enum StorageWidgetDrop {
    static func handle(_ providers: [NSItemProvider], item: DockItem, dock: Dock, model: AppModel) -> Bool {
        guard let widget = item.widget, providers.contains(where: { $0.canLoadObject(ofClass: URL.self) }) else { return false }
        let fields = WidgetFields(model: model, itemID: item.id, dockID: dock.id)
        switch widget.kind {
        case .folderStack?:
            guard let first = widget.strings("folders").first else {
                model.flashHint("Add a folder to this stack first.")
                return false
            }
            DropLoader.urls(from: providers) { ItemActions.move($0, into: URL(fileURLWithPath: first)) }
        case .appStack?:
            DropLoader.urls(from: providers) { urls in
                var paths = fields.current.strings("items")
                for url in urls where !paths.contains(url.path) { paths.append(url.path) }
                fields.set("items", .array(paths.map(JSONValue.string)))
            }
        case .shelf?:
            let move = widget.string("dropAction", "copy") == "move"
            DropLoader.urls(from: providers) { ShelfOps.add($0, model: model, move: move) }
        case .fileShelf?:
            DropLoader.urls(from: providers) { FileShelfOps.add($0, fields: fields) }
        case .trash?:
            DropLoader.urls(from: providers) { urls in
                for url in urls {
                    do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch {
                        model.flashHint("Couldn't move \(url.lastPathComponent) to the Trash")
                    }
                }
            }
        default:
            return false
        }
        return true
    }
}

/// Settings rows for the storage widgets, placed inside the item sheet's Form.
struct StorageWidgetSettings: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dockID) }

    var body: some View {
        let current = fields.current
        switch item.widget?.kind {
        case .finder?: finder(current)
        case .link?: link(current)
        case .folderStack?: folderStack
        case .appStack?: appStack(current)
        case .shelf?: shelf
        case .fileShelf?: fileShelf(current)
        case .trash?:
            Text("Drop files on the Trash to delete them. Emptying it asks Finder, so macOS may ask for permission the first time.")
                .foregroundStyle(Tokens.textMuted)
        default: EmptyView()
        }
    }

    // MARK: Finder and Link

    @ViewBuilder
    private func finder(_ current: WidgetConfig) -> some View {
        Picker("Opens", selection: fields.string("location", "home")) {
            Text("Home").tag("home")
            Text("Documents").tag("documents")
            Text("Downloads").tag("downloads")
            Text("Desktop").tag("desktop")
            Text("Applications").tag("applications")
            Text("Another folder").tag("custom")
        }
        if current.string("location", "home") == "custom" {
            HStack {
                TextField("Folder", text: fields.string("path", ""), prompt: Text("~/Projects"))
                Button("Choose…") {
                    if let url = StorageDialogs.choose(files: false, folders: true, multiple: false).first {
                        fields.set("path", .string(url.path))
                    }
                }
            }
        }
        Toggle("Show a dot while Finder is running", isOn: fields.bool("showRunningDot", true))
    }

    @ViewBuilder
    private func link(_ current: WidgetConfig) -> some View {
        TextField("Web address", text: fields.string("url", ""), prompt: Text("example.com"))
        TextField("Name", text: fields.string("title", ""), prompt: Text("Optional"))
        Toggle("Show the name under the icon", isOn: fields.bool("showTitle", false))
        Picker("Icon", selection: fields.string("iconSource", "favicon")) {
            Text("Website icon").tag("favicon")
            Text("Symbol").tag("symbol")
            Text("Image file").tag("file")
        }
        switch current.string("iconSource", "favicon") {
        case "symbol":
            TextField("Symbol name", text: fields.string("symbol", "link"))
            ColorPicker("Symbol color", selection: fields.color("symbolColor", Tokens.text))
        case "file":
            HStack {
                TextField("Image", text: fields.string("iconFile", ""))
                Button("Choose…") {
                    if let url = StorageDialogs.choose(files: true, folders: false, multiple: false).first {
                        fields.set("iconFile", .string(url.path))
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: Stacks

    @ViewBuilder
    private var folderStack: some View {
        pathList("Folders", key: "folders", addTitle: "Add Folders…", files: false, folders: true)
        TextField("Name", text: fields.string("name", ""), prompt: Text("Folder Stack"))
        ColorPicker("Icon color", selection: fields.color("tint", Tokens.accent))
        openWithRow
    }

    @ViewBuilder
    private var openWithRow: some View {
        let app = fields.current.string("openWith", "")
        HStack {
            Text("Open folders with")
            Spacer()
            Text(app.isEmpty ? "Default" : FileManager.default.displayName(atPath: app)).foregroundStyle(Tokens.textMuted)
            Button("Choose…") { if let path = AppPicker.pick() { fields.set("openWith", .string(path)) } }
            if !app.isEmpty { Button("Use Default") { fields.set("openWith", nil) } }
        }
    }

    @ViewBuilder
    private func appStack(_ current: WidgetConfig) -> some View {
        pathList("Items", key: "items", addTitle: "Add Items…", files: true, folders: true)
        TextField("Name", text: fields.string("name", ""), prompt: Text("App Stack"))
        Picker("Grid spacing", selection: fields.string("density", "comfortable")) {
            Text("Comfortable").tag("comfortable")
            Text("Compact").tag("compact")
        }
        .pickerStyle(.segmented)
        Stepper("Columns: \(StorageLogic.clampedColumns(current.double("columns", 5)))",
                value: Binding(get: { StorageLogic.clampedColumns(current.double("columns", 5)) },
                               set: { fields.set("columns", .number(Double($0))) }),
                in: 3...8)
        Toggle("Open items with a single click", isOn: fields.bool("singleClickOpens", false))
    }

    // MARK: Shelves

    @ViewBuilder
    private var shelf: some View {
        Picker("When files are dropped", selection: fields.string("dropAction", "copy")) {
            Text("Copy them").tag("copy")
            Text("Move them").tag("move")
        }
        Picker("After dragging a file out", selection: fields.string("afterDrag", "keep")) {
            Text("Keep it on the shelf").tag("keep")
            Text("Remove it from the shelf").tag("remove")
        }
        Picker("Opens while dragging files", selection: fields.string("dragOpen", "near")) {
            Text("When they come near").tag("near")
            Text("When they're right over it").tag("over")
        }
        if fields.current.string("dragOpen", "near") == "near" {
            ValueSlider(title: "Distance", value: fields.double("dragDistance", 60), range: 10...300, format: "%.0f", unit: " pt")
        }
        Toggle("Show how many files are on the shelf", isOn: fields.bool("showCount", false))
        ColorPicker("Icon color", selection: fields.color("iconColor", Tokens.text))
    }

    @ViewBuilder
    private func fileShelf(_ current: WidgetConfig) -> some View {
        Picker("After dragging a file out", selection: fields.string("afterDrag", "keep")) {
            Text("Keep it on the shelf").tag("keep")
            Text("Remove it from the shelf").tag("remove")
            Text("Ask each time").tag("ask")
        }
        Toggle("Show how many files are on the shelf", isOn: fields.bool("showCount", false))
        ColorPicker("Icon color", selection: fields.color("iconColor", Tokens.text))
        LabeledContent("On the shelf", value: "\(current.strings("refs").count)")
        if !current.strings("refs").isEmpty {
            Button("Clear Shelf") { fields.set("refs", .array([])) }
        }
    }

    // MARK: Path lists

    @ViewBuilder
    private func pathList(_ title: String, key: String, addTitle: String, files: Bool, folders: Bool) -> some View {
        let paths = fields.current.strings(key)
        Section(title) {
            if paths.isEmpty { Text("Nothing added yet.").foregroundStyle(Tokens.textMuted) }
            ForEach(paths, id: \.self) { path in
                HStack {
                    Image(nsImage: IconProvider.icon(forPath: path)).resizable().frame(width: 20, height: 20)
                    Text(FileManager.default.displayName(atPath: path)).lineLimit(1)
                    Spacer()
                    Button("Remove") { fields.set(key, .array(paths.filter { $0 != path }.map(JSONValue.string))) }
                }
            }
            Button(addTitle) {
                var updated = paths
                for url in StorageDialogs.choose(files: files, folders: folders) where !updated.contains(url.path) {
                    updated.append(url.path)
                }
                fields.set(key, .array(updated.map(JSONValue.string)))
            }
        }
    }
}
