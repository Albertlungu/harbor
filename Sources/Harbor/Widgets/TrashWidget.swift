import AppKit
import HarborCore
import SwiftUI

enum TrashEmptyOutcome {
    case done
    case automationDenied
    case failed(String)
}

/// Reads and empties ~/.Trash.
enum TrashService {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    static let automationSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// Nil when the folder cannot be read, which is the case without Full Disk Access.
    static func hasItems() -> Bool? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
        return names.contains { !$0.hasPrefix(".") }
    }

    @MainActor
    static func empty() -> TrashEmptyOutcome {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        guard let error else { return .done }
        // -1743 is "not authorized to send Apple events", the Automation permission.
        if (error["NSAppleScriptErrorNumber"] as? Int) == -1743 { return .automationDenied }
        return .failed(error["NSAppleScriptErrorMessage"] as? String ?? "Finder could not empty the Trash.")
    }

    @MainActor
    static func confirmEmpty() -> Bool {
        StorageDialogs.confirm("Empty the Trash?", message: "Everything in the Trash is deleted for good. This can't be undone.",
                               action: "Empty Trash")
    }

    /// Empties with any problem reported in a dialog. `confirm` is false when Command was held, to skip asking.
    @MainActor
    static func emptyWithDialogs(confirm: Bool = true) {
        if confirm, !confirmEmpty() { return }
        switch empty() {
        case .done: Celebration.shared.play(dock: nil)
        case .automationDenied:
            let alert = NSAlert()
            alert.messageText = "Harbor can't control Finder"
            alert.informativeText = "Allow Harbor to control Finder in System Settings, under Privacy & Security, then Automation."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(automationSettings) }
        case .failed(let message):
            StorageDialogs.notice("Couldn't empty the Trash", message: message)
        }
    }
}

struct TrashWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var full = false
    @State private var open = false

    var body: some View {
        StorageGlyph(symbol: full ? "trash.fill" : "trash", size: size)
            .contentShape(Rectangle())
            .onTapGesture { open.toggle() }
            .task {
                // Polling is cheap and the folder has no change notification we can rely on without access.
                while !Task.isCancelled {
                    full = TrashService.hasItems() ?? false
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .storagePopover(isPresented: $open, state: state, sized: false) {
                FolderBrowser(folder: TrashService.url, options: item.folder, role: role, arrowEdge: state.popoverEdge,
                              save: { options in model.store.updateItem(item.id, in: dock.id) { $0.folder = options } },
                              onClose: { open = false })
            }
            .onChange(of: open) { _, isOpen in if !isOpen { full = TrashService.hasItems() ?? false } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trash")
            .accessibilityValue(full ? "Has items" : "Empty")
            .accessibilityAddTraits(.isButton)
    }

    private var role: FolderBrowserRole {
        FolderBrowserRole(
            kind: .trash, emptyTitle: Copy.emptyTrash(model.playful), emptySymbol: "trash",
            deniedHint: "Harbor needs Full Disk Access to list what's in the Trash. You can still empty it, or open it in Finder.",
            clear: ("Empty Trash", {
                // Command-click skips the confirmation, as Option does in Finder.
                TrashService.emptyWithDialogs(confirm: !NSEvent.modifierFlags.contains(.command))
                full = TrashService.hasItems() ?? false
            }))
    }
}
