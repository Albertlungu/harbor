import Foundation

/// Pure rules behind the clicker, timer, metronome and pet widgets, kept free of UI so they can be tested.
public enum ToolLogic {
    public static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public enum ClickerLogic {
    public static let stepRange = 1...100

    public static func step(_ raw: Double) -> Int { ToolLogic.clamp(Int(raw.rounded()), stepRange) }

    /// A tally never goes below zero, so a decrease at zero is a no-op.
    public static func next(count: Int, step: Int, increase: Bool) -> Int {
        let delta = ToolLogic.clamp(step, stepRange)
        return increase ? count + delta : max(0, count - delta)
    }
}

public enum TimerLogic {
    public static let minuteRange = 1...180
    public static let defaultMinutes = 5

    public static func minutes(_ raw: Double) -> Int { ToolLogic.clamp(Int(raw.rounded()), minuteRange) }

    public static func remaining(end: Date, now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }

    /// Fraction of the ring still full, 1 at the start and 0 at the end.
    public static func progress(end: Date, now: Date, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return ToolLogic.clamp(remaining(end: end, now: now) / total, 0...1)
    }

    /// Rounds up so the display reads 00:01 until the very last instant.
    public static func clock(_ remaining: TimeInterval) -> String {
        let whole = Int(max(0, remaining).rounded(.up))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

public enum MetronomeLogic {
    public static let bpmRange = 30...300
    public static let beatRange = 1...12
    public static let defaultBPM = 100
    public static let defaultBeats = 4

    public static func bpm(_ raw: Double) -> Int { ToolLogic.clamp(Int(raw.rounded()), bpmRange) }
    public static func beats(_ raw: Double) -> Int { ToolLogic.clamp(Int(raw.rounded()), beatRange) }
    public static func volume(_ raw: Double) -> Double { ToolLogic.clamp(raw, 0...1) }

    public static func beatInterval(bpm: Int) -> TimeInterval { 60 / Double(ToolLogic.clamp(bpm, bpmRange)) }

    /// Tempo from taps: averages the gaps between the last four taps. A pause longer
    /// than two seconds starts a fresh count, so an old tap cannot skew the result.
    public struct TapTempo: Sendable {
        public static let maxTaps = 4
        public static let resetGap: TimeInterval = 2
        private var taps: [TimeInterval] = []

        public init() {}

        /// Records a tap at `time` (seconds on any monotonic clock) and returns the tempo once two taps exist.
        public mutating func tap(at time: TimeInterval) -> Int? {
            if let last = taps.last, time - last > Self.resetGap { taps.removeAll() }
            taps.append(time)
            if taps.count > Self.maxTaps { taps.removeFirst(taps.count - Self.maxTaps) }
            guard taps.count >= 2, let first = taps.first, let last = taps.last else { return nil }
            let average = (last - first) / Double(taps.count - 1)
            guard average > 0 else { return nil }
            return ToolLogic.clamp(Int((60 / average).rounded()), bpmRange)
        }

        public mutating func reset() { taps.removeAll() }
    }
}

/// Pet needs are fullness levels: 100 is content, 0 is empty.
public struct PetNeeds: Equatable, Sendable {
    public static let range = 0.0...100.0
    /// About one point every three minutes.
    public static let pointsPerSecond = 1.0 / 180

    public var happiness: Double
    public var hunger: Double
    public var energy: Double

    public init(happiness: Double = 80, hunger: Double = 80, energy: Double = 80) {
        self.happiness = ToolLogic.clamp(happiness, Self.range)
        self.hunger = ToolLogic.clamp(hunger, Self.range)
        self.energy = ToolLogic.clamp(energy, Self.range)
    }

    public func decayed(by elapsed: TimeInterval) -> PetNeeds {
        let loss = max(0, elapsed) * Self.pointsPerSecond
        return PetNeeds(happiness: happiness - loss, hunger: hunger - loss, energy: energy - loss)
    }

    public func petted() -> PetNeeds { PetNeeds(happiness: happiness + 5, hunger: hunger, energy: energy) }
    public func fed() -> PetNeeds { PetNeeds(happiness: happiness, hunger: hunger + 25, energy: energy) }
    public func played() -> PetNeeds { PetNeeds(happiness: happiness + 15, hunger: hunger, energy: energy - 10) }

    public static func cells(_ raw: Double) -> Int { ToolLogic.clamp(Int(raw.rounded()), 1...3) }
}
