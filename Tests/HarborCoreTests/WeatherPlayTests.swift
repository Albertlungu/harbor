import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

@Suite struct WeatherPlayTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let window = CGRect(x: 200, y: 200, width: 400, height: 300)

    private func surfaces(_ windows: [CGRect]) -> [RoamSurface] {
        RoamSurfaces.build(screen: screen, menuBarHeight: 24, windows: windows.map { RoamWindow(frame: $0) },
                           docks: [], walkOnWindows: true)
    }

    private func world(_ season: Season, evening: Bool = false) -> WeatherWorld {
        var w = WeatherWorld(width: 1000, height: 800, season: season, intensity: 0, evening: evening, seed: 7)
        w.setSurfaces(surfaces([window]))
        return w
    }

    private func run(_ w: inout WeatherWorld, seconds: Double, pets: [WeatherPet] = []) -> [WeatherEvent] {
        var events: [WeatherEvent] = []
        for _ in 0..<Int(seconds * 30) { events += w.step(dt: 1.0 / 30, pets: pets) }
        return events
    }

    private func windowLedge(_ w: WeatherWorld) -> Int { w.ledges.firstIndex { $0.y == 500 }! }

    private func bury(_ w: inout WeatherWorld, depth: Double) {
        let i = windowLedge(w)
        w.ledges[i].heights = Array(repeating: depth, count: w.ledges[i].count)
    }

    /// Pile on every ledge plus what is in the air on its way down, as area.
    private func mass(_ w: WeatherWorld) -> Double {
        let piled = w.ledges.reduce(0) { $0 + $1.heights.reduce(0, +) * WeatherLedge.column }
        return piled + w.particles.reduce(0) { $0 + $1.mass }
    }

    private func poses(_ events: [WeatherEvent]) -> [WeatherPetPose] {
        events.compactMap { if case .pose(_, let pose, _, _) = $0 { pose } else { nil } }
    }

    // MARK: A window going away

    @Test func snowOnAClosedWindowFallsAsClodsAndLandsBelow() {
        var w = world(.winter)
        bury(&w, depth: 3)
        let before = mass(w)
        w.setSurfaces(surfaces([]))
        let clods = w.particles.filter { $0.kind == .chunk }
        #expect(clods.count > 10)
        // Clods of different sizes, with loose powder among them.
        #expect(Set(clods.map { Int($0.size * 2) }).count > 3)
        #expect(w.particles.contains { $0.kind == .flake && $0.mass > 0 })
        #expect(abs(mass(w) - before) < 0.5)

        // A moment later they are still on their way down, tumbling.
        _ = run(&w, seconds: 0.2)
        let falling = w.particles.filter { $0.kind == .chunk }
        #expect(falling.contains { $0.y > 100 && $0.y < 500 })

        // The clods land within a second or so; the loose powder drifts down after them.
        _ = run(&w, seconds: 2)
        #expect(!w.particles.contains { $0.kind == .chunk })
        #expect(abs(mass(w) - before) < before * 0.03)
        _ = run(&w, seconds: 18)
        let floor = w.ledges.first { $0.y == 0 }!
        #expect(abs(floor.heights.reduce(0, +) * WeatherLedge.column - before) < before * 0.05)
    }

    @Test func leavesOnAClosedWindowFlutterDownAsLeaves() {
        var w = world(.autumn)
        bury(&w, depth: 4)
        let before = mass(w)
        w.setSurfaces(surfaces([]))
        #expect(w.particles.filter { $0.kind == .leaf }.count > 20)
        #expect(abs(mass(w) - before) < 0.5)
        _ = run(&w, seconds: 25)
        #expect(abs(mass(w) - before) < before * 0.05)
        let floor = w.ledges.first { $0.y == 0 }!
        #expect(floor.heights.reduce(0, +) * WeatherLedge.column > before * 0.7)
    }

    @Test func aMovedWindowShakesOffItsRainAndFlowers() {
        var w = world(.spring)
        let i = windowLedge(w)
        w.ledges[i].water = Array(repeating: 1, count: w.ledges[i].count)
        w.ledges[i].flowers = [WeatherFlower(column: 40, growth: 1, tint: 1)]
        w.setSurfaces(surfaces([window.offsetBy(dx: 0, dy: 40)]))
        #expect(w.particles.contains { $0.kind == .drop })
        #expect(w.particles.contains { $0.kind == .blossom })
        _ = run(&w, seconds: 4)
        #expect(w.ledges.contains { $0.flowers.contains { $0.tint == 1 } })
    }

    @Test func aSpaceSwitchStillClearsQuietly() {
        var w = world(.winter)
        bury(&w, depth: 3)
        w.setSurfaces(surfaces([]), quietly: true)
        #expect(w.particles.isEmpty)
    }

    // MARK: Pile shape

    @Test func relaxingOnlyLooksNearWhatWasDisturbed() {
        var ledge = WeatherLedge(y: 0, minX: 0, maxX: 800)
        ledge.heights = Array(repeating: 4, count: ledge.count)
        ledge.restless = false
        ledge.deposit(x: 101, amount: 6, cap: 40)
        ledge.relax(slope: 0.9, edgeHold: 50, roughness: 0.8, rate: 0.5)
        let span = ledge.unsettled!
        #expect(span.lowerBound >= 47 && span.upperBound <= 53)
        #expect(ledge.heights[0] == 4 && ledge.heights[300] == 4)
    }

    @Test func aSlumpedHeapIsLumpyNotATriangle() {
        var ledge = WeatherLedge(y: 0, minX: 0, maxX: 200)
        ledge.heights[50] = 40
        ledge.restless = true
        for _ in 0..<600 { ledge.relax(slope: 0.9, edgeHold: 50, roughness: 0.8, rate: 0.5) }
        #expect(abs(ledge.heights.reduce(0, +) - 40) < 0.001)
        let steps = zip(ledge.heights, ledge.heights.dropFirst()).map { abs($0 - $1) }.filter { $0 > 0.05 }
        // Stretches hold steeper or shallower than others, so the flanks are not straight; the variation is
        // gradual, so no single column stands out as a spike.
        #expect(steps.max()! > steps.min()! * 1.5)
        #expect(steps.max()! <= 0.9 * WeatherLedge.column * 1.8 + 0.001)
        #expect(!ledge.restless)
    }

    @Test func aSnowballImpactLeavesALumpyPileAndKeepsItsSnow() {
        var w = world(.winter)
        bury(&w, depth: 4)
        let li = windowLedge(w)
        let before = w.ledges[li].heights.reduce(0, +) * WeatherLedge.column
        let area = Double.pi * 10 * 10 * 0.8
        w.impact(on: li, x: 400, area: area, radius: 10, vx: 600)
        _ = run(&w, seconds: 4)
        let ledge = w.ledges[li]
        #expect(abs(ledge.heights.reduce(0, +) * WeatherLedge.column - (before + area)) < area * 0.05)

        let lo = ledge.index(x: 360)!, hi = ledge.index(x: 460)!
        let profile = Array(ledge.heights[lo...hi])
        let peak = profile.indices.max { profile[$0] < profile[$1] }!
        #expect(profile[peak] > 5)
        // Lopsided about its peak.
        var mismatch = 0.0
        for k in 1...8 where peak - k >= 0 && peak + k < profile.count {
            mismatch += abs(profile[peak + k] - profile[peak - k])
        }
        #expect(mismatch > 1)
        // And its flanks change steepness instead of running straight.
        let raised = profile.indices.dropLast().filter { profile[$0] > 4.3 || profile[$0 + 1] > 4.3 }
        let slopes = raised.map { abs(profile[$0 + 1] - profile[$0]) }
        #expect(slopes.max()! - slopes.min()! > 0.4)
    }

    // MARK: Pointer play in every season

    @Test func clickingSnowKicksItAndHoldingStillMakesAnAngel() {
        var w = world(.winter)
        bury(&w, depth: 6)
        let pressed1 = w.pointerDown(x: 300, y: 505)
        #expect(pressed1)
        w.pointerUp(vx: 0, vy: 0)
        #expect(w.balls.isEmpty)
        #expect(w.particles.contains { $0.kind == .flake && $0.mass > 0 })

        let pressed2 = w.pointerDown(x: 450, y: 505)
        #expect(pressed2)
        _ = run(&w, seconds: 1)
        w.pointerUp(vx: 0, vy: 0)
        #expect(w.balls.isEmpty)
        let ledge = w.ledges[windowLedge(w)]
        #expect(ledge.height(x: 450) < ledge.height(x: 450 + 18) - 2)
        #expect(ledge.height(x: 450) < ledge.height(x: 450 - 18) - 2)
    }

    @Test func aHandfulOfLeavesIsTossedAndFlutters() {
        var w = world(.autumn)
        bury(&w, depth: 6)
        let pressed3 = w.pointerDown(x: 300, y: 505)
        #expect(pressed3)
        w.pointerDragged(x: 300, y: 540)
        w.pointerDragged(x: 310, y: 580)
        #expect(w.carried.count >= 2)
        #expect(w.carried.allSatisfy { $0.kind == .leaf })
        let held = w.carried.count
        w.pointerUp(vx: 400, vy: 300)
        #expect(w.carried.isEmpty)
        #expect(w.particles.filter { $0.kind == .leaf && $0.vx > 0 }.count >= held / 2)
    }

    @Test func clickingALeafPileKicksItUp() {
        var w = world(.autumn)
        bury(&w, depth: 6)
        let pressed4 = w.pointerDown(x: 300, y: 505)
        #expect(pressed4)
        w.pointerUp(vx: 0, vy: 0)
        #expect(w.particles.filter { $0.kind == .leaf && $0.vy > 0 }.count >= 3)
    }

    @Test func aPickedFlowerReplantsWhereItIsDropped() {
        var w = world(.spring)
        let li = windowLedge(w)
        w.ledges[li].flowers = [WeatherFlower(column: 50, growth: 1, tint: 2)]
        let x = w.ledges[li].centerX(50)
        #expect(w.hitTest(x: x, y: 508))
        let pressed5 = w.pointerDown(x: x, y: 508)
        #expect(pressed5)
        #expect(w.ledges[li].flowers.isEmpty)
        w.pointerDragged(x: 760, y: 300)
        w.pointerUp(vx: 0, vy: 0)
        _ = run(&w, seconds: 4)
        let floor = w.ledges.first { $0.y == 0 }!
        #expect(floor.flowers.contains { $0.tint == 2 && abs(floor.centerX($0.column) - 760) < 30 })
    }

    @Test func clickingAPuddleSplashes() {
        var w = world(.spring)
        let li = windowLedge(w)
        w.ledges[li].water = Array(repeating: 1.5, count: w.ledges[li].count)
        #expect(w.hitTest(x: 300, y: 501))
        let pressed6 = w.pointerDown(x: 300, y: 501)
        #expect(pressed6)
        w.pointerUp(vx: 0, vy: 0)
        #expect(w.particles.filter { $0.kind == .splash }.count >= 10)
        #expect(w.ledges[li].water[w.ledges[li].index(x: 300)!] < 1.5)
    }

    @Test func draggingABubbleBlowsItBiggerUntilItPops() {
        var w = world(.summer)
        w.particles = [WeatherParticle(kind: .bubble, x: 300, y: 300, size: 10, life: 30)]
        let pressed7 = w.pointerDown(x: 300, y: 300)
        #expect(pressed7)
        for k in 1...20 { w.pointerDragged(x: 300 + Double(k % 2) * 20, y: 300) }
        #expect(w.carried.first!.size > 20)
        w.pointerUp(vx: 50, vy: 0)
        #expect(w.particles.contains { $0.kind == .bubble && $0.size > 20 })

        w.particles = [WeatherParticle(kind: .bubble, x: 500, y: 300, size: 10, life: 30)]
        let pressed8 = w.pointerDown(x: 500, y: 300)
        #expect(pressed8)
        var events: [WeatherEvent] = []
        for k in 1...80 {
            w.pointerDragged(x: 500 + Double(k % 2) * 25, y: 300)
            events += w.step(dt: 1.0 / 60)
        }
        #expect(events.contains { if case .popped = $0 { true } else { false } })
        #expect(w.carried.isEmpty)
    }

    @Test func firefliesCaughtInAJarAreLetGo() {
        var w = world(.summer, evening: true)
        w.particles = [WeatherParticle(kind: .firefly, x: 300, y: 300, size: 3, life: 30),
                       WeatherParticle(kind: .firefly, x: 330, y: 320, size: 3, life: 30)]
        #expect(w.hitTest(x: 305, y: 305))
        let pressed9 = w.pointerDown(x: 305, y: 305)
        #expect(pressed9)
        #expect(w.carried.count == 2)
        _ = run(&w, seconds: 15)
        #expect(w.carried.isEmpty)
        #expect(w.particles.contains { $0.kind == .firefly })
    }

    // MARK: Pets

    @Test func theBrainPicksByWeight() {
        let options = [WeatherPlayOption(kind: .dive, x: 0, y: 0, weight: 1),
                       WeatherPlayOption(kind: .scoop, x: 0, y: 0, weight: 3)]
        #expect(WeatherPlayBrain.pick(options, dice: 0.1)?.kind == .dive)
        #expect(WeatherPlayBrain.pick(options, dice: 0.5)?.kind == .scoop)
        #expect(WeatherPlayBrain.pick(options, dice: 0.999)?.kind == .scoop)
        #expect(WeatherPlayBrain.pick([], dice: 0.5) == nil)
        #expect(WeatherPlayBrain.pause(playful: 1.6, dice: 0.5) < WeatherPlayBrain.pause(playful: 0.5, dice: 0.5))
        #expect(WeatherPlayBrain.pause(playful: 1, dice: 0) >= 10)
    }

    @Test func eachSeasonOffersItsOwnPlay() {
        let pet = WeatherPet(id: "pup", x: 300, y: 500, vx: 0, vy: 0, unit: 32)
        var winter = world(.winter)
        bury(&winter, depth: 6)
        let kinds = winter.playOptions(for: pet).map(\.kind)
        #expect(kinds.contains(.dive) && kinds.contains(.scoop))

        var autumn = world(.autumn)
        autumn.particles = [WeatherParticle(kind: .leaf, x: 360, y: 600, size: 6)]
        #expect(autumn.playOptions(for: pet).map(\.kind) == [.chaseLeaf])

        var spring = world(.spring)
        let li = windowLedge(spring)
        spring.ledges[li].water[60] = 1
        spring.ledges[li].flowers = [WeatherFlower(column: 80, growth: 1, tint: 0)]
        let springKinds = spring.playOptions(for: pet).map(\.kind)
        #expect(springKinds.contains(.splash) && springKinds.contains(.sniff))

        var summer = world(.summer)
        summer.particles = [WeatherParticle(kind: .bubble, x: 320, y: 560, size: 10, life: 20),
                            WeatherParticle(kind: .seed, x: 280, y: 540, size: 5, life: 20)]
        let summerKinds = summer.playOptions(for: pet).map(\.kind)
        #expect(summerKinds.contains(.chaseBubble) && summerKinds.contains(.snapSeed))

        // Nothing to play with off a ledge.
        #expect(winter.playOptions(for: WeatherPet(id: "pup", x: 300, y: 650, vx: 0, vy: 0, unit: 32)).isEmpty)
    }

    @Test func aPetDivesIntoLeavesRollsAboutAndShakesOff() {
        var w = world(.autumn)
        bury(&w, depth: 8)
        let li = windowLedge(w)
        let pet = WeatherPet(id: "pup", x: 300, y: 500, vx: 0, vy: 0, unit: 32)
        let events = run(&w, seconds: 9, pets: [pet])
        #expect(events.contains { if case .nudge(let id, _, let dy) = $0 { id == "pup" && dy > 200 } else { false } })
        let seen = poses(events)
        #expect(seen.contains(.pounce) && seen.contains(.roll) && seen.contains(.shake))
        #expect(seen.firstIndex(of: .roll)! < seen.firstIndex(of: .shake)!)
        // It ploughed a hollow where it rolled.
        #expect(w.ledges[li].height(x: 300) < 7)
    }

    @Test func aPetFetchesASmallSnowballAndThrowsIt() {
        var w = world(.winter)
        let li = windowLedge(w)
        var ball = Snowball(id: 99, x: 340, y: 505, r: 6, state: .resting)
        ball.groundY = w.ledges[li].y
        w.balls = [ball]
        let pet = WeatherPet(id: "pup", x: 330, y: 500, vx: 0, vy: 0, unit: 32)
        var events: [WeatherEvent] = []
        var thrown = false
        for _ in 0..<(30 * 10) {
            events += w.step(dt: 1.0 / 30, pets: [pet])
            if w.balls.contains(where: { $0.state == .flying }) { thrown = true }
        }
        let seen = poses(events)
        #expect(seen.contains(.carry) && seen.contains(.toss))
        #expect(thrown)
        #expect(events.contains { if case .splat = $0 { true } else { false } } || w.balls.contains { $0.state == .resting })
    }

    @Test func aPetStacksASmallBallOnABigOne() {
        var w = world(.winter)
        let li = windowLedge(w)
        var small = Snowball(id: 1, x: 340, y: 505, r: 6, state: .resting)
        small.groundY = w.ledges[li].y
        var big = Snowball(id: 2, x: 420, y: 510, r: 14, state: .resting)
        big.groundY = w.ledges[li].y
        w.balls = [small, big]
        var x = 330.0
        var events: [WeatherEvent] = []
        for _ in 0..<(30 * 14) {
            // The pet walks wherever it is asked to, a little each frame.
            let pet = WeatherPet(id: "pup", x: x, y: 500, vx: 0, vy: 0, unit: 32)
            let step = w.step(dt: 1.0 / 30, pets: [pet])
            events += step
            for case .walk(_, let to) in step { x = to }
        }
        #expect(w.balls.contains { $0.below == 2 })
        #expect(poses(events).contains(.carry))
    }

    @Test func aQuietPetDoesNotPlay() {
        var w = world(.autumn)
        bury(&w, depth: 8)
        let events = run(&w, seconds: 40, pets: [WeatherPet(id: "pup", x: 300, y: 500, vx: 0, vy: 0, unit: 32, playful: 0)])
        #expect(!events.contains {
            switch $0 {
            case .nudge, .walk, .pose: true
            default: false
            }
        })
    }

    @Test func playIsATreatNotConstant() {
        var w = world(.autumn)
        bury(&w, depth: 8)
        let events = run(&w, seconds: 60, pets: [WeatherPet(id: "pup", x: 300, y: 500, vx: 0, vy: 0, unit: 32)])
        let dives = events.filter { if case .pose(_, .roll, _, _) = $0 { true } else { false } }.count
        #expect(dives >= 1 && dives <= 3)
    }
}
