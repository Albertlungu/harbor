import AppKit
import Carbon.HIToolbox
import HarborCore
import Observation

/// Registers each dock's global shortcut with the system and toggles docks when pressed.
@MainActor
@Observable
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    /// Docks whose shortcut the system refused, with a message.
    private(set) var failures: [UUID: String] = [:]

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var registered: [Hotkey: (ref: EventHotKeyRef, id: UInt32)] = [:]
    @ObservationIgnored private var idsToHotkey: [UInt32: Hotkey] = [:]
    @ObservationIgnored private var nextID: UInt32 = 1
    @ObservationIgnored private var handlerInstalled = false
    @ObservationIgnored private var hideTasks: [UUID: Task<Void, Never>] = [:]

    func start(model: AppModel) {
        self.model = model
        installHandler()
        sync()
    }

    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.store.docks.map(\.behavior.hotkey)
        } onChange: { [weak self] in
            Task { @MainActor in self?.sync() }
        }
    }

    /// Registers every distinct shortcut in use and unregisters the rest. Refused
    /// shortcuts are retried on the next sync.
    func sync() {
        defer { observe() }
        guard let model else { return }
        let wanted = Set(model.store.docks.compactMap(\.behavior.hotkey))
        for (hotkey, entry) in registered where !wanted.contains(hotkey) {
            UnregisterEventHotKey(entry.ref)
            registered[hotkey] = nil
            idsToHotkey[entry.id] = nil
        }
        failures = [:]
        for hotkey in wanted where registered[hotkey] == nil {
            var ref: EventHotKeyRef?
            let id = nextID
            nextID += 1
            let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers,
                                             EventHotKeyID(signature: OSType(0x4842_5242), id: id), // "HBRB"
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[hotkey] = (ref, id)
                idsToHotkey[id] = hotkey
            } else {
                for dock in model.store.docks where dock.behavior.hotkey == hotkey {
                    failures[dock.id] = "macOS didn't accept \(hotkey.display); another app may be using it."
                }
            }
        }
    }

    fileprivate func pressed(id: UInt32) {
        guard let model, let hotkey = idsToHotkey[id] else { return }
        for dock in model.store.docks where dock.behavior.hotkey == hotkey {
            let wasVisible = model.store.isVisible(dock.id)
            let autoHidden = model.dockController.controllers(for: dock.id).contains { $0.autoHidden }
            if wasVisible && autoHidden {
                for c in model.dockController.controllers(for: dock.id) { c.revealFromHotkey(duration: dock.behavior.hideAgainAfter) }
                continue
            }
            model.store.toggle(dock.id, source: .shortcut)
            hideTasks[dock.id]?.cancel()
            if !wasVisible, dock.behavior.hideAgainAfter > 0 {
                let delay = dock.behavior.hideAgainAfter
                hideTasks[dock.id] = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    model.store.hide(dock.id, source: .shortcut)
                }
            }
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, 1, &spec, nil, nil)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func display(_ flags: NSEvent.ModifierFlags, event: NSEvent) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
        return s + (key == " " ? "Space" : key)
    }
}

private func hotkeyCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &id)
    let value = id.id
    MainActor.assumeIsolated { HotkeyCenter.shared.pressed(id: value) }
    return noErr
}
