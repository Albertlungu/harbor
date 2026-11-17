import HarborCore
import SwiftUI

/// What the body is doing, independent of where the numbers come from, so the dev renderer can pose it too.
struct PetBodyState {
    var moving = false
    var falling = false
    var carried = false
    var sitting = false
    var napping = false
    /// 1 walking right, -1 walking left.
    var facing = 1.0
    /// Stride phase in radians; one full turn is one step with each foot.
    var phase = 0.0
    var time = 0.0
}

/// Poses layered over the expression for walking, falling, dangling, sitting and napping.
enum PetLocomotion {
    /// How far the head turns toward the direction of travel while walking.
    static let walkTurn = 0.75

    static func apply(_ pose: inout PetPose, _ state: PetBodyState, species: PetSpecies, unit: CGFloat) {
        let u = Double(unit)
        if state.moving, !state.carried, !state.falling {
            walk(&pose, phase: state.phase, facing: state.facing, gait: species.gait, unit: u)
        }
        if state.falling {
            // Limbs flung out, as if bracing for the landing.
            let flail = sin(state.time * 18) * 6
            pose.flipperLeft += 60 + flail
            pose.flipperRight += 60 - flail
            pose.footLeft = CGSize(width: -0.05 * u, height: 0.02 * u + flail * 0.002 * u)
            pose.footRight = CGSize(width: 0.05 * u, height: 0.02 * u - flail * 0.002 * u)
            pose.scale.height *= 1.05
            pose.scale.width *= 0.97
        }
        if state.carried {
            // Held by the scruff: arms up, feet dangling and swaying a little behind the body.
            let sway = sin(state.time * 3)
            pose.flipperLeft += 50
            pose.flipperRight += 50
            pose.rotation += sway * 6
            pose.footLeft = CGSize(width: -sway * 0.015 * u, height: 0.045 * u)
            pose.footRight = CGSize(width: -sway * 0.015 * u, height: 0.045 * u)
            pose.scale.height *= 1.06
            pose.scale.width *= 0.96
        }
        if state.sitting {
            pose.scale.height *= 0.92
            pose.scale.width *= 1.04
            pose.footLeft = CGSize(width: -0.03 * u, height: 0.005 * u)
            pose.footRight = CGSize(width: 0.03 * u, height: 0.005 * u)
        }
        if state.napping {
            pose.tucked = true
            pose.scale.height *= 0.9
            pose.scale.width *= 1.06
            pose.flipperLeft -= 8
            pose.flipperRight -= 8
        }
    }

    private static func walk(_ pose: inout PetPose, phase: Double, facing: Double, gait: PetGait.Kind, unit u: Double) {
        let swing = sin(phase)
        switch gait {
        case .walk:
            let left = PetGait.foot(phase: phase)
            let right = PetGait.foot(phase: phase + .pi)
            pose.footLeft = CGSize(width: left.x * facing * u, height: left.y * u)
            pose.footRight = CGSize(width: right.x * facing * u, height: right.y * u)
            // The body rises over each planted foot, twice per stride, and leans into the walk.
            pose.offset.height -= abs(swing) * 0.03 * u
            pose.rotation += facing * 5 + swing * 1.5
            pose.headTilt += sin(phase * 2) * 2
            pose.flipperLeft += 10 - 14 * swing
            pose.flipperRight += 10 + 14 * swing
        case .waddle:
            let left = PetGait.foot(phase: phase, reach: 0.035, lift: 0.03)
            let right = PetGait.foot(phase: phase + .pi, reach: 0.035, lift: 0.03)
            pose.footLeft = CGSize(width: left.x * facing * u, height: left.y * u)
            pose.footRight = CGSize(width: right.x * facing * u, height: right.y * u)
            pose.offset.height -= abs(swing) * 0.02 * u
            pose.rotation += facing * 3 + swing * 8
            pose.flipperLeft += 28 + 10 * sin(phase * 2)
            pose.flipperRight += 28 + 10 * sin(phase * 2)
        case .hop:
            // Airborne for the first half of each cycle, then a squash on landing.
            let air = max(0, swing)
            let land = max(0, -swing)
            pose.offset.height -= air * 0.11 * u
            pose.scale.height *= 1 + 0.06 * air - 0.08 * land
            pose.scale.width *= 1 - 0.03 * air + 0.06 * land
            pose.rotation += facing * (2 + 8 * air)
            let trail = CGSize(width: -facing * 0.045 * air * u, height: 0.015 * air * u)
            pose.footLeft = trail
            pose.footRight = trail
            pose.flipperLeft += 20 * air
            pose.flipperRight += 20 * air
        case .galumph:
            pose.offset.height -= abs(swing) * 0.04 * u
            pose.rotation += facing * 4 + swing * 3
            pose.scale.width *= 1 + 0.04 * cos(phase * 2)
            pose.scale.height *= 1 - 0.04 * cos(phase * 2)
            pose.flipperLeft += 18 + 18 * swing
            pose.flipperRight += 18 - 18 * swing
        }
    }
}

/// Accumulates stride phase so a changing walk speed changes the cadence without the feet jumping.
@MainActor
final class PetStrideClock {
    private var last: Double?
    private(set) var phase = 0.0

    func advance(to time: Double, rate: Double) -> Double {
        if let last { phase += min(max(time - last, 0), 0.1) * rate * 2 * .pi }
        last = time
        phase = phase.truncatingRemainder(dividingBy: 2 * .pi * 64)
        return phase
    }
}

/// Eases the head turn toward a moving target, retargeting from wherever the turn currently stands.
@MainActor
final class PetTurnClock {
    private var from = 0.0
    private var target = 0.0
    private var changedAt = 0.0

    func value(at time: Double, target next: Double) -> Double {
        if next != target {
            from = PetGait.turn(from: from, to: target, elapsed: time - changedAt)
            target = next
            changedAt = time
        }
        return PetGait.turn(from: from, to: target, elapsed: time - changedAt)
    }
}
