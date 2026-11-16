import HarborCore
import SwiftUI

/// Plays an open effect once each time `trigger` changes.
struct OpenEffectModifier: ViewModifier {
    let trigger: Int
    let effect: OpenEffect
    let edge: ScreenEdge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One keyframe target. The duration belongs to the stage that ends on this pose.
    struct Pose {
        var duration = 0.1
        var sx = 1.0
        var sy = 1.0
        /// Points toward the dock's inward side.
        var move = 0.0
        var rotation = 0.0
        var glow = 0.0
        var ring = 1.0
        var ringOpacity = 0.0
        var opacity = 1.0
    }

    func body(content: Content) -> some View {
        let poses = Self.poses(for: effect, reduceMotion: reduceMotion)
        let anchor = Self.anchor(for: edge)
        let direction = Self.direction(for: edge)
        let accent = Tokens.accent
        content.keyframeAnimator(initialValue: Pose(), trigger: trigger) { view, pose in
            view
                .background {
                    Circle().fill(accent.opacity(0.6)).blur(radius: 9).scaleEffect(1.25).opacity(pose.glow)
                }
                .overlay {
                    Circle().strokeBorder(accent, lineWidth: 2).scaleEffect(pose.ring).opacity(pose.ringOpacity)
                }
                .scaleEffect(x: pose.sx, y: pose.sy, anchor: anchor)
                .rotationEffect(.degrees(pose.rotation), anchor: anchor)
                .offset(x: direction.width * pose.move, y: direction.height * pose.move)
                .opacity(pose.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.sx) { Self.frames(poses, \.sx) }
            KeyframeTrack(\.sy) { Self.frames(poses, \.sy) }
            KeyframeTrack(\.move) { Self.frames(poses, \.move) }
            KeyframeTrack(\.rotation) { Self.frames(poses, \.rotation) }
            KeyframeTrack(\.glow) { Self.frames(poses, \.glow) }
            KeyframeTrack(\.ring) { Self.frames(poses, \.ring) }
            KeyframeTrack(\.ringOpacity) { Self.frames(poses, \.ringOpacity) }
            KeyframeTrack(\.opacity) { Self.frames(poses, \.opacity) }
        }
    }

    @KeyframeTrackContentBuilder<Double>
    private static func frames(_ poses: [Pose], _ key: KeyPath<Pose, Double>) -> some KeyframeTrackContent<Double> {
        CubicKeyframe(poses[0][keyPath: key], duration: poses[0].duration)
        CubicKeyframe(poses[1][keyPath: key], duration: poses[1].duration)
        CubicKeyframe(poses[2][keyPath: key], duration: poses[2].duration)
        // The last stage springs back to rest so the icon settles with a little life instead of stopping dead.
        SpringKeyframe(poses[3][keyPath: key], duration: poses[3].duration, spring: .init(duration: 0.15, bounce: 0.3))
    }

    /// Squash and stretch pivot on the side facing the screen edge, so icons stay planted on the dock.
    private static func anchor(for edge: ScreenEdge) -> UnitPoint {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    private static func direction(for edge: ScreenEdge) -> CGSize {
        switch edge {
        case .bottom: CGSize(width: 0, height: -1)
        case .top: CGSize(width: 0, height: 1)
        case .left: CGSize(width: 1, height: 0)
        case .right: CGSize(width: -1, height: 0)
        }
    }

    // Four stages per effect, at most about 0.42 s in total.
    private static func poses(for effect: OpenEffect, reduceMotion: Bool) -> [Pose] {
        if reduceMotion {
            return [Pose(duration: 0.08, opacity: 0.55), Pose(duration: 0.08, opacity: 0.8),
                    Pose(duration: 0.08, opacity: 1), Pose(duration: 0.1)]
        }
        switch effect {
        case .plop:
            return [Pose(duration: 0.08, sx: 0.92, sy: 1.1, move: 3), Pose(duration: 0.09, sx: 1.12, sy: 0.88),
                    Pose(duration: 0.1, sx: 0.97, sy: 1.04), Pose(duration: 0.15)]
        case .pop:
            return [Pose(duration: 0.1, sx: 1.18, sy: 1.18), Pose(duration: 0.1, sx: 0.96, sy: 0.96),
                    Pose(duration: 0.08, sx: 1.02, sy: 1.02), Pose(duration: 0.14)]
        case .bounce:
            return [Pose(duration: 0.05, sx: 1.06, sy: 0.92), Pose(duration: 0.12, sx: 0.96, sy: 1.06, move: 10),
                    Pose(duration: 0.1, sx: 1.04, sy: 0.96), Pose(duration: 0.15)]
        case .ripple:
            return [Pose(duration: 0.1, sx: 1.04, sy: 1.04, ring: 1.0, ringOpacity: 0.5),
                    Pose(duration: 0.1, sx: 1.02, sy: 1.02, ring: 1.25, ringOpacity: 0.35),
                    Pose(duration: 0.12, ring: 1.5, ringOpacity: 0.15), Pose(duration: 0.1, ring: 1.65, ringOpacity: 0)]
        case .wobble:
            return [Pose(duration: 0.08, sx: 1.06, sy: 0.94, rotation: 8), Pose(duration: 0.09, sx: 0.97, sy: 1.04, rotation: -6),
                    Pose(duration: 0.09, rotation: 3), Pose(duration: 0.15)]
        case .glow:
            return [Pose(duration: 0.1, sx: 1.03, sy: 1.03, glow: 0.7), Pose(duration: 0.1, sx: 1.03, sy: 1.03, glow: 0.8),
                    Pose(duration: 0.1, glow: 0.4), Pose(duration: 0.15)]
        }
    }
}

/// Entrance for popover and panel content: a little smaller and transparent, then springing in.
struct PopEntrance: ViewModifier {
    let from: Double
    var trigger: Int?
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        if let trigger {
            // A persistent panel never re-appears, so its replays are driven by the counter instead.
            content.keyframeAnimator(initialValue: Entrance(), trigger: trigger) { view, value in
                view.scaleEffect(value.scale).opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(enabled && !reduceMotion ? from : 1, duration: 0.001)
                    SpringKeyframe(1, duration: 0.35, spring: Tokens.Motion.popSpring)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(enabled ? 0 : 1, duration: 0.001)
                    LinearKeyframe(1, duration: 0.18)
                }
            }
        } else {
            content
                .scaleEffect(enabled && !reduceMotion && !shown ? from : 1)
                .opacity(enabled && !shown ? 0 : 1)
                .onAppear { withAnimation(Tokens.Motion.popAnimation) { shown = true } }
        }
    }

    private struct Entrance {
        var scale = 1.0
        var opacity = 1.0
    }
}

extension View {
    func popEntrance(from scale: Double = 0.96, enabled: Bool = true) -> some View {
        modifier(PopEntrance(from: scale, enabled: enabled))
    }
}
