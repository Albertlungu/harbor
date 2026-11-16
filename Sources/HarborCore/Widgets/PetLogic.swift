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

/// What the pet is feeling right now. Each case maps to a composable face so new moods only need a table row.
public enum PetExpression: String, Equatable, Sendable, CaseIterable {
    case calm, happy, curious, surprised, sleepy, asleep, hungry, shy, proud, excited
}

public enum PetEyes: Equatable, Sendable {
    case open, wide, sparkle, halfLid
    /// Closed and curved upward, a contented squint.
    case arcUp
    /// Closed and curved downward, as in sleep.
    case arcDown
}

public enum PetMouth: Equatable, Sendable {
    case w, smile, openSmile, o, flat
}

public enum PetBrow: Equatable, Sendable {
    case none, raised, worried
}

public enum PetGazeMode: Equatable, Sendable {
    case follow, down, away
}

/// The pieces of a face, kept apart from drawing so expressions can be tested and combined.
public struct PetFace: Equatable, Sendable {
    public var eyes: PetEyes
    public var mouth: PetMouth
    public var brow: PetBrow
    public var gaze: PetGazeMode = .follow
    /// Multiplier on the resting blush opacity.
    public var blush: Double = 1
    /// Head tilt in degrees.
    public var tilt: Double = 0
    /// Horizontal squash that makes the body look bashful.
    public var squish: Double = 0
    public var chinUp: Bool = false
    public var wiggles: Bool = false
}

extension PetExpression {
    public var face: PetFace {
        switch self {
        case .calm: PetFace(eyes: .open, mouth: .w, brow: .none)
        case .happy: PetFace(eyes: .arcUp, mouth: .openSmile, brow: .none, blush: 1.3)
        case .curious: PetFace(eyes: .wide, mouth: .smile, brow: .raised, tilt: 9)
        case .surprised: PetFace(eyes: .wide, mouth: .o, brow: .raised, blush: 0.6)
        case .sleepy: PetFace(eyes: .halfLid, mouth: .flat, brow: .none)
        case .asleep: PetFace(eyes: .arcDown, mouth: .flat, brow: .none)
        case .hungry: PetFace(eyes: .open, mouth: .flat, brow: .worried, gaze: .down)
        case .shy: PetFace(eyes: .open, mouth: .flat, brow: .worried, gaze: .away, blush: 2.2, squish: 1)
        case .proud: PetFace(eyes: .arcUp, mouth: .smile, brow: .none, chinUp: true)
        case .excited: PetFace(eyes: .sparkle, mouth: .openSmile, brow: .raised, blush: 1.4, wiggles: true)
        }
    }
}

/// Everything the expression state machine looks at.
public struct PetContext: Equatable, Sendable {
    public var needs: PetNeeds
    public var bond: Double
    public var idle: TimeInterval
    public var hour: Int
    /// Seconds the pointer has rested on the pet since the last click, 0 when it is elsewhere.
    public var hover: TimeInterval
    public var clickStreak: Int

    public init(needs: PetNeeds = PetNeeds(), bond: Double = 0, idle: TimeInterval = 0, hour: Int = 12,
                hover: TimeInterval = 0, clickStreak: Int = 0) {
        self.needs = needs
        self.bond = bond
        self.idle = idle
        self.hour = hour
        self.hover = hover
        self.clickStreak = clickStreak
    }
}

/// Pure rules behind the pet's behavior, kept free of UI so they can be tested.
public enum PetLogic {
    public static let hungryBelow = 30.0
    public static let sleepyBelow = 30.0
    public static let happyAtLeast = 85.0

    /// Idle time before the pet gets bored, regardless of the hour.
    public static let boredAfter: TimeInterval = 25
    /// How far ahead of the nap the yawn starts.
    public static let yawnLead: TimeInterval = 15
    public static let shyAfter: TimeInterval = 1.5
    public static let warmAfter: TimeInterval = 5
    public static let proudBond = 60.0

    public static func isNight(hour: Int) -> Bool { hour >= 23 || hour < 6 }

    /// Nights nap quickly, mornings are groggy, and midday is the most awake stretch.
    public static func napDelay(hour: Int) -> TimeInterval {
        if isNight(hour: hour) { return 40 }
        if (6..<9).contains(hour) { return 60 }
        if (11..<15).contains(hour) { return 100 }
        return 75
    }

    public static func shouldSleep(idle: TimeInterval, hour: Int) -> Bool { idle >= napDelay(hour: hour) }

    public static func shouldYawn(idle: TimeInterval, hour: Int) -> Bool {
        idle >= max(boredAfter, napDelay(hour: hour) - yawnLead) && !shouldSleep(idle: idle, hour: hour)
    }

    /// Hunger outranks tiredness because a fish bubble is the clearer cue to act on.
    public static func expression(_ c: PetContext) -> PetExpression {
        if shouldSleep(idle: c.idle, hour: c.hour) { return .asleep }
        if c.clickStreak >= 2 { return .excited }
        if c.hover >= warmAfter { return c.bond >= 20 ? .happy : .proud }
        if c.hover >= shyAfter { return .shy }
        if c.hover > 0 { return .curious }
        if c.needs.hunger < hungryBelow { return .hungry }
        if c.needs.energy < sleepyBelow || c.idle >= boredAfter { return .sleepy }
        if c.needs.happiness >= happyAtLeast, c.needs.hunger >= 50, c.needs.energy >= 50 {
            return c.bond >= proudBond ? .happy : .proud
        }
        return (6..<9).contains(c.hour) && c.idle >= 10 ? .sleepy : .calm
    }

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

    /// Taps still inside the window at `time`, without recording one.
    public func streak(at time: TimeInterval) -> Int { taps.filter { time - $0 <= Self.window }.count }

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

public enum PetIdle: String, Equatable, Sendable, CaseIterable {
    case lookAround, wave, scratch, yawn, chaseTail, hum, peek
}

extension PetLogic {
    public static let bondRange = 0.0...100.0
    public static let pettingBond = 2.0
    public static let feedingBond = 4.0
    /// Slow enough that a few days away only cools the pet, never erases it.
    public static let bondDecayPerDay = 2.0

    public static func bond(_ bond: Double, afterPetting: Bool) -> Double {
        ToolLogic.clamp(bond + (afterPetting ? pettingBond : feedingBond), bondRange)
    }

    public static func decayedBond(_ bond: Double, elapsed: TimeInterval) -> Double {
        ToolLogic.clamp(bond - max(0, elapsed) / 86_400 * bondDecayPerDay, bondRange)
    }

    /// A hover heart is the reward for a bond worth showing off.
    public static func showsHoverHeart(bond: Double) -> Bool { bond >= 50 }

    /// 0.5 for a stranger up to 1.5 for a devoted friend.
    public static func affection(bond: Double) -> Double { 0.5 + ToolLogic.clamp(bond, bondRange) / 100 }

    public static func idleWeight(_ idle: PetIdle, bond: Double, hour: Int) -> Double {
        let warm = affection(bond: bond)
        switch idle {
        case .lookAround: return 30
        case .wave: return 14 * warm * warm
        case .scratch: return 14
        case .yawn: return (6..<9).contains(hour) ? 30 : (isNight(hour: hour) ? 18 : 8)
        case .chaseTail: return 2
        case .hum: return 12 * warm * warm
        case .peek: return 20
        }
    }

    /// Weighted pick that never returns `previous`. `roll` is uniform in 0..<1 so tests can drive it.
    public static func pickIdle(previous: PetIdle?, bond: Double, hour: Int, roll: Double) -> PetIdle {
        let options = PetIdle.allCases.filter { $0 != previous }
        let weights = options.map { idleWeight($0, bond: bond, hour: hour) }
        var target = ToolLogic.clamp(roll, 0...0.999_999_9) * weights.reduce(0, +)
        for (option, weight) in zip(options, weights) {
            if target < weight { return option }
            target -= weight
        }
        return options[options.count - 1]
    }

    /// Seconds before the next idle act, shorter around midday when the pet is liveliest.
    public static func idleDelay(hour: Int, roll: Double) -> TimeInterval {
        let base = 5 + ToolLogic.clamp(roll, 0...1) * 5
        return (11..<15).contains(hour) ? base * 0.8 : base
    }

    public static let blinkDuration: TimeInterval = 0.13
    public static let doubleBlinkChance = 0.15

    /// Random gaps keep blinks from looking like a metronome; a double blink now and then breaks the rhythm further.
    public static func blinkPlan(delayRoll: Double, doubleRoll: Double) -> (delay: TimeInterval, double: Bool) {
        (2.5 + ToolLogic.clamp(delayRoll, 0...1) * 3.5, doubleRoll < doubleBlinkChance)
    }

    /// Rare treats, about one per hour on screen.
    public static let surprisesPerHour = 1.0

    public static func surpriseProbability(visibleFor seconds: TimeInterval) -> Double {
        1 - exp(-max(0, seconds) / 3600 * surprisesPerHour)
    }
}

public enum PetSurprise: String, Equatable, Sendable, CaseIterable {
    case sneeze, flop, gift

    public static func pick(roll: Double) -> PetSurprise {
        let all = allCases
        return all[min(Int(ToolLogic.clamp(roll, 0...1) * Double(all.count)), all.count - 1)]
    }
}

/// Closed-form animation curves so views can sample them at any instant without stored state.
public enum PetMotion {
    public static let breathPeriod: TimeInterval = 3.5
    /// Share of the cycle spent inhaling; the exhale gets the rest, so it is faster.
    public static let inhaleShare = 0.6

    /// 0 at rest to 1 at a full breath, with a slow inhale and a quicker exhale.
    public static func breath(at time: TimeInterval) -> Double {
        let phase = (time / breathPeriod).truncatingRemainder(dividingBy: 1)
        let p = phase < 0 ? phase + 1 : phase
        if p < inhaleShare { return 0.5 - 0.5 * cos(Double.pi * p / inhaleShare) }
        return 0.5 + 0.5 * cos(Double.pi * (p - inhaleShare) / (1 - inhaleShare))
    }

    /// Step response of a damped spring from 0 toward 1; overshoots when damping is under 1.
    public static func spring(_ time: TimeInterval, response: Double = 0.3, damping: Double = 0.6) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        guard damping < 1 else { return 1 - exp(-omega * time) * (1 + omega * time) }
        let damped = omega * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * omega * time)
        return 1 - decay * (cos(damped * time) + damping * omega / damped * sin(damped * time))
    }

    public static let hopAnticipation: TimeInterval = 0.12
    public static let hopAir: TimeInterval = 0.38
    public static let hopDuration: TimeInterval = 1.5

    /// Lift as a fraction of the hop height and a vertical squash (positive squashes, negative stretches).
    public static func hop(elapsed: TimeInterval) -> (lift: Double, squash: Double) {
        guard elapsed >= 0 else { return (0, 0) }
        if elapsed < hopAnticipation { return (0, 0.14 * sin(elapsed / hopAnticipation * Double.pi / 2)) }
        let flight = elapsed - hopAnticipation
        if flight < hopAir {
            let p = flight / hopAir
            return (4 * p * (1 - p), -0.08 * sin(p * Double.pi))
        }
        // Landing squash settles through a spring so the pet overshoots before it rests.
        return (0, 0.16 * (1 - spring(flight - hopAir)))
    }
}
