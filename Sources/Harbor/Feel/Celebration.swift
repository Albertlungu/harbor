import AppKit
import HarborCore
import SwiftUI

/// Confetti for small milestones. It lives in its own click-through panel so it never
/// steals focus or blocks the thing underneath, and the panel is gone once the burst ends.
@MainActor
final class Celebration {
    static let shared = Celebration()
    weak var model: AppModel?

    private static let size = CGSize(width: 560, height: 640)
    /// Where the burst starts, measured up from the panel's bottom edge.
    private static let originLift: CGFloat = 240

    /// Bursts over a dock, or at the pointer when the dock is unknown.
    func play(dock id: UUID?) {
        guard enabled else { return }
        if let id, let bar = model?.dockController.controllers(for: id).first?.barFrame, !bar.isEmpty {
            show(origin: CGPoint(x: bar.midX, y: bar.midY), glow: bar)
        } else {
            let p = NSEvent.mouseLocation
            show(origin: p, glow: CGRect(x: p.x - 60, y: p.y - 30, width: 120, height: 60))
        }
    }

    /// Bursts up from the bottom of a window.
    func play(window: NSWindow?) {
        guard enabled, let frame = window?.frame else { return }
        show(origin: CGPoint(x: frame.midX, y: frame.minY + 60), glow: frame)
    }

    private var enabled: Bool { model?.store.settings.celebrations == true }

    private func show(origin: CGPoint, glow: CGRect) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let frame = reduceMotion
            ? glow.insetBy(dx: -24, dy: -24)
            : CGRect(x: origin.x - Self.size.width / 2, y: origin.y - Self.originLift, width: Self.size.width, height: Self.size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let colors = Self.colors()
        panel.contentView = NSHostingView(rootView: reduceMotion
            ? AnyView(GlowView(color: colors[0], corner: 14))
            : AnyView(ConfettiView(colors: colors, origin: CGPoint(x: Self.size.width / 2, y: Self.size.height - Self.originLift))))
        panel.orderFrontRegardless()
        let life = reduceMotion ? GlowView.duration : Confetti.lifetime
        Task { @MainActor [panel] in
            try? await Task.sleep(for: .seconds(life + 0.15))
            panel.orderOut(nil)
            panel.close()
        }
    }

    private static func colors() -> [Color] {
        let look = Appearance.shared
        return [look.accent] + [WidgetCategory.apps, .folders, .clocks, .tasks, .system].map {
            Appearance.color(look.palette.spec.hue(for: $0))
        }
    }
}

private struct ConfettiView: View {
    let colors: [Color]
    let origin: CGPoint
    @State private var start = Date()
    private let particles = Confetti.burst(count: 32, seed: UInt64.random(in: 1...UInt64.max))

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { gc, _ in
                let t = context.date.timeIntervalSince(start)
                for p in particles {
                    let pose = Confetti.pose(of: p, at: t)
                    guard pose.opacity > 0 else { continue }
                    var piece = gc
                    piece.opacity = pose.opacity
                    piece.translateBy(x: origin.x + pose.x, y: origin.y + pose.y)
                    piece.rotate(by: .radians(pose.angle))
                    let w = p.size, h = p.shape == .circle ? p.size : p.size * 0.55
                    let box = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                    let path = p.shape == .circle ? Path(ellipseIn: box) : Path(roundedRect: box, cornerRadius: 1.5)
                    piece.fill(path, with: .color(colors[p.colorIndex % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The Reduce Motion stand-in: a soft glow that rises and fades without moving.
private struct GlowView: View {
    static let duration = 0.7
    let color: Color
    let corner: CGFloat
    @State private var shown = false

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(color.opacity(0.35))
            .blur(radius: 10)
            .opacity(shown ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: Self.duration)) { shown = true } }
    }
}
