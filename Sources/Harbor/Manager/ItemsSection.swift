import AppKit
import HarborCore
import SwiftUI
import UniformTypeIdentifiers

/// Lists a dock's items with reorder, hide, options and remove.
struct ItemsSection: View {
    @Environment(AppModel.self) private var model
    let dock: Dock

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if dock.items.isEmpty {
                EmptyDockCards(dock: dock)
            } else {
                List {
                    ForEach(dock.items) { item in
                        ItemRow(item: item, dock: dock)
                    }
                    .onMove { model.store.moveItems(in: dock.id, from: $0, to: $1) }
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    DropLoader.urls(from: providers) { urls in
                        model.store.addItems(urls.map(DockItem.file(at:)), to: dock.id)
                    }
                    return true
                }
            }
            Divider()
            HStack {
                AddMenu(dock: dock)
                Spacer()
                Button(model.store.editing.contains(dock.id) ? "Done Editing" : "Edit on Dock") {
                    model.store.setEditing(dock.id, !model.store.editing.contains(dock.id))
                }
                .disabled(!dock.enabled)
            }
            .padding(Tokens.Space.m)
        }
        .sheet(isPresented: Binding(
            get: { model.showingLibraryFor == dock.id },
            set: { if !$0 { model.showingLibraryFor = nil } })
        ) {
            WidgetLibrary(dock: dock).environment(model)
        }
    }
}

struct AddMenu: View {
    @Environment(AppModel.self) private var model
    let dock: Dock

    var body: some View {
        Menu {
            Button("Apps, Files and Folders…") { AddMenuActions.pick(model: model, dockID: dock.id) }
            Button("Widgets…") { model.showingLibraryFor = dock.id }
            Divider()
            if model.nativeDock.isReadable {
                Button("Copy of the macOS Dock") { model.addNativeDockCopy(to: dock.id) }
            }
            Button("System Monitor Set") { model.store.addMonitorPreset(to: dock.id) }
        } label: {
            Label("Add to Dock", systemImage: "plus")
        }
        .fixedSize()
    }
}

private struct EmptyDockCards: View {
    @Environment(AppModel.self) private var model
    let dock: Dock

    var body: some View {
        VStack(spacing: Tokens.Space.xl) {
            Text("This dock is empty").font(.title3.weight(.semibold))
            Text("Start with one of these, or drag apps and folders here from Finder.")
                .foregroundStyle(Tokens.textMuted)
            HStack(spacing: Tokens.Space.l) {
                card("Apps & Files", symbol: "app.badge.plus") {
                    AddMenuActions.pick(model: model, dockID: dock.id)
                }
                card("Widgets", symbol: "square.grid.3x3") { model.showingLibraryFor = dock.id }
                if model.nativeDock.isReadable {
                    card("macOS Dock Copy", symbol: "dock.rectangle") { model.addNativeDockCopy(to: dock.id) }
                }
                card("System Monitor", symbol: "gauge.with.dots.needle.33percent") {
                    model.store.addMonitorPreset(to: dock.id)
                }
            }
        }
        .padding(Tokens.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            DropLoader.urls(from: providers) { urls in
                model.store.addItems(urls.map(DockItem.file(at:)), to: dock.id)
            }
            return true
        }
    }

    private func card(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Tokens.Space.m) {
                Image(systemName: symbol).font(.system(size: 28))
                Text(title).font(.callout)
            }
            .frame(width: 120, height: 96)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Tokens.border))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
enum AddMenuActions {
    static func pick(model: AppModel, dockID: UUID) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        NSApp.activate()
        if panel.runModal() == .OK {
            model.store.addItems(panel.urls.map(DockItem.file(at:)), to: dockID)
        }
    }
}

private struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dock: Dock

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: "line.3.horizontal").foregroundStyle(Tokens.textMuted)
            icon.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Tokens.textMuted).lineLimit(1)
            }
            if item.hidden {
                Text("Hidden").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Tokens.surface, in: Capsule())
            }
            Spacer()
            Button { model.itemSheet = ItemRef(dockID: dock.id, itemID: item.id) } label: {
                Image(systemName: item.kind == .widget ? "slider.horizontal.3" : "ellipsis.circle")
            }
            .help(item.kind == .widget ? "Widget settings" : "Item options")
            if item.kind != .widget {
                Button {
                    model.store.updateItem(item.id, in: dock.id) { $0.hidden.toggle() }
                } label: { Image(systemName: item.hidden ? "eye.slash" : "eye") }
                .help(item.hidden ? "Show on dock" : "Hide from dock")
            }
            Button { model.store.removeItem(item.id, from: dock.id) } label: { Image(systemName: "minus.circle") }
                .help("Remove")
                .accessibilityLabel("Remove \(item.displayName)")
        }
        .buttonStyle(.borderless)
        .opacity(item.hidden ? 0.5 : 1)
    }

    @ViewBuilder
    private var icon: some View {
        if let kind = item.widget?.kind {
            Image(systemName: WidgetCatalog.symbol(for: kind))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WidgetLibrary.tint(for: WidgetCatalog.category(for: kind)))
                .frame(width: 24, height: 24)
                .background(WidgetLibrary.tint(for: WidgetCatalog.category(for: kind)).opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(nsImage: IconProvider.icon(for: item, library: model.store.config.icons,
                                             iconsDirectory: model.file.iconsDirectory))
                .resizable()
        }
    }

    private var subtitle: String {
        if let widget = item.widget {
            if widget.kind == .link, let url = URL(string: widget.string("url", "")) { return url.host() ?? "Link" }
            return "Widget"
        }
        switch item.kind {
        case .app: return "App"
        case .folder: return item.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Folder"
        default: return item.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "File"
        }
    }
}

extension AppModel {
    /// Adds the native Dock's apps (as a Live Dock widget), folders and a Trash.
    func addNativeDockCopy(to dockID: UUID) {
        let others = nativeDock.others().map { DockItem.file(at: URL(fileURLWithPath: $0)) }
        if store.dock(dockID)?.hasWidget(.liveDock) == false {
            store.addWidget(.liveDock, to: dockID)
        }
        store.addItems(others, to: dockID)
        store.addWidget(.trash, to: dockID)
    }
}
