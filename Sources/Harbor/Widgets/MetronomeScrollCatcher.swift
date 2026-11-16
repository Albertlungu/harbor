import AppKit
import HarborCore
import SwiftUI

/// Reports scroll-wheel input over its own frame as whole tempo steps.
///
/// A local event monitor is used instead of an overlay view that overrides `scrollWheel(with:)`:
/// AppKit routes scroll events by hit testing, so an overlay would have to be hit-testable and would
/// then swallow the clicks that toggle and tap the metronome. The monitor sees every scroll event
/// in the app, so it never touches hit testing, and it only acts when the pointer is inside this view.
struct MetronomeScrollCatcher: NSViewRepresentable {
    /// Called with signed steps (positive raises the tempo) and whether Shift was held.
    let onSteps: @MainActor (Int, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onSteps = onSteps
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onSteps = onSteps }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.removeMonitor() }

    final class CatcherView: NSView {
        var onSteps: @MainActor (Int, Bool) -> Void = { _, _ in }
        private var monitor: Any?
        private var accumulator = MetronomeInput.ScrollAccumulator()

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // NSEvent is not Sendable, so only a Bool crosses the isolation boundary.
                nonisolated(unsafe) let captured = event
                let consumed = MainActor.assumeIsolated { self?.handle(captured) ?? false }
                return consumed ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard let window, event.window === window,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            let steps = accumulator.add(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
            if steps != 0 { onSteps(steps, event.modifierFlags.contains(.shift)) }
            // Consumed, so the dock beneath does not also react to the scroll.
            return true
        }
    }
}
