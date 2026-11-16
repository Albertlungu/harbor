import AppKit
import HarborCore

/// Removes an item dragged off its dock in Edit Mode and dropped on empty desktop.
///
/// SwiftUI reports no end of drag for `onDrag`, and a drop on bare desktop reaches no drop handler,
/// so the tracker watches the mouse button instead. It runs only while a drag is in flight.
@MainActor
final class DragOutTracker {
    static let shared = DragOutTracker()

    private var timer: Timer?

    func begin(item: DockItem, dockID: UUID, model: AppModel) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self?.finish(item: item, dockID: dockID, model: model)
            }
        }
    }

    private func finish(item: DockItem, dockID: UUID, model: AppModel) {
        timer?.invalidate()
        timer = nil
        let point = NSEvent.mouseLocation
        let overDock = model.dockController.windows.values.contains {
            $0.barFrame.insetBy(dx: -8, dy: -8).contains(point)
        }
        guard !overDock, Self.isEmptyDesktop(at: point),
              model.store.dock(dockID)?.items.contains(where: { $0.id == item.id }) == true else { return }
        if item.kind == .widget {
            model.confirmRemoveWidget(item, from: dockID)
        } else {
            model.store.removeItem(item.id, from: dockID)
        }
    }

    /// True when no app window (layer 0) is under the point; the desktop itself sits below layer 0.
    private static func isEmptyDesktop(at point: CGPoint) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.maxY else { return false }
        let quartz = CGPoint(x: point.x, y: primaryHeight - point.y)
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            if bounds.contains(quartz) { return false }
        }
        return true
    }
}
