import Foundation

public enum PetSoundCue: String, CaseIterable, Sendable {
    case step, hop, land, grab, slide, climb, chirp, purr, sigh, startle
}

/// Soft synthesized sounds for the roaming pet. Kept as data and pure functions so loudness and
/// length can be checked under test without any audio hardware.
public enum PetSoundSynth {
    public static let sampleRate = 44_100.0

    /// One gliding tone or breath of noise inside a cue.
    struct Voice {
        var start = 0.0
        var duration: Double
        var fromHz: Double
        var toHz: Double
        var attack: Double
        /// Exponential decay time constant; nil holds the level until the release.
        var decay: Double?
        var release: Double
        /// Share of filtered noise mixed in; 1 is noise only.
        var noise = 0.0
        /// Gain of the octave above, which rounds out low tones on small speakers.
        var harmonic = 0.0
        var tremoloHz = 0.0
    }

    /// Steps and climbs alternate between two takes so a walk does not sound mechanical.
    public static func variants(for cue: PetSoundCue) -> Int {
        cue == .step || cue == .climb ? 2 : 1
    }

    /// Peak level of each cue; frequent sounds sit lowest so they stay in the background.
    public static func peak(for cue: PetSoundCue) -> Float {
        switch cue {
        case .step, .climb: 0.3
        case .slide, .sigh: 0.32
        case .grab, .chirp, .purr: 0.45
        case .hop, .startle: 0.5
        case .land: 0.55
        }
    }

    static func voices(for cue: PetSoundCue, variant: Int) -> [Voice] {
        let lift = variant == 0 ? 1.0 : 1.1
        switch cue {
        case .step:
            return [Voice(duration: 0.045, fromHz: 210 * lift, toHz: 150 * lift, attack: 0.002, decay: 0.012,
                          release: 0.012, noise: 0.3)]
        case .hop:
            return [Voice(duration: 0.12, fromHz: 320, toHz: 560, attack: 0.005, decay: 0.06, release: 0.03)]
        case .land:
            return [Voice(duration: 0.1, fromHz: 170, toHz: 95, attack: 0.002, decay: 0.03, release: 0.03,
                          noise: 0.25, harmonic: 0.3)]
        case .grab:
            return [Voice(duration: 0.1, fromHz: 620, toHz: 820, attack: 0.004, decay: 0.05, release: 0.03,
                          harmonic: 0.2)]
        case .slide:
            return [Voice(duration: 0.28, fromHz: 260, toHz: 200, attack: 0.06, decay: nil, release: 0.12, noise: 1)]
        case .climb:
            return [Voice(duration: 0.06, fromHz: 420 * lift, toHz: 470 * lift, attack: 0.003, decay: 0.02,
                          release: 0.015)]
        case .chirp:
            return [Voice(duration: 0.07, fromHz: 880, toHz: 1000, attack: 0.004, decay: 0.035, release: 0.02),
                    Voice(start: 0.08, duration: 0.08, fromHz: 1100, toHz: 1250, attack: 0.004, decay: 0.04,
                          release: 0.02)]
        case .purr:
            return [Voice(duration: 0.6, fromHz: 105, toHz: 100, attack: 0.08, decay: nil, release: 0.2,
                          harmonic: 0.5, tremoloHz: 24)]
        case .sigh:
            return [Voice(duration: 0.45, fromHz: 340, toHz: 230, attack: 0.08, decay: 0.25, release: 0.15,
                          noise: 0.5)]
        case .startle:
            return [Voice(duration: 0.12, fromHz: 520, toHz: 980, attack: 0.003, decay: 0.06, release: 0.03,
                          harmonic: 0.15)]
        }
    }

    public static func duration(for cue: PetSoundCue) -> Double {
        voices(for: cue, variant: 0).map { $0.start + $0.duration }.max() ?? 0
    }

    /// Mono samples for one take of a cue, normalized to the cue's peak so volume is the only other loudness control.
    public static func samples(for cue: PetSoundCue, variant: Int = 0, sampleRate: Double = sampleRate) -> [Float] {
        let voices = voices(for: cue, variant: variant)
        let count = Int(duration(for: cue) * sampleRate)
        var out = [Double](repeating: 0, count: count)
        // A fixed seed keeps every render of a cue identical.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15 &+ UInt64(variant)
        for voice in voices {
            var phase = 0.0
            var filtered = 0.0
            let first = Int(voice.start * sampleRate)
            let length = Int(voice.duration * sampleRate)
            for n in 0..<length where first + n < count {
                let t = Double(n) / sampleRate
                var envelope = voice.attack > 0 ? min(t / voice.attack, 1) : 1
                if let decay = voice.decay { envelope *= exp(-t / decay) }
                let tail = voice.duration - t
                if voice.release > 0, tail < voice.release { envelope *= max(tail / voice.release, 0) }
                if voice.tremoloHz > 0 { envelope *= 0.7 + 0.3 * sin(2 * .pi * voice.tremoloHz * t) }
                let glide = min(t / voice.duration, 1)
                let hz = voice.fromHz + (voice.toHz - voice.fromHz) * glide
                phase += 2 * .pi * hz / sampleRate
                let tone = sin(phase) + voice.harmonic * sin(2 * phase)
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let white = Double(seed >> 11) / Double(1 << 53) * 2 - 1
                // A one-pole low-pass turns the hiss into a soft breath.
                filtered += 0.12 * (white - filtered)
                let value = tone * (1 - voice.noise) + filtered * 4 * voice.noise
                out[first + n] += value * envelope
            }
        }
        let top = out.reduce(0) { max($0, abs($1)) }
        guard top > 0 else { return out.map(Float.init) }
        let scale = Double(peak(for: cue)) / top
        return out.map { Float($0 * scale) }
    }
}

/// Keeps the pet's sounds sparse: a short gap between any two, a per-cue repeat interval, and a cap
/// on how many may play in a sliding window, so a long walk never turns into a stream of ticks.
public struct PetSoundGate: Sendable {
    public static let minGap = 0.08
    public static let window = 2.0
    public static let maxPerWindow = 5

    public static func interval(for cue: PetSoundCue) -> Double {
        switch cue {
        case .step: 0.3
        case .climb: 0.25
        case .hop, .land, .grab: 0.2
        case .slide: 0.5
        case .chirp: 1
        case .startle: 1.5
        case .purr: 3
        case .sigh: 4
        }
    }

    private var lastAny = -Double.infinity
    private var lastByCue: [PetSoundCue: Double] = [:]
    private var recent: [Double] = []

    public init() {}

    /// Whether `cue` may play at `now` (seconds on any steady clock); admitting it records the play.
    public mutating func admit(_ cue: PetSoundCue, at now: Double) -> Bool {
        recent.removeAll { now - $0 >= Self.window }
        guard now - lastAny >= Self.minGap,
              now - (lastByCue[cue] ?? -.infinity) >= Self.interval(for: cue) else { return false }
        // Steps give way first when the budget runs low, leaving room for the sounds that mean something.
        let budget = cue == .step || cue == .climb ? Self.maxPerWindow - 2 : Self.maxPerWindow
        guard recent.count < budget else { return false }
        lastAny = now
        lastByCue[cue] = now
        recent.append(now)
        return true
    }
}
