import AppKit
import HarborCore
import SwiftUI

/// Options for one item: label, folder behavior and custom icon, or a widget's settings.
struct ItemOptionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ref: ItemRef

    var body: some View {
        VStack(spacing: 0) {
            if let dock = model.store.dock(ref.dockID), let item = dock.items.first(where: { $0.id == ref.itemID }) {
                HStack {
                    Text(item.displayName).font(.headline)
                    Spacer()
                }
                .padding(Tokens.Space.l)
                Divider()
                if item.kind == .widget {
                    WidgetSettingsForm(item: item, dockID: dock.id)
                } else {
                    ItemOptionsForm(item: item, dockID: dock.id)
                }
            } else {
                ContentUnavailableView("This item was removed", systemImage: "questionmark.square.dashed")
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Tokens.Space.m)
        }
        .frame(width: 480, height: 520)
    }
}

private struct ItemOptionsForm: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID
    @State private var iconURL = ""
    @State private var showingLibrary = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: field(\.customName, default: ""), prompt: Text(defaultName))
                Toggle("Always show the name", isOn: field(\.alwaysShowLabel, default: false))
                    .disabled(model.store.dock(dockID)?.style.alwaysShowNames == true)
                if item.kind == .file {
                    Toggle("Hide the file extension", isOn: field(\.hideExtension, default: false))
                }
            }

            if item.kind == .folder { folderSection }

            Section("Icon") {
                HStack {
                    Image(nsImage: IconProvider.icon(for: item, library: model.store.config.icons,
                                                     iconsDirectory: model.file.iconsDirectory))
                        .resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Button("Choose Image…") { pickIconFile() }
                        Button("Choose from Library…") { showingLibrary = true }
                            .disabled(model.store.config.icons.isEmpty)
                        if item.customIconID != nil {
                            Button("Use the Original Icon") { setIcon(nil) }
                        }
                    }
                }
                HStack {
                    TextField("Image address", text: $iconURL, prompt: Text("https://…"))
                    Button("Download") {
                        Task { if let id = await IconLibrary.download(iconURL, model: model) { setIcon(id) } }
                    }
                    .disabled(URL(string: iconURL)?.scheme?.hasPrefix("http") != true)
                }
                Text("Custom icons only change how the item looks on your docks. The app itself isn't modified.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
            }
        }
        .formStyle(.grouped)
        .popover(isPresented: $showingLibrary) {
            IconPicker { id in
                setIcon(id)
                showingLibrary = false
            }
            .environment(model)
        }
    }

    private var defaultName: String {
        var copy = item
        copy.customName = nil
        return copy.displayName
    }

    @ViewBuilder
    private var folderSection: some View {
        Section("When clicked") {
            Picker("Clicking opens", selection: field(\.folder.onClick, default: .inherit)) {
                Text("App default").tag(FolderClick.inherit)
                Text("A browser beside the dock").tag(FolderClick.browse)
                Text("A Finder window").tag(FolderClick.openInFinder)
            }
            LabeledContent("Open with") {
                HStack {
                    Text(item.folder.openWithApp.map { FileManager.default.displayName(atPath: $0) } ?? "App default")
                    Button("Choose…") {
                        if let app = AppPicker.pick() { model.store.updateItem(item.id, in: dockID) { $0.folder.openWithApp = app } }
                    }
                    if item.folder.openWithApp != nil {
                        Button("Reset") { model.store.updateItem(item.id, in: dockID) { $0.folder.openWithApp = nil } }
                    }
                }
            }
        }
        Section("Browser") {
            Picker("Layout", selection: field(\.folder.layout, default: .grid)) {
                Text("Grid").tag(FolderLayout.grid)
                Text("List").tag(FolderLayout.list)
                Text("Fan").tag(FolderLayout.fan)
            }
            .pickerStyle(.segmented)
            if item.folder.layout == .grid {
                Stepper("Columns: \(item.folder.columns)", value: field(\.folder.columns, default: 5), in: 2...10)
                ValueSlider(title: "Icon size", value: field(\.folder.iconSize, default: 48), range: 24...96, unit: " pt")
                Toggle("Show file names", isOn: field(\.folder.showNames, default: true))
            }
            Picker("Sort by", selection: field(\.folder.sort, default: .name)) {
                Text("Name").tag(FolderSort.name)
                Text("Kind").tag(FolderSort.kind)
                Text("Date modified").tag(FolderSort.dateModified)
            }
            Toggle("Reverse order", isOn: field(\.folder.reverse, default: false))
            Toggle("Folders first", isOn: field(\.folder.foldersFirst, default: true))
            Toggle("Show hidden files", isOn: field(\.folder.showHidden, default: false))
            Toggle("Show previews", isOn: field(\.folder.showPreviews, default: true))
            Toggle("Close after dragging a file out", isOn: field(\.folder.closeAfterDragOut, default: false))
        }
    }

    private func field<T>(_ keyPath: WritableKeyPath<DockItem, T>, default fallback: T) -> Binding<T> {
        Binding(
            get: { model.store.dock(dockID)?.items.first { $0.id == item.id }?[keyPath: keyPath] ?? fallback },
            set: { v in model.store.updateItem(item.id, in: dockID) { $0[keyPath: keyPath] = v } })
    }

    private func field(_ keyPath: WritableKeyPath<DockItem, String?>, default fallback: String) -> Binding<String> {
        Binding(
            get: { model.store.dock(dockID)?.items.first { $0.id == item.id }?[keyPath: keyPath] ?? fallback },
            set: { v in model.store.updateItem(item.id, in: dockID) { $0[keyPath: keyPath] = v.isEmpty ? nil : v } })
    }

    private func setIcon(_ id: UUID?) {
        model.store.updateItem(item.id, in: dockID) { $0.customIconID = id }
    }

    private func pickIconFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url, let id = IconLibrary.importFile(url, model: model) {
            setIcon(id)
        }
    }
}

@MainActor
enum AppPicker {
    static func pick() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// Imported icons stored in the app's Icons folder and listed in the config.
@MainActor
enum IconLibrary {
    static func importFile(_ url: URL, model: AppModel) -> UUID? {
        guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return nil }
        return store(data, ext: url.pathExtension.isEmpty ? "png" : url.pathExtension, source: nil, model: model)
    }

    static func download(_ address: String, model: AppModel) async -> UUID? {
        guard let url = URL(string: address), let (data, _) = try? await URLSession.shared.data(from: url),
              NSImage(data: data) != nil else {
            model.flashHint("That address didn't return an image.")
            return nil
        }
        return store(data, ext: url.pathExtension.isEmpty ? "png" : url.pathExtension, source: address, model: model)
    }

    private static func store(_ data: Data, ext: String, source: String?, model: AppModel) -> UUID? {
        let dir = model.file.iconsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let asset = IconAsset(fileName: "\(UUID().uuidString).\(ext)", sourceURL: source)
        guard (try? data.write(to: dir.appendingPathComponent(asset.fileName))) != nil else { return nil }
        model.store.updateIcons { $0.append(asset) }
        return asset.id
    }

    static func usage(of id: UUID, in docks: [Dock]) -> [(dock: String, item: String)] {
        docks.flatMap { dock in
            dock.items.filter { $0.customIconID == id }.map { (dock.name, $0.displayName) }
        }
    }

    static func delete(_ id: UUID, model: AppModel) {
        guard let asset = model.store.config.icons.first(where: { $0.id == id }) else { return }
        for dock in model.store.docks {
            for item in dock.items where item.customIconID == id {
                model.store.updateItem(item.id, in: dock.id) { $0.customIconID = nil }
            }
        }
        try? FileManager.default.removeItem(at: model.file.iconsDirectory.appendingPathComponent(asset.fileName))
        model.store.updateIcons { $0.removeAll { $0.id == id } }
    }
}

struct IconPicker: View {
    @Environment(AppModel.self) private var model
    let choose: (UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(56)), count: 5), spacing: Tokens.Space.m) {
                ForEach(model.store.config.icons) { asset in
                    Button { choose(asset.id) } label: {
                        if let image = IconProvider.customIcon(asset.id, library: model.store.config.icons,
                                                               directory: model.file.iconsDirectory) {
                            Image(nsImage: image).resizable().frame(width: 48, height: 48)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Tokens.Space.l)
        }
        .frame(width: 340, height: 280)
    }
}
