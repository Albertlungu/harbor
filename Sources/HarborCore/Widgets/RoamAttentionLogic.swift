import CoreGraphics
import Foundation

public enum RoamAttentionReason: String, CaseIterable, Sendable {
    /// The text caret where the user is typing.
    case caret
    /// Typing where no caret position could be found; the point is the focused element.
    case typing
    /// A window that just came to the front.
    case window
    case menu
    /// A notification banner appearing.
    case banner
    /// The pointer resting in one place.
    case dwell
    /// Nothing holds the pet's interest any more; published with no point.
    case bored
}

/// Something on screen that might catch the pet's eye, in AppKit coordinates.
public struct RoamAttentionSignal: Equatable, Sendable {
    public var reason: RoamAttentionReason
    public var point: CGPoint

    public init(reason: RoamAttentionReason, point: CGPoint) {
        self.reason = reason
        self.point = point
    }
}

public struct RoamAttentionState: Sendable {
    public internal(set) var focus: RoamAttentionSignal?
    var since = 0.0
    var interest = 0.0
    /// When the current focus stops being interesting.
    public internal(set) var boredAt = 0.0
    var lastSwitch = -Double.infinity
    /// After growing bored the pet looks at nothing for a moment, unless a banner appears.
    var restUntil = -Double.infinity
    var visits: [Visit] = []

    struct Visit: Sendable {
        var point: CGPoint
        var time: Double
    }

    public init() {}
}

/// How the pet chooses what to look at: urgent things win, places it looked at recently lose their
/// pull, and anything it stares at long enough becomes boring. Dice keep it from being predictable.
public enum RoamAttentionLogic {
    /// Signals within this distance of an earlier look count as the same place.
    public static let nearby = 60.0
    /// How long a look keeps a place stale.
    public static let memory = 30.0
    /// Pull lost for each recent look at the same place.
    public static let visitPenalty = 0.35
    /// The pet holds a new focus at least this long before something else can take it, except a banner.
    public static let minHold = 0.8
    /// A caret or menu moving less than this is the same thing moving, not a new one.
    public static let followRadius = 120.0
    /// Seconds the pet looks at nothing after losing interest.
    public static let rest = 2.0
    /// Typical seconds of interest; scaled by how interesting the thing was and by the dice.
    public static let attentionSpan = 6.0
    /// Gives even a mild signal a fair chance of being noticed.
    static let curiosity = 0.25

    public static func priority(_ reason: RoamAttentionReason) -> Double {
        switch reason {
        case .banner: 1
        case .menu: 0.9
        case .window: 0.75
        case .caret: 0.7
        case .typing: 0.6
        case .dwell: 0.45
        case .bored: 0
        }
    }

    /// 1 for a place not looked at lately, falling with each recent look near it.
    public static func novelty(of point: CGPoint, at now: Double, state: RoamAttentionState) -> Double {
        let looks = state.visits.filter { now - $0.time < memory && distance($0.point, point) < nearby }.count
        return max(0, 1 - Double(looks) * visitPenalty)
    }

    /// Considers a signal; returns true when the published focus changed (a new focus or the same one moved).
    public static func offer(_ signal: RoamAttentionSignal, at now: Double, state: inout RoamAttentionState,
                             roll: () -> Double) -> Bool {
        guard signal.reason != .bored else { return false }
        if let focus = state.focus, sameThing(focus, signal) {
            guard distance(focus.point, signal.point) > 2 else { return false }
            state.focus = signal
            return true
        }
        let interest = priority(signal.reason) * novelty(of: signal.point, at: now, state: state)
        guard interest > 0, signal.reason == .banner || now >= state.restUntil else { return false }
        if state.focus != nil {
            guard signal.reason == .banner || now - state.lastSwitch >= minHold,
                  interest > currentInterest(at: now, state: state) + 0.05 else { return false }
        }
        guard roll() < interest + curiosity else { return false }
        state.focus = signal
        state.since = now
        state.interest = interest
        state.boredAt = now + attentionSpan * (0.6 + 0.8 * roll()) * (0.5 + interest)
        state.lastSwitch = now
        state.visits.removeAll { now - $0.time >= memory }
        state.visits.append(.init(point: signal.point, time: now))
        return true
    }

    /// Lets the pet lose interest; returns true when the focus was dropped.
    public static func tick(at now: Double, state: inout RoamAttentionState) -> Bool {
        guard state.focus != nil, now >= state.boredAt else { return false }
        state.focus = nil
        state.interest = 0
        state.restUntil = now + rest
        return true
    }

    /// The pull of the current focus, fading to nothing as boredom approaches.
    static func currentInterest(at now: Double, state: RoamAttentionState) -> Double {
        guard state.focus != nil else { return 0 }
        let span = max(state.boredAt - state.since, 0.001)
        return state.interest * max(0, 1 - (now - state.since) / span)
    }

    /// A caret and typing at the same spot, or a menu sliding to the next one, are one thing in motion.
    static func sameThing(_ a: RoamAttentionSignal, _ b: RoamAttentionSignal) -> Bool {
        let typing: Set<RoamAttentionReason> = [.caret, .typing]
        let family = a.reason == b.reason || (typing.contains(a.reason) && typing.contains(b.reason))
        return family && a.reason != .dwell && a.reason != .banner && distance(a.point, b.point) < followRadius
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
