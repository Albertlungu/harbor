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
    func storagePopover<Popup: View>(isPresented: Binding<Bool>, state: DockViewState,
                                     @ViewBuilder content: @escaping () -> Popup) -> some View {
        modifier(StoragePopover(isPresented: isPresented, state: state, popup: content))
    }

    func hoverHighlight(selected: Bool = false) -> some View {
        modifier(HoverHighlight(selected: selected))
    }
}

private struct StoragePopover<Popup: View>: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    let state: DockViewState
    let popup: () -> Popup

    private var edge: Edge {
        switch state.hugEdge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented, arrowEdge: edge) {
                popup()
                    .frame(width: Tokens.Storage.popoverWidth)
                    .environment(model)
            }
            .onChange(of: isPresented) { _, open in state.menuOpen = open }
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

/// SwiftUI reports no result for drags, so the end of one is the mouse button coming up.
@MainActor
enum DragWatcher {
    static func onEnd(in box: WindowBox, _ completion: @escaping @MainActor (_ droppedInside: Bool) -> Void) {
        Task { @MainActor in
            // The drag session starts a beat after the gesture; give it time before looking at the button.
            try? await Task.sleep(for: .milliseconds(250))
            while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            let inside = box.window?.frame.contains(NSEvent.mouseLocation) ?? false
            completion(inside)
        }
    }
}
