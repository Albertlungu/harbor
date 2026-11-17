import AppKit
import SwiftUI
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
    /// While the radius slider is dragged the top corners are masked too, so the curve can be lined up by eye
    /// against the display's own rounded top corners.
    var previewTop = false {
        didSet { if previewTop != oldValue { update() } }
    }

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
        let wanted = Applied(radius: settings.screenCornerRadius.rounded(), top: settings.roundTopCorners || previewTop,
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

/// The corner radius slider, with a marked detent at the radius that matches the display's top corners.
/// macOS doesn't report that radius, so the detent starts at an estimate and can be moved to wherever the
/// previewed top masks line up.
struct CornerRadiusSlider: View {
    @Environment(AppModel.self) private var model
    private let range: ClosedRange<Double> = 6...32
    /// How close a drag has to come to the detent before it snaps there.
    private let snapDistance = 1.2

    var body: some View {
        let settings = model.store.settings
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: Binding(get: { settings.screenCornerRadius }, set: { set($0) }), in: range) {
                Text("Radius")
            } onEditingChanged: { editing in
                ScreenCorners.shared.previewTop = editing
            }
            .overlay(alignment: .bottomLeading) { detentMark(at: settings.screenCornerMatch) }
            HStack {
                Text(abs(settings.screenCornerRadius - settings.screenCornerMatch) < 0.5
                     ? "Matches the top corners" : "Drag to the mark to match the top corners")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                Spacer()
                Button("Use as the Top-Corner Match") {
                    model.store.updateSettings { $0.screenCornerMatch = $0.screenCornerRadius.rounded() }
                }
                .controlSize(.small)
            }
        }
    }

    private func set(_ value: Double) {
        let match = model.store.settings.screenCornerMatch
        var next = value
        if abs(value - match) < snapDistance {
            next = match
            if model.store.settings.screenCornerRadius != match {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        model.store.updateSettings { $0.screenCornerRadius = next }
    }

    /// A small tick under the track. The track spans the slider minus the knob's width, so the tick is placed
    /// along that inset span to sit under the knob when it rests on the detent.
    private func detentMark(at value: Double) -> some View {
        GeometryReader { proxy in
            let knob = 20.0
            let labelWidth = 0.0
            let track = proxy.size.width - labelWidth - knob
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            Capsule()
                .fill(Tokens.accent)
                .frame(width: 2, height: 6)
                .offset(x: labelWidth + knob / 2 + track * fraction - 1, y: proxy.size.height - 2)
        }
        .allowsHitTesting(false)
    }
}
