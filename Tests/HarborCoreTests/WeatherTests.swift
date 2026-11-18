import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

@Suite struct WeatherTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let window = CGRect(x: 200, y: 200, width: 400, height: 300)

    private func surfaces(_ windows: [CGRect]) -> [RoamSurface] {
        RoamSurfaces.build(screen: screen, menuBarHeight: 24, windows: windows.map { RoamWindow(frame: $0) },
                           docks: [], walkOnWindows: true)
    }

    private func world(_ season: Season, windows: [CGRect]? = nil, evening: Bool = false) -> WeatherWorld {
        var w = WeatherWorld(width: 1000, height: 800, season: season, intensity: 1, evening: evening, seed: 7)
        w.setSurfaces(surfaces(windows ?? [window]))
        return w
    }

    private func run(_ w: inout WeatherWorld, seconds: Double, pets: [WeatherPet] = []) -> [WeatherEvent] {
        var events: [WeatherEvent] = []
        for _ in 0..<Int(seconds * 30) { events += w.step(dt: 1.0 / 30, pets: pets) }
        return events
    }

    private func windowLedge(_ w: WeatherWorld) -> Int { w.ledges.firstIndex { $0.y == 500 }! }

    /// Fills the window's ledge with an even layer of `depth`.
    private func bury(_ w: inout WeatherWorld, depth: Double) {
        let i = windowLedge(w)
        w.ledges[i].heights = Array(repeating: depth, count: w.ledges[i].count)
    }

    // MARK: Seasons

    private func date(_ month: Int, _ day: Int = 15) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func seasonFollowsTheMonth() {
        #expect(Season.on(date(1), southern: false, calendar: utc) == .winter)
        #expect(Season.on(date(4), southern: false, calendar: utc) == .spring)
        #expect(Season.on(date(7), southern: false, calendar: utc) == .summer)
        #expect(Season.on(date(11, 17), southern: false, calendar: utc) == .autumn)
        #expect(Season.on(date(12), southern: false, calendar: utc) == .winter)
    }

    @Test func southernHemisphereIsSixMonthsAway() {
        #expect(Season.on(date(1), southern: true, calendar: utc) == .summer)
        #expect(Season.on(date(11), southern: true, calendar: utc) == .spring)
    }

    @Test func fixedSeasonIgnoresTheDate() {
        var settings = WeatherSettings()
        settings.season = .winter
        #expect(settings.season(at: date(7), calendar: utc) == .winter)
    }

    @Test func eveningIsDuskToDawn() {
        #expect(Season.isEvening(hour: 21))
        #expect(Season.isEvening(hour: 2))
        #expect(!Season.isEvening(hour: 14))
    }

    @Test func oldConfigsGetWeatherOnInAutomatic() throws {
        let settings = try JSONDecoder().decode(WeatherSettings.self, from: Data("{}".utf8))
        #expect(settings.enabled && settings.season == .auto && settings.accumulation && !settings.sounds)
        let app = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(app.weather == WeatherSettings())
    }

    // MARK: Height field

    @Test func aHeapSlumpsToTheAngleOfRepose() {
        var ledge = WeatherLedge(y: 100, minX: 0, maxX: 200)
        ledge.heights[50] = 30
        ledge.restless = true
        var spilled = 0.0
        for _ in 0..<400 {
            let spill = ledge.relax(slope: 0.6, edgeHold: 5)
            spilled += spill.left + spill.right
        }
        let steepest = zip(ledge.heights, ledge.heights.dropFirst()).map { abs($0 - $1) }.max()!
        #expect(steepest <= 0.6 * WeatherLedge.column + 0.01)
        #expect(spilled == 0)
        #expect(abs(ledge.heights.reduce(0, +) - 30) < 0.001)
        #expect(!ledge.restless)
    }

    @Test func snowPiledAtAnOpenEndSpillsOver() {
        var ledge = WeatherLedge(y: 100, minX: 0, maxX: 40)
        ledge.heights[ledge.count - 1] = 20
        ledge.restless = true
        let spill = ledge.relax(slope: 0.6, edgeHold: 5)
        #expect(spill.right > 0)
        #expect(ledge.heights.last! <= 5)
    }

    @Test func meltingNeverGoesBelowZero() {
        var ledge = WeatherLedge(y: 0, minX: 0, maxX: 20)
        ledge.heights = [3, 0.2, 0, 1, 1, 1, 1, 1, 1, 1]
        ledge.melt(depth: 0.5, dry: 0)
        #expect(ledge.heights[0] == 2.5)
        #expect(ledge.heights[1] == 0)
        #expect(ledge.heights.allSatisfy { $0 >= 0 })
    }

    @Test func aPileStaysPutWhenItsLedgeIsUnchanged() {
        var old = WeatherLedge(y: 500, minX: 200, maxX: 600)
        old.heights[10] = 4
        var new = [WeatherLedge(y: 500, minX: 200, maxX: 600)]
        let spills = WeatherLedge.carry(from: [old], into: &new)
        #expect(spills.isEmpty)
        #expect(new[0].heights[10] == 4)
    }

    @Test func aPileFallsOffAWindowThatMoved() {
        var old = WeatherLedge(y: 500, minX: 200, maxX: 600)
        for i in 0..<old.count { old.heights[i] = 2 }
        var new = [WeatherLedge(y: 520, minX: 200, maxX: 600)]
        let spills = WeatherLedge.carry(from: [old], into: &new)
        let area = spills.reduce(0) { $0 + $1.area }
        #expect(abs(area - 2 * 400) < 0.001)
        #expect(new[0].heights.allSatisfy { $0 == 0 })
    }

    @Test func columnsSitOnASharedGrid() {
        let ledge = WeatherLedge(y: 0, minX: 201, maxX: 300)
        #expect(ledge.minX == 202)
        #expect(ledge.index(x: 202.5) == 0)
        #expect(ledge.index(x: 150) == nil)
    }

    // MARK: Falling

    @Test func snowSettlesOnWindowTops() {
        var w = world(.winter)
        _ = run(&w, seconds: 120)
        let top = w.ledges[windowLedge(w)]
        #expect(top.heights.reduce(0, +) > 50)
        #expect(w.particles.count <= WeatherWorld.maxParticles)
        // The window shelters the ground beneath it.
        let floor = w.ledges.first { $0.y == 0 }!
        let under = (floor.index(x: 300)!..<floor.index(x: 500)!).map { floor.heights[$0] }.reduce(0, +)
        let open = (floor.index(x: 700)!..<floor.index(x: 900)!).map { floor.heights[$0] }.reduce(0, +)
        #expect(under < open)
    }

    @Test func nothingSettlesWithAccumulationOff() {
        var w = world(.winter)
        w.accumulation = false
        _ = run(&w, seconds: 30)
        #expect(w.ledges.allSatisfy { $0.heights.allSatisfy { $0 == 0 } })
    }

    @Test func closingAWindowDropsItsSnow() {
        var w = world(.winter)
        bury(&w, depth: 3)
        w.intensity = 0
        w.setSurfaces(surfaces([]))
        #expect(w.particles.contains { $0.kind == .chunk })
        _ = run(&w, seconds: 3)
        let floor = w.ledges.first { $0.y == 0 }!
        #expect(floor.heights.reduce(0, +) > 100)
    }

    @Test func aSpaceSwitchHidesSnowWithoutDroppingIt() {
        var w = world(.winter)
        bury(&w, depth: 3)
        w.setSurfaces(surfaces([]), quietly: true)
        #expect(w.particles.isEmpty)
    }

    @Test func leavesPileUpInAutumn() {
        var w = world(.autumn)
        _ = run(&w, seconds: 120)
        #expect(w.ledges[windowLedge(w)].heights.reduce(0, +) > 5)
        #expect(w.particles.contains { $0.kind == .leaf })
    }

    @Test func summerEveningsBringFireflies() {
        var night = world(.summer, evening: true)
        _ = run(&night, seconds: 20)
        #expect(night.particles.contains { $0.kind == .firefly })
        var day = world(.summer)
        _ = run(&day, seconds: 60)
        #expect(!day.particles.contains { $0.kind == .firefly })
        #expect(day.particles.contains { $0.kind == .seed })
    }

    @Test func aCalmEmptyScreenIsStill() {
        var w = world(.winter)
        w.intensity = 0
        _ = run(&w, seconds: 1)
        #expect(w.isStill)
    }

    // MARK: Pointer

    @Test func onlyPilesTakeClicks() {
        var w = world(.winter)
        #expect(!w.hitTest(x: 400, y: 502))
        bury(&w, depth: 6)
        #expect(w.hitTest(x: 400, y: 503))
        #expect(!w.hitTest(x: 400, y: 530))
        w.interactions = false
        #expect(!w.hitTest(x: 400, y: 503))
    }

    @Test func rollingABallThroughADriftGrowsIt() {
        var w = world(.winter)
        bury(&w, depth: 6)
        let pressed = w.pointerDown(x: 250, y: 503)
        #expect(pressed)
        let start = w.balls[0].r
        let before = w.ledges[windowLedge(w)].heights.reduce(0, +)
        for x in stride(from: 252.0, through: 500, by: 2) { w.pointerDragged(x: x, y: 500 + w.balls[0].r) }
        #expect(w.balls[0].r > start * 2)
        #expect(w.ledges[windowLedge(w)].heights.reduce(0, +) < before)
    }

    @Test func aGentleDropRestsAndAHardThrowSplats() {
        var w = world(.winter)
        bury(&w, depth: 6)
        w.intensity = 0
        w.pointerDown(x: 300, y: 503)
        w.pointerDragged(x: 300, y: 560)
        w.pointerUp(vx: 0, vy: 0)
        _ = run(&w, seconds: 1)
        #expect(w.balls.count == 1 && w.balls[0].state == .resting)

        w.pointerDown(x: 450, y: 503)
        w.pointerDragged(x: 450, y: 700)
        w.pointerUp(vx: 0, vy: -1500)
        let events = run(&w, seconds: 1)
        #expect(events.contains { if case .splat = $0 { true } else { false } })
        #expect(w.balls.count == 1)
    }

    /// Rolls a ball of radius `r` on the window's drift, then lets go of it a little above the highest ball at `x`.
    private func makeBall(_ w: inout WeatherWorld, r: Double, x: Double) {
        let top = w.balls.filter { abs($0.x - x) < 20 }.map { $0.y + $0.r }.max() ?? 508
        bury(&w, depth: 8)
        w.pointerDown(x: 220, y: 503)
        var px = 222.0
        while w.balls.last!.r < r, px < 590 {
            w.pointerDragged(x: px, y: 500 + w.balls.last!.r)
            px += 2
        }
        w.pointerDragged(x: x, y: top + r + 25)
        w.pointerUp(vx: 0, vy: 0)
        _ = run(&w, seconds: 1.5)
    }

    @Test func threeBallsStackedBiggestFirstMakeASnowman() {
        var w = world(.winter)
        w.intensity = 0
        makeBall(&w, r: 18, x: 400)
        makeBall(&w, r: 13, x: 402)
        #expect(w.balls.allSatisfy { !$0.snowman })
        var events: [WeatherEvent] = []
        let top = w.balls.map { $0.y + $0.r }.max()!
        bury(&w, depth: 8)
        w.pointerDown(x: 220, y: 503)
        var px = 222.0
        while w.balls.last!.r < 9, px < 590 { w.pointerDragged(x: px, y: 500 + w.balls.last!.r); px += 2 }
        w.pointerDragged(x: 399, y: top + 35)
        w.pointerUp(vx: 0, vy: 0)
        events += run(&w, seconds: 1.5)
        #expect(events.contains { if case .snowman = $0 { true } else { false } })
        #expect(w.balls.filter(\.snowman).count == 3)
    }

    @Test func aWrongOrderStackIsNotASnowman() {
        var base = Snowball(id: 1, x: 0, y: 10, r: 8, state: .resting)
        base.groundY = 0
        var middle = Snowball(id: 2, x: 0, y: 25, r: 12, state: .resting)
        middle.below = 1
        var head = Snowball(id: 3, x: 0, y: 40, r: 6, state: .resting)
        head.below = 2
        #expect(Snowball.snowmen([base, middle, head]).isEmpty)
        middle.r = 7
        base.r = 12
        #expect(Snowball.snowmen([base, middle, head]) == [1, 2, 3])
    }

    @Test func ballsGrowWithArea() {
        #expect(Snowball.grown(4, area: 0) == 4)
        #expect(Snowball.grown(4, area: 300) > 8)
        #expect(Snowball.grown(30, area: 100_000) == Snowball.maxRadius)
    }

    @Test func restingBallsMeltAway() {
        var w = world(.spring)
        w.balls = [Snowball(id: 1, x: 300, y: 505, r: 6, state: .resting)]
        w.balls[0].groundY = 500
        w.intensity = 0
        _ = run(&w, seconds: 120)
        #expect(w.balls.isEmpty)
    }

    @Test func rakingGathersLeavesIntoAHeap() {
        var w = world(.autumn)
        w.intensity = 0
        bury(&w, depth: 2)
        let pressed = w.pointerDown(x: 220, y: 501)
        #expect(pressed)
        for x in stride(from: 222.0, through: 400, by: 2) { w.pointerDragged(x: x, y: 501) }
        w.pointerUp(vx: 0, vy: 0)
        let ledge = w.ledges[windowLedge(w)]
        #expect(ledge.height(x: 404) > 10)
        #expect(ledge.height(x: 300) < 1)
    }

    @Test func clickingABubblePopsIt() {
        var w = world(.summer)
        w.intensity = 0
        w.particles = [WeatherParticle(kind: .bubble, x: 100, y: 100, size: 10, life: 10)]
        #expect(w.hitTest(x: 104, y: 100))
        let pressed = w.pointerDown(x: 104, y: 100)
        #expect(pressed)
        #expect(!w.particles.contains { $0.kind == .bubble })
    }

    @Test func aFastPointerBlowsFlakesAlong() {
        var w = world(.winter)
        w.intensity = 0
        w.particles = [WeatherParticle(kind: .flake, x: 100, y: 700, vy: -40, size: 2)]
        w.pointerMoved(x: 95, y: 700, vx: 1200, vy: 0)
        _ = w.step(dt: 1.0 / 30)
        #expect(w.particles[0].vx > 100)
    }

    // MARK: Pets

    @Test func aPetWalkingThroughSnowLeavesFootprints() {
        var w = world(.winter)
        w.intensity = 0
        bury(&w, depth: 6)
        var pets: [WeatherPet] = []
        var x = 250.0
        for _ in 0..<90 {
            x += 50.0 / 30
            pets = [WeatherPet(id: "pup", x: x, y: 500, vx: 50, vy: 0, unit: 32)]
            _ = w.step(dt: 1.0 / 30, pets: pets)
        }
        let ledge = w.ledges[windowLedge(w)]
        let trodden = (ledge.index(x: 260)!..<ledge.index(x: 320)!).map { ledge.heights[$0] }.min()!
        #expect(trodden < 5.9)
    }

    @Test func aPetLandingInAPileThrowsUpAPuff() {
        var w = world(.autumn)
        w.intensity = 0
        bury(&w, depth: 6)
        _ = w.step(dt: 1.0 / 30, pets: [WeatherPet(id: "pup", x: 300, y: 520, vx: 0, vy: -600, unit: 32)])
        _ = w.step(dt: 1.0 / 30, pets: [WeatherPet(id: "pup", x: 300, y: 500, vx: 0, vy: 0, unit: 32)])
        #expect(w.particles.filter { $0.kind == .leaf }.count >= 4)
    }

    @Test func aPetNearBubblesGoesAfterThem() {
        var w = world(.summer)
        w.intensity = 0
        w.particles = [WeatherParticle(kind: .bubble, x: 360, y: 430, size: 10, life: 60)]
        let events = run(&w, seconds: 8, pets: [WeatherPet(id: "pup", x: 300, y: 500, vx: 0, vy: 0, unit: 32)])
        #expect(events.contains {
            switch $0 {
            case .nudge(let pet, let dx, _): pet == "pup" && dx > 0
            case .walk(let pet, let x): pet == "pup" && x > 300
            default: false
            }
        })
    }

    // MARK: Drawing

    @Test func aFlatPileIsOneQuad() {
        var w = world(.winter)
        bury(&w, depth: 4)
        var sprites: [WeatherSprite] = []
        w.pileSprites(into: &sprites)
        #expect(sprites.count == 1)
        #expect(sprites[0].rect.w == 2)
    }

    @Test func spriteLayoutMatchesTheShader() {
        #expect(MemoryLayout<WeatherSprite>.stride == 48)
    }
}
