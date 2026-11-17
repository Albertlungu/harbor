import CoreGraphics
import Foundation

public enum RoamMode: String, CaseIterable, Sendable {
    case patrol, hangOut, follow, curious

    public var title: String {
        switch self {
        case .patrol: "Patrol"
        case .hangOut: "Hang Out"
        case .follow: "Follow the Pointer"
        case .curious: "Extra Curious"
        }
    }
}

public enum RoamSurfaceKind: Equatable, Sendable {
    case menuBar, window, dockBar, floor, element
}

/// A horizontal ledge the pet can stand on, or hang under when it is a ceiling. `y` is the walking line in
/// AppKit coordinates (y up).
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

public enum RoamWallKind: Equatable, Sendable {
    case screen, window
}

/// A vertical edge the pet can climb, at `x` from `minY` to `maxY` in AppKit coordinates.
public struct RoamWall: Equatable, Sendable {
    public var kind: RoamWallKind
    public var x: Double
    public var minY: Double
    public var maxY: Double
    /// Which side the pet hangs on: -1 left of the line (a window's left edge), 1 right of it
    /// (the screen's left side). The pet's feet point the other way, at the wall.
    public var normal: Double

    public init(kind: RoamWallKind, x: Double, minY: Double, maxY: Double, normal: Double) {
        self.kind = kind
        self.x = x
        self.minY = minY
        self.maxY = maxY
        self.normal = normal
    }
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
    /// `elements` are notable controls inside windows; their top edges are ledges too, hidden behind any
    /// window in front of the window that holds them.
    public static func build(screen: CGRect, menuBarHeight: Double, windows: [RoamWindow], docks: [CGRect],
                             walkOnWindows: Bool, elements: [CGRect] = []) -> [RoamSurface] {
        var result = [RoamSurface(kind: .floor, y: screen.minY, minX: screen.minX, maxX: screen.maxX)]
        let menuY = screen.maxY - menuBarHeight
        let zone = titleZone(windows)

        func cut(_ kind: RoamSurfaceKind, y: Double, span: ClosedRange<Double>, occluders: [CGRect]) {
            var blockers = occluders
            if let zone { blockers.append(zone) }
            result += uncovered(kind, y: y, span: span, by: blockers)
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
        if walkOnWindows {
            for element in elements {
                let top = element.maxY
                guard top <= menuY + edgeSlack, top > screen.minY + edgeSlack,
                      element.maxX > screen.minX, element.minX < screen.maxX else { continue }
                let owner = windows.firstIndex { $0.frame.contains(CGPoint(x: element.midX, y: element.midY)) }
                cut(.element, y: top, span: max(element.minX, screen.minX)...min(element.maxX, screen.maxX),
                    occluders: windows[..<(owner ?? windows.count)].map(\.frame))
            }
        }
        for bar in docks where bar.maxX > screen.minX && bar.minX < screen.maxX {
            let top = bar.maxY
            guard top > screen.minY + edgeSlack, top < menuY else { continue }
            cut(.dockBar, y: top, span: max(bar.minX, screen.minX)...min(bar.maxX, screen.maxX), occluders: [])
        }
        return result
    }

    /// The parts of a line at `y` across `span` that no blocker crosses, long enough to stand on.
    private static func uncovered(_ kind: RoamSurfaceKind, y: Double, span: ClosedRange<Double>,
                                  by blockers: [CGRect]) -> [RoamSurface] {
        var pieces = [span]
        for blocker in blockers where blocker.minY + edgeSlack < y && y < blocker.maxY - edgeSlack {
            pieces = pieces.flatMap { piece -> [ClosedRange<Double>] in
                guard blocker.maxX > piece.lowerBound, blocker.minX < piece.upperBound else { return [piece] }
                var rest: [ClosedRange<Double>] = []
                if blocker.minX > piece.lowerBound { rest.append(piece.lowerBound...blocker.minX) }
                if blocker.maxX < piece.upperBound { rest.append(blocker.maxX...piece.upperBound) }
                return rest
            }
        }
        return pieces.filter { $0.upperBound - $0.lowerBound >= minLength }
            .map { RoamSurface(kind: kind, y: y, minX: $0.lowerBound, maxX: $0.upperBound) }
    }

    /// Every underside the pet can hang from upside down: the menu bar's lower edge (the screen's top when
    /// there is no menu bar, still of kind `menuBar`), and the bottom edges of windows that no window in
    /// front covers and that leave room to hang above the floor.
    public static func ceilings(screen: CGRect, menuBarHeight: Double, windows: [RoamWindow], walkOnWindows: Bool,
                                unit: Double = 32) -> [RoamSurface] {
        let top = screen.maxY - menuBarHeight
        var result = [RoamSurface(kind: .menuBar, y: top, minX: screen.minX, maxX: screen.maxX)]
        guard walkOnWindows else { return result }
        for (index, window) in windows.enumerated() {
            let frame = window.frame
            let bottom = frame.minY
            guard bottom > screen.minY + unit * 1.5, bottom < top - unit,
                  frame.maxX > screen.minX, frame.minX < screen.maxX else { continue }
            result += uncovered(.window, y: bottom, span: max(frame.minX, screen.minX)...min(frame.maxX, screen.maxX),
                                by: windows[..<index].map(\.frame))
        }
        return result
    }

    /// Every climbable edge on one screen: the screen's sides, and the left and right edges of windows
    /// where no window in front covers them and the pet's side of the edge is on the screen.
    public static func walls(screen: CGRect, menuBarHeight: Double, windows: [RoamWindow],
                             walkOnWindows: Bool) -> [RoamWall] {
        let top = screen.maxY - menuBarHeight
        var result = [RoamWall(kind: .screen, x: screen.minX, minY: screen.minY, maxY: top, normal: 1),
                      RoamWall(kind: .screen, x: screen.maxX, minY: screen.minY, maxY: top, normal: -1)]
        guard walkOnWindows else { return result }
        for (index, window) in windows.enumerated() {
            let frame = window.frame
            let low = max(frame.minY, screen.minY)
            let high = min(frame.maxY, top)
            guard high - low >= minLength else { continue }
            for (x, normal) in [(Double(frame.minX), -1.0), (Double(frame.maxX), 1.0)] {
                guard x + normal * minLength > screen.minX, x + normal * minLength < screen.maxX else { continue }
                var pieces = [low...high]
                for blocker in windows[..<index].map(\.frame)
                where blocker.minX + edgeSlack < x && x < blocker.maxX - edgeSlack {
                    pieces = pieces.flatMap { piece -> [ClosedRange<Double>] in
                        guard blocker.maxY > piece.lowerBound, blocker.minY < piece.upperBound else { return [piece] }
                        var rest: [ClosedRange<Double>] = []
                        if blocker.minY > piece.lowerBound { rest.append(piece.lowerBound...blocker.minY) }
                        if blocker.maxY < piece.upperBound { rest.append(blocker.maxY...piece.upperBound) }
                        return rest
                    }
                }
                for piece in pieces where piece.upperBound - piece.lowerBound >= minLength {
                    result.append(RoamWall(kind: .window, x: x, minY: piece.lowerBound, maxY: piece.upperBound,
                                           normal: normal))
                }
            }
        }
        return result
    }
}

public enum RoamPhysics {
    public static let gravity = 1400.0
    /// The highest a jump lifts the pet's feet, about seven body lengths at the default size.
    public static let maxJumpHeight = 230.0
    /// The fastest the pet travels sideways through the air when it jumps on purpose.
    public static let airSpeed = 380.0
    /// Fastest throw the pet accepts, so a flick sends it flying without leaving the screen in one frame.
    public static let maxThrowSpeed = 2400.0
    /// How much speed the pet keeps when it bounces off the screen's sides or top.
    public static let bounce = 0.45
    /// How hard a pet grips a wall it slides down; it grips harder when that would not stop it in time.
    public static let slideGrip = 1100.0

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

    /// The pet in the air: feet at (`x`, `y`) and velocity in points per second. After a grab,
    /// `x` is the wall and `y` the middle of the body; after catching a ceiling, `y` is the ceiling.
    public struct Flight: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var vx: Double
        public var vy: Double
        public var landedOn: RoamSurface?
        public var grabbed: RoamWall?
        public var grabbedCeiling: RoamSurface?
        public var hitSide = false
        public var hitTop = false

        public init(x: Double, y: Double, vx: Double, vy: Double) {
            self.x = x
            self.y = y
            self.vx = vx
            self.vy = vy
        }
    }

    /// One step of flight. Ledges catch the pet only on its way down, so it can jump up through one;
    /// it grabs any of `walls` its side meets from the open side, and any of `ceilings` its head meets
    /// on the way up; the screen's sides and `maxY` bounce it back.
    public static func fly(_ flight: Flight, dt: Double, surfaces: [RoamSurface], walls: [RoamWall],
                           ceilings: [RoamSurface] = [], half: Double, minX: Double, maxX: Double,
                           maxY: Double = .infinity) -> Flight {
        var next = Flight(x: flight.x + flight.vx * dt, y: flight.y, vx: flight.vx, vy: flight.vy - gravity * dt)
        next.y = flight.y + (flight.vy + next.vy) / 2 * dt

        var grab: (wall: RoamWall, t: Double, middle: Double)?
        for wall in walls {
            let line = wall.x + wall.normal * half
            let before = (flight.x - line) * wall.normal
            let after = (next.x - line) * wall.normal
            guard before >= 0, after < 0 else { continue }
            let t = before / (before - after)
            let middle = flight.y + (next.y - flight.y) * t + half
            // Too near the bottom to hold on: the pet slips past instead.
            guard middle >= wall.minY + half + 2, middle <= wall.maxY - half else { continue }
            if grab == nil || t < grab!.t { grab = (wall, t, middle) }
        }

        var hang: (ceiling: RoamSurface, t: Double)?
        if next.y > flight.y {
            let head = flight.y + half * 2
            let nextHead = next.y + half * 2
            let catches = ceilings.filter { $0.contains(x: next.x) && $0.y >= head - 0.5 && $0.y <= nextHead }
            if let ceiling = catches.min(by: { $0.y < $1.y }) {
                hang = (ceiling, max(0, ceiling.y - head) / (nextHead - head))
            }
        }
        if let hang, grab.map({ hang.t < $0.t }) ?? true {
            var held = Flight(x: flight.x + (next.x - flight.x) * hang.t, y: hang.ceiling.y, vx: 0, vy: 0)
            held.grabbedCeiling = hang.ceiling
            return held
        }

        var landing: (ledge: RoamSurface, t: Double)?
        if next.y < flight.y {
            let catches = surfaces.filter { $0.contains(x: next.x) && $0.y <= flight.y + 0.5 && $0.y >= next.y }
            if let ledge = catches.max(by: { $0.y < $1.y }) {
                landing = (ledge, max(0, flight.y - ledge.y) / (flight.y - next.y))
            }
        }

        if let grab, landing.map({ grab.t <= $0.t }) ?? true {
            var held = Flight(x: grab.wall.x, y: grab.middle, vx: 0, vy: flight.vy + (next.vy - flight.vy) * grab.t)
            held.grabbed = grab.wall
            return held
        }
        if let landing {
            next.y = landing.ledge.y
            next.landedOn = landing.ledge
            return next
        }
        if next.y + half * 2 > maxY {
            next.y = maxY - half * 2
            next.vy = -abs(next.vy) * bounce
            next.hitTop = true
        }
        if next.x < minX || next.x > maxX {
            next.x = min(max(next.x, minX), maxX)
            next.vx = -next.vx * bounce
            next.hitSide = true
        }
        return next
    }

    /// Launch velocity for an aimed jump that moves the feet by (`dx`, `dy`) over an arc peaking
    /// `clearance` above the higher end, or nil when that is beyond the pet's jump.
    public static func launch(dx: Double, dy: Double, clearance: Double) -> (vx: Double, vy: Double)? {
        var apex = max(dy, 0) + clearance
        while apex <= maxJumpHeight {
            let vy = (2 * gravity * apex).squareRoot()
            let time = vy / gravity + (2 * (apex - dy) / gravity).squareRoot()
            let vx = dx / time
            if abs(vx) <= airSpeed { return (vx, vy) }
            // A longer, higher arc buys time to cover the distance.
            apex += 8
        }
        return nil
    }
}

public enum RoamActivity: Equatable, Sendable {
    /// `falling` covers all flight, jumps included. On a wall or under a ceiling the pet is `climbing`,
    /// `sliding` or `clinging`. Following the pointer it gathers itself (`detaching`) and then swims
    /// through the air with no gravity (`floating`).
    case walking, resting, sitting, napping, falling, carried, fadingOut, fadingIn, climbing, sliding, clinging
    case detaching, floating

    /// Whether the pet's picture changes every frame.
    public var isMoving: Bool {
        switch self {
        case .walking, .falling, .carried, .fadingOut, .fadingIn, .climbing, .sliding, .detaching, .floating: true
        case .resting, .sitting, .napping, .clinging: false
        }
    }

    /// Holding a wall or a ceiling; which one is in `RoamState.wall` or `RoamState.ceiling`.
    public var isOnWall: Bool { self == .climbing || self == .sliding || self == .clinging }
}

public enum RoamEvent: Equatable, Sendable {
    case landed(impact: Double)
    case startled
    case woke
    case turned
    case jumped
    /// Caught a wall in flight or when dropped next to one.
    case grabbedWall
    /// A slide down a wall came to a stop.
    case slid
    /// Stepped from a ledge onto a wall to start climbing.
    case climbed
}

public struct RoamState: Equatable, Sendable {
    /// The feet on a ledge, under a ceiling or in the air; on a wall, `x` is the wall and `y` the middle of
    /// the body.
    public var x: Double
    public var y: Double
    /// Velocity in flight, and the slide speed along a wall, in points per second.
    public var vx = 0.0
    public var vy = 0.0
    /// 1 faces the pet's own right, -1 its left. On a wall the pet is turned so its feet face the wall,
    /// so its right is down the wall when the wall is on its left; under a ceiling its right is the screen's left.
    public var facing = 1.0
    /// How fast it is walking or climbing this step, in points per second.
    public var speed = 0.0
    public var activity: RoamActivity = .resting
    public var timeLeft = 1.0
    public var preferMenuBar = false
    public var pointerStill = 0.0
    public var lastPointer: CGPoint?
    public var alpha = 1.0
    /// The wall held while climbing, sliding or clinging.
    public var wall: RoamWall?
    /// The ceiling hung from while climbing or clinging upside down.
    public var ceiling: RoamSurface?
    /// Thrown hard enough to tumble end over end until it lands or grabs something.
    public var tumbling = false
    /// How far the tumble has turned the pet, in degrees clockwise.
    public var spin = 0.0
    /// Legs still to travel, planned by `RoamNav`.
    public var route: [RoamMove] = []
    /// What the route was planned toward, so it is replanned only once that moves.
    public var routeTarget: CGPoint?
    public var replanIn = 0.0
    /// Where a planned leap should come down; nil for a fall or a throw, which may grab any wall.
    public var aim: RoamSpot?
    /// Deceleration of the current slide along a wall.
    public var grip = 0.0

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct RoamEnvironment: Sendable {
    public var surfaces: [RoamSurface]
    public var walls: [RoamWall]
    public var ceilings: [RoamSurface]
    /// Routes over `surfaces` and `walls`; pass a cached one, since building it flies every possible leap.
    public var nav: RoamNav
    public var mode: RoamMode
    public var home: CGPoint
    public var pointer: CGPoint
    public var lively: Bool
    public var screenMinX: Double
    public var screenMaxX: Double
    /// The screen's bottom and top, which bound a floating pet and bounce a thrown one.
    public var screenMinY: Double
    public var screenMaxY: Double
    /// Something worth a look, such as where the person is typing; Extra Curious heads for it.
    public var attention: CGPoint?
    /// Notable controls in windows, in AppKit coordinates; their tops are among `surfaces`.
    public var elements: [CGRect]
    /// The pet's size in points.
    public var unit: Double

    public init(surfaces: [RoamSurface], walls: [RoamWall] = [], ceilings: [RoamSurface] = [], nav: RoamNav? = nil,
                mode: RoamMode, home: CGPoint, pointer: CGPoint, lively: Bool, screenMinX: Double, screenMaxX: Double,
                screenMinY: Double = -.infinity, screenMaxY: Double = .infinity, attention: CGPoint? = nil,
                elements: [CGRect] = [], unit: Double = 32) {
        self.surfaces = surfaces
        self.walls = walls
        self.ceilings = ceilings
        self.nav = nav ?? RoamNav(ledges: surfaces, walls: walls, ceilings: ceilings, half: unit / 2,
                                  screenMinX: screenMinX, screenMaxX: screenMaxX)
        self.mode = mode
        self.home = home
        self.pointer = pointer
        self.lively = lively
        self.screenMinX = screenMinX
        self.screenMaxX = screenMaxX
        self.screenMinY = screenMinY
        self.screenMaxY = screenMaxY
        self.attention = attention
        self.elements = elements
        self.unit = unit
    }

    public var half: Double { unit / 2 }
}
