import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

@Suite struct RoamLogicTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func surfaces(windows: [RoamWindow] = [], docks: [CGRect] = [], menuBar: Double = 24,
                          walkOnWindows: Bool = true) -> [RoamSurface] {
        RoamSurfaces.build(screen: screen, menuBarHeight: menuBar, windows: windows, docks: docks,
                           walkOnWindows: walkOnWindows)
    }

    private func environment(_ surfaces: [RoamSurface], mode: RoamMode = .patrol, home: CGPoint = CGPoint(x: 500, y: 0),
                             pointer: CGPoint = .zero, lively: Bool = false) -> RoamEnvironment {
        RoamEnvironment(surfaces: surfaces, mode: mode, home: home, pointer: pointer, lively: lively,
                        screenMinX: 0, screenMaxX: 1000)
    }

    /// Runs the brain at 30 steps a second with dice that always return `dice`.
    @discardableResult
    private func run(_ state: inout RoamState, seconds: Double, env: RoamEnvironment, dice: Double = 0.5) -> [RoamEvent] {
        var events: [RoamEvent] = []
        for _ in 0..<Int(seconds * 30) {
            events += RoamBrain.step(&state, dt: 1.0 / 30, env: env, roll: { dice })
        }
        return events
    }

    private struct Dice {
        var seed: UInt64
        mutating func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
    }

    // MARK: Surfaces

    @Test func floorAndMenuBarAlwaysExist() {
        let list = surfaces()
        #expect(list.contains { $0.kind == .floor && $0.y == 0 && $0.minX == 0 && $0.maxX == 1000 })
        #expect(list.contains { $0.kind == .menuBar && $0.y == 776 })
        #expect(surfaces(menuBar: 0).contains { $0.kind == .menuBar } == false)
        #expect(surfaces(windows: [RoamWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))]).contains { $0.kind == .floor })
    }

    @Test func windowTopsBecomeSurfacesUnlessDisabled() {
        let window = RoamWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        let list = surfaces(windows: [window])
        #expect(list.contains { $0.kind == .window && $0.y == 400 && $0.minX == 100 && $0.maxX == 500 })
        #expect(surfaces(windows: [window], walkOnWindows: false).contains { $0.kind == .window } == false)
    }

    @Test func coveredWindowTopsAreCutAway() {
        let front = RoamWindow(frame: CGRect(x: 200, y: 100, width: 200, height: 400))
        let back = RoamWindow(frame: CGRect(x: 100, y: 100, width: 600, height: 300))
        let tops = surfaces(windows: [front, back]).filter { $0.kind == .window && $0.y == 400 }
        #expect(tops.count == 2)
        #expect(tops.contains { $0.minX == 100 && $0.maxX == 200 })
        #expect(tops.contains { $0.minX == 400 && $0.maxX == 700 })
    }

    @Test func titleBarOfFocusedWindowIsNeverWalkable() {
        let front = RoamWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 400), isFront: true)
        let behind = RoamWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 480))
        let list = surfaces(windows: [front, behind])
        let strip = RoamSurfaces.titleZone([front, behind])
        #expect(strip == CGRect(x: 100, y: 472, width: 400, height: 28))
        // The back window's top at 480 lies inside the strip, so only the part left of the focused window survives.
        let tops = list.filter { $0.kind == .window && $0.y == 480 }
        #expect(tops.count == 1)
        #expect(tops.allSatisfy { $0.maxX <= 100 })
        // The focused window's own top edge stays available: the pet stands above the strip, not in it.
        #expect(list.contains { $0.kind == .window && $0.y == 500 })
    }

    @Test func releaseInsideTitleBarLiftsToTheTopEdge() {
        let zone = CGRect(x: 100, y: 472, width: 400, height: 28)
        #expect(RoamSurfaces.escapingTitleZone(x: 200, y: 480, zone: zone) == 500)
        #expect(RoamSurfaces.escapingTitleZone(x: 50, y: 480, zone: zone) == 480)
        #expect(RoamSurfaces.escapingTitleZone(x: 200, y: 300, zone: zone) == 300)
        #expect(RoamSurfaces.escapingTitleZone(x: 200, y: 480, zone: nil) == 480)
    }

    @Test func dockTopsAreSurfaces() {
        let list = surfaces(docks: [CGRect(x: 300, y: 0, width: 400, height: 70)])
        #expect(list.contains { $0.kind == .dockBar && $0.y == 70 && $0.minX == 300 && $0.maxX == 700 })
    }

    @Test func tinyLedgesAreDropped() {
        let sliver = RoamWindow(frame: CGRect(x: 100, y: 100, width: 10, height: 100))
        #expect(surfaces(windows: [sliver]).contains { $0.kind == .window } == false)
    }

    // MARK: Physics

    @Test func fallLandsOnTheHighestLedgeBelow() {
        let ledges = [RoamSurface(kind: .floor, y: 0, minX: 0, maxX: 1000),
                      RoamSurface(kind: .window, y: 200, minX: 100, maxX: 300),
                      RoamSurface(kind: .window, y: 100, minX: 100, maxX: 300)]
        var y = 400.0
        var speed = 0.0
        var landed: RoamSurface?
        for _ in 0..<300 where landed == nil {
            let fall = RoamPhysics.fall(x: 200, y: y, speed: speed, dt: 1.0 / 30, surfaces: ledges)
            y = fall.y
            speed = fall.speed
            landed = fall.landedOn
        }
        #expect(landed?.y == 200)
        #expect(y == 200)
    }

    @Test func fallMissingEveryLedgeStillEndsOnTheFloor() {
        let ledges = surfaces(windows: [RoamWindow(frame: CGRect(x: 100, y: 100, width: 300, height: 200))])
        var state = RoamState(x: 700, y: 600)
        state.activity = .falling
        let events = run(&state, seconds: 3, env: environment(ledges))
        #expect(state.y == 0)
        #expect(state.activity != .falling)
        #expect(events.contains { if case .landed = $0 { true } else { false } })
    }

    @Test func landingImpactGrowsWithHeight() {
        func impact(from height: Double) -> Double {
            var state = RoamState(x: 700, y: height)
            state.activity = .falling
            for event in run(&state, seconds: 3, env: environment(surfaces())) {
                if case .landed(let value) = event { return value }
            }
            return 0
        }
        #expect(impact(from: 600) > impact(from: 100))
    }

    @Test func losingTheLedgeStartlesThenFalls() {
        var state = RoamState(x: 200, y: 400)
        state.activity = .resting
        state.timeLeft = 100
        let gone = environment(surfaces())
        let events = run(&state, seconds: 0.1, env: gone)
        #expect(events.first == .startled)
        run(&state, seconds: 2, env: gone)
        #expect(state.y == 0)
    }

    // MARK: Walking

    @Test func walkingSpeedMatchesTheDesign() {
        var calm = RoamState(x: 300, y: 0)
        calm.activity = .walking
        calm.timeLeft = 100
        run(&calm, seconds: 2, env: environment(surfaces()))
        #expect(abs(calm.x - 390) < 1)
        var lively = RoamState(x: 300, y: 0)
        lively.activity = .walking
        lively.timeLeft = 100
        run(&lively, seconds: 2, env: environment(surfaces(), lively: true))
        #expect(abs(lively.x - 440) < 1)
    }

    @Test func turnsAroundAtTheScreenEdge() {
        var state = RoamState(x: 990, y: 0)
        state.activity = .walking
        state.timeLeft = 100
        let events = run(&state, seconds: 1, env: environment(surfaces()))
        #expect(events.contains(.turned))
        #expect(state.facing == -1)
        #expect(state.x <= 1000)
    }

    @Test func patrolCanStepOffALedgeEnd() {
        let ledges = surfaces(windows: [RoamWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300))])
        var state = RoamState(x: 495, y: 400)
        state.activity = .walking
        state.timeLeft = 100
        run(&state, seconds: 1, env: environment(ledges), dice: 0.1)
        #expect(state.y < 400)
        var turner = RoamState(x: 495, y: 400)
        turner.activity = .walking
        turner.timeLeft = 100
        run(&turner, seconds: 1, env: environment(ledges), dice: 0.9)
        #expect(turner.y == 400)
        #expect(turner.facing == -1)
    }

    @Test func restsAboutHalfTheTime() {
        var state = RoamState(x: 500, y: 0)
        var dice = Dice(seed: 7)
        let env = environment(surfaces())
        var walking = 0
        let steps = 30 * 600
        for _ in 0..<steps {
            _ = RoamBrain.step(&state, dt: 1.0 / 30, env: env, roll: { dice.next() })
            if state.activity == .walking { walking += 1 }
        }
        let ratio = Double(walking) / Double(steps)
        #expect(ratio > 0.35 && ratio < 0.65)
    }

    // MARK: Patrol on the menu bar

    @Test func patrolReturnsToThePreferredMenuBarEdgeByFading() {
        var state = RoamState(x: 500, y: 0)
        state.preferMenuBar = true
        state.activity = .resting
        state.timeLeft = 0
        let env = environment(surfaces())
        run(&state, seconds: 0.1, env: env)
        #expect(state.activity == .fadingOut)
        run(&state, seconds: 1, env: env)
        #expect(state.y == 776)
        #expect(state.alpha == 1)
    }

    @Test func menuBarPetNeverStepsOffItsEdge() {
        var state = RoamState(x: 996, y: 776)
        state.preferMenuBar = true
        state.activity = .walking
        state.timeLeft = 100
        run(&state, seconds: 2, env: environment(surfaces()), dice: 0.0)
        #expect(state.y == 776)
    }

    // MARK: Hang out

    @Test func hangOutStaysNearHome() {
        var state = RoamState(x: 500, y: 0)
        var dice = Dice(seed: 99)
        let env = environment(surfaces(), mode: .hangOut, home: CGPoint(x: 500, y: 0))
        var farthest = 0.0
        for _ in 0..<(30 * 900) {
            _ = RoamBrain.step(&state, dt: 1.0 / 30, env: env, roll: { dice.next() })
            farthest = max(farthest, abs(state.x - 500))
        }
        #expect(farthest <= RoamBrain.hangOutRadius + 1)
    }

    @Test func quietModeForcesHangOut() {
        #expect(RoamBrain.effectiveMode(.follow, quiet: true) == .hangOut)
        #expect(RoamBrain.effectiveMode(.follow, quiet: false) == .follow)
    }

    // MARK: Follow

    @Test func followStopsAtComfortableDistance() {
        var state = RoamState(x: 100, y: 0)
        let env = environment(surfaces(), mode: .follow, pointer: CGPoint(x: 600, y: 300))
        run(&state, seconds: 8, env: env)
        let gap = abs(600 - state.x)
        #expect(gap >= RoamBrain.followDistance - 6 && gap <= RoamBrain.followDistance + 10)
        #expect(state.activity != .walking)
    }

    @Test func followBacksAwayFromACursorOnTop() {
        var state = RoamState(x: 600, y: 0)
        let env = environment(surfaces(), mode: .follow, pointer: CGPoint(x: 605, y: 20))
        run(&state, seconds: 3, env: env)
        #expect(abs(state.x - 605) >= RoamBrain.followDistance - 6)
    }

    @Test func stillPointerMakesItSitThenNapAndMovingWakesIt() {
        var state = RoamState(x: 540, y: 0)
        var env = environment(surfaces(), mode: .follow, pointer: CGPoint(x: 600, y: 300))
        run(&state, seconds: 11, env: env)
        #expect(state.activity == .sitting)
        run(&state, seconds: 21, env: env)
        #expect(state.activity == .napping)
        env.pointer = CGPoint(x: 640, y: 300)
        let events = run(&state, seconds: 0.1, env: env)
        #expect(events.contains(.woke))
        #expect(state.activity != .napping)
    }

    // MARK: Cadence and hit testing

    @Test func snapshotAndFrameCadence() {
        #expect(RoamBrain.snapshotInterval(.walking) == 0.5)
        #expect(RoamBrain.snapshotInterval(.sitting) == 2)
        #expect(RoamBrain.snapshotInterval(.napping) == nil)
        #expect(RoamBrain.frameInterval(.walking) == 1.0 / 30)
        #expect(RoamBrain.frameInterval(.resting) == nil)
    }

    @Test func hitTestFollowsTheEllipseNotTheSquare() {
        let feet = CGPoint(x: 100, y: 50)
        #expect(RoamBrain.hits(point: CGPoint(x: 100, y: 66), feet: feet, unit: 32))
        #expect(!RoamBrain.hits(point: CGPoint(x: 100 + 15, y: 50 + 2), feet: feet, unit: 32))
        #expect(!RoamBrain.hits(point: CGPoint(x: 100, y: 120), feet: feet, unit: 32))
    }
}
