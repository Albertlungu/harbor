import Foundation

extension EffectKind {
    /// Effects that react to the pointer rather than playing on their own.
    public var followsPointer: Bool { self == .ripples || self == .trail }

    /// The effect Seasonal stands for on `date`: a few holidays, otherwise the northern-hemisphere season.
    public static func seasonal(on date: Date, calendar: Calendar = .current) -> EffectKind {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1, day = parts.day ?? 1
        switch (month, day) {
        case (12, 31), (1, 1): return .fireworks
        case (2, 14): return .hearts
        case (7, 4): return .fireworks
        default: break
        }
        switch month {
        case 12, 1, 2: return .snow
        case 3, 4, 5: return .petals
        case 6, 7, 8: return .fireflies
        default: return .leaves
        }
    }

    /// `effects` with Seasonal swapped for the effect it stands for on `date`.
    public static func resolve(_ effects: Set<EffectKind>, on date: Date, calendar: Calendar = .current) -> Set<EffectKind> {
        guard effects.contains(.seasonal) else { return effects }
        var out = effects
        out.remove(.seasonal)
        out.insert(seasonal(on: date, calendar: calendar))
        return out
    }
}

/// Stateless helpers so every ambient particle is a pure function of its index and the time.
public enum EffectMath {
    public static func fract(_ x: Double) -> Double { x - floor(x) }

    /// A stable pseudo-random value in 0..<1 for `seed`.
    public static func hash(_ seed: Double) -> Double { fract(sin(seed * 12.9898 + 78.233) * 43758.5453) }

    /// Position along a looping track of `span` points travelled at `speed` points per second,
    /// starting at a seed-chosen offset. `margin` lets a particle leave fully before it wraps.
    public static func travel(seed: Double, t: Double, speed: Double, span: Double, margin: Double = 0) -> Double {
        let length = max(span + margin * 2, 1)
        return fract(t * speed / length + hash(seed)) * length - margin
    }

    /// 0 at night, 1 at midday, with sunrise and sunset easing over about two hours around 6 and 18.
    public static func daylight(hour: Double) -> Double {
        let h = fract(hour / 24) * 24
        let sun = sin((h - 6) / 12 * .pi)
        return min(max((sun + 0.25) / 0.5, 0), 1)
    }

    /// The local hour as a fraction, e.g. 13.5 for half past one.
    public static func hour(of date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }
}

/// Recent pointer positions along the dock, kept short so pointer effects can fade them out.
public struct PointerTrail: Sendable, Equatable {
    public struct Mark: Sendable, Equatable {
        public var position: Double
        public var time: Double
    }

    public private(set) var marks: [Mark] = []
    /// Minimum points between marks, so a still pointer does not pile marks on one spot.
    public var spacing: Double
    public var lifetime: Double

    public init(spacing: Double, lifetime: Double) {
        self.spacing = spacing
        self.lifetime = lifetime
    }

    public mutating func record(_ position: Double, at time: Double) {
        marks.removeAll { time - $0.time > lifetime }
        if let last = marks.last, abs(last.position - position) < spacing { return }
        marks.append(Mark(position: position, time: time))
    }

    /// Marks still visible at `time`, each with its age from 0 (new) to 1 (gone).
    public func live(at time: Double) -> [(mark: Mark, age: Double)] {
        marks.compactMap { m in
            let age = (time - m.time) / lifetime
            return age >= 0 && age < 1 ? (m, age) : nil
        }
    }
}
