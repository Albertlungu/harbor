import AppKit
import HarborCore

/// Rounds the screen's corners by masking them in black, like the displays on newer MacBooks.
///
/// Each corner is its own tiny window instead of one screen-sized overlay, so the window server only
/// composites a few hundred pixels per corner rather than a transparent layer over the whole display.
@MainActor
final class ScreenCorners {
    static let shared = ScreenCorners()

    private var model: AppModel?
    private var panels: [NSPanel] = []
    private var applied: Applied?
    private var screenObserver: NSObjectProtocol?

    private struct Applied: Equatable {
        var radius: Double
        var top: Bool
        var screens: [CGRect]
    }

    func start(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        observe()
        update()
    }

    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.store.settings.roundScreenCorners
            _ = model.store.settings.roundTopCorners
            _ = model.store.settings.screenCornerRadius
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        guard let settings = model?.store.settings, settings.roundScreenCorners else {
            removeAll()
            return
        }
        let wanted = Applied(radius: settings.screenCornerRadius.rounded(), top: settings.roundTopCorners,
                             screens: NSScreen.screens.map(\.frame))
        guard wanted != applied else { return }
        removeAll()
        applied = wanted
        for screen in wanted.screens {
            var corners: [Corner] = [.bottomLeft, .bottomRight]
            if wanted.top { corners += [.topLeft, .topRight] }
            for corner in corners { panels.append(makePanel(corner, radius: wanted.radius, screen: screen)) }
        }
    }

    private func removeAll() {
        for panel in panels { panel.orderOut(nil) }
        panels = []
        applied = nil
    }

    private enum Corner { case bottomLeft, bottomRight, topLeft, topRight }

    private func makePanel(_ corner: Corner, radius: Double, screen: CGRect) -> NSPanel {
        let side = CGFloat(radius)
        let origin: CGPoint
        switch corner {
        case .bottomLeft: origin = CGPoint(x: screen.minX, y: screen.minY)
        case .bottomRight: origin = CGPoint(x: screen.maxX - side, y: screen.minY)
        case .topLeft: origin = CGPoint(x: screen.minX, y: screen.maxY - side)
        case .topRight: origin = CGPoint(x: screen.maxX - side, y: screen.maxY - side)
        }
        let panel = NSPanel(contentRect: CGRect(origin: origin, size: CGSize(width: side, height: side)),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        // Above menus, docks and fullscreen apps so nothing pokes past the curve; the cursor still draws on top.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .readOnly

        let view = NSView(frame: CGRect(origin: .zero, size: panel.frame.size))
        view.wantsLayer = true
        let mask = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(view.bounds)
        // The circle is centred on the corner's inner point, so the even-odd fill leaves only the outer wedge black.
        let center: CGPoint
        switch corner {
        case .bottomLeft: center = CGPoint(x: side, y: side)
        case .bottomRight: center = CGPoint(x: 0, y: side)
        case .topLeft: center = CGPoint(x: side, y: 0)
        case .topRight: center = CGPoint(x: 0, y: 0)
        }
        path.addEllipse(in: CGRect(x: center.x - side, y: center.y - side, width: side * 2, height: side * 2))
        mask.path = path
        mask.fillRule = .evenOdd
        mask.fillColor = NSColor.black.cgColor
        view.layer?.addSublayer(mask)
        panel.contentView = view
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        return panel
    }
}
