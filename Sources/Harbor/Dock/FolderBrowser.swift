import AppKit
import HarborCore
import QuickLookUI
import SwiftUI

/// Browses a folder beside the dock in a grid, list or fan.
struct FolderBrowser: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    let options: FolderOptions
    let onClose: () -> Void

    @State private var entries: [URL] = []
    @State private var selection: URL?
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Text(folder.lastPathComponent).font(.headline)
                Spacer()
                Button("Open in Finder") {
                    NSWorkspace.shared.open(folder)
                    onClose()
                }
                .buttonStyle(.link)
            }
            if denied {
                ContentUnavailableView {
                    Label("Can't read this folder", systemImage: "lock")
                } description: {
                    Text("Allow Harbor to access it in System Settings, or open it in Finder.")
                }
            } else if entries.isEmpty {
                ContentUnavailableView("Empty folder", systemImage: "folder")
            } else {
                switch options.layout {
                case .grid: grid
                case .list: list
                case .fan: fan
                }
            }
        }
        .padding(Tokens.Space.l)
        .frame(width: options.layout == .list ? 300 : nil)
        .onAppear(perform: load)
        .onKeyPress(.space) {
            if let selection { QuickLook.shared.preview(selection) }
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            DropLoader.urls(from: providers) { urls in
                ItemActions.move(urls, into: folder, copy: true)
                load()
            }
            return true
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(CGFloat(options.iconSize) + 24), spacing: Tokens.Space.m),
                            count: max(1, min(options.columns, entries.count)))
        return ScrollView {
            LazyVGrid(columns: columns, spacing: Tokens.Space.l) {
                ForEach(entries, id: \.self) { url in
                    VStack(spacing: Tokens.Space.xs) {
                        thumbnail(url, size: CGFloat(options.iconSize))
                        if options.showNames {
                            Text(url.lastPathComponent).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                        }
                    }
                    .padding(Tokens.Space.xs)
                    .background(selection == url ? Tokens.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .modifier(EntryInteractions(url: url, selection: $selection, onOpen: open, closeAfterDrag: closeAfterDrag))
                }
            }
        }
        .frame(maxHeight: 420)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(entries, id: \.self) { url in
                    HStack {
                        thumbnail(url, size: 20)
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, Tokens.Space.s)
                    .padding(.vertical, 3)
                    .background(selection == url ? Tokens.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .modifier(EntryInteractions(url: url, selection: $selection, onOpen: open, closeAfterDrag: closeAfterDrag))
                }
            }
        }
        .frame(maxHeight: 420)
    }

    private var fan: some View {
        VStack(alignment: .trailing, spacing: Tokens.Space.xs) {
            ForEach(Array(entries.prefix(12).enumerated()), id: \.element) { index, url in
                HStack {
                    Text(url.lastPathComponent).font(.callout).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                    thumbnail(url, size: 36)
                }
                .rotationEffect(.degrees(Double(index) * -1.5), anchor: .trailing)
                .modifier(EntryInteractions(url: url, selection: $selection, onOpen: open, closeAfterDrag: closeAfterDrag))
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ url: URL, size: CGFloat) -> some View {
        Image(nsImage: IconProvider.icon(forPath: url.path))
            .resizable()
            .frame(width: size, height: size)
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        onClose()
    }

    private func closeAfterDrag() {
        if options.closeAfterDragOut { onClose() }
    }

    private func load() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .typeIdentifierKey]
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                     options: options.showHidden ? [] : [.skipsHiddenFiles]) else {
            denied = true
            return
        }
        denied = false
        entries = FolderSorting.sorted(urls, options: options)
    }
}

enum FolderSorting {
    static func sorted(_ urls: [URL], options: FolderOptions) -> [URL] {
        let sorted = urls.sorted { a, b in
            if options.foldersFirst {
                let da = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let db = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if da != db { return da }
            }
            switch options.sort {
            case .name:
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            case .kind:
                if a.pathExtension != b.pathExtension { return a.pathExtension < b.pathExtension }
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            case .dateModified:
                let ma = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let mb = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return ma > mb
            }
        }
        return options.reverse ? sorted.reversed() : sorted
    }
}

private struct EntryInteractions: ViewModifier {
    let url: URL
    @Binding var selection: URL?
    let onOpen: (URL) -> Void
    let closeAfterDrag: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onOpen(url) }
            .onTapGesture { selection = url }
            .onDrag {
                closeAfterDrag()
                return NSItemProvider(object: url as NSURL)
            }
            .contextMenu {
                Button("Open") { onOpen(url) }
                Button("Show in Finder") { ItemActions.reveal(url) }
                Button("Quick Look") { QuickLook.shared.preview(url) }
            }
    }
}

/// Minimal Quick Look panel driver.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var url: URL?

    func preview(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }
}
