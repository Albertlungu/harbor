import Foundation

/// Pure rules for playing the metronome straight from the dock: tap detection, scroll steps and clamping.
public enum MetronomeInput {
    /// Taps closer together than this belong to one rhythm.
    public static let tapWindow: TimeInterval = 1.5
    public static let maxTaps = 4
    /// Trackpads report points, a mouse wheel reports lines; this many points feel like one wheel notch.
    public static let pointsPerStep = 8.0
    public static let shiftMultiplier = 5

    public static func clampedBPM(_ value: Int) -> Int { ToolLogic.clamp(value, MetronomeLogic.bpmRange) }

    /// Applies scroll steps (positive raises the tempo); Shift makes each step coarser.
    public static func adjusted(bpm: Int, steps: Int, shift: Bool) -> Int {
        clampedBPM(bpm + steps * (shift ? shiftMultiplier : 1))
    }

    public struct TapResult: Equatable, Sendable {
        /// Taps in the current rhythm, counting this one.
        public let count: Int
        /// Set from the second tap on; the first tap is an ordinary play/stop click.
        public let bpm: Int?
        public var isTempo: Bool { bpm != nil }
    }

    public struct TapSequence: Sendable {
        private var taps: [TimeInterval] = []

        public init() {}

        public mutating func tap(at time: TimeInterval) -> TapResult {
            if let last = taps.last, time - last > MetronomeInput.tapWindow || time < last { taps.removeAll() }
            taps.append(time)
            if taps.count > MetronomeInput.maxTaps { taps.removeFirst(taps.count - MetronomeInput.maxTaps) }
            return TapResult(count: taps.count, bpm: Self.bpm(from: taps))
        }

        /// Averages every gap in the window rather than only the last, so one sloppy tap is smoothed out.
        public static func bpm(from taps: [TimeInterval]) -> Int? {
            guard taps.count >= 2, let first = taps.first, let last = taps.last else { return nil }
            let average = (last - first) / Double(taps.count - 1)
            guard average > 0 else { return nil }
            return MetronomeInput.clampedBPM(Int((60 / average).rounded()))
        }
    }

    /// Turns raw scroll deltas into whole tempo steps, carrying the remainder to the next event
    /// so slow trackpad movement still adds up instead of being rounded away.
    public struct ScrollAccumulator: Sendable {
        private var remainder = 0.0
        private var wasPrecise = false

        public init() {}

        public mutating func add(delta: Double, precise: Bool) -> Int {
            // A device switch would otherwise misread leftover points as lines.
            if precise != wasPrecise { remainder = 0 }
            wasPrecise = precise
            remainder += precise ? delta / MetronomeInput.pointsPerStep : delta
            let steps = Int(remainder.rounded(.towardZero))
            remainder -= Double(steps)
            return steps
        }
    }
}
