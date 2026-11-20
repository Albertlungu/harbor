import AppKit

/// Keeps the hidden macOS Dock from being pushed into view. On macOS 26 and later the Dock
/// ignores its auto-hide delay when the pointer keeps moving into its edge after reaching it;
/// what it reads is the movement delta of events whose pointer is pinned to that edge. An event
/// tap zeroes just that delta: the pointer's position and Harbor's own edge reveal, which go
/// by position, are untouched. Needs Accessibility; without it the tap can't be created.
@MainActor
final class DockPushGuard {
    /// Shared with the tap callback, which runs on its own thread so pointer events never wait on
    /// the main thread: an active tap holds every mouse move in the session until it returns.
    private final class State: @unchecked Sendable {
        enum Edge { case bottom, left, right }
        private let lock = NSLock()
        private var edge = Edge.bottom
        /// Display bounds in global top-left-origin coordinates, the same space as `CGEvent.location`.
        private var displays: [CGRect] = []
        private var tap: CFMachPort?

        func update(edge: Edge, displays: [CGRect]) {
            lock.withLock {
                self.edge = edge
                self.displays = displays
            }
        }

        func setTap(_ tap: CFMachPort?) { lock.withLock { self.tap = tap } }
        var currentTap: CFMachPort? { lock.withLock { tap } }

        /// Zeroes the delta that would push the Dock out, if the event is pinned to its edge.
        func filter(_ event: CGEvent) {
            let (edge, displays) = lock.withLock { (self.edge, self.displays) }
            let p = event.location
            guard let d = displays.first(where: { $0.insetBy(dx: -1, dy: -1).contains(p) }) else { return }
            let blocks = switch edge {
            case .bottom: p.y >= d.maxY - 1 && event.getIntegerValueField(.mouseEventDeltaY) > 0
            case .left: p.x <= d.minX && event.getIntegerValueField(.mouseEventDeltaX) < 0
            case .right: p.x >= d.maxX - 1 && event.getIntegerValueField(.mouseEventDeltaX) > 0
            }
            if blocks { event.setIntegerValueField(edge == .bottom ? .mouseEventDeltaY : .mouseEventDeltaX, value: 0) }
        }
    }

    /// Carries the tap's source to its thread and that thread's run loop back to `start`.
    private final class LoopBox: @unchecked Sendable {
        let source: CFRunLoopSource
        var loop: CFRunLoop?
        init(source: CFRunLoopSource) { self.source = source }
    }

    private let state = State()
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?

    /// Starts the tap if it isn't running; returns whether it is running afterwards.
    @discardableResult
    func start() -> Bool {
        refresh()
        guard state.currentTap == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let state = Unmanaged<State>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = state.currentTap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                state.filter(event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(state).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        state.setTap(tap)
        let box = LoopBox(source: source)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(box.loop, box.source, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Harbor Dock push guard"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        CGEvent.tapEnable(tap: tap, enable: true)
        self.source = source
        loop = box.loop
        return true
    }

    func stop() {
        guard let tap = state.currentTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source, let loop {
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFRunLoopStop(loop)
        }
        CFMachPortInvalidate(tap)
        state.setTap(nil)
        source = nil
        loop = nil
    }

    /// Re-reads the displays and which edge the Dock sits on; call when either may have changed.
    func refresh() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        let edge: State.Edge = switch orientation {
        case "left": .left
        case "right": .right
        default: .bottom
        }
        state.update(edge: edge, displays: ids.prefix(Int(count)).map { CGDisplayBounds($0) })
    }
}
