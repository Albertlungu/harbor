import AppKit
import HarborCore
import SwiftUI

struct FilePanelEntry: Identifiable, Hashable {
    let id: String
    let url: URL

    var missing: Bool { !FileManager.default.fileExists(atPath: url.path) }
}

/// The tile grid shared by Shelf and File Shelf popovers.
struct FilePanel: View {
    struct Labels {
        let title: String
        let clearButton: String
        let clearTitle: String
        let clearMessage: String
        let removeItem: String
        let emptyTitle: String
        let emptyHint: String
        let emptySymbol: String
    }

    let labels: Labels
    let entries: [FilePanelEntry]
    let searchable: Bool
    let showsCopy: Bool
    let onRemove: (FilePanelEntry) -> Void
    let onClear: () -> Void
    let onAdd: ([URL]) -> Void
    let onDragEnd: (FilePanelEntry, Bool) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection: String?
    @State private var box = WindowBox()

    private var visible: [FilePanelEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? entries : entries.filter { $0.url.lastPathComponent.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Text(labels.title).font(.headline)
                Spacer()
                if !entries.isEmpty {
                    Button(labels.clearButton) {
                        if StorageDialogs.confirm(labels.clearTitle, message: labels.clearMessage, action: labels.clearButton) {
                            onClear()
                        }
                    }
                    .buttonStyle(.link)
                }
            }
            if searchable && !entries.isEmpty {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search files")
            }
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(labels.emptyTitle, systemImage: labels.emptySymbol)
                } description: {
                    Text(labels.emptyHint)
                }
                .frame(height: 160)
            } else if visible.isEmpty {
                NoResultsView(query: query).frame(height: 160)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.m), count: 3),
                              spacing: Tokens.Space.m) {
                        ForEach(visible) { entry in tile(entry) }
                    }
                }
                // Lazy grids have no ideal height, so a popover would shrink the grid to nothing.
                .frame(height: min(360, CGFloat((visible.count + 2) / 3) * 104))
            }
        }
        .padding(Tokens.Storage.popoverPadding)
        .background(WindowReader(box: box))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            DropLoader.urls(from: providers) { onAdd($0) }
            return true
        }
    }

    private func tile(_ entry: FilePanelEntry) -> some View {
        let missing = entry.missing
        return VStack(spacing: Tokens.Space.xs) {
            if missing {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 36))
                    .foregroundStyle(Tokens.textMuted)
                    .frame(width: 48, height: 48)
            } else {
                Image(nsImage: IconProvider.icon(forPath: entry.url.path)).resizable().frame(width: 48, height: 48)
            }
            Text(entry.url.lastPathComponent).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            if missing { Text("Missing file").font(.caption2).foregroundStyle(Tokens.danger) }
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Space.s)
        .contentShape(Rectangle())
        .hoverHighlight(selected: selection == entry.id)
        .onTapGesture(count: 2) { if !missing { open(entry) } }
        .onTapGesture { selection = entry.id }
        .onDrag {
            DragWatcher.onEnd(in: box) { inside in onDragEnd(entry, inside) }
            return NSItemProvider(object: entry.url as NSURL)
        }
        .contextMenu {
            if !missing {
                Button("Open") { open(entry) }
                Button("Show in Finder") { ItemActions.reveal(entry.url) }
            }
            if showsCopy {
                if !missing { Button("Copy") { copyFile(entry.url) } }
                Button("Copy Path") { copyPath(entry.url) }
            }
            Divider()
            Button(labels.removeItem) { onRemove(entry) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.url.lastPathComponent + (missing ? ", missing file" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { if !missing { open(entry) } }
        .accessibilityAction(named: labels.removeItem) { onRemove(entry) }
    }

    private func open(_ entry: FilePanelEntry) {
        NSWorkspace.shared.open(entry.url)
        onClose()
    }

    private func copyFile(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    private func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}
