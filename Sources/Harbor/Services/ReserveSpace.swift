import AppKit
import ApplicationServices
import HarborCore

private let reserveCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let name = notification as String
    nonisolated(unsafe) let window = element
    nonisolated(unsafe) let target = refcon
    MainActor.assumeIsolated {
        Unmanaged<ReserveSpace>.fromOpaque(target).takeUnretainedValue().handle(element: window, notification: name)
    }
}

/// Keeps other apps' windows out of the strip a pinned dock reserves, driven by Accessibility notifications.
/// Observers exist only while some dock reserves space and Accessibility is granted.
@MainActor
final class ReserveSpace {
    private var strips: [ReservedStrip] = []
    private var reserveOnDrag = false
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pending: [CFHashCode: AXUIElement] = [:]
    private var flushTask: Task<Void, Never>?
    private var lastDragSeen = Date.distantPast
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private var active: Bool { !strips.isEmpty && WindowControl.isTrusted }

    func update(strips newStrips: [ReservedStrip], reserveOnDrag: Bool) {
        let wasActive = !observers.isEmpty || !workspaceObservers.isEmpty
        let changed = newStrips != strips
        strips = newStrips
        self.reserveOnDrag = reserveOnDrag
        switch (wasActive, active) {
        case (false, true): start()
        case (true, false): stop()
        case (true, true) where changed: scanAll()
        default: break
        }
    }

    // MARK: Observers

    private func start() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.attach(pid: pid) } }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.detach(pid: pid) } }
        })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            attach(pid: app.processIdentifier)
        }
        scanAll()
    }

    private func stop() {
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceObservers = []
        for pid in Array(observers.keys) { detach(pid: pid) }
        flushTask?.cancel()
        flushTask = nil
        pending = [:]
    }

    private func attach(pid: pid_t) {
        guard pid != ownPID, observers[pid] == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, reserveCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        guard AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
        for window in WindowControl.windows(of: pid) { watch(window.element, with: observer) }
    }

    private func detach(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func watch(_ window: AXUIElement, with observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
    }

    // MARK: Events

    fileprivate func handle(element: AXUIElement, notification: String) {
        guard active else { return }
        if notification == kAXWindowCreatedNotification as String {
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, let observer = observers[pid] { watch(element, with: observer) }
        } else {
            // A move or resize while the button is down is the user dragging; without one it is a zoom or an app's own doing.
            let now = Date()
            if NSEvent.pressedMouseButtons & 1 != 0 { lastDragSeen = now }
            if now.timeIntervalSince(lastDragSeen) < 0.3 && !reserveOnDrag { return }
        }
        enqueue(element)
    }

    private func scanAll() {
        for pid in observers.keys {
            for window in WindowControl.windows(of: pid) { enqueue(window.element) }
        }
    }

    private func enqueue(_ element: AXUIElement) {
        pending[CFHash(element)] = element
        guard flushTask == nil else { return }
        // Debounced so a drag or an animated zoom costs one adjustment, not hundreds.
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        guard active else { pending = [:]; return }
        if Self.menuIsOpen() {
            // Moving a window under an open menu is jarring; try again shortly.
            flushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.flush()
            }
            return
        }
        let elements = pending.values
        pending = [:]
        for element in elements { adjust(element) }
    }

    private static func menuIsOpen() -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let popUp = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return info.contains { ($0[kCGWindowLayer as String] as? Int) == popUp }
    }

    // MARK: Adjusting

    private func adjust(_ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ownPID,
              WindowControl.string(element, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String),
              WindowControl.bool(element, kAXMinimizedAttribute) != true,
              WindowControl.bool(element, "AXFullScreen") != true,
              let quartz = WindowControl.frame(of: element),
              let primaryHeight = NSScreen.screens.first?.frame.maxY else { return }
        let original = CGRect(x: quartz.minX, y: primaryHeight - quartz.maxY, width: quartz.width, height: quartz.height)
        let center = CGPoint(x: original.midX, y: original.midY)
        var fitted = original
        for strip in strips where strip.screenFrame.contains(center) {
            fitted = DockLayoutEngine.fit(window: fitted, avoiding: strip)
        }
        guard fitted != original else { return }
        var size = fitted.size
        var origin = CGPoint(x: fitted.minX, y: primaryHeight - fitted.maxY)
        // Size first: a resize can shift the origin in some apps, so the position is set last.
        if fitted.size != original.size, let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }
}
