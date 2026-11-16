import CoreGraphics
import Foundation

public enum RoamMode: String, CaseIterable, Sendable {
    case patrol, hangOut, follow

    public var title: String {
        switch self {
        case .patrol: "Patrol"
        case .hangOut: "Hang Out"
        case .follow: "Follow the Pointer"
        }
    }
}

public enum RoamSurfaceKind: Equatable, Sendable {
    case menuBar, window, dockBar, floor
}

/// A horizontal ledge the pet can stand on. `y` is the walking line in AppKit coordinates (y up).
public struct RoamSurface: Equatable, Sendable {
    public var kind: RoamSurfaceKind
    public var y: Double
    public var minX: Double
    public var maxX: Double

    public init(kind: RoamSurfaceKind, y: Double, minX: Double, maxX: Double) {
        self.kind = kind
        self.y = y
        self.minX = minX
        self.maxX = maxX
    }

    public func contains(x: Double) -> Bool { x >= minX && x <= maxX }
}

/// A window of another app in AppKit coordinates. Lists are ordered front to back.
public struct RoamWindow: Equatable, Sendable {
    public var frame: CGRect
    /// The focused window, whose title bar the pet must keep clear of.
    public var isFront: Bool

    public init(frame: CGRect, isFront: Bool = false) {
        self.frame = frame
        self.isFront = isFront
    }
}

public enum RoamSurfaces {
    public static let titleBarHeight = 28.0
    /// Ledges shorter than this are too small to be worth standing on.
    public static let minLength = 24.0
    private static let edgeSlack = 0.5

    /// The strip along the top of the focused window where the pet may never stand.
    public static func titleZone(_ windows: [RoamWindow]) -> CGRect? {
        guard let front = windows.first(where: \.isFront)?.frame else { return nil }
        return CGRect(x: front.minX, y: front.maxY - titleBarHeight, width: front.width, height: titleBarHeight)
    }

    /// Where a pet released at `y` ends up: dropped inside the title zone, it is lifted onto the window's top edge.
    public static func escapingTitleZone(x: Double, y: Double, zone: CGRect?) -> Double {
        guard let zone, x >= zone.minX, x <= zone.maxX, y > zone.minY, y < zone.maxY else { return y }
        return zone.maxY
    }

    /// Every ledge on one screen. Window tops hidden behind a window in front, or under the focused
    /// window's title bar, are cut away; the floor and menu bar edge are never occluded.
    public static func build(screen: CGRect, menuBarHeight: Double, windows: [RoamWindow], docks: [CGRect],
                             walkOnWindows: Bool) -> [RoamSurface] {
        var result = [RoamSurface(kind: .floor, y: screen.minY, minX: screen.minX, maxX: screen.maxX)]
        let menuY = screen.maxY - menuBarHeight
        let zone = titleZone(windows)

        func cut(_ kind: RoamSurfaceKind, y: Double, span: ClosedRange<Double>, occluders: [CGRect]) {
            var pieces = [span]
            var blockers = occluders.filter { $0.minY + edgeSlack < y && y < $0.maxY - edgeSlack }
            if let zone, zone.minY + edgeSlack < y, y < zone.maxY - edgeSlack { blockers.append(zone) }
            for blocker in blockers {
                pieces = pieces.flatMap { piece -> [ClosedRange<Double>] in
                    guard blocker.maxX > piece.lowerBound, blocker.minX < piece.upperBound else { return [piece] }
                    var rest: [ClosedRange<Double>] = []
                    if blocker.minX > piece.lowerBound { rest.append(piece.lowerBound...blocker.minX) }
                    if blocker.maxX < piece.upperBound { rest.append(blocker.maxX...piece.upperBound) }
                    return rest
                }
            }
            for piece in pieces where piece.upperBound - piece.lowerBound >= minLength {
                result.append(RoamSurface(kind: kind, y: y, minX: piece.lowerBound, maxX: piece.upperBound))
            }
        }

        if menuBarHeight > 0 {
            cut(.menuBar, y: menuY, span: screen.minX...screen.maxX, occluders: [])
        }
        if walkOnWindows {
            for (index, window) in windows.enumerated() {
                let frame = window.frame
                let top = frame.maxY
                guard top <= menuY + edgeSlack, top > screen.minY + edgeSlack,
                      frame.maxX > screen.minX, frame.minX < screen.maxX else { continue }
                cut(.window, y: top, span: max(frame.minX, screen.minX)...min(frame.maxX, screen.maxX),
                    occluders: windows[..<index].map(\.frame))
            }
        }
        for bar in docks where bar.maxX > screen.minX && bar.minX < screen.maxX {
            let top = bar.maxY
            guard top > screen.minY + edgeSlack, top < menuY else { continue }
            cut(.dockBar, y: top, span: max(bar.minX, screen.minX)...min(bar.maxX, screen.maxX), occluders: [])
        }
        return result
    }
}

public enum RoamPhysics {
    public static let gravity = 1400.0

    /// The ledge a pet standing at (`x`, `y`) is on, if any.
    public static func ground(x: Double, y: Double, in surfaces: [RoamSurface], tolerance: Double = 1) -> RoamSurface? {
        surfaces.filter { abs($0.y - y) <= tolerance && $0.contains(x: x) }.max { $0.y < $1.y }
    }

    public struct Fall: Equatable, Sendable {
        public var y: Double
        public var speed: Double
        public var landedOn: RoamSurface?
    }

    /// One step of free fall. The highest ledge crossed during the step catches the pet.
    public static func fall(x: Double, y: Double, speed: Double, dt: Double, surfaces: [RoamSurface]) -> Fall {
        let nextSpeed = speed + gravity * dt
        let nextY = y - (speed + nextSpeed) / 2 * dt
        let catches = surfaces.filter { $0.contains(x: x) && $0.y <= y + 0.5 && $0.y >= nextY }
        if let landing = catches.max(by: { $0.y < $1.y }) {
            return Fall(y: landing.y, speed: nextSpeed, landedOn: landing)
        }
        return Fall(y: nextY, speed: nextSpeed, landedOn: nil)
    }
}

public enum RoamActivity: Equatable, Sendable {
    case walking, resting, sitting, napping, falling, carried, fadingOut, fadingIn

    /// Whether the pet's picture changes every frame.
    public var isMoving: Bool {
        switch self {
        case .walking, .falling, .carried, .fadingOut, .fadingIn: true
        case .resting, .sitting, .napping: false
        }
    }
}

public enum RoamEvent: Equatable, Sendable {
    case landed(impact: Double)
    case startled
    case woke
    case turned
}

public struct RoamState: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var fallSpeed = 0.0
    /// 1 faces right, -1 faces left.
    public var facing = 1.0
    public var activity: RoamActivity = .resting
    public var timeLeft = 1.0
    public var preferMenuBar = false
    public var pointerStill = 0.0
    public var lastPointer: CGPoint?
    public var alpha = 1.0

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct RoamEnvironment: Sendable {
    public var surfaces: [RoamSurface]
    public var mode: RoamMode
    public var home: CGPoint
    public var pointer: CGPoint
    public var lively: Bool
    public var screenMinX: Double
    public var screenMaxX: Double

    public init(surfaces: [RoamSurface], mode: RoamMode, home: CGPoint, pointer: CGPoint, lively: Bool,
                screenMinX: Double, screenMaxX: Double) {
        self.surfaces = surfaces
        self.mode = mode
        self.home = home
        self.pointer = pointer
        self.lively = lively
        self.screenMinX = screenMinX
        self.screenMaxX = screenMaxX
    }
}

/// Behavior rules for the roaming pet, free of UI so they run under test with scripted dice.
public enum RoamBrain {
    public static let calmSpeed = 45.0
    public static let livelySpeed = 70.0
    public static let trotSpeed = 70.0
    public static let hangOutRadius = 120.0
    public static let followDistance = 60.0
    public static let sitAfterStill = 10.0
    public static let napAfterStill = 30.0
    public static let fadeTime = 0.25
    /// Chance of stepping off a ledge's end rather than turning around, while on patrol.
    public static let stepOffChance = 0.35
    private static let pointerMoved = 3.0

    public static func walkSpeed(lively: Bool) -> Double { lively ? livelySpeed : calmSpeed }

    /// Quiet mode keeps the pet in place.
    public static func effectiveMode(_ mode: RoamMode, quiet: Bool) -> RoamMode { quiet ? .hangOut : mode }

    /// Seconds between window snapshots, or nil when none are needed.
    public static func snapshotInterval(_ activity: RoamActivity) -> Double? {
        switch activity {
        case .walking, .falling, .carried, .fadingOut, .fadingIn: 0.5
        case .resting, .sitting: 2
        case .napping: nil
        }
    }

    /// Seconds between brain steps and frames, or nil when nothing is moving and a slow beat will do.
    public static func frameInterval(_ activity: RoamActivity) -> Double? { activity.isMoving ? 1.0 / 30 : nil }

    /// The pet's body is an ellipse standing on its feet; `feet` is the bottom center.
    public static func hits(point: CGPoint, feet: CGPoint, unit: Double) -> Bool {
        let rx = unit * 0.46
        let ry = unit * 0.5
        let dx = (point.x - feet.x) / rx
        let dy = (point.y - (feet.y + ry)) / ry
        return dx * dx + dy * dy <= 1
    }

    public static func step(_ s: inout RoamState, dt: Double, env: RoamEnvironment, roll: () -> Double) -> [RoamEvent] {
        var events: [RoamEvent] = []
        switch s.activity {
        case .carried:
            return events
        case .falling:
            let fall = RoamPhysics.fall(x: s.x, y: s.y, speed: s.fallSpeed, dt: dt, surfaces: env.surfaces)
            s.y = fall.y
            s.fallSpeed = fall.speed
            if fall.landedOn != nil {
                events.append(.landed(impact: fall.speed))
                s.fallSpeed = 0
                s.activity = .resting
                s.timeLeft = 0.5 + roll() * 0.8
            }
            return events
        case .fadingOut:
            s.alpha -= dt / fadeTime
            if s.alpha <= 0 {
                if let bar = env.surfaces.first(where: { $0.kind == .menuBar }) {
                    s.x = min(max(s.x, bar.minX + 12), bar.maxX - 12)
                    s.y = bar.y
                    s.alpha = 0
                    s.activity = .fadingIn
                } else {
                    s.alpha = 1
                    s.activity = .resting
                }
            }
            return events
        case .fadingIn:
            s.alpha += dt / fadeTime
            if s.alpha >= 1 {
                s.alpha = 1
                s.activity = .resting
                s.timeLeft = 1 + roll() * 2
            }
            return events
        case .walking, .resting, .sitting, .napping:
            break
        }

        guard let ground = RoamPhysics.ground(x: s.x, y: s.y, in: env.surfaces) else {
            s.activity = .falling
            s.fallSpeed = 0
            events.append(.startled)
            return events
        }

        if env.mode == .follow {
            followStep(&s, dt: dt, env: env, ground: ground, roll: roll, events: &events)
        } else {
            wanderStep(&s, dt: dt, env: env, ground: ground, roll: roll, events: &events)
        }
        return events
    }

    // MARK: Patrol and hang out

    private static func wanderStep(_ s: inout RoamState, dt: Double, env: RoamEnvironment, ground: RoamSurface,
                                   roll: () -> Double, events: inout [RoamEvent]) {
        s.timeLeft -= dt
        switch s.activity {
        case .walking:
            advance(&s, speed: walkSpeed(lively: env.lively), dt: dt, env: env, ground: ground, roll: roll, events: &events)
            if s.timeLeft <= 0, s.activity == .walking {
                s.activity = .resting
                s.timeLeft = 2 + roll() * 4
            }
        case .resting:
            guard s.timeLeft <= 0 else { return }
            if env.mode == .patrol, s.preferMenuBar, ground.kind != .menuBar,
               env.surfaces.contains(where: { $0.kind == .menuBar }) {
                s.activity = .fadingOut
                return
            }
            let pick = roll()
            if env.mode == .hangOut, pick < 0.2 {
                s.activity = .napping
                s.timeLeft = 20 + roll() * 20
            } else if pick < (env.mode == .hangOut ? 0.45 : 0.15) {
                s.activity = .sitting
                s.timeLeft = 5 + roll() * 7
            } else {
                startWalk(&s, env: env, roll: roll)
            }
        case .sitting, .napping:
            guard s.timeLeft <= 0 else { return }
            if s.activity == .napping { events.append(.woke) }
            s.activity = .resting
            s.timeLeft = 0.5 + roll()
        default:
            break
        }
    }

    private static func startWalk(_ s: inout RoamState, env: RoamEnvironment, roll: () -> Double) {
        var facing = roll() < 0.5 ? -1.0 : 1.0
        if env.mode == .hangOut {
            if s.x > env.home.x + hangOutRadius { facing = -1 }
            if s.x < env.home.x - hangOutRadius { facing = 1 }
        }
        s.facing = facing
        s.activity = .walking
        s.timeLeft = 2 + roll() * 4
    }

    /// Moves along the ledge, turning at its ends or, now and then on patrol, stepping off.
    private static func advance(_ s: inout RoamState, speed: Double, dt: Double, env: RoamEnvironment,
                                ground: RoamSurface, roll: () -> Double, events: inout [RoamEvent]) {
        var lower = max(ground.minX, env.screenMinX)
        var upper = min(ground.maxX, env.screenMaxX)
        if env.mode == .hangOut {
            lower = max(lower, min(env.home.x - hangOutRadius, s.x))
            upper = min(upper, max(env.home.x + hangOutRadius, s.x))
        }
        let next = s.x + s.facing * speed * dt
        if next >= lower, next <= upper {
            s.x = next
            return
        }
        let canStepOff = env.mode == .patrol && ground.kind != .floor && !(s.preferMenuBar && ground.kind == .menuBar)
            && (next < ground.minX || next > ground.maxX)
        if canStepOff, roll() < stepOffChance {
            s.x = next
            s.activity = .falling
            s.fallSpeed = 0
            return
        }
        s.x = min(max(next, lower), upper)
        s.facing = -s.facing
        events.append(.turned)
    }

    // MARK: Follow

    private static func followStep(_ s: inout RoamState, dt: Double, env: RoamEnvironment, ground: RoamSurface,
                                   roll: () -> Double, events: inout [RoamEvent]) {
        let pointer = env.pointer
        let moved = s.lastPointer.map { hypot($0.x - pointer.x, $0.y - pointer.y) > pointerMoved } ?? false
        s.lastPointer = pointer
        if moved {
            s.pointerStill = 0
            if s.activity == .napping { events.append(.woke) }
            if s.activity == .napping || s.activity == .sitting {
                s.activity = .resting
                s.timeLeft = 0
            }
        } else {
            s.pointerStill += dt
        }

        let dx = pointer.x - s.x
        let comfort = followDistance
        let tooClose = abs(dx) < comfort - 6
        let tooFar = abs(dx) > comfort + 10
        let speed = env.lively ? livelySpeed * 1.3 : trotSpeed

        if tooClose, s.activity != .sitting, s.activity != .napping {
            // Backing away keeps the pet from ever sitting under the cursor.
            s.facing = dx < 0 ? 1 : -1
            s.activity = .walking
        } else if tooFar, s.activity != .sitting, s.activity != .napping {
            s.facing = dx < 0 ? -1 : 1
            s.activity = .walking
        } else if s.activity == .walking, !tooClose, !tooFar {
            s.activity = .resting
        }

        switch s.activity {
        case .walking:
            let next = s.x + s.facing * speed * dt
            let lower = max(ground.minX, env.screenMinX)
            let upper = min(ground.maxX, env.screenMaxX)
            if next >= lower, next <= upper {
                s.x = next
            } else if pointer.y < s.y - 40, next < ground.minX || next > ground.maxX, ground.kind != .floor {
                s.x = next
                s.activity = .falling
                s.fallSpeed = 0
            } else {
                s.x = min(max(next, lower), upper)
                s.activity = .resting
            }
        case .resting, .sitting, .napping:
            if s.pointerStill >= napAfterStill, s.activity != .napping {
                s.activity = .napping
            } else if s.pointerStill >= sitAfterStill, s.activity == .resting {
                s.activity = .sitting
            }
        default:
            break
        }
    }
}
