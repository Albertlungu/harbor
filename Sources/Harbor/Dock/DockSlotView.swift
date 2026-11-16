import AppKit
import HarborCore
import SwiftUI
import UniformTypeIdentifiers

/// One app, file, folder or widget on a dock.
struct DockSlotView: View {
    @Environment(AppModel.self) private var model
    let slot: DockSlot
    let dock: Dock
    let size: CGSize
    let iconSize: CGFloat
    let hovered: Bool
    let editing: Bool
    let state: DockViewState

    @State private var dropTargeted = false
    @State private var bounce = false
    @State private var showFolder = false

    var body: some View {
        content
            .scaleEffect(dropTargeted ? 1.08 : 1)
            .offset(bounceOffset)
            .overlay(alignment: .topLeading) { removeBadge }
            .contentShape(Rectangle())
            .onTapGesture { tap() }
            .contextMenu { ItemContextMenu(slot: slot, dock: dock, editing: editing) }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
            .modifier(EditDragModifier(slot: slot, dock: dock, editing: editing))
            .popover(isPresented: $showFolder, arrowEdge: popoverEdge) {
                if let item = slot.item, let url = item.url {
                    FolderBrowser(folder: url, options: item.folder, onClose: { showFolder = false })
                        .environment(model)
                }
            }
            .onChange(of: showFolder) { _, open in state.menuOpen = open }
            .onChange(of: hovered) { _, isHovered in previewHover(isHovered) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch slot {
        case .app(_, let path, _, let spacer):
            if spacer {
                Color.clear
            } else {
                AppIcon(path: path, image: IconProvider.icon(forPath: path), iconSize: iconSize, dock: dock)
            }
        case .item(let item):
            if item.kind == .widget, let widget = item.widget {
                WidgetView(item: item, widget: widget, dock: dock, size: size, state: state)
            } else if item.kind == .app, let path = item.path {
                AppIcon(path: path, image: icon(for: item), iconSize: iconSize, dock: dock)
            } else {
                Image(nsImage: icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .modifier(TintModifier(style: dock.style))
            }
        }
    }

    private func icon(for item: DockItem) -> NSImage {
        IconProvider.icon(for: item, library: model.store.config.icons, iconsDirectory: model.file.iconsDirectory)
    }

    private var accessibilityName: String {
        switch slot {
        case .item(let item): item.displayName
        case .app(_, _, let name, _): name
        }
    }

    private var popoverEdge: Edge {
        switch state.hugEdge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    private var bounceOffset: CGSize {
        guard bounce else { return .zero }
        let d: CGFloat = 12
        switch state.hugEdge {
        case .bottom: return CGSize(width: 0, height: -d)
        case .top: return CGSize(width: 0, height: d)
        case .left: return CGSize(width: d, height: 0)
        case .right: return CGSize(width: -d, height: 0)
        }
    }

    @ViewBuilder
    private var removeBadge: some View {
        if editing, case .item(let item) = slot {
            Button {
                if item.kind == .widget {
                    model.confirmRemoveWidget(item, from: dock.id)
                } else {
                    model.store.removeItem(item.id, from: dock.id)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Tokens.textMuted)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .offset(x: -4, y: -4)
            .accessibilityLabel("Remove \(item.displayName)")
        }
    }

    // MARK: Actions

    /// The app this slot launches, if it is one.
    private var appPath: String? {
        switch slot {
        case .app(_, let path, _, let spacer): spacer ? nil : path
        case .item(let item): item.kind == .app ? item.path : nil
        }
    }

    private func previewHover(_ isHovered: Bool) {
        guard !editing, let path = appPath else { return }
        let previews = model.dockController.previews
        if isHovered {
            let owner = model.dockController.controllers(for: dock.id).first { $0.state.screenID == state.screenID }
            previews.hoverBegan(path: path, from: owner)
        } else {
            previews.hoverEnded()
        }
    }

    private func tap() {
        guard !editing else { return }
        switch slot {
        case .app(_, let path, _, let spacer):
            guard !spacer else { return }
            let item = DockItem(kind: .app, path: path)
            open(item)
        case .item(let item):
            guard item.kind != .widget else { return }
            open(item)
        }
    }

    private func open(_ item: DockItem) {
        if item.kind == .app, let path = item.path, !model.running.isRunning(path: path),
           model.store.settings.attentionStyle == .bounce, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.easeOut(duration: 0.25).repeatCount(3, autoreverses: true)) { bounce = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                bounce = false
            }
        }
        ItemActions.open(item, dock: dock, running: model.running, settings: model.store.settings) { _ in
            showFolder = true
        }
    }

    /// Dropping files while the dock is locked sends them to the item instead of pinning.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if editing {
            guard case .item(let target) = slot,
                  let index = dock.items.firstIndex(where: { $0.id == target.id }) else { return false }
            DropLoader.urls(from: providers) { urls in
                model.store.addItems(urls.map(DockItem.file(at:)), to: dock.id, at: index)
            }
            return true
        }
        switch slot {
        case .app(_, let path, _, let spacer):
            guard !spacer else { return false }
            DropLoader.urls(from: providers) { ItemActions.open($0, withApp: URL(fileURLWithPath: path)) }
            return true
        case .item(let item):
            switch item.kind {
            case .app:
                guard let url = item.url else { return false }
                DropLoader.urls(from: providers) { ItemActions.open($0, withApp: url) }
                return true
            case .folder:
                guard let url = item.url else { return false }
                DropLoader.urls(from: providers) { ItemActions.move($0, into: url) }
                return true
            case .widget:
                return WidgetDrop.handle(providers, item: item, dock: dock, model: model)
            case .file:
                model.flashHint("Right-click the dock and choose Edit Dock to add items.")
                return false
            }
        }
    }
}

struct AppIcon: View {
    @Environment(AppModel.self) private var model
    let path: String
    let image: NSImage
    let iconSize: CGFloat
    let dock: Dock

    var body: some View {
        let running = model.running.app(atPath: path)
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: iconSize, height: iconSize)
            .modifier(TintModifier(style: dock.style))
            .overlay(alignment: .bottom) {
                if running != nil && model.store.settings.showRunningIndicators {
                    Circle()
                        .fill(model.store.settings.indicatorColor?.color ?? Tokens.indicator)
                        .frame(width: Tokens.Dock.indicatorSize, height: Tokens.Dock.indicatorSize)
                        .offset(y: Tokens.Dock.indicatorSize + 2)
                }
            }
            .opacity(running?.isHidden == true ? 0.6 : 1)
    }
}

struct TintModifier: ViewModifier {
    let style: DockStyle

    func body(content: Content) -> some View {
        if style.tintIcons {
            content
                .overlay(style.tintColor.color.blendMode(.color).opacity(style.tintIntensity))
                .compositingGroup()
        } else {
            content
        }
    }
}

/// Reordering by drag while the dock is in Edit Mode.
struct EditDragModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    let slot: DockSlot
    let dock: Dock
    let editing: Bool

    func body(content: Content) -> some View {
        if editing, case .item(let item) = slot {
            content
                .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                        guard let string = value as? String, let id = UUID(uuidString: string) else { return }
                        Task { @MainActor in
                            guard let index = model.store.dock(dock.id)?.items.firstIndex(where: { $0.id == item.id })
                            else { return }
                            model.store.moveItem(id, in: dock.id, to: index)
                        }
                    }
                    return true
                }
        } else {
            content
        }
    }
}
