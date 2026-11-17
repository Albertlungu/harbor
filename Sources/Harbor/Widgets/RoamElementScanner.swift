import AppKit
import ApplicationServices
import HarborCore

/// Finds the prominent elements of the frontmost window through the Accessibility API, so the pet
/// can stand on panes, text areas and menus as well as window tops. Blocking; run it off the main thread.
enum RoamElementScanner {
    static let maxDepth = 12
    static let maxElements = 400
    static let timeBudget: TimeInterval = 0.04
    /// Seconds a slow app may take to answer one query before the scan gives up on it.
    static let messagingTimeout: Float = 0.05

    /// Roles worth descending into; everything else (tables, text, controls) only has rows, cells or nothing below.
    private static let containers: Set<String> = [
        "AXWindow", "AXGroup", "AXSplitGroup", "AXScrollArea", "AXTabGroup", "AXWebArea", "AXSheet",
        "AXPopover", "AXLayoutArea", "AXDrawer",
    ]
    private static let attributes: [String] = [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute,
                                                kAXSizeAttribute, kAXChildrenAttribute]

    /// Ledge frames in AppKit coordinates for the frontmost app's focused window and any open context menu.
    /// Empty without Accessibility permission or when Harbor itself is in front.
    static func scan(ownPID: pid_t, primaryHeight: CGFloat) -> [CGRect] {
        RoamElements.ledges(candidates(ownPID: ownPID, primaryHeight: primaryHeight))
    }

    static func candidates(ownPID: pid_t, primaryHeight: CGFloat) -> [RoamElementCandidate] {
        guard AXIsProcessTrusted(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ownPID else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var result: [RoamElementCandidate] = []
        let deadline = Date().addingTimeInterval(timeBudget)
        if let window = AXRead.element(app, kAXFocusedWindowAttribute) {
            result += walk(window, primaryHeight: primaryHeight, deadline: deadline)
        }
        // Context menus hang off the application element while they are open.
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
           let elements = children as? [AXUIElement] {
            for element in elements where AXRead.string(element, kAXRoleAttribute) == "AXMenu" {
                guard let frame = AXRead.frame(element) else { continue }
                let menu = AXRead.appKit(frame, primaryHeight: primaryHeight)
                result.append(RoamElementCandidate(role: "AXMenu", frame: menu, windowFrame: menu, depth: 0))
            }
        }
        return result
    }

    /// Breadth-first walk of one window, so large panes near the root are seen before any budget runs out.
    private static func walk(_ window: AXUIElement, primaryHeight: CGFloat, deadline: Date) -> [RoamElementCandidate] {
        guard let windowAX = AXRead.frame(window) else { return [] }
        let windowFrame = AXRead.appKit(windowAX, primaryHeight: primaryHeight)
        let minSpan = max(RoamElements.minWidth, RoamElements.minWidthFraction * windowFrame.width)
        // Each entry carries the visible region of its nearest scrolling ancestor, so off-screen content is skipped.
        var queue: [(element: AXUIElement, depth: Int, clip: CGRect)] = [(window, 0, windowAX)]
        var head = 0
        var result: [RoamElementCandidate] = []
        while head < queue.count, head < maxElements, Date() < deadline {
            let (element, depth, clip) = queue[head]
            head += 1
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &raw) == .success,
                  let values = raw as [AnyObject]?, values.count == 5,
                  let role = values[0] as? String,
                  let origin = AXRead.point(values[2]), let size = AXRead.size(values[3]) else { continue }
            let frame = CGRect(origin: origin, size: size)
            let visible = frame.intersection(clip)
            guard !visible.isNull, visible.width >= minSpan, visible.height >= RoamElements.minHeight else { continue }
            // A top scrolled out of view is not a real edge, though the element's children may still be useful.
            if depth > 0, frame.minY >= clip.minY - 1 {
                let shown = CGRect(x: visible.minX, y: frame.minY, width: visible.width, height: visible.height)
                result.append(RoamElementCandidate(role: role, subrole: values[1] as? String,
                                                   frame: AXRead.appKit(shown, primaryHeight: primaryHeight),
                                                   windowFrame: windowFrame, depth: depth))
            }
            guard depth < maxDepth, containers.contains(role), let children = values[4] as? [AXUIElement] else { continue }
            let childClip = role == "AXScrollArea" ? visible : clip
            for child in children { queue.append((child, depth + 1, childClip)) }
        }
        return result
    }
}

/// Rescans the frontmost window when it changes: app switches, focus moves, window moves and
/// resizes, and menus opening or closing. Scans run on a serial queue, at most twice a second.
@MainActor
final class RoamElementWatcher {
    static let minInterval: TimeInterval = 0.5
    /// Lets a burst of notifications, like a window drag, settle into one scan.
    static let debounce: TimeInterval = 0.15

    /// Ledge frames in AppKit coordinates, delivered on the main thread after each scan.
    var onUpdate: (([CGRect]) -> Void)?

    private let ownPID: pid_t
    private let queue = DispatchQueue(label: "harbor.roam.elements", qos: .utility)
    private var observer: RoamAXObserver?
    private var activation: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private var lastScan = Date.distantPast
    private var scanning = false
    private var dirty = false

    init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    func start() {
        guard activation == nil, WindowControl.isTrusted else { return }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeFrontmost()
                self?.requestScan()
            }
        }
        observeFrontmost()
        requestScan()
    }

    func stop() {
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        observer?.invalidate()
        observer = nil
        pending?.cancel()
        pending = nil
        dirty = false
    }

    /// Schedules a scan, coalescing with one already waiting.
    func requestScan() {
        guard activation != nil else { return }
        if scanning { dirty = true; return }
        guard pending == nil else { return }
        let wait = max(Self.debounce, Self.minInterval - Date().timeIntervalSince(lastScan))
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.runScan()
        }
    }

    private func observeFrontmost() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard observer?.pid != pid else { return }
        observer?.invalidate()
        observer = nil
        guard let pid, pid != ownPID else { return }
        let names = [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification,
                     kAXWindowMovedNotification, kAXWindowResizedNotification,
                     kAXMenuOpenedNotification, kAXMenuClosedNotification] as [String]
        observer = RoamAXObserver(pid: pid, notifications: names) { [weak self] _, _ in self?.requestScan() }
    }

    private func runScan() {
        pending = nil
        scanning = true
        let ownPID = ownPID
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        queue.async { [weak self] in
            let rects = RoamElementScanner.scan(ownPID: ownPID, primaryHeight: primaryHeight)
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                self.lastScan = Date()
                guard self.activation != nil else { return }
                self.onUpdate?(rects)
                if self.dirty {
                    self.dirty = false
                    self.requestScan()
                }
            }
        }
    }
}
