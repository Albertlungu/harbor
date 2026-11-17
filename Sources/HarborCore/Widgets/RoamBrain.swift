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
    /// How far from the pointer a following pet keeps the middle of its body.
    public static let followDistance = 60.0
    public static let sitAfterStill = 10.0
    public static let napAfterStill = 30.0
    public static let fadeTime = 0.25
    /// Chance of stepping off a ledge's end rather than turning around, while on patrol.
    public static let stepOffChance = 0.35
    /// Chance, when a patrolling pet finishes a rest, that it sets off for another ledge, wall or ceiling;
    /// higher on the floor, where there is least to see.
    public static let exploreChance = 0.3
    public static let floorExploreChance = 0.55
    /// A pet let go with its side this close to a wall catches hold of it.
    public static let grabReach = 10.0
    /// Slide speed when put down against a wall, so it always slips a little before it holds.
    public static let dropSlide = 150.0
    /// Slower than this the pet was put down rather than thrown.
    public static let throwThreshold = 150.0
    /// A tumbling pet flying sideways faster than this bounces off walls and ceilings instead of catching them.
    public static let tumbleGrabSpeed = 600.0
    /// Fastest tumble, in degrees a second.
    public static let maxSpin = 900.0
    /// How long a following pet crouches before it springs off its surface.
    public static let detachTime = 0.28
    /// How fast it springs away from the surface.
    public static let popSpeed = 260.0
    /// Top speed and acceleration while swimming through the air after the pointer.
    public static let floatSpeed = 420.0
    public static let livelyFloatSpeed = 540.0
    public static let floatAccel = 1600.0
    /// Spring stiffness toward the follow point, per second squared; damping is set for no overshoot.
    public static let floatStiffness = 16.0
    private static let pointerMoved = 3.0

    public static func walkSpeed(lively: Bool) -> Double { lively ? livelySpeed : calmSpeed }
    public static func climbSpeed(lively: Bool) -> Double { lively ? livelyClimbSpeed : calmClimbSpeed }

    /// Quiet mode keeps the pet in place.
    public static func effectiveMode(_ mode: RoamMode, quiet: Bool) -> RoamMode { quiet ? .hangOut : mode }

    /// Seconds between window snapshots, or nil when none are needed.
    public static func snapshotInterval(_ activity: RoamActivity) -> Double? {
        switch activity {
        case .walking, .falling, .carried, .fadingOut, .fadingIn, .climbing, .sliding, .detaching: 0.5
        case .resting, .sitting, .clinging, .floating: 2
        case .napping: nil
        }
    }

    /// Seconds between brain steps while still; a moving pet steps on every display refresh instead.
    public static func idleInterval(_ activity: RoamActivity) -> Double { activity == .napping ? 1 : 0.5 }

    /// Whether the pet needs a step on every display refresh: it is moving, or a route is under way, where
    /// waiting for the slow idle beat would stall it between legs.
    public static func needsFrames(_ s: RoamState) -> Bool { s.activity.isMoving || !s.route.isEmpty }

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

    /// The middle of the body: above the feet, out from the wall it holds, or below the ceiling it hangs from.
    public static func middle(_ s: RoamState, half: Double) -> CGPoint {
        if let wall = s.wall, s.activity.isOnWall { return CGPoint(x: wall.x + wall.normal * half, y: s.y) }
        if s.ceiling != nil, s.activity.isOnWall { return CGPoint(x: s.x, y: s.y - half) }
        return CGPoint(x: s.x, y: s.y + half)
    }

    /// Which way the pet faces, in its own turned frame, to look `dy` along a wall.
    public static func climbFacing(_ wall: RoamWall, dy: Double) -> Double { dy >= 0 ? -wall.normal : wall.normal }

    /// Which way the pet faces, in its own upside-down frame, to look `dx` along a ceiling.
    public static func hangFacing(dx: Double) -> Double { dx < 0 ? 1 : -1 }

    // MARK: Release

    /// Let go after being carried. Put down beside a wall, the pet grabs it and slides a little before it
    /// holds; let go while the pointer is moving fast, it flies off with that velocity, tumbling.
    public static func release(_ s: inout RoamState, velocity: CGVector, env: RoamEnvironment) -> [RoamEvent] {
        var events: [RoamEvent] = []
        s.route = []
        s.routeTarget = nil
        s.aim = nil
        s.wall = nil
        s.ceiling = nil
        s.spin = 0
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
        s.tumbling = speed >= throwThreshold
        s.activity = .falling
        if abs(vx) > 1 { s.facing = vx < 0 ? -1 : 1 }
        if s.tumbling { events.append(.jumped) }
        return events
    }

    /// A push from outside, such as weather. A pet holding on, or standing, only lets go when the push is
    /// strong enough; one already in the air takes all of it.
    public static func nudge(_ s: inout RoamState, impulse: CGVector, env: RoamEnvironment) -> [RoamEvent] {
        let push = hypot(Double(impulse.dx), Double(impulse.dy))
        switch s.activity {
        case .falling, .floating:
            s.vx += Double(impulse.dx)
            s.vy += Double(impulse.dy)
            return []
        case .carried, .fadingOut, .fadingIn, .detaching:
            return []
        case .walking, .resting, .sitting, .napping, .climbing, .sliding, .clinging:
            guard push >= throwThreshold else { return [] }
            letGo(&s, half: env.half, vx: Double(impulse.dx), vy: max(Double(impulse.dy), 0))
            s.route = []
            return [.startled]
        }
    }

    /// Takes hold of `wall` at the current height, gripping hard enough to stop before its bottom.
    private static func grab(_ s: inout RoamState, wall: RoamWall, half: Double, events: inout [RoamEvent]) {
        let room = max(s.y - (wall.minY + half), 1)
        s.wall = wall
        s.ceiling = nil
        s.x = wall.x
        s.vx = 0
        s.tumbling = false
        s.spin = 0
        s.grip = s.vy < 0 ? max(RoamPhysics.slideGrip, s.vy * s.vy / (2 * room))
            : RoamPhysics.slideGrip + RoamPhysics.gravity
        s.activity = .sliding
        events.append(.grabbedWall)
    }

    /// Lets go of whatever it stands on or holds, moving off with the given velocity; its feet end up where
    /// they would be standing upright in the air.
    private static func letGo(_ s: inout RoamState, half: Double, vx: Double, vy: Double) {
        if let wall = s.wall {
            s.x = wall.x + wall.normal * half
            s.y -= half
        } else if s.ceiling != nil {
            s.y -= half * 2
        }
        s.wall = nil
        s.ceiling = nil
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
        case .detaching:
            detachStep(&s, dt: dt, env: env, events: &events)
            return events
        case .floating:
            guard env.mode == .follow else {
                // Out of follow mode, gravity takes over from wherever it is.
                s.activity = .falling
                s.aim = nil
                return events
            }
            notePointer(&s, dt: dt, env: env, events: &events)
            floatStep(&s, dt: dt, env: env)
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
            let held = s.ceiling != nil ? holdCeiling(&s, env: env, events: &events)
                : holdWall(&s, env: env, events: &events)
            guard held else { return events }
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
        } else if s.wall != nil || s.ceiling != nil {
            hangIdle(&s, dt: dt, env: env, roll: roll, events: &events)
        } else if let ground {
            wanderStep(&s, dt: dt, env: env, ground: ground, roll: roll, events: &events)
        }
        return events
    }

    // MARK: Air, walls and ceilings

    private static func fly(_ s: inout RoamState, dt: Double, env: RoamEnvironment, roll: () -> Double,
                            events: inout [RoamEvent]) {
        // A planned leap only catches what it aims for; a fall catches whatever it meets, and a hard throw
        // nothing until it slows down.
        let wild = s.tumbling && abs(s.vx) > tumbleGrabSpeed
        let walls = s.aim.map { $0.wall.map { [$0] } ?? [] } ?? (wild ? [] : env.walls)
        let ceilings = s.aim.map { $0.ceiling.map { [$0] } ?? [] } ?? (wild ? [] : env.ceilings)
        let flight = RoamPhysics.fly(RoamPhysics.Flight(x: s.x, y: s.y, vx: s.vx, vy: s.vy), dt: dt,
                                     surfaces: env.surfaces, walls: walls, ceilings: ceilings, half: env.half,
                                     minX: env.screenMinX, maxX: env.screenMaxX, maxY: env.screenMaxY)
        s.x = flight.x
        s.y = flight.y
        s.vx = flight.vx
        s.vy = flight.vy
        if s.tumbling {
            // It rolls the way it travels, as if it had been bowled.
            let rate = min(max(s.vx * 1.2, -maxSpin), maxSpin)
            s.spin = (s.spin + rate * dt).truncatingRemainder(dividingBy: 360)
        }
        if let wall = flight.grabbed {
            if s.aim?.wall != wall { s.route = [] }
            s.aim = nil
            grab(&s, wall: wall, half: env.half, events: &events)
        } else if let ceiling = flight.grabbedCeiling {
            if s.aim?.ceiling != ceiling { s.route = [] }
            s.aim = nil
            s.ceiling = ceiling
            s.wall = nil
            s.tumbling = false
            s.spin = 0
            s.activity = .clinging
            s.timeLeft = s.route.isEmpty ? 0.6 + roll() * 1.2 : 0.1
            events.append(.grabbedWall)
        } else if let ledge = flight.landedOn {
            events.append(.landed(impact: -flight.vy))
            if s.aim?.ledge != ledge { s.route = [] }
            s.aim = nil
            s.vx = 0
            s.vy = 0
            s.tumbling = false
            s.spin = 0
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
        letGo(&s, half: half, vx: held.normal * 20, vy: 0)
        s.route = []
        events.append(.startled)
        return false
    }

    /// Keeps hold of the ceiling as windows shift; a pet whose ceiling went away falls.
    private static func holdCeiling(_ s: inout RoamState, env: RoamEnvironment, events: inout [RoamEvent]) -> Bool {
        guard let held = s.ceiling else { return false }
        if let ceiling = env.ceilings.first(where: { abs($0.y - held.y) < 2 && $0.contains(x: s.x) }) {
            s.ceiling = ceiling
            s.y = ceiling.y
            return true
        }
        letGo(&s, half: env.half, vx: 0, vy: 0)
        s.route = []
        events.append(.startled)
        return false
    }

    /// Holding a wall or ceiling with nowhere planned: after a breather, head somewhere or let go.
    private static func hangIdle(_ s: inout RoamState, dt: Double, env: RoamEnvironment, roll: () -> Double,
                                 events: inout [RoamEvent]) {
        s.activity = .clinging
        s.timeLeft -= dt
        guard s.timeLeft <= 0, let here = here(s, ground: nil) else { return }
        let target = env.mode == .hangOut ? env.home
            : env.mode == .curious ? curiosity(env, from: here, roll: roll) : somewhere(env, from: here, roll: roll)
        if let target, let route = env.nav.route(from: here, toward: target, effort: 0.5), !route.isEmpty {
            s.route = route
            s.timeLeft = 0
        } else if let wall = s.wall {
            letGo(&s, half: env.half, vx: wall.normal * 90, vy: 120)
            events.append(.jumped)
        } else {
            letGo(&s, half: env.half, vx: 0, vy: 0)
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
            let hanging = s.ceiling != nil
            let pace = hanging ? climb : walk
            let dx = x - s.x
            if abs(dx) > 0.01 { s.facing = hanging ? hangFacing(dx: dx) : (dx < 0 ? -1 : 1) }
            s.activity = hanging ? .climbing : .walking
            if abs(dx) <= pace * dt {
                s.x = x
                s.speed = abs(dx) / dt
                s.route.removeFirst()
            } else {
                s.x += (dx < 0 ? -1 : 1) * pace * dt
                s.speed = pace
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
                s.ceiling = nil
                s.x = wall.x
                s.y = y
                s.activity = .clinging
                events.append(.climbed)
            case .ceiling(let ceiling, let x):
                s.ceiling = ceiling
                s.wall = nil
                s.x = x
                s.y = ceiling.y
                s.activity = .clinging
                events.append(.climbed)
            case .ledge(let ledge, let x):
                s.wall = nil
                s.ceiling = nil
                s.x = x
                s.y = ledge.y
                s.activity = .resting
            }
            s.timeLeft = 0
        case .leap(let vx, let vy, let onto):
            guard env.nav.contains(onto) else { return s.route = [] }
            s.route.removeFirst()
            letGo(&s, half: env.half, vx: vx, vy: vy)
            s.aim = onto
            if abs(vx) > 1 { s.facing = vx < 0 ? -1 : 1 }
            events.append(.jumped)
        }
        if s.route.isEmpty, s.activity == .walking || s.activity == .climbing {
            s.activity = s.wall == nil && s.ceiling == nil ? .resting : .clinging
            s.timeLeft = 0.8 + roll() * 1.5
        }
    }

    private static func here(_ s: RoamState, ground: RoamSurface?) -> RoamSpot? {
        if let wall = s.wall { return .wall(wall, y: s.y) }
        if let ceiling = s.ceiling { return .ceiling(ceiling, x: s.x) }
        return ground.map { .ledge($0, x: s.x) }
    }

    /// A random spot on another ledge, wall or ceiling that can be reached from `here`.
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
            let explore = ground.kind == .floor ? floorExploreChance : exploreChance
            if env.mode == .hangOut, pick < 0.2 {
                s.activity = .napping
                s.timeLeft = 20 + roll() * 20
            } else if pick < (env.mode == .hangOut ? 0.45 : env.mode == .curious ? 0.1 : 0.15) {
                s.activity = .sitting
                s.timeLeft = 5 + roll() * 7
            } else if env.mode == .curious
                        || (env.mode == .patrol && pick < 0.15 + explore && !(s.preferMenuBar && ground.kind == .menuBar)),
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

    /// Tracks how long the pointer has been still, waking a napping pet when it moves.
    private static func notePointer(_ s: inout RoamState, dt: Double, env: RoamEnvironment, events: inout [RoamEvent]) {
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
    }

    /// On a surface in follow mode: while the pointer is busy, gather up and spring off into the air;
    /// once it has been still a while, watch it, then sit, then nap.
    private static func followStep(_ s: inout RoamState, dt: Double, env: RoamEnvironment, ground: RoamSurface?,
                                   roll: () -> Double, events: inout [RoamEvent]) {
        notePointer(&s, dt: dt, env: env, events: &events)
        s.route = []
        // Whatever it was about to do, it is ready to follow within half a second.
        s.timeLeft = min(s.timeLeft, 0.5) - dt
        let middle = middle(s, half: env.half)
        let dx = env.pointer.x - middle.x
        if s.pointerStill < sitAfterStill {
            if s.timeLeft <= 0 {
                s.activity = .detaching
                s.timeLeft = detachTime
            } else if s.activity == .walking || s.activity == .climbing {
                s.activity = s.wall == nil && s.ceiling == nil ? .resting : .clinging
            }
            return
        }
        // Standing still, it watches the pointer.
        if let wall = s.wall {
            s.facing = climbFacing(wall, dy: env.pointer.y - middle.y)
            s.activity = .clinging
        } else if s.ceiling != nil {
            if abs(dx) > 2 { s.facing = hangFacing(dx: dx) }
            s.activity = .clinging
        } else if ground != nil {
            if abs(dx) > 2 { s.facing = dx < 0 ? -1 : 1 }
            if s.pointerStill >= napAfterStill {
                s.activity = .napping
            } else if s.activity == .resting || s.activity == .walking {
                s.activity = .sitting
            }
        }
    }

    /// The crouch before springing off: when it ends, the pet pushes away from its surface into free flight.
    private static func detachStep(_ s: inout RoamState, dt: Double, env: RoamEnvironment, events: inout [RoamEvent]) {
        guard env.mode == .follow else {
            s.activity = s.wall == nil && s.ceiling == nil ? .resting : .clinging
            s.timeLeft = 0.5
            return
        }
        s.timeLeft -= dt
        guard s.timeLeft <= 0 else { return }
        let toward = env.pointer.x - middle(s, half: env.half).x
        let drift = min(max(toward, -1), 1) * 60
        if let wall = s.wall {
            letGo(&s, half: env.half, vx: wall.normal * popSpeed, vy: popSpeed * 0.3)
        } else if s.ceiling != nil {
            letGo(&s, half: env.half, vx: drift, vy: -popSpeed * 0.5)
        } else {
            letGo(&s, half: env.half, vx: drift, vy: popSpeed)
        }
        s.activity = .floating
        s.tumbling = false
        s.spin = 0
        s.route = []
        events.append(.jumped)
    }

    /// Where a following pet wants its middle: `followDistance` from the pointer, on the side it is already on.
    public static func followPoint(middle: CGPoint, pointer: CGPoint, facing: Double) -> CGPoint {
        var dx = middle.x - pointer.x
        var dy = middle.y - pointer.y
        var length = hypot(dx, dy)
        if length < 1 {
            dx = -facing
            dy = 0.4
            length = hypot(dx, dy)
        }
        return CGPoint(x: pointer.x + dx / length * followDistance, y: pointer.y + dy / length * followDistance)
    }

    /// Swims toward the follow point on a critically damped spring, within the pet's top speed and
    /// acceleration, kept inside the screen. With the pointer long still it lets gravity take it down.
    private static func floatStep(_ s: inout RoamState, dt: Double, env: RoamEnvironment) {
        if s.pointerStill >= napAfterStill {
            s.activity = .falling
            s.aim = nil
            return
        }
        let half = env.half
        let middle = CGPoint(x: s.x, y: s.y + half)
        let goal = followPoint(middle: middle, pointer: env.pointer, facing: s.facing)
        let k = floatStiffness
        let damping = 2 * k.squareRoot()
        var ax = k * (goal.x - middle.x) - damping * s.vx
        var ay = k * (goal.y - middle.y) - damping * s.vy
        let accel = hypot(ax, ay)
        if accel > floatAccel {
            ax *= floatAccel / accel
            ay *= floatAccel / accel
        }
        s.vx += ax * dt
        s.vy += ay * dt
        let top = env.lively ? livelyFloatSpeed : floatSpeed
        let speed = hypot(s.vx, s.vy)
        if speed > top {
            s.vx *= top / speed
            s.vy *= top / speed
        }
        s.x += s.vx * dt
        s.y += s.vy * dt
        let lowX = env.screenMinX + half
        let highX = env.screenMaxX - half
        if s.x < lowX || s.x > highX {
            s.x = min(max(s.x, lowX), highX)
            s.vx = 0
        }
        let lowY = env.screenMinY
        let highY = env.screenMaxY - half * 2
        if s.y < lowY || s.y > highY {
            s.y = min(max(s.y, lowY), highY)
            s.vy = 0
        }
        s.speed = hypot(s.vx, s.vy)
        let toward = env.pointer.x - s.x
        if abs(toward) > 4 { s.facing = toward < 0 ? -1 : 1 }
    }
}

extension RoamMove {
    /// Walks and climbs keep to one ledge, wall or ceiling; transfers and leaps change it.
    public var staysOnSegment: Bool {
        switch self {
        case .walk, .climb: true
        case .transfer, .leap: false
        }
    }
}

extension RoamSpot {
    public var ledge: RoamSurface? {
        if case .ledge(let ledge, _) = self { return ledge }
        return nil
    }

    public var wall: RoamWall? {
        if case .wall(let wall, _) = self { return wall }
        return nil
    }

    public var ceiling: RoamSurface? {
        if case .ceiling(let ceiling, _) = self { return ceiling }
        return nil
    }
}
