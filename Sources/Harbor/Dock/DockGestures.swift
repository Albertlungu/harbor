import AppKit
import HarborCore

extension DockSlot {
    /// The app this slot launches, if it is one.
    var appPath: String? {
        switch self {
        case .app(_, let path, _, let spacer): spacer ? nil : path
        case .item(let item): item.kind == .app ? item.path : nil
        }
    }
}

/// The actions behind modifier-clicks and scrolling on dock icons.
@MainActor
enum DockGestures {
    static func modifier(for flags: NSEvent.ModifierFlags) -> ClickModifier? {
        let f = flags.intersection([.command, .option, .shift, .control])
        // Control-click is the context menu.
        if f.contains(.control) { return nil }
        switch f {
        case [.command]: return .command
        case [.option]: return .option
        case [.command, .option]: return .optionCommand
        case [.shift]: return .shift
        default: return nil
        }
    }

    /// Runs the action mapped to `modifier`. Returns false when nothing is mapped, so the click opens the item as usual.
    static func click(_ modifier: ClickModifier, slot: DockSlot, settings: AppSettings, running: RunningApps) -> Bool {
        guard settings.clickGestures, let action = settings.clickGestureActions[modifier], action != .nothing else { return false }
        return perform(action, slot: slot, running: running)
    }

    @discardableResult
    static func perform(_ action: GestureAction, slot: DockSlot, running: RunningApps) -> Bool {
        if action == .revealInFinder {
            let url = slot.appPath.map { URL(fileURLWithPath: $0) } ?? slot.item?.url
            guard let url else { return false }
            ItemActions.reveal(url)
            return true
        }
        guard let path = slot.appPath, let app = running.app(atPath: path),
              let live = NSRunningApplication(processIdentifier: app.pid) else { return false }
        switch action {
        case .toggleHidden:
            if live.isHidden { live.unhide() } else { live.hide() }
        case .showOnlyThis:
            for other in NSWorkspace.shared.runningApplications
            where other.activationPolicy == .regular && other.processIdentifier != app.pid
                && other.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                other.hide()
            }
            live.unhide()
            live.activate()
        case .quit:
            live.terminate()
        case .minimizeFront:
            WindowControl.minimizeFront(of: app.pid)
        case .nothing, .revealInFinder:
            return false
        }
        return true
    }
}

/// Middle clicks over dock panels, through a local event monitor.
@MainActor
final class GestureMonitor {
    private unowned let model: AppModel
    private var tokens: [Any] = []

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        let token = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
            let window = event.windowNumber, button = event.buttonNumber
            let consumed = MainActor.assumeIsolated { self?.handleMiddleClick(window: window, button: button) ?? false }
            return consumed ? nil : event
        }
        if let token { tokens.append(token) }
    }

    private func handleMiddleClick(window: Int, button: Int) -> Bool {
        guard button == 2,
              let controller = model.dockController.windows.values.first(where: { $0.panel.windowNumber == window }),
              !model.store.editing.contains(controller.dockID),
              let id = controller.state.hoveredSlotID,
              let slot = controller.state.slots.first(where: { $0.id == id }),
              slot.appPath != nil else { return false }
        return DockGestures.click(.middle, slot: slot, settings: model.store.settings, running: model.running)
    }
}
