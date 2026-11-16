import AppKit
import HarborCore
import Observation

/// Receives commands from harbor-mcp, asks for approval, applies them through the
/// store and replies. The helper never writes the config file itself.
@MainActor
@Observable
final class AssistantBridge {
    static let shared = AssistantBridge()

    private(set) var undoSnapshot: Config?
    var canUndo: Bool { undoSnapshot != nil }

    @ObservationIgnored private var model: AppModel?
    @ObservationIgnored private var allowedThisSession = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    private var access: AssistantAccess {
        AssistantAccess(rawValue: UserDefaults.standard.string(forKey: AssistantAccess.defaultsKey) ?? "") ?? .ask
    }

    func start(model: AppModel) {
        self.model = model
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(AssistantChannel.commandName), object: nil, queue: .main
        ) { note in
            guard let json = note.userInfo?[AssistantChannel.payloadKey] as? String else { return }
            MainActor.assumeIsolated { AssistantBridge.shared.receive(json) }
        }
    }

    func undoLast() {
        guard let snapshot = undoSnapshot, let model else { return }
        model.store.replaceConfig(snapshot)
        undoSnapshot = nil
    }

    private func receive(_ json: String) {
        guard let command = AssistantCommand.decode(json) else { return }
        guard let model else { return reply(command, ok: false, "Harbor is not ready.") }
        switch access {
        case .off:
            return reply(command, ok: false, "AI assistant access is turned off in Harbor's Integrations settings.")
        case .ask:
            if !allowedThisSession && !approve(command) {
                return reply(command, ok: false, "The change was not allowed.")
            }
        case .always:
            break
        }
        let before = model.store.config
        let result = apply(command, store: model.store)
        if result.ok && command.changesConfig { undoSnapshot = before }
        reply(command, ok: result.ok, result.message)
    }

    /// Returns true when the user allows the command.
    private func approve(_ command: AssistantCommand) -> Bool {
        let alert = NSAlert()
        alert.messageText = "An AI assistant wants to change your docks"
        alert.informativeText = command.summary
        alert.addButton(withTitle: "Allow Once")
        alert.addButton(withTitle: "Allow for This Session")
        alert.addButton(withTitle: "Deny")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn:
            allowedThisSession = true
            return true
        default: return false
        }
    }

    private func apply(_ command: AssistantCommand, store: DockStore) -> (ok: Bool, message: String) {
        let name = command.dock ?? ""
        let matches = DockMatching.matches(name, in: store.docks)
        if command.action != .create && (name.isEmpty || matches.isEmpty) {
            return (false, "No dock named \"\(name)\".")
        }
        switch command.action {
        case .show:
            for dock in matches {
                if !dock.enabled { store.setEnabled(dock.id, true) }
                store.show(dock.id)
            }
            return (true, "Showing \(matches.count) dock(s).")
        case .hide:
            for dock in matches { store.hide(dock.id, source: .assistant) }
            return (true, "Hid \(matches.count) dock(s).")
        case .toggle:
            for dock in matches { store.toggle(dock.id, source: .assistant) }
            return (true, "Toggled \(matches.count) dock(s).")
        case .create:
            guard !name.isEmpty else { return (false, "A name is required.") }
            let dock = store.createDock(name: name)
            return (true, "Created dock \"\(dock.name)\".")
        case .addApp:
            guard let path = command.appPath, FileManager.default.fileExists(atPath: path) else {
                return (false, "The app was not found.")
            }
            let item = DockItem.file(at: URL(fileURLWithPath: path))
            store.addItems([item], to: matches[0].id)
            return (true, "Added \(item.displayName) to \"\(matches[0].name)\".")
        case .removeItem:
            guard let itemName = command.itemName, let item = DockMatching.item(named: itemName, in: matches[0]) else {
                return (false, "No item named \"\(command.itemName ?? "")\" in \"\(matches[0].name)\".")
            }
            store.removeItem(item.id, from: matches[0].id)
            return (true, "Removed \(item.displayName) from \"\(matches[0].name)\".")
        case .setStyle:
            guard let change = command.style else { return (false, "No style change was given.") }
            var probe = matches[0]
            guard change.apply(to: &probe) else { return (false, "That style value is not supported.") }
            store.updateDock(matches[0].id) { change.apply(to: &$0) }
            return (true, "Updated \"\(matches[0].name)\".")
        }
    }

    private func reply(_ command: AssistantCommand, ok: Bool, _ message: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(AssistantChannel.replyName), object: nil,
            userInfo: [AssistantChannel.payloadKey: AssistantReply(id: command.id, ok: ok, message: message).encoded()],
            deliverImmediately: true)
    }
}
