import Foundation

public enum ConfettiShape: Sendable { case rect, circle }

public struct ConfettiParticle: Sendable, Equatable {
    /// Start offset from the burst origin and launch velocity, in points and points per second (y grows downward).
    public var x0: Double
    public var y0: Double
    public var vx: Double
    public var vy: Double
    public var angle0: Double
    /// Radians per second.
    public var spin: Double
    public var size: Double
    public var shape: ConfettiShape
    /// Picks a palette colour by index, modulo the colours available.
    public var colorIndex: Int
}

public struct ConfettiPose: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var angle: Double
    public var opacity: Double
}

/// Closed-form confetti so the burst needs no per-frame state and can be tested exactly.
public enum Confetti {
    public static let gravity = 900.0
    public static let fadeDuration = 1.2
    /// Particles hold full opacity this long, then fade over `fadeDuration`.
    public static let holdDuration = 0.4
    public static var lifetime: Double { holdDuration + fadeDuration }

    public static func burst(count: Int = 32, seed: UInt64 = 1) -> [ConfettiParticle] {
        var rng = SplitMix64(seed: seed)
        let n = min(max(count, 24), 40)
        return (0..<n).map { i in
            // A fan aimed upward, so the pieces rise before gravity pulls them down.
            let heading = -Double.pi / 2 + (rng.unit() - 0.5) * 1.6
            let speed = 380 + rng.unit() * 380
            return ConfettiParticle(
                x0: (rng.unit() - 0.5) * 24, y0: 0,
                vx: cos(heading) * speed, vy: sin(heading) * speed,
                angle0: rng.unit() * 2 * .pi, spin: (rng.unit() - 0.5) * 16,
                size: 5 + rng.unit() * 5, shape: i % 3 == 0 ? .circle : .rect, colorIndex: i)
        }
    }

    public static func pose(of p: ConfettiParticle, at t: Double) -> ConfettiPose {
        let t = max(t, 0)
        let fade = min(max((t - holdDuration) / fadeDuration, 0), 1)
        return ConfettiPose(x: p.x0 + p.vx * t, y: p.y0 + p.vy * t + 0.5 * gravity * t * t,
                            angle: p.angle0 + p.spin * t, opacity: 1 - fade)
    }
}

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
