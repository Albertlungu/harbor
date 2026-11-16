import Foundation

/// A direction in the pet's view space, x to the right and y downward.
public struct PetVector: Equatable, Sendable {
    public static let zero = PetVector(x: 0, y: 0)
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum PetMood: String, Equatable, Sendable {
    case content, hungry, sleepy, happy
}

/// Pure rules behind the pet's behavior, kept free of UI so they can be tested.
public enum PetLogic {
    public static let hungryBelow = 30.0
    public static let sleepyBelow = 30.0
    public static let happyAtLeast = 85.0

    /// Hunger outranks tiredness because a fish bubble is the clearer cue to act on.
    public static func mood(for needs: PetNeeds) -> PetMood {
        if needs.hunger < hungryBelow { return .hungry }
        if needs.energy < sleepyBelow { return .sleepy }
        if needs.happiness >= happyAtLeast, needs.hunger >= 50, needs.energy >= 50 { return .happy }
        return .content
    }

    public static let napDelay: TimeInterval = 120
    public static let nightNapDelay: TimeInterval = 30

    public static func isNight(hour: Int) -> Bool { hour >= 23 || hour < 6 }

    public static func napDelay(hour: Int) -> TimeInterval { isNight(hour: hour) ? nightNapDelay : napDelay }

    public static func shouldSleep(idle: TimeInterval, hour: Int) -> Bool { idle >= napDelay(hour: hour) }

    /// Pointer distance beyond which the eyes stop following, in points.
    public static let trackingRange = 600.0
    /// Distance at which the pupils reach the edge of the eye; closer pointers move them proportionally less.
    public static let gazeRamp = 120.0

    /// Pupil direction from the pet's center to the pointer, within the unit disc, or nil when out of range.
    public static func gaze(dx: Double, dy: Double) -> PetVector? {
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance <= trackingRange else { return nil }
        guard distance > 0.001 else { return .zero }
        let strength = min(1, distance / gazeRamp)
        return PetVector(x: dx / distance * strength, y: dy / distance * strength)
    }

    /// Pulls a vector back into the unit disc so a pupil never leaves the eye.
    public static func clampGaze(_ vector: PetVector) -> PetVector {
        let length = (vector.x * vector.x + vector.y * vector.y).squareRoot()
        guard length > 1 else { return vector }
        return PetVector(x: vector.x / length, y: vector.y / length)
    }

    public static let feedAmount = 20.0

    public static func fed(_ needs: PetNeeds) -> PetNeeds {
        PetNeeds(happiness: needs.happiness, hunger: needs.hunger + feedAmount, energy: needs.energy)
    }
}

/// Detects a burst of rapid clicks: three taps within a short window trigger a trick.
public struct PetTapTracker: Sendable {
    public static let window: TimeInterval = 1.5
    public static let burst = 3
    private var taps: [TimeInterval] = []

    public init() {}

    /// Records a tap at `time` (seconds on any monotonic clock) and reports whether it completes a burst.
    public mutating func tap(at time: TimeInterval) -> Bool {
        taps.append(time)
        taps.removeAll { time - $0 > Self.window }
        guard taps.count >= Self.burst else { return false }
        // Clearing makes the next burst need fresh taps instead of retriggering on every click.
        taps.removeAll()
        return true
    }
}
