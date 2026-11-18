import AppKit
import HarborCore
import SwiftUI

/// A small Finder window beside the dock: navigation, Finder's four views, sorting and search
/// over one pinned folder, with view and sort saved on the dock item.
struct FolderBrowser: View {
    let onClose: () -> Void
    /// The popover's arrow edge, which tells the resize handles which way the popover grows.
    let arrowEdge: Edge
    @State private var model: FolderBrowserModel
    private let options: FolderOptions
    /// The size while a resize handle is dragged; saved on the item when the drag ends.
    @State private var dragSize: CGSize?
    @State private var measured: CGSize = .zero

    init(folder: URL, options: FolderOptions, arrowEdge: Edge, save: @escaping (FolderOptions) -> Void,
         onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.arrowEdge = arrowEdge
        self.options = options
        _model = State(initialValue: FolderBrowserModel(root: folder, options: options, persist: save, close: onClose))
    }

    var body: some View {
        let size = self.size
        VStack(spacing: 0) {
            FolderToolbar(model: model)
            Divider()
            content
                .frame(height: size == nil ? contentHeight : nil)
            Divider()
            statusBar
        }
        // A definite size: popovers in a borderless panel won't present content that sizes to zero.
        .frame(width: size?.width ?? width, height: size?.height)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { measured = $0 }
        .overlay {
            if model.options.layout != .fan {
                ResizeHandles(arrowEdge: arrowEdge, current: { measured },
                              resize: { dragSize = $0 },
                              finish: {
                                  if let dragSize { model.saveSize(dragSize) }
                                  dragSize = nil
                              })
            }
        }
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

    /// The hand-picked size, if any; the fan keeps its own fixed size.
    private var size: CGSize? {
        if let dragSize { return dragSize }
        guard model.options.layout != .fan, let width = model.options.browserWidth,
              let height = model.options.browserHeight else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// Invisible strips and corners along the popover's edges that resize it like a window, except on
/// the side facing the dock, where the arrow keeps it attached to its item.
private struct ResizeHandles: View {
    let arrowEdge: Edge
    let current: () -> CGSize
    let resize: (CGSize) -> Void
    let finish: () -> Void
    @State private var start: (mouse: NSPoint, size: CGSize)?

    private struct Spot: Hashable {
        var vertical: ScreenEdge?
        var horizontal: ScreenEdge?
    }

    /// The popover grows toward its arrow edge: one above a bottom dock grows upward.
    private var far: ScreenEdge {
        switch arrowEdge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .left
        case .trailing: .right
        }
    }

    private var pinned: ScreenEdge {
        switch far {
        case .top: .bottom
        case .bottom: .top
        case .left: .right
        case .right: .left
        }
    }

    private var spots: [Spot] {
        var spots: [Spot] = []
        for vertical in [ScreenEdge.top, .bottom, nil] {
            for horizontal in [ScreenEdge.left, .right, nil] where vertical != nil || horizontal != nil {
                if vertical != pinned, horizontal != pinned { spots.append(Spot(vertical: vertical, horizontal: horizontal)) }
            }
        }
        return spots
    }

    var body: some View {
        ZStack {
            ForEach(spots, id: \.self) { spot in
                let corner = spot.vertical != nil && spot.horizontal != nil
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: spot.horizontal == nil ? nil : (corner ? 14 : 6),
                           height: spot.vertical == nil ? nil : (corner ? 14 : 6))
                    .pointerStyle(.frameResize(position: position(spot)))
                    .gesture(drag(spot))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(spot))
            }
        }
    }

    /// Tracks the pointer in screen coordinates: the popover's window moves as it resizes, so
    /// view-local drag translations would drift.
    private func drag(_ spot: Spot) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                let origin = start ?? (mouse, current())
                if start == nil { start = origin }
                let limit = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)
                    .map { CGSize(width: $0.visibleFrame.width - 40, height: $0.visibleFrame.height - 80) } ?? .zero
                let translation = CGSize(width: mouse.x - origin.mouse.x, height: origin.mouse.y - mouse.y)
                guard translation != .zero else { return }
                resize(FolderBrowserResize.size(from: origin.size, translation: translation, vertical: spot.vertical,
                                                horizontal: spot.horizontal, growsToward: far, limit: limit))
            }
            .onEnded { _ in
                start = nil
                finish()
            }
    }

    private func alignment(_ spot: Spot) -> Alignment {
        let h: HorizontalAlignment = spot.horizontal == .left ? .leading : (spot.horizontal == .right ? .trailing : .center)
        let v: VerticalAlignment = spot.vertical == .top ? .top : (spot.vertical == .bottom ? .bottom : .center)
        return Alignment(horizontal: h, vertical: v)
    }

    private func position(_ spot: Spot) -> FrameResizePosition {
        switch (spot.vertical, spot.horizontal) {
        case (.top, .left): .topLeading
        case (.top, .right): .topTrailing
        case (.bottom, .left): .bottomLeading
        case (.bottom, .right): .bottomTrailing
        case (.top, _): .top
        case (.bottom, _): .bottom
        case (_, .left): .leading
        default: .trailing
        }
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
                    .disabled(model.options.sort != .name)
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
