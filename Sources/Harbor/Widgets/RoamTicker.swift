import AppKit
import QuartzCore

/// Calls back once per refresh of the display the view is on (60 or 120 Hz), only while running,
/// so a still pet costs no frames at all.
@MainActor
final class RoamTicker: NSObject {
    private var link: CADisplayLink?
    private let tick: @MainActor () -> Void

    init(view: NSView, tick: @escaping @MainActor () -> Void) {
        self.tick = tick
        super.init()
        let link = view.displayLink(target: self, selector: #selector(fire))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    var running: Bool {
        get { !(link?.isPaused ?? true) }
        set { if link?.isPaused == newValue { link?.isPaused = !newValue } }
    }

    /// The link holds its target strongly, so it has to be broken before the pet goes away.
    func invalidate() {
        link?.invalidate()
        link = nil
    }

    @objc private func fire(_ link: CADisplayLink) { tick() }
}
