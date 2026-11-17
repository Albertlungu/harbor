import CoreGraphics
import Foundation

/// How the roaming pet is drawn: the middle of its body and how far it is turned, in degrees clockwise.
/// The brain moves it between surfaces in single steps; this smooths those steps into continuous motion.
public enum RoamPose {
    /// Seconds to swing around a corner from one surface to the next.
    public static let turnTime = 0.24
    /// Time constant for easing the angle toward its target outside of corners, such as after a grab.
    public static let settleTime = 0.05
    /// Most a floating pet leans into its swim.
    public static let floatLean = 18.0

    /// The turn that puts the pet's feet on its surface: 0 standing, ±90 on a wall, 180 under a ceiling.
    /// In the air it leans with its swim, or spins with a tumble.
    public static func angle(_ s: RoamState) -> Double {
        if s.activity.isOnWall {
            if let wall = s.wall { return wall.normal * 90 }
            if s.ceiling != nil { return 180 }
        }
        switch s.activity {
        case .falling where s.tumbling: return s.spin
        case .floating: return min(max(s.vx / RoamBrain.floatSpeed, -1), 1) * floatLean
        default: return 0
        }
    }

    /// Whether the pet's feet are on a surface, where a change of angle means it went around a corner.
    public static func isAttached(_ activity: RoamActivity) -> Bool {
        switch activity {
        case .walking, .resting, .sitting, .napping, .climbing, .sliding, .clinging: true
        case .falling, .carried, .fadingOut, .fadingIn, .detaching, .floating: false
        }
    }

    /// The signed shortest turn from `from` to `to`, in degrees.
    public static func delta(from: Double, to: Double) -> Double { remainder(to - from, 360) }

    /// One step of easing `angle` toward `target` along the shorter way round.
    public static func settle(_ angle: Double, toward target: Double, dt: Double) -> Double {
        let step = delta(from: angle, to: target) * (1 - exp(-dt / settleTime))
        let next = angle + step
        return abs(delta(from: next, to: target)) < 0.05 ? target : next
    }
}

/// A swing around a corner: the body travels a curve from where it stood on the old surface to where it
/// stands on the new one while it turns. Around an inside corner both ends are the same point and the pet
/// simply rolls; around an outside corner it bends over the edge.
public struct RoamTurn: Equatable, Sendable {
    public var from: CGPoint
    public var to: CGPoint
    public var fromAngle: Double
    public var toAngle: Double
    public var duration: Double
    public var elapsed = 0.0

    public init(from: CGPoint, to: CGPoint, fromAngle: Double, toAngle: Double, duration: Double = RoamPose.turnTime) {
        self.from = from
        self.to = to
        self.fromAngle = fromAngle
        self.toAngle = toAngle
        self.duration = duration
    }

    public var isDone: Bool { elapsed >= duration }

    /// Where the curve bends: the body keeps going the way it went along the old surface, then comes in
    /// the way the new surface runs.
    public var control: CGPoint {
        let level = abs(remainder(fromAngle, 180)) < 45
        return level ? CGPoint(x: to.x, y: from.y) : CGPoint(x: from.x, y: to.y)
    }

    /// The middle and angle at the current point of the swing, eased in and out.
    public var sample: (middle: CGPoint, angle: Double) {
        let raw = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        let t = raw * raw * (3 - 2 * raw)
        let c = control
        let a = (1 - t) * (1 - t)
        let b = 2 * (1 - t) * t
        let d = t * t
        let middle = CGPoint(x: a * from.x + b * c.x + d * to.x, y: a * from.y + b * c.y + d * to.y)
        return (middle, fromAngle + RoamPose.delta(from: fromAngle, to: toAngle) * t)
    }
}
