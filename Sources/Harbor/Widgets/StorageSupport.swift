import AppKit
import HarborCore
import SwiftUI

/// Small modal dialogs used by the storage widgets.
@MainActor
enum StorageDialogs {
    static func confirm(_ title: String, message: String, action: String, destructive: Bool = true) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = destructive
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func notice(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    static func askText(_ title: String, message: String, initial: String, action: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Lets the person pick files or folders; empty when cancelled.
    static func choose(files: Bool, folders: Bool, multiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = multiple
        NSApp.activate()
        return panel.runModal() == .OK ? panel.urls : []
    }
}

extension View {
    /// A popover anchored away from the dock edge that keeps auto-hide away while it is open.
    /// `sized` gives the popover the storage panels' fixed width; a browser picks its own.
    func storagePopover<Popup: View>(isPresented: Binding<Bool>, state: DockViewState, sized: Bool = true,
                                     @ViewBuilder content: @escaping () -> Popup) -> some View {
        modifier(StoragePopover(isPresented: isPresented, state: state, sized: sized, popup: content))
    }

    func hoverHighlight(selected: Bool = false) -> some View {
        modifier(HoverHighlight(selected: selected))
    }
}

private struct StoragePopover<Popup: View>: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    let state: DockViewState
    let sized: Bool
    let popup: () -> Popup
    @Environment(\.dockEdge) private var dockEdge
    @State private var openTrigger = 0

    private var edge: Edge { state.popoverEdge }

    func body(content: Content) -> some View {
        content
            .modifier(OpenEffectModifier(trigger: openTrigger, effect: model.store.settings.openEffect, edge: dockEdge))
            .popover(isPresented: $isPresented, arrowEdge: edge) {
                popup()
                    .frame(width: sized ? Tokens.Storage.popoverWidth : nil)
                    .environment(model)
                    .popEntrance(enabled: model.store.settings.openAnimation)
            }
            .onChange(of: isPresented) { _, open in
                state.menuOpen = open
                if open, !model.store.editing.contains(state.dockID) {
                    OpenFeedback.fire(&openTrigger, settings: model.store.settings)
                }
            }
    }
}

private struct HoverHighlight: ViewModifier {
    let selected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        let opacity = selected ? Tokens.Storage.selectedOpacity : (hovering ? Tokens.Storage.hoverOpacity : 0)
        content
            .background(RoundedRectangle(cornerRadius: Tokens.Storage.tileRadius, style: .continuous)
                .fill(Tokens.accent.opacity(opacity)))
            .onHover { hovering = $0 }
    }
}

/// An SF Symbol on a soft rounded tile, the dock face of the shelf and trash widgets.
struct StorageGlyph: View {
    let symbol: String
    var color: Color?
    let size: CGSize

    var body: some View {
        let side = min(size.width, size.height)
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).fill(.quaternary)
            Image(systemName: symbol)
                .font(.system(size: side * 0.46))
                .foregroundStyle(color ?? Color.primary)
        }
        .frame(width: side, height: side)
        .frame(width: size.width, height: size.height)
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Tokens.onBadge)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Tokens.badge))
            .accessibilityHidden(true)
    }
}

/// Finds the window that hosts a view, so a drag can be judged against its frame.
@MainActor
final class WindowBox {
    weak var window: NSWindow?
}

struct WindowReader: NSViewRepresentable {
    let box: WindowBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        capture(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { capture(view) }

    private func capture(_ view: NSView) {
        Task { @MainActor [weak view, box] in box.window = view?.window }
    }
}

extension DockViewState {
    /// The side of a popover that faces the dock, where its arrow sits.
    var popoverEdge: Edge {
        switch hugEdge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }
}

/// Opens a storage popover the moment a file drag comes within `reach` of the widget, so files can go
/// straight into it. One opened that way closes again once the pointer leaves both the widget and the
/// popover, dragging or not, unless it was clicked in.
struct DragSpring: ViewModifier {
    @Binding var isPresented: Bool
    /// Points between the pointer and the widget; zero means right over it.
    let reach: CGFloat
    /// Off while the dock is hidden, since the widget can't be seen.
    let enabled: Bool
    /// The popover's window, read from inside it.
    let popup: WindowBox
    @State private var anchor = ViewBox()
    @State private var token = UUID()
    @State private var sprung = false

    func body(content: Content) -> some View {
        content
            .background(ViewReader(box: anchor))
            .onAppear(perform: register)
            .onDisappear { FileDragTracker.shared.stop(token) }
            .onChange(of: reach) { register() }
            .onChange(of: enabled) { register() }
            .onChange(of: isPresented) { _, open in if !open { sprung = false } }
    }

    private func register() {
        let reach = reach, enabled = enabled
        FileDragTracker.shared.observe(token) { event in handle(event, reach: reach, enabled: enabled) }
    }

    private func handle(_ event: FileDragTracker.Event, reach: CGFloat, enabled: Bool) {
        guard let widget = anchor.screenRect else { return }
        let inPopup = { (p: CGPoint) in popup.window?.frame.insetBy(dx: -6, dy: -6).contains(p) ?? false }
        let near = { (p: CGPoint) in Self.distance(from: p, to: widget) <= reach }
        switch event {
        case .dragged(let p):
            if enabled, !isPresented, near(p) {
                isPresented = true
                sprung = true
            } else if sprung, isPresented, !near(p), !inPopup(p) {
                isPresented = false
            }
        case .ended(let p), .moved(let p):
            if sprung, isPresented, !near(p), !inPopup(p) { isPresented = false }
        case .pressed(let p):
            // A click inside means it's being used; it then stays open like one opened by clicking.
            if sprung, inPopup(p) { sprung = false }
        }
    }

    private static func distance(from p: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

@MainActor
final class ViewBox {
    weak var view: NSView?

    /// The view's frame in screen coordinates, as `NSEvent.mouseLocation` reports points.
    var screenRect: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

struct ViewReader: NSViewRepresentable {
    let box: ViewBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}
