import CoreGraphics
import Foundation

/// Behavior rules for the roaming pet, free of UI so they run under test with scripted dice.
public enum RoamBrain {
    public static let calmSpeed = 45.0
    public static let livelySpeed = 70.0
    public static let trotSpeed = 70.0
    public static let calmClimbSpeed = 30.0
    public static let livelyClimbSpeed = 48.0
    public static let hangOutRadius = 120.0
    public static let followDistance = 60.0
    public static let sitAfterStill = 10.0
    public static let napAfterStill = 30.0
    public static let fadeTime = 0.25
    /// Chance of stepping off a ledge's end rather than turning around, while on patrol.
    public static let stepOffChance = 0.35
    /// Chance, when a patrolling pet finishes a rest, that it sets off for another ledge or wall.
    public static let exploreChance = 0.25
    /// A pet let go with its side this close to a wall catches hold of it.
    public static let grabReach = 10.0
    /// Slide speed when put down against a wall, so it always slips a little before it holds.
    public static let dropSlide = 150.0
    /// Slower than this the pet was put down rather than thrown.
    public static let throwThreshold = 150.0
    private static let pointerMoved = 3.0
    private static let replanEvery = 0.4

    public static func walkSpeed(lively: Bool) -> Double { lively ? livelySpeed : calmSpeed }
    public static func climbSpeed(lively: Bool) -> Double { lively ? livelyClimbSpeed : calmClimbSpeed }

    /// Quiet mode keeps the pet in place.
    public static func effectiveMode(_ mode: RoamMode, quiet: Bool) -> RoamMode { quiet ? .hangOut : mode }

    /// Seconds between window snapshots, or nil when none are needed.
    public static func snapshotInterval(_ activity: RoamActivity) -> Double? {
        switch activity {
        case .walking, .falling, .carried, .fadingOut, .fadingIn, .climbing, .sliding: 0.5
        case .resting, .sitting, .clinging: 2
        case .napping: nil
        }
    }

    /// Seconds between brain steps while still; a moving pet steps on every display refresh instead.
    public static func idleInterval(_ activity: RoamActivity) -> Double { activity == .napping ? 1 : 0.5 }

    /// The pet's body is an ellipse standing on its feet; `feet` is the bottom center.
    public static func hits(point: CGPoint, feet: CGPoint, unit: Double) -> Bool {
        hits(point: point, middle: CGPoint(x: feet.x, y: feet.y + unit * 0.5), unit: unit, sideways: false)
    }

    /// On a wall the pet lies on its side, so its ellipse turns with it.
    public static func hits(point: CGPoint, middle: CGPoint, unit: Double, sideways: Bool) -> Bool {
        let across = unit * 0.46
        let along = unit * 0.5
        let dx = (point.x - middle.x) / (sideways ? along : across)
        let dy = (point.y - middle.y) / (sideways ? across : along)
        return dx * dx + dy * dy <= 1
    }

    /// Which way the pet faces, in its own turned frame, to look `dy` along a wall.
    public static func climbFacing(_ wall: RoamWall, dy: Double) -> Double { dy >= 0 ? -wall.normal : wall.normal }

    // MARK: Release

    /// Let go after being carried. Put down beside a wall, the pet grabs it and slides a little before it
    /// holds; let go while the pointer is moving fast, it flies off with that velocity.
    public static func release(_ s: inout RoamState, velocity: CGVector, env: RoamEnvironment) -> [RoamEvent] {
        var events: [RoamEvent] = []
        s.route = []
        s.routeTarget = nil
        s.aim = nil
        s.wall = nil
        let half = env.half
        var vx = Double(velocity.dx)
        var vy = Double(velocity.dy)
        let speed = hypot(vx, vy)
        if speed > RoamPhysics.maxThrowSpeed {
            vx *= RoamPhysics.maxThrowSpeed / speed
            vy *= RoamPhysics.maxThrowSpeed / speed
        }
        let middle = s.y + half
        if speed < throwThreshold {
            let nearby = env.walls.filter { wall in
                let side = (s.x - wall.x) * wall.normal - half
                return side >= -half && side <= grabReach
                    && middle >= wall.minY + half + 2 && middle <= wall.maxY - half
            }
            if let wall = nearby.min(by: { abs($0.x - s.x) < abs($1.x - s.x) }) {
                s.y = middle
                s.vy = -dropSlide
                grab(&s, wall: wall, half: half, events: &events)
                return events
            }
            vx = 0
            vy = 0
        }
        s.vx = vx
        s.vy = vy
        s.activity = .falling
        if abs(vx) > 1 { s.facing = vx < 0 ? -1 : 1 }
        return events
    }

    /// Takes hold of `wall` at the current height, gripping hard enough to stop before its bottom.
    private static func grab(_ s: inout RoamState, wall: RoamWall, half: Double, events: inout [RoamEvent]) {
        let room = max(s.y - (wall.minY + half), 1)
        s.wall = wall
        s.x = wall.x
        s.vx = 0
        s.grip = s.vy < 0 ? max(RoamPhysics.slideGrip, s.vy * s.vy / (2 * room))
            : RoamPhysics.slideGrip + RoamPhysics.gravity
        s.activity = .sliding
        events.append(.grabbedWall)
    }

    /// Lets go of the wall, pushing off with the given velocity.
    private static func detach(_ s: inout RoamState, half: Double, vx: Double, vy: Double) {
        guard let wall = s.wall else { return }
        s.x = wall.x + wall.normal * half
        s.y -= half
        s.wall = nil
        s.vx = vx
        s.vy = vy
        s.aim = nil
        s.activity = .falling
    }

    // MARK: Step

    public static func step(_ s: inout RoamState, dt: Double, env: RoamEnvironment, roll: () -> Double) -> [RoamEvent] {
        var events: [RoamEvent] = []
        s.speed = 0
        var ground: RoamSurface?
        switch s.activity {
        case .carried:
            return events
        case .falling:
            fly(&s, dt: dt, env: env, roll: roll, events: &events)
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
        case .sliding, .climbing, .clinging:
            guard holdWall(&s, env: env, events: &events) else { return events }
            if s.activity == .sliding {
                slide(&s, dt: dt, env: env, roll: roll, events: &events)
                return events
            }
        case .walking, .resting, .sitting, .napping:
            ground = RoamPhysics.ground(x: s.x, y: s.y, in: env.surfaces)
            guard ground != nil else {
                s.activity = .falling
                s.vx = 0
                s.vy = 0
                s.aim = nil
                s.route = []
                events.append(.startled)
                return events
            }
        }

        if env.mode == .follow {
            followStep(&s, dt: dt, env: env, ground: ground, roll: roll, events: &events)
        } else if !s.route.isEmpty {
            travel(&s, dt: dt, env: env, walk: walkSpeed(lively: env.lively), climb: climbSpeed(lively: env.lively),
                   roll: roll, events: &events)
        } else if s.wall != nil {
            wallIdle(&s, dt: dt, env: env, roll: roll, events: &events)
        } else if let ground {
            wanderStep(&s, dt: dt, env: env, ground: ground, roll: roll, events: &events)
        }
        return events
    }

    // MARK: Air and walls

    private static func fly(_ s: inout RoamState, dt: Double, env: RoamEnvironment, roll: () -> Double,
                            events: inout [RoamEvent]) {
        // A planned leap only grabs the wall it aims for; a fall or a throw grabs whatever it meets.
        let grabbable = s.aim.map { $0.wall.map { [$0] } ?? [] } ?? env.walls
        let flight = RoamPhysics.fly(RoamPhysics.Flight(x: s.x, y: s.y, vx: s.vx, vy: s.vy), dt: dt,
                                     surfaces: env.surfaces, walls: grabbable, half: env.half,
                                     minX: env.screenMinX, maxX: env.screenMaxX)
        s.x = flight.x
        s.y = flight.y
        s.vx = flight.vx
        s.vy = flight.vy
        if let wall = flight.grabbed {
            if s.aim?.wall != wall { s.route = [] }
            s.aim = nil
            grab(&s, wall: wall, half: env.half, events: &events)
        } else if let ledge = flight.landedOn {
            events.append(.landed(impact: -flight.vy))
            if s.aim?.ledge != ledge { s.route = [] }
            s.aim = nil
            s.vx = 0
            s.vy = 0
            s.activity = .resting
            // A short crouch before the next leg of a route; a longer one after a fall.
            s.timeLeft = s.route.isEmpty ? 0.5 + roll() * 0.8 : 0.12
        } else if abs(s.vx) > 1 {
            s.facing = s.vx < 0 ? -1 : 1
        }
    }

    /// Slows a slide along the wall until the pet holds still.
    private static func slide(_ s: inout RoamState, dt: Double, env: RoamEnvironment, roll: () -> Double,
                              events: inout [RoamEvent]) {
        let speed = s.vy
        let next = speed < 0 ? min(0, speed + s.grip * dt) : max(0, speed - s.grip * dt)
        s.y += (speed + next) / 2 * dt
        if let wall = s.wall { s.y = min(max(s.y, wall.minY + env.half), wall.maxY - env.half) }
        s.vy = next
        if next == 0 {
            s.activity = .clinging
            s.timeLeft = s.route.isEmpty ? 0.6 + roll() * 1.2 : 0.1
            events.append(.slid)
        }
    }

    /// Keeps hold of the wall as windows shift between snapshots; a pet whose wall went away falls.
    private static func holdWall(_ s: inout RoamState, env: RoamEnvironment, events: inout [RoamEvent]) -> Bool {
        guard let held = s.wall else {
            s.activity = .falling
            return false
        }
        let half = env.half
        if let wall = env.walls.first(where: { $0.normal == held.normal && abs($0.x - held.x) < 2
                                          && s.y >= $0.minY + half - 2 && s.y <= $0.maxY - half + 2 }) {
            s.wall = wall
            s.x = wall.x
            s.y = min(max(s.y, wall.minY + half), wall.maxY - half)
            return true
        }
        detach(&s, half: half, vx: held.normal * 20, vy: 0)
        s.route = []
        events.append(.startled)
        return false
    }

    /// Holding a wall with nowhere planned: after a breather, head somewhere or push off.
    private static func wallIdle(_ s: inout RoamState, dt: Double, env: RoamEnvironment, roll: () -> Double,
                                 events: inout [RoamEvent]) {
        s.activity = .clinging
        s.timeLeft -= dt
        guard s.timeLeft <= 0, let wall = s.wall else { return }
        let here = RoamSpot.wall(wall, y: s.y)
        let target = env.mode == .hangOut ? env.home
            : env.mode == .curious ? curiosity(env, from: here, roll: roll) : somewhere(env, from: here, roll: roll)
        if let target, let route = env.nav.route(from: here, toward: target, effort: 0.5), !route.isEmpty {
            s.route = route
            s.timeLeft = 0
        } else {
            detach(&s, half: env.half, vx: wall.normal * 90, vy: 120)
            events.append(.jumped)
        }
    }

    // MARK: Routes

    /// Follows the planned route one leg at a time.
    private static func travel(_ s: inout RoamState, dt: Double, env: RoamEnvironment, walk: Double, climb: Double,
                               roll: () -> Double, events: inout [RoamEvent]) {
        if s.activity == .resting || s.activity == .clinging, s.timeLeft > 0 {
            s.timeLeft -= dt
            return
        }
        guard let move = s.route.first else { return }
        switch move {
        case .walk(let x):
            guard s.wall == nil else { return s.route = [] }
            let dx = x - s.x
            if abs(dx) > 0.01 { s.facing = dx < 0 ? -1 : 1 }
            s.activity = .walking
            if abs(dx) <= walk * dt {
                s.x = x
                s.speed = abs(dx) / dt
                s.route.removeFirst()
            } else {
                s.x += (dx < 0 ? -1 : 1) * walk * dt
                s.speed = walk
            }
        case .climb(let y):
            guard let wall = s.wall else { return s.route = [] }
            let dy = y - s.y
            if abs(dy) > 0.01 { s.facing = climbFacing(wall, dy: dy) }
            s.activity = .climbing
            if abs(dy) <= climb * dt {
                s.y = y
                s.speed = abs(dy) / dt
                s.route.removeFirst()
            } else {
                s.y += (dy < 0 ? -1 : 1) * climb * dt
                s.speed = climb
            }
        case .transfer(let spot):
            guard env.nav.contains(spot) else { return s.route = [] }
            s.route.removeFirst()
            switch spot {
            case .wall(let wall, let y):
                s.wall = wall
                s.x = wall.x
                s.y = y
                s.activity = .clinging
                events.append(.climbed)
            case .ledge(let ledge, let x):
                s.wall = nil
                s.x = x
                s.y = ledge.y
                s.activity = .resting
            }
            s.timeLeft = 0
        case .leap(let vx, let vy, let onto):
            guard env.nav.contains(onto) else { return s.route = [] }
            s.route.removeFirst()
            if s.wall != nil {
                detach(&s, half: env.half, vx: vx, vy: vy)
            } else {
                s.vx = vx
                s.vy = vy
                s.activity = .falling
            }
            s.aim = onto
            if abs(vx) > 1 { s.facing = vx < 0 ? -1 : 1 }
            events.append(.jumped)
        }
        if s.route.isEmpty, s.activity == .walking || s.activity == .climbing {
            s.activity = s.wall == nil ? .resting : .clinging
            s.timeLeft = 0.8 + roll() * 1.5
        }
    }

    private static func here(_ s: RoamState, ground: RoamSurface?) -> RoamSpot? {
        if let wall = s.wall { return .wall(wall, y: s.y) }
        return ground.map { .ledge($0, x: s.x) }
    }

    /// A random spot on another ledge or wall that can be reached from `here`.
    private static func somewhere(_ env: RoamEnvironment, from here: RoamSpot, roll: () -> Double) -> CGPoint? {
        let spots = env.nav.reachable(from: here)
        guard !spots.isEmpty else { return nil }
        return spots[min(Int(roll() * Double(spots.count)), spots.count - 1)].point(half: env.half)
    }

    /// Where Extra Curious looks next: what has the person's attention, else a control, else anywhere.
    private static func curiosity(_ env: RoamEnvironment, from here: RoamSpot, roll: () -> Double) -> CGPoint? {
        if let attention = env.attention { return attention }
        if !env.elements.isEmpty {
            let element = env.elements[min(Int(roll() * Double(env.elements.count)), env.elements.count - 1)]
            return CGPoint(x: element.midX, y: element.maxY)
        }
        return somewhere(env, from: here, roll: roll)
    }

    // MARK: Patrol, hang out and curious

    private static func wanderStep(_ s: inout RoamState, dt: Double, env: RoamEnvironment, ground: RoamSurface,
                                   roll: () -> Double, events: inout [RoamEvent]) {
        s.timeLeft -= dt
        switch s.activity {
        case .walking:
            advance(&s, speed: walkSpeed(lively: env.lively), dt: dt, env: env, ground: ground, roll: roll, events: &events)
            if s.timeLeft <= 0, s.activity == .walking {
                s.activity = .resting
                s.timeLeft = env.mode == .curious ? 1 + roll() * 2 : 2 + roll() * 4
            }
        case .resting:
            guard s.timeLeft <= 0 else { return }
            if env.mode == .patrol, s.preferMenuBar, ground.kind != .menuBar,
               env.surfaces.contains(where: { $0.kind == .menuBar }) {
                s.activity = .fadingOut
                return
            }
            let here = RoamSpot.ledge(ground, x: s.x)
            if env.mode == .hangOut, abs(ground.y - env.home.y) > 2 || abs(s.x - env.home.x) > hangOutRadius + 1,
               let route = env.nav.route(from: here, toward: env.home, effort: 0.5), !route.isEmpty {
                s.route = route
                return
            }
            let pick = roll()
            if env.mode == .hangOut, pick < 0.2 {
                s.activity = .napping
                s.timeLeft = 20 + roll() * 20
            } else if pick < (env.mode == .hangOut ? 0.45 : env.mode == .curious ? 0.1 : 0.15) {
                s.activity = .sitting
                s.timeLeft = 5 + roll() * 7
            } else if env.mode == .curious || (env.mode == .patrol && pick < 0.15 + exploreChance),
                      let route = setOff(env, from: here, roll: roll) {
                s.route = route
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

    /// A route somewhere new: for patrol only one that leaves the current ledge, which plain walks cover.
    private static func setOff(_ env: RoamEnvironment, from here: RoamSpot, roll: () -> Double) -> [RoamMove]? {
        let target = env.mode == .curious ? curiosity(env, from: here, roll: roll) : somewhere(env, from: here, roll: roll)
        guard let target, let route = env.nav.route(from: here, toward: target, effort: 0.5), !route.isEmpty
        else { return nil }
        if env.mode == .patrol, route.allSatisfy(\.staysOnSegment) { return nil }
        return route
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
            s.speed = speed
            return
        }
        let canStepOff = env.mode != .hangOut && ground.kind != .floor && !(s.preferMenuBar && ground.kind == .menuBar)
            && (next < ground.minX || next > ground.maxX)
        if canStepOff, roll() < stepOffChance {
            s.x = next
            s.vx = s.facing * speed
            s.vy = 0
            s.aim = nil
            s.activity = .falling
            return
        }
        s.x = min(max(next, lower), upper)
        s.facing = -s.facing
        events.append(.turned)
    }

    // MARK: Follow

    private static func followStep(_ s: inout RoamState, dt: Double, env: RoamEnvironment, ground: RoamSurface?,
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
        let speed = env.lively ? livelySpeed * 1.3 : trotSpeed

        // Head for the reachable spot nearest the pointer, replanning only as often as it is worth.
        s.replanIn -= dt
        let drifted = s.routeTarget.map { hypot($0.x - pointer.x, $0.y - pointer.y) > 40 } ?? true
        if (s.replanIn <= 0 || drifted), s.activity != .sitting, s.activity != .napping {
            s.replanIn = replanEvery
            s.routeTarget = pointer
            let route = here(s, ground: ground).flatMap { env.nav.route(from: $0, toward: pointer) } ?? []
            let next = route.allSatisfy(\.staysOnSegment) ? [] : route
            if next != s.route {
                s.route = next
                s.timeLeft = 0
            }
        }
        if !s.route.isEmpty {
            travel(&s, dt: dt, env: env, walk: speed, climb: livelyClimbSpeed, roll: roll, events: &events)
            return
        }

        if let wall = s.wall {
            followOnWall(&s, dt: dt, env: env, wall: wall)
        } else if let ground {
            followOnLedge(&s, dt: dt, env: env, ground: ground, speed: speed)
        }
    }

    private static func followOnWall(_ s: inout RoamState, dt: Double, env: RoamEnvironment, wall: RoamWall) {
        let dy = env.pointer.y - s.y
        let lowest = wall.minY + env.half
        let highest = wall.maxY - env.half
        let goal = min(max(env.pointer.y - (dy < 0 ? -1 : 1) * followDistance, lowest), highest)
        let tooFar = abs(dy) > followDistance + 10 && abs(goal - s.y) > 0.5
        if tooFar || (s.activity == .climbing && abs(goal - s.y) > 0.5 && abs(dy) > followDistance) {
            let step = livelyClimbSpeed * dt
            let delta = min(max(goal - s.y, -step), step)
            s.activity = .climbing
            s.facing = climbFacing(wall, dy: delta)
            s.y += delta
            s.speed = abs(delta) / dt
        } else {
            s.activity = .clinging
            s.facing = climbFacing(wall, dy: dy)
        }
    }

    private static func followOnLedge(_ s: inout RoamState, dt: Double, env: RoamEnvironment, ground: RoamSurface,
                                      speed: Double) {
        let pointer = env.pointer
        let dx = pointer.x - s.x
        let comfort = followDistance
        let tooClose = abs(dx) < comfort - 6
        let tooFar = abs(dx) > comfort + 10

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
                s.speed = speed
            } else if pointer.y < s.y - 40, next < ground.minX || next > ground.maxX, ground.kind != .floor {
                s.x = next
                s.vx = s.facing * speed
                s.vy = 0
                s.aim = nil
                s.activity = .falling
            } else {
                s.x = min(max(next, lower), upper)
                s.activity = .resting
            }
        case .resting, .sitting, .napping:
            // Standing still, it watches the pointer.
            if abs(dx) > 2 { s.facing = dx < 0 ? -1 : 1 }
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

extension RoamMove {
    /// Walks and climbs keep to one ledge or wall; transfers and leaps change it.
    public var staysOnSegment: Bool {
        switch self {
        case .walk, .climb: true
        case .transfer, .leap: false
        }
    }
}

extension RoamSpot {
    public var ledge: RoamSurface? {
        switch self {
        case .ledge(let ledge, _): ledge
        case .wall: nil
        }
    }

    public var wall: RoamWall? {
        switch self {
        case .wall(let wall, _): wall
        case .ledge: nil
        }
    }
}
