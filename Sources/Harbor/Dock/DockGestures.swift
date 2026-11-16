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

/// Middle clicks and scroll-wheel gestures over dock panels, through local event monitors.
@MainActor
final class GestureMonitor {
    private unowned let model: AppModel
    private var tokens: [Any] = []
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollAction = Date.distantPast

    /// What the handler needs from an event, copied so the closure stays Sendable-clean.
    private struct Input {
        let type: NSEvent.EventType
        let windowNumber: Int
        let button: Int
        let deltaY: CGFloat
        let precise: Bool
        let momentum: Bool
    }

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        let token = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp, .scrollWheel]) { [weak self] event in
            let input = Input(type: event.type, windowNumber: event.windowNumber, button: event.buttonNumber,
                              deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                              momentum: !event.momentumPhase.isEmpty)
            let consumed = MainActor.assumeIsolated { self?.handle(input) ?? false }
            return consumed ? nil : event
        }
        if let token { tokens.append(token) }
    }

    private func handle(_ input: Input) -> Bool {
        let settings = model.store.settings
        guard let controller = model.dockController.windows.values.first(where: { $0.panel.windowNumber == input.windowNumber }),
              !model.store.editing.contains(controller.dockID),
              let id = controller.state.hoveredSlotID,
              let slot = controller.state.slots.first(where: { $0.id == id }),
              let path = slot.appPath else { return false }

        if input.type == .otherMouseUp {
            guard input.button == 2, DockGestures.click(.middle, slot: slot, settings: settings, running: model.running)
            else { return false }
            return true
        }

        guard settings.scrollGestures, !input.momentum, let app = model.running.app(atPath: path) else { return false }
        // Trackpads report many small deltas; a notch of wheel travel counts as one step.
        scrollAccumulator += input.precise ? input.deltaY : input.deltaY * 10
        guard abs(scrollAccumulator) >= 12, Date().timeIntervalSince(lastScrollAction) > 0.2 else { return true }
        let up = scrollAccumulator > 0
        scrollAccumulator = 0
        lastScrollAction = Date()
        switch settings.scrollAction {
        case .browsePreviews:
            // Scrolling down moves forward through the windows, like reading a list.
            model.dockController.previews.browse(path: path, from: controller, step: up ? -1 : 1)
        case .cycleWindows:
            WindowControl.cycle(app.pid)
        case .showHide:
            guard let live = NSRunningApplication(processIdentifier: app.pid) else { return true }
            if up {
                live.unhide()
                live.activate()
            } else {
                live.hide()
            }
        }
        return true
    }
}
