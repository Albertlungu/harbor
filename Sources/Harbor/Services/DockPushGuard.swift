import AppKit

/// Keeps the hidden macOS Dock from being pushed into view. On macOS 26 and later the Dock
/// ignores its auto-hide delay when the pointer keeps moving into its edge after reaching it;
/// what it reads is the movement delta of events whose pointer is pinned to that edge. An event
/// tap zeroes just that delta: the pointer's position and Harbor's own edge reveal, which go
/// by position, are untouched. Needs Accessibility; without it the tap can't be created.
@MainActor
final class DockPushGuard {
    /// Read by the tap callback, which runs on the main run loop.
    private final class State: @unchecked Sendable {
        enum Edge { case bottom, left, right }
        var edge = Edge.bottom
        /// Display bounds in global top-left-origin coordinates, the same space as `CGEvent.location`.
        var displays: [CGRect] = []
        var tap: CFMachPort?

        func blocks(_ event: CGEvent) -> Bool {
            let p = event.location
            guard let d = displays.first(where: { $0.insetBy(dx: -1, dy: -1).contains(p) }) else { return false }
            switch edge {
            case .bottom: return p.y >= d.maxY - 1 && event.getIntegerValueField(.mouseEventDeltaY) > 0
            case .left: return p.x <= d.minX && event.getIntegerValueField(.mouseEventDeltaX) < 0
            case .right: return p.x >= d.maxX - 1 && event.getIntegerValueField(.mouseEventDeltaX) > 0
            }
        }
    }

    private let state = State()
    private var source: CFRunLoopSource?

    /// Starts the tap if it isn't running; returns whether it is running afterwards.
    @discardableResult
    func start() -> Bool {
        refresh()
        guard state.tap == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let state = Unmanaged<State>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = state.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if state.blocks(event) {
                event.setIntegerValueField(state.edge == .bottom ? .mouseEventDeltaY : .mouseEventDeltaX, value: 0)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(state).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        state.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap = state.tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        state.tap = nil
        source = nil
    }

    /// Re-reads the displays and which edge the Dock sits on; call when either may have changed.
    func refresh() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        state.displays = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        state.edge = switch orientation {
        case "left": .left
        case "right": .right
        default: .bottom
        }
    }
}
