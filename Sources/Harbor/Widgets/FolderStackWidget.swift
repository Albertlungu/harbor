import AppKit
import HarborCore
import SwiftUI

/// Several folders behind one dock icon; picking a folder in the popover opens it.
struct FolderStackWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var open = false

    private var title: String {
        let name = widget.string("name", "")
        return name.isEmpty ? "Folder Stack" : name
    }

    var body: some View {
        let side = min(size.width, size.height)
        Image(systemName: "folder.fill")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: side * 0.78))
            .foregroundStyle(colorSetting(widget, "tint") ?? Tokens.accent)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if widget.strings("folders").isEmpty {
                    model.openItemSettings(item.id, in: dock.id)
                } else {
                    open.toggle()
                }
            }
            .storagePopover(isPresented: $open, state: state) {
                FolderStackList(item: item, dockID: dock.id, onClose: { open = false })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityHint(widget.strings("folders").isEmpty ? "Opens settings to add folders" : "Shows the folders in this stack")
            .accessibilityAddTraits(.isButton)
    }
}

private struct FolderStackList: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID
    let onClose: () -> Void

    private var widget: WidgetConfig { WidgetFields(model: model, itemID: item.id, dockID: dockID).current }

    var body: some View {
        let name = widget.string("name", "")
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(name.isEmpty ? "Folder Stack" : name).font(.headline)
            VStack(spacing: Tokens.Space.xxs) {
                ForEach(widget.strings("folders"), id: \.self) { path in row(path) }
            }
        }
        .padding(Tokens.Storage.popoverPadding)
    }

    private func row(_ path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let exists = FileManager.default.fileExists(atPath: path)
        return Button {
            guard exists else { return }
            open(url)
        } label: {
            HStack(spacing: Tokens.Space.l) {
                Image(nsImage: IconProvider.icon(forPath: path)).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(url.lastPathComponent).lineLimit(1)
                    Text(exists ? url.deletingLastPathComponent().path : "Can't find this folder")
                        .font(.caption)
                        .foregroundStyle(exists ? Tokens.textMuted : Tokens.danger)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.s)
            .contentShape(Rectangle())
            .opacity(exists ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityHint(exists ? "Opens this folder" : "Folder is missing")
    }

    private func open(_ url: URL) {
        let app = widget.string("openWith", "")
        if app.isEmpty {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: app),
                                    configuration: NSWorkspace.OpenConfiguration())
        }
        onClose()
    }
}
