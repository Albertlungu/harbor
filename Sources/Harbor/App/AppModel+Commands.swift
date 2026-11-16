import AppKit
import HarborCore
import SwiftUI

extension AppModel {
    func openItemSettings(_ itemID: UUID, in dockID: UUID) {
        selectedDockID = dockID
        managerSection = .items
        itemSheet = ItemRef(dockID: dockID, itemID: itemID)
        windows.showManager()
    }

    func confirmRemoveWidget(_ item: DockItem, from dockID: UUID) {
        let alert = NSAlert()
        alert.messageText = "Remove \(item.displayName)?"
        alert.informativeText = "Its settings will be lost."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            store.removeItem(item.id, from: dockID)
        }
    }

    func confirmRemoveItem(_ item: DockItem, from dockID: UUID) {
        let alert = NSAlert()
        alert.messageText = "Remove \(item.displayName) from the dock?"
        alert.informativeText = "The original stays where it is."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            store.removeItem(item.id, from: dockID)
        }
    }

    /// Shows a short message next to the pointer.
    func flashHint(_ text: String) {
        HintHUD.shared.show(text)
    }
}

struct ItemRef: Identifiable, Equatable {
    let dockID: UUID
    let itemID: UUID
    var id: UUID { itemID }
}

@MainActor
final class HintHUD {
    static let shared = HintHUD()
    private let panel = DockPanel()
    private var hideTask: Task<Void, Never>?

    func show(_ text: String) {
        let view = FirstClickHostingView(rootView: LabelPill(text: text).padding(4))
        panel.contentView = view
        let size = view.fittingSize
        let mouse = NSEvent.mouseLocation
        panel.setFrame(NSRect(x: mouse.x - size.width / 2, y: mouse.y + 24, width: size.width, height: size.height), display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}
