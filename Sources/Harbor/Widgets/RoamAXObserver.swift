import AppKit
import ApplicationServices

/// Accessibility notifications from one app, delivered on the main run loop. Registered on the
/// application element, so notifications from all of the app's windows and elements arrive.
@MainActor
final class RoamAXObserver {
    typealias Handler = @MainActor (AXUIElement, String) -> Void

    let pid: pid_t
    private var observer: AXObserver?
    private let handler: Handler

    init?(pid: pid_t, notifications: [String], handler: @escaping Handler) {
        self.pid = pid
        self.handler = handler
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, name, refcon in
            guard let refcon else { return }
            let target = Unmanaged<RoamAXObserver>.fromOpaque(refcon).takeUnretainedValue()
            // The run loop source sits on the main run loop, so the callback is already on the main thread.
            MainActor.assumeIsolated { target.handler(element, name as String) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return nil }
        observer = created
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var added = 0
        for name in notifications where AXObserverAddNotification(created, app, name as CFString, refcon) == .success {
            added += 1
        }
        guard added > 0 else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
    }

    isolated deinit { invalidate() }

    func invalidate() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }
}

/// Small typed reads of accessibility attributes, safe to call from any thread.
enum AXRead {
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// The element's frame in accessibility coordinates (top-left origin, y down).
    static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let point = point(position), let extent = self.size(size) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    static func point(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    static func rect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    /// Converts an accessibility rect to AppKit coordinates, which measure y up from the primary screen's bottom.
    static func appKit(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
