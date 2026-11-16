import Foundation

extension OpenEffect {
    public var title: String {
        switch self {
        case .plop: "Plop"
        case .pop: "Pop"
        case .bounce: "Bounce"
        case .ripple: "Ripple"
        case .wobble: "Wobble"
        case .glow: "Glow"
        }
    }

    public var summary: String {
        switch self {
        case .plop: "Squashes and stretches, then lands."
        case .pop: "A quick swell, then settles."
        case .bounce: "One springy hop toward the screen's center."
        case .ripple: "A soft ring spreads from the icon."
        case .wobble: "A jelly wiggle."
        case .glow: "A brief soft light behind the icon."
        }
    }

    /// SF Symbol that hints at the motion, for the settings tiles.
    public var symbolName: String {
        switch self {
        case .plop: "drop.fill"
        case .pop: "burst.fill"
        case .bounce: "arrow.up.to.line"
        case .ripple: "dot.circle.and.hand.point.up.left.fill"
        case .wobble: "waveform.path"
        case .glow: "sun.max.fill"
        }
    }
}

/// Parameters for one effect's sound. Kept as data so the table can be tested without any audio.
public struct OpenSoundSpec: Equatable, Sendable {
    public struct Partial: Equatable, Sendable {
        public let startHz: Double
        public let endHz: Double
        public let gain: Double
    }

    public let partials: [Partial]
    /// Seconds over which the pitch moves from `startHz` to `endHz`; zero keeps it fixed.
    public let sweep: TimeInterval
    public let duration: TimeInterval
    public let attack: TimeInterval
    /// Exponential decay time constant; nil leaves the body flat.
    public let decay: TimeInterval?
    public let release: TimeInterval
    public let vibratoHz: Double
    /// Fraction of the pitch the vibrato swings.
    public let vibratoDepth: Double
}

public enum OpenEffectSound {
    public static let sampleRate = 44_100.0
    public static let defaultVolume = 0.5
    /// Headroom so the quietest and loudest effects sit at a similar level without clipping.
    static let peak: Float = 0.8

    public static func volume(_ raw: Double) -> Double {
        raw.isNaN ? defaultVolume : ToolLogic.clamp(raw, 0...1)
    }

    public static func spec(for effect: OpenEffect) -> OpenSoundSpec {
        func tone(_ start: Double, _ end: Double? = nil, gain: Double = 1) -> OpenSoundSpec.Partial {
            .init(startHz: start, endHz: end ?? start, gain: gain)
        }
        switch effect {
        case .plop:
            return .init(partials: [tone(420, 180)], sweep: 0.09, duration: 0.14, attack: 0.003,
                         decay: 0.04, release: 0.02, vibratoHz: 0, vibratoDepth: 0)
        case .pop:
            return .init(partials: [tone(900)], sweep: 0, duration: 0.09, attack: 0.001,
                         decay: 0.01, release: 0.01, vibratoHz: 0, vibratoDepth: 0)
        case .bounce:
            return .init(partials: [tone(260, 520)], sweep: 0.12, duration: 0.12, attack: 0.005,
                         decay: 0.07, release: 0.03, vibratoHz: 0, vibratoDepth: 0)
        case .ripple:
            return .init(partials: [tone(660), tone(990, gain: 0.5)], sweep: 0, duration: 0.3, attack: 0.01,
                         decay: 0.1, release: 0.05, vibratoHz: 0, vibratoDepth: 0)
        case .wobble:
            return .init(partials: [tone(400)], sweep: 0, duration: 0.2, attack: 0.01,
                         decay: 0.12, release: 0.04, vibratoHz: 18, vibratoDepth: 0.06)
        case .glow:
            return .init(partials: [tone(520)], sweep: 0, duration: 0.25, attack: 0.07,
                         decay: nil, release: 0.12, vibratoHz: 0, vibratoDepth: 0)
        }
    }

    /// Mono samples for the effect, normalized to a fixed peak so volume is the only loudness control.
    public static func samples(for effect: OpenEffect, sampleRate: Double = sampleRate) -> [Float] {
        let spec = spec(for: effect)
        let count = Int(spec.duration * sampleRate)
        var phases = [Double](repeating: 0, count: spec.partials.count)
        var out = [Float](repeating: 0, count: count)
        for n in 0..<count {
            let t = Double(n) / sampleRate
            var envelope = 1.0
            if spec.attack > 0 { envelope *= min(t / spec.attack, 1) }
            if let decay = spec.decay { envelope *= exp(-t / decay) }
            let tail = spec.duration - t
            if spec.release > 0, tail < spec.release { envelope *= max(tail / spec.release, 0) }
            let bend = spec.vibratoHz > 0 ? 1 + spec.vibratoDepth * sin(2 * .pi * spec.vibratoHz * t) : 1
            let glide = spec.sweep > 0 ? min(t / spec.sweep, 1) : 0
            var value = 0.0
            for (index, partial) in spec.partials.enumerated() {
                let hz = (partial.startHz + (partial.endHz - partial.startHz) * glide) * bend
                // Integrating the frequency keeps the chirp free of phase jumps.
                phases[index] += 2 * .pi * hz / sampleRate
                value += sin(phases[index]) * partial.gain
            }
            out[n] = Float(value * envelope)
        }
        let top = out.reduce(0) { max($0, abs($1)) }
        guard top > 0 else { return out }
        let scale = peak / top
        return out.map { $0 * scale }
    }
}
