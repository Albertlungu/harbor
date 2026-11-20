import AppKit

/// Follows file drags anywhere on screen. AppKit only tells the view under the pointer about a drag,
/// so widgets that react to one coming near watch the drag pasteboard instead: it changes when a drag
/// starts, and the pointer is polled while the button stays down. Runs only while something observes it.
@MainActor
final class FileDragTracker {
    static let shared = FileDragTracker()

    enum Event {
        /// A file drag is under way with the pointer here.
        case dragged(CGPoint)
        /// The file drag ended here, dropped or cancelled.
        case ended(CGPoint)
        /// The pointer moved with no drag.
        case moved(CGPoint)
        /// The mouse button went down here.
        case pressed(CGPoint)
    }

    private var handlers: [UUID: @MainActor (Event) -> Void] = [:]
    private var monitors: [Any] = []
    private var poll: Timer?
    private var baseline = 0
    private var dragging = false

    func observe(_ id: UUID, _ handler: @escaping @MainActor (Event) -> Void) {
        handlers[id] = handler
        guard monitors.isEmpty else { return }
        let down: (NSEvent) -> Void = { _ in MainActor.assumeIsolated { self.buttonDown() } }
        let moved: (NSEvent) -> Void = { _ in
            MainActor.assumeIsolated { if !self.dragging { self.send(.moved(NSEvent.mouseLocation)) } }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: down) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { down($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { moved($0); return $0 }) { monitors.append(m) }
    }

    func stop(_ id: UUID) {
        handlers[id] = nil
        guard handlers.isEmpty else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        poll?.invalidate()
        poll = nil
        dragging = false
    }

    private func buttonDown() {
        baseline = NSPasteboard(name: .drag).changeCount
        send(.pressed(NSEvent.mouseLocation))
        poll?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in MainActor.assumeIsolated { self.tick() } }
        // Common modes keep it running while a drag from Harbor's own views tracks the mouse.
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func tick() {
        let point = NSEvent.mouseLocation
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            poll?.invalidate()
            poll = nil
            if dragging {
                dragging = false
                send(.ended(point))
            }
            return
        }
        if !dragging {
            let board = NSPasteboard(name: .drag)
            guard board.changeCount != baseline else { return }
            baseline = board.changeCount
            guard board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
            dragging = true
        }
        send(.dragged(point))
    }

    private func send(_ event: Event) {
        for handler in handlers.values { handler(event) }
    }
}
