import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

/// Ceilings, corner swings and the drawn angle.
@Suite struct RoamCeilingTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let menuBar = 24.0

    private func environment(_ windows: [RoamWindow], mode: RoamMode = .patrol) -> RoamEnvironment {
        RoamEnvironment(surfaces: RoamSurfaces.build(screen: screen, menuBarHeight: menuBar, windows: windows, docks: [],
                                                     walkOnWindows: true),
                        walls: RoamSurfaces.walls(screen: screen, menuBarHeight: menuBar, windows: windows,
                                                  walkOnWindows: true),
                        ceilings: RoamSurfaces.ceilings(screen: screen, menuBarHeight: menuBar, windows: windows,
                                                        walkOnWindows: true),
                        mode: mode, home: CGPoint(x: 500, y: 0), pointer: .zero, lively: false,
                        screenMinX: 0, screenMaxX: 1000, screenMinY: 0, screenMaxY: 800)
    }

    private func run(_ state: inout RoamState, seconds: Double, env: RoamEnvironment,
                     until done: (RoamState) -> Bool = { _ in false }) -> [RoamEvent] {
        var events: [RoamEvent] = []
        for _ in 0..<Int(seconds * 120) {
            events += RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: { 0.5 })
            if done(state) { break }
        }
        return events
    }

    // MARK: Ceilings

    @Test func ceilingsAreTheMenuBarUndersideAndUncoveredWindowBottoms() {
        let front = RoamWindow(frame: CGRect(x: 300, y: 250, width: 200, height: 200))
        let back = RoamWindow(frame: CGRect(x: 100, y: 300, width: 600, height: 300))
        let low = RoamWindow(frame: CGRect(x: 700, y: 20, width: 200, height: 100))
        let list = RoamSurfaces.ceilings(screen: screen, menuBarHeight: menuBar, windows: [front, back, low],
                                         walkOnWindows: true)
        #expect(list.contains(RoamSurface(kind: .menuBar, y: 776, minX: 0, maxX: 1000)))
        #expect(list.contains(RoamSurface(kind: .window, y: 250, minX: 300, maxX: 500)))
        // The front window covers the middle of the back window's bottom.
        #expect(list.contains(RoamSurface(kind: .window, y: 300, minX: 100, maxX: 300)))
        #expect(list.contains(RoamSurface(kind: .window, y: 300, minX: 500, maxX: 700)))
        // Too close to the floor to hang from.
        #expect(!list.contains { $0.y == 20 })
        let none = RoamSurfaces.ceilings(screen: screen, menuBarHeight: menuBar, windows: [front], walkOnWindows: false)
        #expect(none.count == 1)
    }

    @Test func climbsTheScreenSideOntoTheCeilingAndWalksUpsideDown() {
        let env = environment([])
        let floor = env.surfaces.first { $0.kind == .floor }!
        let route = env.nav.route(from: .ledge(floor, x: 200), toward: CGPoint(x: 400, y: 700)) ?? []
        #expect(route.contains { if case .transfer(.ceiling) = $0 { true } else { false } })
        var state = RoamState(x: 200, y: 0)
        state.activity = .resting
        state.route = route
        var upsideDown = false
        var facingMatched = true
        for _ in 0..<(120 * 60) {
            let before = state
            _ = RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: { 0.5 })
            if state.ceiling != nil, state.activity == .climbing {
                upsideDown = true
                if RoamPose.angle(state) != 180 { facingMatched = false }
                let dx = state.x - before.x
                if abs(dx) > 0.01, state.facing != RoamBrain.hangFacing(dx: dx) { facingMatched = false }
            }
            if state.route.isEmpty, state.ceiling != nil { break }
        }
        #expect(upsideDown)
        #expect(facingMatched)
        #expect(state.y == 776)
        #expect(abs(state.x - 400) < 1)
        #expect(RoamBrain.middle(state, half: 16) == CGPoint(x: state.x, y: 760))
    }

    @Test func jumpsUpToHangUnderALowWindow() {
        let window = RoamWindow(frame: CGRect(x: 300, y: 150, width: 300, height: 300))
        let env = environment([window])
        let floor = env.surfaces.first { $0.kind == .floor }!
        let route = env.nav.route(from: .ledge(floor, x: 100), toward: CGPoint(x: 450, y: 134)) ?? []
        #expect(route.contains { if case .leap(_, _, .ceiling(let c, _)) = $0 { c.y == 150 } else { false } })
        var state = RoamState(x: 100, y: 0)
        state.activity = .resting
        state.route = route
        let events = run(&state, seconds: 20, env: env) { $0.route.isEmpty && $0.ceiling != nil }
        #expect(events.contains(.grabbedWall))
        #expect(state.ceiling?.y == 150)
    }

    @Test func aPetWhoseCeilingGoesAwayFalls() {
        let window = RoamWindow(frame: CGRect(x: 300, y: 150, width: 300, height: 300))
        var state = RoamState(x: 400, y: 150)
        state.ceiling = RoamSurface(kind: .window, y: 150, minX: 300, maxX: 600)
        state.activity = .clinging
        state.timeLeft = 100
        let events = run(&state, seconds: 0.1, env: environment([]))
        #expect(events.contains(.startled))
        #expect(state.activity == .falling)
        #expect(state.y <= 150 - 32 && state.y > 100)
        _ = window
    }

    // MARK: Corners

    @Test func anInsideCornerRollsInPlace() {
        let turn = RoamTurn(from: CGPoint(x: 16, y: 16), to: CGPoint(x: 16, y: 16), fromAngle: 0, toAngle: 90)
        var probe = turn
        var last = 0.0
        for step in 0...24 {
            probe.elapsed = Double(step) * 0.01
            let sample = probe.sample
            #expect(hypot(sample.middle.x - 16, sample.middle.y - 16) < 1e-9)
            #expect(sample.angle >= last - 1e-9)
            last = sample.angle
        }
        #expect(last == 90)
    }

    @Test func anOutsideCornerBendsOverTheEdgeContinuously() {
        // Over the top right corner of a window at (500, 300): from standing on top to the right side.
        var turn = RoamTurn(from: CGPoint(x: 500, y: 316), to: CGPoint(x: 516, y: 284), fromAngle: 0, toAngle: -90)
        #expect(turn.control == CGPoint(x: 516, y: 316))
        var previous = turn.sample.middle
        #expect(previous == CGPoint(x: 500, y: 316))
        for step in 1...24 {
            turn.elapsed = Double(step) * 0.01
            let sample = turn.sample
            // Never cuts inside the window, and never jumps.
            #expect(sample.middle.x >= 500 - 1e-9 || sample.middle.y >= 316 - 1e-9)
            #expect(hypot(sample.middle.x - previous.x, sample.middle.y - previous.y) < 4)
            previous = sample.middle
        }
        #expect(turn.isDone)
        #expect(abs(previous.x - 516) < 1e-9 && abs(previous.y - 284) < 1e-9)
        #expect(turn.sample.angle == -90)
    }

    @Test func anglesTakeTheShortWayRound() {
        #expect(RoamPose.delta(from: -90, to: 180) == -90)
        #expect(RoamPose.delta(from: 170, to: -170) == 20)
        var angle = 0.0
        for _ in 0..<60 { angle = RoamPose.settle(angle, toward: 270, dt: 1.0 / 120) }
        #expect(abs(RoamPose.delta(from: angle, to: -90)) < 0.1)
    }

    @Test func theDrawnAngleFollowsTheSurface() {
        var state = RoamState(x: 0, y: 0)
        state.activity = .clinging
        state.wall = RoamWall(kind: .screen, x: 0, minY: 0, maxY: 700, normal: 1)
        #expect(RoamPose.angle(state) == 90)
        state.wall = nil
        state.ceiling = RoamSurface(kind: .menuBar, y: 776, minX: 0, maxX: 1000)
        #expect(RoamPose.angle(state) == 180)
        state.ceiling = nil
        state.activity = .floating
        state.vx = 10_000
        #expect(RoamPose.angle(state) == RoamPose.floatLean)
        state.activity = .falling
        state.tumbling = true
        state.spin = 123
        #expect(RoamPose.angle(state) == 123)
    }

    @Test func aRouteUnderWayKeepsTheFramesComing() {
        var state = RoamState(x: 0, y: 0)
        state.activity = .clinging
        #expect(!RoamBrain.needsFrames(state))
        state.route = [.climb(to: 100)]
        #expect(RoamBrain.needsFrames(state))
    }

    // MARK: Nudges

    @Test func aSoftNudgeLeavesAStandingPetAndAHardOneKnocksItLoose() {
        let env = environment([])
        var state = RoamState(x: 300, y: 0)
        state.activity = .resting
        #expect(RoamBrain.nudge(&state, impulse: CGVector(dx: 40, dy: 0), env: env).isEmpty)
        #expect(state.activity == .resting)
        #expect(RoamBrain.nudge(&state, impulse: CGVector(dx: 300, dy: 200), env: env) == [.startled])
        #expect(state.activity == .falling)
        #expect(state.vx == 300)
    }
}
