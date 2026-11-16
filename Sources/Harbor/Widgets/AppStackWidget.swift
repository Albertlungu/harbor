import AppKit
import HarborCore
import SwiftUI

/// A hand-picked group of apps and files behind one icon.
struct AppStackWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var open = false

    private var title: String {
        let name = widget.string("name", "")
        return name.isEmpty ? "App Stack" : name
    }

    var body: some View {
        let side = min(size.width, size.height)
        let paths = Array(widget.strings("items").prefix(4))
        let cell = side * 0.36
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).fill(.quaternary)
            VStack(spacing: side * 0.04) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: side * 0.04) {
                        ForEach(0..<2, id: \.self) { col in
                            let index = row * 2 + col
                            if index < paths.count {
                                Image(nsImage: IconProvider.icon(forPath: paths[index])).resizable().frame(width: cell, height: cell)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if widget.strings("items").isEmpty {
                model.openItemSettings(item.id, in: dock.id)
            } else {
                open.toggle()
            }
        }
        .storagePopover(isPresented: $open, state: state) {
            AppStackPanel(item: item, dockID: dock.id, onClose: { open = false })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(widget.strings("items").isEmpty ? "Opens settings to add items" : "Shows the items in this stack")
        .accessibilityAddTraits(.isButton)
    }
}

private struct AppStackPanel: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID
    let onClose: () -> Void

    @State private var selection: String?

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dockID) }

    var body: some View {
        let widget = fields.current
        let paths = widget.strings("items")
        let columns = StorageLogic.clampedColumns(widget.double("columns", 5))
        let compact = widget.string("density", "comfortable") == "compact"
        let spacing = Tokens.Space.s
        let inner = Tokens.Storage.popoverWidth - Tokens.Storage.popoverPadding * 2
        let cell = (inner - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let icon = max(20, min(compact ? 34 : 52, cell - 12))
        let showNames = !compact && cell >= 56
        let name = widget.string("name", "")

        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(name.isEmpty ? "App Stack" : name).font(.headline)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                    ForEach(paths, id: \.self) { path in
                        tile(path, icon: icon, showName: showNames, singleClick: widget.bool("singleClickOpens", false))
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(Tokens.Storage.popoverPadding)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            DropLoader.urls(from: providers) { append($0.map(\.path)) }
            return true
        }
    }

    private func tile(_ path: String, icon: CGFloat, showName: Bool, singleClick: Bool) -> some View {
        let url = URL(fileURLWithPath: path)
        let label = url.deletingPathExtension().lastPathComponent
        return VStack(spacing: Tokens.Space.xs) {
            Image(nsImage: IconProvider.icon(forPath: path)).resizable().frame(width: icon, height: icon)
            if showName {
                Text(label).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Space.s)
        .contentShape(Rectangle())
        .hoverHighlight(selected: selection == path)
        .help(label)
        .onTapGesture(count: 2) { openItem(url) }
        .onTapGesture { if singleClick { openItem(url) } else { selection = path } }
        .contextMenu {
            Button("Open") { openItem(url) }
            Button("Show in Finder") { ItemActions.reveal(url) }
            Button("Remove from Stack") { remove(path) }
            Button("Rename Stack…") { rename() }
            if model.store.settings.showMoveToTrash {
                Divider()
                Button("Move to Trash…") { trash(url) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { openItem(url) }
    }

    private func openItem(_ url: URL) {
        NSWorkspace.shared.open(url)
        onClose()
    }

    private func append(_ new: [String]) {
        var paths = fields.current.strings("items")
        for path in new where !paths.contains(path) { paths.append(path) }
        fields.set("items", .array(paths.map(JSONValue.string)))
    }

    private func remove(_ path: String) {
        let paths = fields.current.strings("items").filter { $0 != path }
        fields.set("items", .array(paths.map(JSONValue.string)))
    }

    private func rename() {
        let current = fields.current.string("name", "")
        if let name = StorageDialogs.askText("Rename Stack", message: "Choose a name for this stack.",
                                             initial: current, action: "Rename") {
            fields.set("name", .string(name))
        }
    }

    private func trash(_ url: URL) {
        guard StorageDialogs.confirm("Move \(url.lastPathComponent) to the Trash?",
                                     message: "The item itself is moved, not just removed from this stack.",
                                     action: "Move to Trash") else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            remove(url.path)
        } catch {
            StorageDialogs.notice("Couldn't move it to the Trash", message: error.localizedDescription)
        }
    }
}
