import AppKit
import HarborCore
import SwiftUI

/// A small Finder window beside the dock: navigation, Finder's four views, sorting and search
/// over one pinned folder, with view and sort saved on the dock item.
struct FolderBrowser: View {
    let onClose: () -> Void
    @State private var model: FolderBrowserModel
    private let options: FolderOptions

    init(folder: URL, options: FolderOptions, save: @escaping (FolderOptions) -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.options = options
        _model = State(initialValue: FolderBrowserModel(root: folder, options: options, persist: save, close: onClose))
    }

    var body: some View {
        VStack(spacing: 0) {
            FolderToolbar(model: model)
            Divider()
            content
                .frame(height: contentHeight)
            Divider()
            statusBar
        }
        // A definite size: popovers in a borderless panel won't present content that sizes to zero.
        .frame(width: width)
        .background(FolderWindowHook(model: model))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: options) { _, new in model.adopt(new) }
    }

    @ViewBuilder
    private var content: some View {
        if model.denied {
            ContentUnavailableView {
                Label("Can't read this folder", systemImage: "lock")
            } description: {
                Text("Allow Harbor to access it in System Settings, or open it in Finder.")
            }
        } else if model.loaded && model.entries.isEmpty {
            ContentUnavailableView("Empty folder", systemImage: "folder")
                .contextMenu { Button("New Folder") { model.newFolder() } }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    DropLoader.urls(from: providers) { FileOperations.transfer($0, into: model.current, move: false) }
                    return true
                }
        } else {
            switch model.options.layout {
            case .grid: FolderIconsView(model: model)
            case .list: FolderListView(model: model)
            case .columns: FolderColumnsView(model: model)
            case .gallery: gallery
            case .fan: FolderFan(model: model)
            }
        }
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            FolderPreview(url: model.selectedURLs.last ?? model.visible.first(where: { !$0.isFolder })?.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            FolderIconsView(model: model, strip: true)
                .frame(height: 90)
        }
    }

    private var statusBar: some View {
        let total = model.visible.count
        let selected = model.selection.count
        return Text(selected > 0 ? "\(selected) of \(total) selected" : "\(total) item\(total == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(Tokens.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Space.xs)
    }

    private var width: CGFloat {
        switch model.options.layout {
        case .list: 620
        case .columns: 640
        case .gallery: 600
        case .fan: 320
        case .grid:
            max(520, CGFloat(min(max(model.options.columns, 2), 10)) * (CGFloat(model.options.iconSize) + 34) + 20)
        }
    }

    private var contentHeight: CGFloat {
        model.options.layout == .gallery ? 420 : 360
    }
}

/// Back, forward, enclosing folder, the folder's name, view and sort pickers, search and Finder.
private struct FolderToolbar: View {
    @Bindable var model: FolderBrowserModel

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            ControlGroup {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.history.canGoBack)
                    .help("Back")
                Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.history.canGoForward)
                    .help("Forward")
            }
            .controlSize(.small)
            .fixedSize()
            Button { model.goUp() } label: { Image(systemName: "arrow.turn.left.up") }
                .controlSize(.small)
                .disabled(!model.canGoUp)
                .help("Enclosing Folder")
            Text(FileManager.default.displayName(atPath: model.current.path))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
                .help(model.current.path)
            Spacer(minLength: 0)
            Picker("View", selection: Binding(get: { model.options.layout == .fan ? nil : model.options.layout },
                                              set: { layout in if let layout { model.updateOptions { $0.layout = layout } } })) {
                Image(systemName: "square.grid.2x2").help("Icons").tag(FolderLayout?.some(.grid))
                Image(systemName: "list.bullet").help("List").tag(FolderLayout?.some(.list))
                Image(systemName: "rectangle.split.3x1").help("Columns").tag(FolderLayout?.some(.columns))
                Image(systemName: "rectangle.bottomthird.inset.filled").help("Gallery").tag(FolderLayout?.some(.gallery))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Menu {
                Picker("Sort By", selection: Binding(get: { model.options.sort },
                                                     set: { key in model.updateOptions { $0.sort = key; $0.reverse = false } })) {
                    ForEach(FolderSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Order", selection: Binding(get: { model.options.ascending },
                                                   set: { up in model.updateOptions { $0.ascending = up } })) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Folders First", isOn: Binding(get: { model.options.foldersFirst },
                                                      set: { on in model.updateOptions { $0.foldersFirst = on } }))
                Toggle("Show Hidden Files", isOn: Binding(get: { model.options.showHidden },
                                                          set: { on in model.updateOptions { $0.showHidden = on } }))
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
            .controlSize(.small)
            .fixedSize()
            .help("Sort by \(model.options.sort.title)")
            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(minWidth: 70, maxWidth: 110)
            Button { model.openCurrentInFinder() } label: { Image(systemName: "macwindow") }
                .controlSize(.small)
                .help("Open in Finder")
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
    }
}

/// The Dock-style fan kept from earlier versions: a short stack of the first entries.
private struct FolderFan: View {
    let model: FolderBrowserModel

    var body: some View {
        VStack(alignment: .trailing, spacing: Tokens.Space.xs) {
            ForEach(Array(model.visible.prefix(12).enumerated()), id: \.element.url) { index, entry in
                HStack {
                    Text(entry.name).font(.callout).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                    Image(nsImage: IconProvider.icon(forPath: entry.url.path)).resizable().frame(width: 36, height: 36)
                }
                .rotationEffect(.degrees(Double(index) * -1.5), anchor: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { model.open([entry.url]) }
                .onDrag {
                    model.draggedOut()
                    return NSItemProvider(object: entry.url as NSURL)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(Tokens.Space.l)
    }
}

/// Hands the popover's window to the model once it exists, for its keyboard shortcuts.
private struct FolderWindowHook: NSViewRepresentable {
    let model: FolderBrowserModel

    func makeNSView(context: Context) -> NSView { HookView(model: model) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class HookView: NSView {
        let model: FolderBrowserModel

        init(model: FolderBrowserModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            model.installKeyMonitor(for: window)
            // Typing, Quick Look and the Edit menu need Harbor active, as Finder is while one of its windows is in front.
            NSApp.activate()
            window.makeKey()
        }
    }
}
