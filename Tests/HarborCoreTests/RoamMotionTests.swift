import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

/// Walls, routes, throws and grips.
@Suite struct RoamMotionTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let menuBar = 24.0

    private func environment(_ windows: [RoamWindow], mode: RoamMode = .patrol, pointer: CGPoint = .zero,
                             home: CGPoint = CGPoint(x: 500, y: 0), attention: CGPoint? = nil) -> RoamEnvironment {
        RoamEnvironment(surfaces: RoamSurfaces.build(screen: screen, menuBarHeight: menuBar, windows: windows, docks: [],
                                                     walkOnWindows: true),
                        walls: RoamSurfaces.walls(screen: screen, menuBarHeight: menuBar, windows: windows,
                                                  walkOnWindows: true),
                        mode: mode, home: home, pointer: pointer, lively: false, screenMinX: 0, screenMaxX: 1000,
                        attention: attention)
    }

    /// Runs the brain at 120 steps a second, the display rate it now moves at.
    @discardableResult
    private func run(_ state: inout RoamState, seconds: Double, env: RoamEnvironment, dice: Double = 0.5,
                     until done: (RoamState) -> Bool = { _ in false }) -> [RoamEvent] {
        var events: [RoamEvent] = []
        for _ in 0..<Int(seconds * 120) {
            events += RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: { dice })
            if done(state) { break }
        }
        return events
    }

    private func standing(_ x: Double, _ y: Double) -> RoamState {
        var state = RoamState(x: x, y: y)
        state.activity = .resting
        state.timeLeft = 100
        return state
    }

    // MARK: Walls

    @Test func wallsAreScreenSidesAndUncoveredWindowEdges() {
        let front = RoamWindow(frame: CGRect(x: 250, y: 300, width: 200, height: 100))
        let back = RoamWindow(frame: CGRect(x: 300, y: 100, width: 400, height: 400))
        let walls = RoamSurfaces.walls(screen: screen, menuBarHeight: menuBar, windows: [front, back], walkOnWindows: true)
        #expect(walls.contains(RoamWall(kind: .screen, x: 0, minY: 0, maxY: 776, normal: 1)))
        #expect(walls.contains(RoamWall(kind: .screen, x: 1000, minY: 0, maxY: 776, normal: -1)))
        // The back window's left edge is covered by the front window between 300 and 400.
        let backLeft = walls.filter { $0.kind == .window && $0.x == 300 }
        #expect(backLeft.count == 2)
        #expect(backLeft.contains { $0.minY == 100 && $0.maxY == 300 })
        #expect(backLeft.contains { $0.minY == 400 && $0.maxY == 500 })
        #expect(walls.contains { $0.x == 700 && $0.normal == 1 && $0.minY == 100 && $0.maxY == 500 })
        let none = RoamSurfaces.walls(screen: screen, menuBarHeight: menuBar, windows: [front], walkOnWindows: false)
        #expect(none.allSatisfy { $0.kind == .screen })
    }

    @Test func droppedBesideAWallItSlidesThenGrips() {
        let window = RoamWindow(frame: CGRect(x: 300, y: 200, width: 400, height: 300))
        let env = environment([window])
        // Let go with its side 4 pt from the window's left edge.
        var state = RoamState(x: 300 - 16 - 4, y: 420)
        let grabbed = RoamBrain.release(&state, velocity: .zero, env: env)
        #expect(grabbed == [.grabbedWall])
        #expect(state.activity == .sliding)
        let middle = state.y
        let events = run(&state, seconds: 2, env: env) { $0.activity == .clinging }
        #expect(events.contains(.slid))
        #expect(state.activity == .clinging)
        #expect(state.y < middle - 3)
        #expect(state.y > middle - 30)
        #expect(state.x == 300)
    }

    @Test func aFastSlideStillGripsBeforeTheBottom() {
        let window = RoamWindow(frame: CGRect(x: 300, y: 200, width: 400, height: 300))
        let env = environment([window])
        // Flung at the wall moving down fast, meeting it just above the bottom.
        var state = RoamState(x: 270, y: 238)
        state.activity = .falling
        state.vx = 600
        state.vy = -600
        let events = run(&state, seconds: 2, env: env) { $0.activity == .clinging || $0.activity == .resting }
        #expect(events.contains(.grabbedWall))
        #expect(state.activity == .clinging)
        #expect(state.y >= 200 + 16)
        #expect(state.wall?.x == 300)
    }

    @Test func farBelowTheBottomItSlipsPast() {
        let window = RoamWindow(frame: CGRect(x: 300, y: 200, width: 400, height: 300))
        let env = environment([window])
        var state = RoamState(x: 270, y: 150)
        state.activity = .falling
        state.vx = 300
        let events = run(&state, seconds: 2, env: env) { $0.activity == .resting }
        #expect(!events.contains(.grabbedWall))
        #expect(state.y == 0)
    }

    // MARK: Routes

    @Test func climbsAWallToReachALedgeTooHighToJump() {
        let window = RoamWindow(frame: CGRect(x: 400, y: 0, width: 300, height: 400))
        let env = environment([window])
        let floor = env.surfaces.first { $0.kind == .floor }!
        let route = env.nav.route(from: .ledge(floor, x: 100), toward: CGPoint(x: 550, y: 400))
        #expect(route?.contains { if case .climb = $0 { true } else { false } } == true)
        #expect(route?.contains { if case .transfer(.ledge(let ledge, _)) = $0 { ledge.y == 400 } else { false } } == true)
        #expect(route?.contains { if case .leap = $0 { true } else { false } } == false)
    }

    @Test func jumpsOntoALowLedge() {
        let window = RoamWindow(frame: CGRect(x: 400, y: 0, width: 300, height: 100))
        let env = environment([window])
        let floor = env.surfaces.first { $0.kind == .floor }!
        let route = env.nav.route(from: .ledge(floor, x: 100), toward: CGPoint(x: 550, y: 100)) ?? []
        #expect(route.contains { if case .leap(_, _, .ledge(let ledge, _)) = $0 { ledge.y == 100 } else { false } })
        #expect(!route.contains { if case .climb = $0 { true } else { false } })
    }

    @Test func plannedLeapsLandWhereThePlanSays() {
        let windows = [RoamWindow(frame: CGRect(x: 400, y: 0, width: 300, height: 100)),
                       RoamWindow(frame: CGRect(x: 120, y: 160, width: 200, height: 60))]
        var state = standing(100, 0)
        state.timeLeft = 0
        let env = environment(windows, mode: .curious, attention: CGPoint(x: 550, y: 110))
        let events = run(&state, seconds: 15, env: env) { $0.y == 100 && $0.activity == .resting }
        #expect(events.contains(.jumped))
        #expect(state.y == 100)
    }

    @Test func aBigLeapReachesALedgeSixBodiesUp() {
        let window = RoamWindow(frame: CGRect(x: 500, y: 0, width: 300, height: 200))
        let env = environment([RoamWindow(frame: CGRect(x: 500, y: 200, width: 300, height: 20)), window])
        let floor = env.surfaces.first { $0.kind == .floor }!
        let route = env.nav.route(from: .ledge(floor, x: 200), toward: CGPoint(x: 650, y: 220)) ?? []
        #expect(route.contains { if case .leap(_, _, .ledge(let ledge, _)) = $0 { ledge.y == 220 } else { false } })
    }

    // MARK: Follow

    @Test func followCrouchesThenSpringsOffIntoTheAir() {
        let env = environment([], mode: .follow, pointer: CGPoint(x: 600, y: 400))
        var state = standing(300, 0)
        state.timeLeft = 0
        var crouched = 0.0
        var sprang = false
        for _ in 0..<(120 * 2) {
            let events = RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: { 0.5 })
            if state.activity == .detaching { crouched += 1.0 / 120 }
            if state.activity == .floating, !sprang {
                sprang = true
                #expect(events.contains(.jumped))
                #expect(state.vy > 100)
            }
        }
        #expect(abs(crouched - RoamBrain.detachTime) < 0.02)
        #expect(sprang)
        #expect(state.y > 100)
    }

    @Test func floatingHasNoGravityAndStaysOnScreen() {
        var env = environment([], mode: .follow, pointer: CGPoint(x: 990, y: 790))
        env.screenMinY = 0
        env.screenMaxY = 800
        var state = RoamState(x: 500, y: 300)
        state.activity = .floating
        state.lastPointer = env.pointer
        var fastest = 0.0
        var hardest = 0.0
        var previous = (vx: 0.0, vy: 0.0)
        for _ in 0..<(120 * 4) {
            _ = RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: { 0.5 })
            fastest = max(fastest, hypot(state.vx, state.vy))
            hardest = max(hardest, hypot(state.vx - previous.vx, state.vy - previous.vy) * 120)
            previous = (state.vx, state.vy)
            #expect(state.x >= 16 && state.x <= 984)
            #expect(state.y >= 0 && state.y <= 768)
        }
        #expect(state.activity == .floating)
        #expect(fastest <= RoamBrain.floatSpeed + 0.001)
        #expect(hardest <= RoamBrain.floatAccel + 1)
        // Hovering in place with the pointer still, it neither sinks nor drifts.
        let parked = (state.x, state.y)
        run(&state, seconds: 1, env: env)
        #expect(abs(state.x - parked.0) < 1 && abs(state.y - parked.1) < 1)
    }

    @Test func theSpringArrivesWithoutOvershoot() {
        let env = environment([], mode: .follow, pointer: CGPoint(x: 700, y: 300))
        var state = RoamState(x: 200, y: 300)
        state.activity = .floating
        state.lastPointer = env.pointer
        var closest = Double.infinity
        for _ in 0..<(120 * 6) {
            _ = RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: { 0.5 })
            closest = min(closest, hypot(700 - state.x, 300 - state.y - 16))
        }
        #expect(closest > RoamBrain.followDistance - 2)
        #expect(abs(hypot(700 - state.x, 300 - state.y - 16) - RoamBrain.followDistance) < 1)
    }

    @Test func leavingFollowFallsAndLands() {
        var env = environment([], mode: .follow, pointer: CGPoint(x: 600, y: 400))
        var state = RoamState(x: 500, y: 300)
        state.activity = .floating
        state.vx = 120
        env.mode = .patrol
        let events = run(&state, seconds: 3, env: env) { $0.activity != .falling && $0.activity != .floating }
        #expect(events.contains { if case .landed = $0 { true } else { false } })
        #expect(state.y == 0)
        #expect(state.x > 500)
    }

    @Test func aFollowerOnAWallSpringsAwayFromIt() {
        let window = RoamWindow(frame: CGRect(x: 400, y: 0, width: 300, height: 400))
        let env = environment([window], mode: .follow, pointer: CGPoint(x: 200, y: 300))
        let wall = env.walls.first { $0.x == 400 }!
        var state = RoamState(x: 400, y: 200)
        state.wall = wall
        state.activity = .clinging
        run(&state, seconds: 1, env: env) { $0.activity == .floating }
        #expect(state.activity == .floating)
        #expect(state.vx * wall.normal > 0)
        #expect(state.wall == nil)
    }

    // MARK: Facing

    @Test func facingFollowsTheWayItMoves() {
        let windows = [RoamWindow(frame: CGRect(x: 400, y: 0, width: 300, height: 120)),
                       RoamWindow(frame: CGRect(x: 100, y: 200, width: 200, height: 300))]
        let env = environment(windows)
        var state = standing(500, 120)
        state.timeLeft = 0
        var seed: UInt64 = 3
        var mismatches = 0
        var walked = 0
        for _ in 0..<(120 * 240) {
            let before = state
            let events = RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            })
            // The step that reaches a ledge's end also turns around.
            guard !events.contains(.turned), state.activity == .walking,
                  before.activity == .walking || before.activity == .resting,
                  before.wall == nil, abs(state.x - before.x) > 0.01 else { continue }
            walked += 1
            if (state.x - before.x).sign != (state.facing < 0 ? .minus : .plus) { mismatches += 1 }
        }
        #expect(walked > 1000)
        #expect(mismatches == 0)
    }

    @Test func aFloatingFollowerFacesThePointer() {
        var env = environment([], mode: .follow, pointer: CGPoint(x: 700, y: 300))
        var state = RoamState(x: 540, y: 300)
        state.activity = .floating
        state.facing = -1
        run(&state, seconds: 0.5, env: env)
        #expect(state.facing == 1)
        env.pointer = CGPoint(x: 300, y: 300)
        run(&state, seconds: 1, env: env)
        #expect(state.facing == -1)
    }

    @Test func speedIsReportedOnlyWhileTravelling() {
        let env = environment([])
        var state = RoamState(x: 300, y: 0)
        state.activity = .walking
        state.timeLeft = 100
        run(&state, seconds: 0.5, env: env)
        #expect(abs(state.speed - RoamBrain.calmSpeed) < 0.001)
        var still = standing(300, 0)
        run(&still, seconds: 0.5, env: env)
        #expect(still.speed == 0)
    }

    // MARK: Throwing

    @Test func aThrowCarriesMomentumIntoAnArc() {
        let env = environment([])
        var thrown = RoamState(x: 200, y: 300)
        _ = RoamBrain.release(&thrown, velocity: CGVector(dx: 500, dy: 400), env: env)
        #expect(thrown.activity == .falling)
        #expect(thrown.facing == 1)
        var peak = thrown.y
        let events = run(&thrown, seconds: 4, env: env) { state in
            peak = max(peak, state.y)
            return state.activity != .falling
        }
        #expect(peak > 340)
        #expect(thrown.x > 500)
        #expect(thrown.y == 0)
        let impact = events.compactMap { if case .landed(let value) = $0 { value } else { nil } }.first ?? 0
        #expect(impact > 900)

        var dropped = RoamState(x: 200, y: 300)
        _ = RoamBrain.release(&dropped, velocity: CGVector(dx: 60, dy: 0), env: env)
        run(&dropped, seconds: 4, env: env) { $0.activity != .falling }
        #expect(dropped.x == 200)
    }

    @Test func aGentleThrowIntoAWallIsCaught() {
        let window = RoamWindow(frame: CGRect(x: 600, y: 100, width: 300, height: 500))
        let env = environment([window])
        var state = RoamState(x: 300, y: 400)
        _ = RoamBrain.release(&state, velocity: CGVector(dx: 480, dy: 200), env: env)
        let events = run(&state, seconds: 3, env: env) { $0.activity == .clinging }
        #expect(events.contains(.grabbedWall))
        #expect(state.wall?.x == 600)
        #expect(state.y >= 116)
        #expect(!state.tumbling)
        #expect(state.spin == 0)
    }

    @Test func aHardThrowTumblesAndBouncesOffTheScreenEdges() {
        var env = environment([])
        env.screenMaxY = 800
        var state = RoamState(x: 700, y: 400)
        let launched = RoamBrain.release(&state, velocity: CGVector(dx: 3000, dy: 1600), env: env)
        #expect(launched == [.jumped])
        #expect(state.tumbling)
        #expect(hypot(state.vx, state.vy) <= RoamPhysics.maxThrowSpeed + 0.001)
        var bouncedSide = false
        var bouncedTop = false
        var spun = 0.0
        var last = state.spin
        let events = run(&state, seconds: 6, env: env) { state in
            if state.vx < 0 { bouncedSide = true }
            if state.y + 32 >= 799.9 { bouncedTop = true }
            spun += abs(RoamPose.delta(from: last, to: state.spin))
            last = state.spin
            #expect(state.x <= 1000 && state.x >= 0)
            #expect(state.y + 32 <= 800.001)
            return state.activity != .falling
        }
        #expect(bouncedSide)
        #expect(bouncedTop)
        #expect(spun > 180)
        #expect(events.contains { if case .landed = $0 { true } else { false } })
        #expect(state.y == 0)
        #expect(!state.tumbling)
        #expect(state.spin == 0)
        #expect(RoamPose.angle(state) == 0)
    }

    // MARK: Modes

    @Test func patrolSometimesClimbsAndJumps() {
        let windows = [RoamWindow(frame: CGRect(x: 400, y: 0, width: 300, height: 120)),
                       RoamWindow(frame: CGRect(x: 100, y: 200, width: 200, height: 300))]
        let env = environment(windows)
        var state = standing(500, 120)
        state.timeLeft = 0
        var seed: UInt64 = 11
        var events: [RoamEvent] = []
        var surfaces: Set<Double> = []
        for _ in 0..<(120 * 600) {
            events += RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            })
            if state.activity == .resting, state.wall == nil { surfaces.insert(state.y) }
        }
        #expect(events.contains(.climbed) || events.contains(.jumped))
        #expect(surfaces.count >= 2)
    }

    @Test func extraCuriousHeadsForTheAttentionPoint() {
        let window = RoamWindow(frame: CGRect(x: 400, y: 0, width: 300, height: 100))
        let env = environment([window], mode: .curious, attention: CGPoint(x: 600, y: 110))
        var state = standing(100, 0)
        state.timeLeft = 0
        run(&state, seconds: 15, env: env) { $0.y == 100 && $0.activity == .resting }
        #expect(state.y == 100)
        #expect(RoamMode.curious.title == "Extra Curious")
        #expect(RoamBrain.effectiveMode(.curious, quiet: true) == .hangOut)
    }

    @Test func elementTopsAreLedgesUnlessCovered() {
        let front = RoamWindow(frame: CGRect(x: 500, y: 100, width: 300, height: 400))
        let back = RoamWindow(frame: CGRect(x: 100, y: 100, width: 600, height: 500))
        let button = CGRect(x: 200, y: 300, width: 400, height: 30)
        let list = RoamSurfaces.build(screen: screen, menuBarHeight: menuBar, windows: [front, back], docks: [],
                                      walkOnWindows: true, elements: [button])
        let tops = list.filter { $0.kind == .element }
        #expect(tops == [RoamSurface(kind: .element, y: 330, minX: 200, maxX: 500)])
    }

    @Test func hitTestTurnsWithThePetOnAWall() {
        let middle = CGPoint(x: 100, y: 100)
        #expect(RoamBrain.hits(point: CGPoint(x: 115, y: 100), middle: middle, unit: 32, sideways: true))
        #expect(!RoamBrain.hits(point: CGPoint(x: 100, y: 115), middle: middle, unit: 32, sideways: true))
    }

    @Test func navigationBuildsQuicklyForABusyDesktop() {
        var windows: [RoamWindow] = []
        for index in 0..<24 {
            let x = Double(index % 6) * 150 + 20
            let y = Double(index / 6) * 170 + 30
            windows.append(RoamWindow(frame: CGRect(x: x, y: y, width: 220, height: 140)))
        }
        let start = Date()
        let env = environment(windows)
        #expect(env.nav.ledges.count > 10)
        #expect(Date().timeIntervalSince(start) < 2)
        let floor = env.surfaces.first { $0.kind == .floor }!
        #expect(env.nav.reachable(from: .ledge(floor, x: 500)).count > 10)
    }
}
