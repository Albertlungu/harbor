import AppKit
import ApplicationServices
import HarborCore

/// Publishes what the roaming pet finds interesting on screen: the caret while the user types, a
/// window coming to the front, an open menu, a notification banner, or the pointer coming to rest.
/// Event driven; nothing polls. Only positions and timing are read, never text or which keys were pressed.
@MainActor
final class RoamAttention {
    typealias Reason = RoamAttentionReason

    /// The point of interest in AppKit coordinates, or nil with `.bored` when the pet loses interest.
    var onChange: ((CGPoint?, Reason) -> Void)?

    /// Caret lookups while typing happen at most this often.
    static let caretInterval: TimeInterval = 0.5
    static let dwellTime: TimeInterval = 1.2
    static let dwellRadius = 8.0
    static let bannerInterval: TimeInterval = 1
    private static let notificationCenterID = "com.apple.notificationcenterui"

    private let ownPID: pid_t
    private let queue = DispatchQueue(label: "harbor.roam.attention", qos: .utility)
    private let epoch = Date()
    private var state = RoamAttentionState()
    private var running = false
    private var activation: NSObjectProtocol?
    private var frontObserver: RoamAXObserver?
    private var bannerObserver: RoamAXObserver?
    private var monitors: [Any] = []
    private var boredomTask: Task<Void, Never>?
    private var caretTask: Task<Void, Never>?
    private var lastCaret = Date.distantPast
    private var lastBanner = Date.distantPast
    private var dwellAnchor = CGPoint(x: -1e6, y: -1e6)
    private var dwellMovedAt = Date.distantPast
    private var dwellReported = true
    private var dwellTask: Task<Void, Never>?

    init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    func start() {
        guard !running else { return }
        running = true
        if let mouse = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { monitors.append(mouse) }
        // Everything below reads other apps, which needs Accessibility permission.
        guard WindowControl.isTrusted else { return }
        // The event is dropped unread: only the moment of a key press matters, never the key.
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.keyPressed() }
        }) { monitors.append(keys) }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontmostChanged() }
        }
        observeFrontmost()
        observeBanners()
    }

    func stop() {
        guard running else { return }
        running = false
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        frontObserver?.invalidate()
        frontObserver = nil
        bannerObserver?.invalidate()
        bannerObserver = nil
        for task in [boredomTask, caretTask, dwellTask] { task?.cancel() }
        boredomTask = nil
        caretTask = nil
        dwellTask = nil
        state = RoamAttentionState()
    }

    // MARK: Sources

    private func frontmostChanged() {
        observeFrontmost()
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != ownPID else { return }
        lookUp(.window) { primaryHeight in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            return AXRead.element(app, kAXFocusedWindowAttribute).flatMap { titleArea(of: $0, primaryHeight) }
        }
    }

    private func observeFrontmost() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard frontObserver?.pid != pid else { return }
        frontObserver?.invalidate()
        frontObserver = nil
        guard let pid, pid != ownPID else { return }
        let names = [kAXFocusedWindowChangedNotification, kAXMenuOpenedNotification] as [String]
        frontObserver = RoamAXObserver(pid: pid, notifications: names) { [weak self] element, name in
            let ref = ElementRef(element: element)
            if name == kAXMenuOpenedNotification {
                self?.lookUp(.menu) { primaryHeight in topCenter(of: ref.element, primaryHeight) }
            } else {
                self?.lookUp(.window) { primaryHeight in titleArea(of: ref.element, primaryHeight) }
            }
        }
    }

    private func observeBanners() {
        guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: Self.notificationCenterID)
            .first else { return }
        let names = [kAXWindowCreatedNotification, kAXCreatedNotification] as [String]
        bannerObserver = RoamAXObserver(pid: center.processIdentifier, notifications: names) { [weak self] element, _ in
            guard let self, Date().timeIntervalSince(self.lastBanner) >= Self.bannerInterval else { return }
            self.lastBanner = Date()
            let ref = ElementRef(element: element)
            let screen = NSScreen.screens.first?.frame ?? .zero
            // Banners slide in at the top right; that is where to look if the element has no usable frame.
            let fallback = CGPoint(x: screen.maxX - 180, y: screen.maxY - 60)
            self.lookUp(.banner) { primaryHeight in
                guard let frame = AXRead.frame(ref.element), frame.width >= 100 else { return fallback }
                let rect = AXRead.appKit(frame, primaryHeight: primaryHeight)
                return CGPoint(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func keyPressed() {
        guard caretTask == nil else { return }
        let wait = max(0.15, Self.caretInterval - Date().timeIntervalSince(lastCaret))
        let ownPID = ownPID
        caretTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            self.caretTask = nil
            self.lastCaret = Date()
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
            self.queue.async { [weak self] in
                guard let found = caretSignal(ownPID: ownPID, primaryHeight: primaryHeight) else { return }
                Task { @MainActor in self?.offer(found) }
            }
        }
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        guard hypot(point.x - dwellAnchor.x, point.y - dwellAnchor.y) > Self.dwellRadius else { return }
        dwellAnchor = point
        dwellMovedAt = Date()
        dwellReported = false
        scheduleDwellCheck()
    }

    /// One pending check at a time; a check that finds the pointer moved since simply waits again.
    private func scheduleDwellCheck() {
        guard dwellTask == nil else { return }
        let wait = max(0.05, Self.dwellTime - Date().timeIntervalSince(dwellMovedAt))
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            self.dwellTask = nil
            guard !self.dwellReported else { return }
            if Date().timeIntervalSince(self.dwellMovedAt) >= Self.dwellTime {
                self.dwellReported = true
                self.offer(RoamAttentionSignal(reason: .dwell, point: self.dwellAnchor))
            } else {
                self.scheduleDwellCheck()
            }
        }
    }

    // MARK: Deciding

    /// Runs a blocking accessibility lookup on the query queue and offers its point, if any, back on the main thread.
    private func lookUp(_ reason: Reason, _ work: @escaping @Sendable (CGFloat) -> CGPoint?) {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        queue.async { [weak self] in
            guard let point = work(primaryHeight) else { return }
            Task { @MainActor in self?.offer(RoamAttentionSignal(reason: reason, point: point)) }
        }
    }

    private func offer(_ signal: RoamAttentionSignal) {
        guard running,
              RoamAttentionLogic.offer(signal, at: now, state: &state, roll: { Double.random(in: 0..<1) })
        else { return }
        publish()
        scheduleBoredom()
    }

    private func publish() {
        onChange?(state.focus?.point, state.focus?.reason ?? .bored)
    }

    private func scheduleBoredom() {
        boredomTask?.cancel()
        let wait = max(0, state.boredAt - now)
        boredomTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            if RoamAttentionLogic.tick(at: self.now, state: &self.state) { self.publish() }
        }
    }

    private var now: Double { Date().timeIntervalSince(epoch) }
}

/// Accessibility elements may be used from any thread; this only carries one onto the query queue.
private struct ElementRef: @unchecked Sendable {
    let element: AXUIElement
}

/// Just under a window's top edge, where its title sits.
private func titleArea(of window: AXUIElement, _ primaryHeight: CGFloat) -> CGPoint? {
    guard let frame = AXRead.frame(window) else { return nil }
    let rect = AXRead.appKit(frame, primaryHeight: primaryHeight)
    return CGPoint(x: rect.midX, y: rect.maxY - RoamSurfaces.titleBarHeight / 2)
}

private func topCenter(of element: AXUIElement, _ primaryHeight: CGFloat) -> CGPoint? {
    guard let frame = AXRead.frame(element) else { return nil }
    let rect = AXRead.appKit(frame, primaryHeight: primaryHeight)
    return CGPoint(x: rect.midX, y: rect.maxY)
}

/// Where the user is typing: the caret's top, or the focused element's top when the app does not report a caret.
/// Uses only the selection's position (`AXSelectedTextRange` and `AXBoundsForRange`), never its text.
private func caretSignal(ownPID: pid_t, primaryHeight: CGFloat) -> RoamAttentionSignal? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.05)
    guard let element = AXRead.element(system, kAXFocusedUIElementAttribute) else { return nil }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success, pid != ownPID else { return nil }
    var range: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
       let range {
        var bounds: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                      range, &bounds) == .success,
           let rect = AXRead.rect(bounds), rect.height > 0 {
            let caret = AXRead.appKit(rect, primaryHeight: primaryHeight)
            return RoamAttentionSignal(reason: .caret, point: CGPoint(x: caret.minX, y: caret.maxY))
        }
    }
    guard let frame = AXRead.frame(element) else { return nil }
    let rect = AXRead.appKit(frame, primaryHeight: primaryHeight)
    return RoamAttentionSignal(reason: .typing, point: CGPoint(x: rect.midX, y: rect.maxY))
}
