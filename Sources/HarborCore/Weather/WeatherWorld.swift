import CoreGraphics
import Foundation

public enum WeatherParticleKind: UInt8, Sendable {
    case flake, leaf, petal, drop, splash, seed, firefly, bubble, chunk, puff
    /// A flower that was picked or fell off its ledge; it replants wherever it lands.
    case blossom
}

public struct WeatherParticle: Equatable, Sendable {
    public var kind: WeatherParticleKind
    public var x: Double
    public var y: Double
    public var vx = 0.0
    public var vy = 0.0
    /// Radius in points.
    public var size: Double
    public var angle = 0.0
    public var phase = 0.0
    /// Seconds left, for kinds that fade.
    public var life = 0.0
    public var tint: UInt8 = 0
    /// Area of pile it puts back where it lands; zero for the season's usual amount.
    public var mass = 0.0
}

/// A roaming pet as the weather sees it, in the screen's local coordinates.
public struct WeatherPet: Equatable, Sendable {
    public var id: String
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var unit: Double
    /// How keen it is to go and play: 0 while it can't or shouldn't (quiet, asleep, held), about 1 normally
    /// and more for a lively pet.
    public var playful: Double

    public init(id: String, x: Double, y: Double, vx: Double, vy: Double, unit: Double, playful: Double = 1) {
        self.id = id
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.unit = unit
        self.playful = playful
    }
}

public enum WeatherEvent: Equatable, Sendable {
    case splat(x: Double, y: Double)
    case popped(x: Double, y: Double)
    case snowman(x: Double, y: Double)
    /// A small hop the weather would like a pet to make, toward something to play with.
    case nudge(pet: String, dx: Double, dy: Double)
    /// A walk along the pet's ledge to `x`.
    case walk(pet: String, x: Double)
    /// How the pet should look for the next `seconds`; `ball` is the radius of a snowball in its paws.
    case pose(pet: String, pose: WeatherPetPose, seconds: Double, ball: Double)
}

/// Seeded so the simulation runs the same way under test.
public struct WeatherRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }

    public mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
}

/// How each season's pile behaves.
public struct SeasonTuning: Sendable {
    /// Particles a second across 1000 points of screen width at full intensity.
    public var rate: Double
    /// Steepest step between neighbouring columns before the pile slumps, on average.
    public var slope: Double
    /// How much the slope a column holds varies from column to column, as a fraction of `slope`.
    public var roughness: Double
    /// Depth an open end holds before it spills over.
    public var edgeHold: Double
    public var cap: Double
    /// Depth one settled particle adds to its column.
    public var deposit: Double
    /// Points a minute the pile loses while it is falling and while it is calm.
    public var melt: Double
    public var calmMelt: Double

    public static func of(_ season: Season) -> SeasonTuning {
        switch season {
        // Packed snow holds steeper, rougher slopes than loose leaf litter, which holds more than petals.
        case .winter: SeasonTuning(rate: 55, slope: 0.9, roughness: 0.8, edgeHold: 5, cap: 40, deposit: 1.6, melt: 0.1,
                                   calmMelt: 0.8)
        case .autumn: SeasonTuning(rate: 10, slope: 0.7, roughness: 0.6, edgeHold: 8, cap: 24, deposit: 2.2, melt: 0.15,
                                   calmMelt: 0.5)
        case .spring: SeasonTuning(rate: 12, slope: 0.5, roughness: 0.4, edgeHold: 3, cap: 6, deposit: 0.6, melt: 0.3,
                                   calmMelt: 0.8)
        case .summer: SeasonTuning(rate: 4, slope: 0.5, roughness: 0, edgeHold: 3, cap: 0, deposit: 0, melt: 1, calmMelt: 1)
        }
    }
}

/// All the weather on one screen: what falls, what has piled up, and what people and pets have made of it.
/// Coordinates are local to the screen, origin at its bottom left, y up.
public struct WeatherWorld: Sendable {
    public static let maxParticles = 900
    public static let gravity = 1100.0

    public var width: Double
    public var height: Double
    public var season: Season { didSet { if season != oldValue { seasonChanged() } } }
    public var intensity: Double
    public var accumulation: Bool
    public var interactions: Bool
    /// Local evening, when summer brings fireflies instead of seeds and bubbles.
    public var evening: Bool
    /// Share of the usual amount that falls, lowered to save power.
    public var detail = 1.0

    public internal(set) var ledges: [WeatherLedge] = []
    public internal(set) var particles: [WeatherParticle] = []
    public internal(set) var balls: [Snowball] = []
    /// Whatever the pointer has picked up: a handful of leaves or petals, cupped fireflies, a flower, a bubble
    /// being blown. They move with the pointer until let go.
    public internal(set) var carried: [WeatherParticle] = []
    public internal(set) var time = 0.0
    public internal(set) var wind = 0.0
    /// Whether it is falling right now; weather comes in spells with calm between them.
    public internal(set) var falling = true
    /// Seconds left of a spring shower.
    public internal(set) var shower = 0.0

    var rng: WeatherRandom
    var windTarget = 0.0
    var windClock = 0.0
    var gust = 0.0
    var gustStrength = 0.0
    var nextGust = 30.0
    var spellLeft: Double
    var nextShower: Double
    var spawnDebt = 0.0
    var meltClock = 0.0
    var nextBallID = 1
    var pointer: (x: Double, y: Double, vx: Double, vy: Double)?
    var hold: Hold?
    /// Where and when the current press began, whether it has moved off that spot yet, and whether it
    /// scooped a fresh ball, so a click, a hold and a drag can each mean something different.
    var press: Press?
    /// Where the pointer holding something is now.
    var grip = (x: 0.0, y: 0.0)
    var petMemory: [String: PetMemory] = [:]
    var events: [WeatherEvent] = []

    enum Hold: Equatable, Sendable {
        case ball(Int)
        case rake(ledgeY: Double, lastX: Double)
        /// Leaves or petals, cupped fireflies, a flower or a growing bubble, all in `carried`.
        case handful, jar, flower, bubble
        /// A snow angel pressed into the pile; nothing more happens until let go.
        case angel
    }

    struct Press: Sendable {
        var x: Double
        var y: Double
        var time: Double
        var moved = false
        var scooped = false
    }

    struct PetMemory: Sendable {
        var vy = 0.0
        var stride = 0.0
        var cooldown = 4.0
        var ball: Int?
        var still = 0.0
        var plan: PetPlan?
    }

    public init(width: Double, height: Double, season: Season, intensity: Double = 0.5, accumulation: Bool = true,
                interactions: Bool = true, evening: Bool = false, seed: UInt64 = 1) {
        self.width = width
        self.height = height
        self.season = season
        self.intensity = intensity
        self.accumulation = accumulation
        self.interactions = interactions
        self.evening = evening
        rng = WeatherRandom(seed: seed)
        spellLeft = rng.range(300, 600)
        nextShower = rng.range(40, 120)
    }

    public var tuning: SeasonTuning { SeasonTuning.of(season) }

    /// Nothing in the air and nothing settling: the screen only needs an occasional beat.
    public var isStill: Bool {
        particles.isEmpty && hold == nil && spawnRate == 0
            && !balls.contains { $0.state != .resting } && !ledges.contains(where: \.restless)
    }

    /// Particles a second this screen is spawning right now.
    public var spawnRate: Double {
        guard intensity > 0 else { return 0 }
        let scale = width / 1000 * (0.15 + intensity * 1.7) * detail
        switch season {
        case .summer:
            return evening ? 0 : tuning.rate * scale
        case .spring:
            return (falling ? tuning.rate * scale : 0) + (shower > 0 ? 160 * scale : 0)
        case .winter, .autumn:
            return falling ? tuning.rate * scale : 0
        }
    }

    private mutating func seasonChanged() {
        particles.removeAll()
        balls.removeAll()
        carried.removeAll()
        hold = nil
        press = nil
        for i in ledges.indices {
            ledges[i].heights = Array(repeating: 0, count: ledges[i].count)
            ledges[i].water = Array(repeating: 0, count: ledges[i].count)
            ledges[i].flowers = []
            ledges[i].restless = false
        }
        falling = true
        spellLeft = rng.range(300, 600)
    }

    // MARK: Surfaces

    /// Replaces the ledges with a new reading of the screen. Piles on ledges that are gone fall as chunks
    /// unless `quietly` (a Space switch, where the windows are only out of sight), and balls whose ground is
    /// gone start to fall.
    /// Windows report square frames but are drawn with round corners about this big.
    public static let windowCornerRadius = 20.0

    /// Pulls window ledges back from the corners of the windows they top, so snow doesn't hang in the air
    /// beside the curve. An end cut short by another window isn't at a corner and stays put.
    public static func roundingCorners(_ surfaces: [RoamSurface], windows: [CGRect]) -> [RoamSurface] {
        let r = windowCornerRadius
        return surfaces.compactMap { surface in
            guard surface.kind == .window else { return surface }
            var s = surface
            for w in windows where abs(w.maxY - s.y) < 0.5 {
                if abs(s.minX - w.minX) < 0.5 { s.minX += r }
                if abs(s.maxX - w.maxX) < 0.5 { s.maxX -= r }
            }
            return s.maxX > s.minX ? s : nil
        }
    }

    public mutating func setSurfaces(_ surfaces: [RoamSurface], quietly: Bool = false) {
        var next = surfaces.filter { $0.kind != .menuBar }
            .map { WeatherLedge(y: $0.y, minX: $0.minX, maxX: $0.maxX) }
            .filter { $0.count > 0 }
            .sorted { $0.y > $1.y }
        let spills = WeatherLedge.carry(from: ledges, into: &next)
        ledges = next
        if !quietly {
            for spill in spills { collapse(spill) }
        }
        var lost: [Int] = []
        for i in balls.indices where balls[i].state == .resting && balls[i].below == nil {
            guard let ground = balls[i].groundY,
                  !ledges.contains(where: { abs($0.y - ground) < 0.5 && $0.contains(x: balls[i].x) }) else { continue }
            if quietly {
                lost.append(balls[i].id)
            } else {
                balls[i].state = .flying
                balls[i].vy = 0
                balls[i].groundY = nil
            }
        }
        for id in lost { removeStack(id) }
    }

    /// The ledge a particle falling from `from` to `to` at `x` lands on: the highest pile top it reached
    /// whose ledge it was still above. A pile that grew past a particle within one step still catches it,
    /// where looking only below its last height would let it fall through and vanish.
    func ledgeHit(x: Double, from: Double, to: Double) -> Int? {
        var best: Int?
        var bestTop = -Double.infinity
        for i in ledges.indices where ledges[i].contains(x: x) && ledges[i].y <= from + 0.5 {
            let top = ledges[i].top(x: x)
            if top >= to, top > bestTop {
                best = i
                bestTop = top
            }
        }
        return best
    }

    /// The ledge whose pile top is highest at `x` among those at or below `y`.
    func ledgeBelow(x: Double, y: Double) -> Int? {
        var best: Int?
        var bestTop = -Double.infinity
        for i in ledges.indices where ledges[i].contains(x: x) {
            let top = ledges[i].top(x: x)
            if top <= y + 0.5, top > bestTop {
                best = i
                bestTop = top
            }
        }
        return best
    }

    // MARK: Step

    /// Advances by `dt` seconds with the roaming pets where they are now; returns what happened.
    public mutating func step(dt rawDt: Double, pets: [WeatherPet] = []) -> [WeatherEvent] {
        let dt = min(rawDt, 0.1)
        time += dt
        updateWind(dt)
        updateSpells(dt)
        spawn(dt)
        stepParticles(dt, pets: pets)
        stepCarried(dt)
        stepBalls(dt)
        stepPets(dt, pets)
        settle(dt)
        let result = events
        events.removeAll()
        return result
    }

    private mutating func updateWind(_ dt: Double) {
        windClock -= dt
        if windClock <= 0 {
            windClock = rng.range(6, 14)
            let reach = season == .autumn ? 40.0 : 22.0
            windTarget = rng.range(-reach, reach)
        }
        nextGust -= dt
        if nextGust <= 0 {
            nextGust = season == .autumn ? rng.range(20, 50) : rng.range(60, 150)
            gust = rng.range(2.5, 4.5)
            gustStrength = (rng.next() < 0.5 ? -1 : 1) * (season == .autumn ? rng.range(120, 200) : rng.range(50, 90))
            if season == .autumn { liftLitter(gustStrength) }
        }
        var target = windTarget
        if gust > 0 {
            gust -= dt
            target += gustStrength * sin(min(1, gust / 3) * .pi)
        }
        wind += (target - wind) * min(1, dt * 0.8)
    }

    private mutating func updateSpells(_ dt: Double) {
        spellLeft -= dt
        if spellLeft <= 0 {
            falling.toggle()
            spellLeft = falling ? rng.range(300, 600) : rng.range(60, 150)
        }
        guard season == .spring else { return }
        if shower > 0 {
            shower -= dt
        } else {
            nextShower -= dt
            if nextShower <= 0 {
                shower = rng.range(40, 70)
                nextShower = rng.range(180, 360)
            }
        }
    }

    // MARK: Spawning

    private mutating func spawn(_ dt: Double) {
        if season == .summer, evening {
            let wanted = Int((6 + intensity * 30) * detail)
            var fireflies = particles.reduce(0) { $0 + ($1.kind == .firefly ? 1 : 0) }
            while fireflies < wanted, rng.next() < dt * 2 { addFirefly(); fireflies += 1 }
            return
        }
        spawnDebt += spawnRate * dt
        while spawnDebt >= 1 {
            spawnDebt -= 1
            guard particles.count < Self.maxParticles else { spawnDebt = 0; return }
            addFalling()
        }
    }

    private mutating func addFalling() {
        let margin = abs(wind) * 4
        let x = rng.range(-margin, width + margin)
        let y = height + rng.range(2, 30)
        switch season {
        case .winter:
            let size = rng.range(1.2, 3.4)
            particles.append(WeatherParticle(kind: .flake, x: x, y: y, vy: -40, size: size, phase: rng.range(0, 6.28)))
        case .autumn:
            particles.append(WeatherParticle(kind: .leaf, x: x, y: y, vy: -40, size: rng.range(5, 8),
                                             angle: rng.range(0, 6.28), phase: rng.range(0, 6.28),
                                             tint: UInt8(rng.next() * 5)))
        case .spring:
            if shower > 0, rng.next() < 0.93 {
                particles.append(WeatherParticle(kind: .drop, x: x, y: y, vy: -650, size: rng.range(0.6, 1.0)))
            } else {
                particles.append(WeatherParticle(kind: .petal, x: x, y: y, vy: -30, size: rng.range(3, 4.5),
                                                 angle: rng.range(0, 6.28), phase: rng.range(0, 6.28),
                                                 tint: UInt8(rng.next() * 3)))
            }
        case .summer:
            if rng.next() < 0.22 {
                let floor = rng.range(40, width - 40)
                particles.append(WeatherParticle(kind: .bubble, x: floor, y: rng.range(10, height * 0.3), vy: 25,
                                                 size: rng.range(8, 18), phase: rng.range(0, 6.28),
                                                 life: rng.range(10, 18)))
            } else {
                let fromSide = wind >= 0 ? -10.0 : width + 10
                let start = rng.next() < 0.5 ? (fromSide, rng.range(height * 0.3, height * 0.9)) : (x, y)
                particles.append(WeatherParticle(kind: .seed, x: start.0, y: start.1, size: rng.range(4, 6),
                                                 phase: rng.range(0, 6.28), life: rng.range(25, 40)))
            }
        }
    }

    private mutating func addFirefly() {
        particles.append(WeatherParticle(kind: .firefly, x: rng.range(0, width), y: rng.range(20, height * 0.55),
                                         vx: rng.range(-15, 15), vy: rng.range(-8, 8), size: rng.range(2.5, 4),
                                         phase: rng.range(0, 6.28), life: rng.range(12, 25)))
    }

    /// Falling chunks for `area` of pile that tipped off an edge or burst from a ball.
    mutating func spawnChunks(x: Double, y: Double, area: Double, vx: Double) {
        guard area > 0 else { return }
        if season != .winter {
            // Leaves and petals fall back as themselves rather than as clumps.
            let count = min(12, Int(area / (tuning.deposit * WeatherLedge.column)) + 1)
            for _ in 0..<count where particles.count < Self.maxParticles {
                kick(x: x + rng.range(-4, 4), y: y, vx: vx + rng.range(-30, 30), vy: rng.range(-20, 40),
                     mass: area / Double(count))
            }
            return
        }
        var left = area
        while left > 0.5, particles.count < Self.maxParticles {
            let piece = min(left, rng.range(6, 18))
            left -= piece
            particles.append(WeatherParticle(kind: .chunk, x: x + rng.range(-3, 3), y: y + rng.range(-2, 2),
                                             vx: vx + rng.range(-15, 15), vy: rng.range(-10, 20),
                                             size: (piece / .pi).squareRoot(), angle: rng.range(0, 6.28),
                                             phase: rng.range(-5, 5), mass: piece))
        }
    }

    /// A run of pile whose ledge went away breaks up and falls as what it is made of: snow as tumbling clods
    /// of every size with loose powder between them, leaves and petals one by one, puddles as drops and
    /// flowers as flowers. Each piece carries its share, so what lands below adds up to what fell.
    mutating func collapse(_ spill: WeatherLedge.Spill) {
        let half = spill.width / 2
        if spill.area > 0.5 {
            switch season {
            case .winter:
                let powder = spill.area * 0.2
                var left = spill.area - powder
                while left > 0.5, particles.count < Self.maxParticles {
                    // Mostly small clods with the odd big slab, the way a cornice breaks.
                    let piece = min(left, rng.next() < 0.2 ? rng.range(16, 40) : rng.range(3, 14))
                    left -= piece
                    particles.append(WeatherParticle(kind: .chunk, x: spill.x + rng.range(-half, half),
                                                     y: spill.y + rng.range(0, max(1, spill.depth)),
                                                     vx: rng.range(-25, 25), vy: rng.range(-30, 30),
                                                     size: (piece / .pi).squareRoot(), angle: rng.range(0, 6.28),
                                                     phase: rng.range(-6, 6), mass: piece))
                }
                let loose = powder + max(0, left)
                let count = min(24, Int(loose / 3) + 1)
                for _ in 0..<count where particles.count < Self.maxParticles {
                    particles.append(WeatherParticle(kind: .flake, x: spill.x + rng.range(-half, half),
                                                     y: spill.y + rng.range(0, max(1, spill.depth)),
                                                     vx: rng.range(-20, 20), vy: rng.range(-140, -40),
                                                     size: rng.range(1.2, 2.6), phase: rng.range(0, 6.28),
                                                     mass: loose / Double(count)))
                }
            case .autumn, .spring:
                let each = tuning.deposit * WeatherLedge.column
                let count = max(1, min(season == .autumn ? 60 : 40, Int((spill.area / each).rounded())))
                for _ in 0..<count {
                    kick(x: spill.x + rng.range(-half, half), y: spill.y + rng.range(0, max(1, spill.depth)),
                         vx: rng.range(-30, 30), vy: rng.range(-50, 20), mass: spill.area / Double(count))
                }
            case .summer:
                break
            }
        }
        if spill.water > 0.3 {
            for _ in 0..<min(30, Int(spill.water / 0.6) + 1) where particles.count < Self.maxParticles {
                particles.append(WeatherParticle(kind: .drop, x: spill.x + rng.range(-half, half), y: spill.y + 1,
                                                 vx: rng.range(-20, 20), vy: rng.range(-260, -90),
                                                 size: rng.range(0.6, 1.0)))
            }
        }
        for tint in spill.blooms where particles.count < Self.maxParticles {
            particles.append(WeatherParticle(kind: .blossom, x: spill.x + rng.range(-half, half), y: spill.y + 4,
                                             vx: rng.range(-30, 30), vy: rng.range(-20, 40), size: 2.2,
                                             phase: rng.range(0, 6.28), tint: tint))
        }
    }

    /// One particle of the season's pile thrown into the air, by a pet's step, the pointer or a gust.
    /// `mass` is the area of pile it puts back where it lands; zero for a puff of snow, which melts in the air.
    mutating func kick(x: Double, y: Double, vx: Double, vy: Double, mass: Double = 0) {
        guard particles.count < Self.maxParticles else { return }
        switch season {
        case .winter:
            if mass > 0 {
                particles.append(WeatherParticle(kind: .flake, x: x, y: y, vx: vx, vy: vy, size: rng.range(1.2, 2.4),
                                                 phase: rng.range(0, 6.28), mass: mass))
            } else {
                particles.append(WeatherParticle(kind: .puff, x: x, y: y, vx: vx, vy: vy, size: rng.range(1, 2.2),
                                                 life: rng.range(0.5, 0.9)))
            }
        case .autumn:
            particles.append(WeatherParticle(kind: .leaf, x: x, y: y, vx: vx, vy: vy, size: rng.range(5, 8),
                                             angle: rng.range(0, 6.28), phase: rng.range(0, 6.28),
                                             tint: UInt8(rng.next() * 5), mass: mass))
        case .spring:
            particles.append(WeatherParticle(kind: .petal, x: x, y: y, vx: vx, vy: vy, size: rng.range(3, 4.5),
                                             angle: rng.range(0, 6.28), phase: rng.range(0, 6.28),
                                             tint: UInt8(rng.next() * 3), mass: mass))
        case .summer:
            break
        }
    }

    /// An autumn gust picks leaves off the tops of the piles.
    private mutating func liftLitter(_ strength: Double) {
        for i in ledges.indices {
            var c = Int(rng.range(0, 6))
            while c < ledges[i].count {
                if ledges[i].heights[c] > 3, rng.next() < 0.5 {
                    let x = ledges[i].centerX(c)
                    let top = ledges[i].y + ledges[i].heights[c]
                    let area = ledges[i].take(x: x, radius: 1, amount: tuning.deposit)
                    kick(x: x, y: top, vx: strength * 0.4, vy: rng.range(60, 140), mass: area)
                }
                c += Int(rng.range(6, 16))
            }
        }
    }

    // MARK: Particles

    private mutating func stepParticles(_ dt: Double, pets: [WeatherPet]) {
        let ease = min(1, dt * 1.5)
        var i = 0
        while i < particles.count {
            var p = particles[i]
            let prevY = p.y
            var alive = true
            switch p.kind {
            case .flake:
                let sway = sin(p.phase + time * 1.3) * 10
                p.vx += (wind * (0.5 + p.size * 0.15) + sway - p.vx) * ease
                p.vy += (-(22 + p.size * 8) - p.vy) * ease
            case .leaf, .petal:
                let leaf = p.kind == .leaf
                let swing = sin(p.phase + time * (leaf ? 1.7 : 2.1))
                p.vx += (wind + swing * (leaf ? 45 : 28) - p.vx) * min(1, dt * 2)
                let fall = (leaf ? 34 : 24) + abs(swing) * (leaf ? 26 : 12)
                p.vy += (-fall - p.vy) * min(1, dt * 2.5)
                p.angle = swing * (leaf ? 1.0 : 0.7) + p.phase
            case .drop:
                p.vx += (wind * 0.4 - p.vx) * ease
            case .splash, .puff:
                p.vy -= Self.gravity * 0.6 * dt
                p.life -= dt
                alive = p.life > 0
            case .chunk:
                p.vy -= Self.gravity * dt
                // Clods tumble as they fall.
                p.angle += p.phase * dt
            case .blossom:
                p.vx += (wind * 0.3 - p.vx) * min(1, dt * 1.5)
                p.vy = max(-240, p.vy - Self.gravity * 0.4 * dt)
                p.angle = sin(p.phase + time * 3) * 0.4
            case .seed:
                p.vx += (wind * 1.6 + sin(p.phase + time * 0.9) * 8 - p.vx) * min(1, dt * 0.8)
                p.vy += (-10 + sin(p.phase + time * 0.6) * 14 - p.vy) * min(1, dt * 0.8)
                p.angle += dt * p.vx * 0.02
                p.life -= dt
                alive = p.life > 0
            case .firefly:
                p.vx += rng.range(-1, 1) * 70 * dt
                p.vy += rng.range(-1, 1) * 50 * dt + (p.y < 20 ? 30 * dt : 0) + (p.y > height * 0.6 ? -30 * dt : 0)
                for pet in pets {
                    let dx = p.x - pet.x, dy = p.y - (pet.y + pet.unit * 0.5)
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d < pet.unit * 1.6, d > 0.1 { p.vx += dx / d * 140 * dt; p.vy += dy / d * 140 * dt }
                }
                let speed = (p.vx * p.vx + p.vy * p.vy).squareRoot()
                if speed > 30 { p.vx *= 30 / speed; p.vy *= 30 / speed }
                p.life -= dt
                alive = p.life > 0
            case .bubble:
                p.vx += (wind * 0.5 + sin(p.phase + time * 2) * 12 - p.vx) * ease
                p.vy += (28 - p.vy) * ease
                p.life -= dt
                if p.life <= 0 || p.y > height - p.size {
                    pop(p)
                    alive = false
                }
                for pet in pets where alive {
                    let dx = p.x - pet.x, dy = p.y - (pet.y + pet.unit * 0.5)
                    if dx * dx + dy * dy < pow(pet.unit * 0.5 + p.size, 2) {
                        pop(p)
                        alive = false
                    }
                }
            }
            if alive, let pointer {
                let speed2 = pointer.vx * pointer.vx + pointer.vy * pointer.vy
                if speed2 > 150 * 150 {
                    let dx = p.x - pointer.x, dy = p.y - pointer.y
                    let reach = 70.0
                    let d2 = dx * dx + dy * dy
                    if d2 < reach * reach {
                        let falloff = 1 - d2.squareRoot() / reach
                        let pull = falloff * min(1, dt * 10) * (p.kind == .chunk || p.kind == .drop ? 0.2 : 1)
                        p.vx += (pointer.vx * 0.7 - p.vx) * pull
                        p.vy += (pointer.vy * 0.7 - p.vy) * pull
                    }
                }
            }
            p.x += p.vx * dt
            p.y += p.vy * dt
            if alive, p.vy < 0, p.kind != .splash, p.kind != .puff, p.kind != .firefly, p.kind != .bubble,
               let li = ledgeHit(x: p.x, from: prevY, to: p.y) {
                land(p, on: li)
                alive = false
            }
            if alive, p.y < -20 || p.x < -80 || p.x > width + 80 || p.y > height + 80 { alive = false }
            if alive {
                particles[i] = p
                i += 1
            } else {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
            }
        }
    }

    private mutating func land(_ p: WeatherParticle, on li: Int) {
        let t = tuning
        switch p.kind {
        case .flake:
            // Snow that fell off something lands whatever the setting, so a closed window's pile isn't lost.
            if p.mass > 0 {
                ledges[li].deposit(x: p.x, amount: p.mass / WeatherLedge.column, cap: t.cap)
            } else if accumulation {
                ledges[li].deposit(x: p.x, amount: t.deposit * p.size / 2.3, cap: t.cap)
            }
        case .leaf, .petal:
            if p.mass > 0 {
                ledges[li].deposit(x: p.x, amount: p.mass / WeatherLedge.column, cap: t.cap)
            } else if accumulation {
                ledges[li].deposit(x: p.x, amount: t.deposit, cap: t.cap)
            }
        case .chunk:
            let top = ledges[li].top(x: p.x)
            let area = p.mass > 0 ? p.mass : .pi * p.size * p.size
            // A clod lands as a clod: a small lopsided lump, a little of it bursting into powder.
            mound(on: li, x: p.x + p.vx * 0.01, area: area,
                  halfWidth: max(WeatherLedge.column, p.size * rng.range(0.8, 1.3)))
            let speed = (p.vx * p.vx + p.vy * p.vy).squareRoot()
            for _ in 0..<(speed > 300 ? 3 : 1) { kick(x: p.x, y: top, vx: rng.range(-50, 50), vy: rng.range(40, 110)) }
        case .blossom:
            replant(p, on: li)
        case .drop:
            let top = ledges[li].top(x: p.x)
            for _ in 0..<2 where particles.count < Self.maxParticles {
                particles.append(WeatherParticle(kind: .splash, x: p.x, y: top + 1, vx: rng.range(-50, 50),
                                                 vy: rng.range(50, 110), size: 0.9, life: 0.35))
            }
            if accumulation, ledges[li].y > 0.5, let c = ledges[li].index(x: p.x) {
                ledges[li].water[c] = min(3, ledges[li].water[c] + 0.35)
                // Water runs to the sides so a puddle spreads into a shallow pool.
                for n in [c - 1, c + 1] where n >= 0 && n < ledges[li].count {
                    ledges[li].water[n] = min(3, ledges[li].water[n] + 0.15)
                }
            }
        default:
            break
        }
    }

    /// Puts down `area` of pile as a rounded bump about `halfWidth` either side of `x`, each column a little
    /// more or less than its neighbours so it never comes out as a neat cone. Columns past the ledge's ends
    /// are moved in, so none of it is lost.
    mutating func mound(on li: Int, x: Double, area: Double, halfWidth: Double) {
        guard area > 0, ledges[li].count > 0 else { return }
        let ledge = ledges[li]
        let first = ledge.index(x: min(max(x - halfWidth, ledge.minX), ledge.maxX - 0.01)) ?? 0
        let last = ledge.index(x: min(max(x + halfWidth, ledge.minX), ledge.maxX - 0.01)) ?? ledge.count - 1
        var weights: [Double] = []
        weights.reserveCapacity(last - first + 1)
        for i in first...last {
            let d = (ledge.centerX(i) - x) / max(halfWidth, 1)
            weights.append(max(0.05, 1 - d * d) * rng.range(0.55, 1.45))
        }
        let total = weights.reduce(0, +)
        for (k, i) in (first...last).enumerated() {
            ledges[li].heights[i] = min(tuning.cap, ledges[li].heights[i] + area * weights[k] / total / WeatherLedge.column)
        }
        ledges[li].mark(first, last)
    }

    /// Spreads `area` of pile over the columns in `x ± radius`.
    mutating func depositArea(on li: Int, x: Double, area: Double, radius: Double) {
        let columns = max(1, Int(radius * 2 / WeatherLedge.column))
        let each = area / Double(columns) / WeatherLedge.column
        for k in 0..<columns {
            let cx = x - radius + (Double(k) + 0.5) * WeatherLedge.column
            ledges[li].deposit(x: cx, amount: each, cap: tuning.cap)
        }
    }

    mutating func pop(_ p: WeatherParticle) {
        events.append(.popped(x: p.x, y: p.y))
        for k in 0..<8 where particles.count < Self.maxParticles {
            let a = Double(k) / 8 * 2 * .pi
            particles.append(WeatherParticle(kind: .splash, x: p.x + cos(a) * p.size, y: p.y + sin(a) * p.size,
                                             vx: cos(a) * 60, vy: sin(a) * 60 + 30, size: 0.9, life: 0.3, tint: 1))
        }
    }

    // MARK: Settling

    private mutating func settle(_ dt: Double) {
        let t = tuning
        for i in ledges.indices where ledges[i].restless {
            let spill = ledges[i].relax(slope: t.slope, edgeHold: t.edgeHold, roughness: t.roughness, rate: 0.5)
            if spill.left > 0.5 {
                spawnChunks(x: ledges[i].minX - 2, y: ledges[i].y + t.edgeHold, area: spill.left, vx: -12)
            }
            if spill.right > 0.5 {
                spawnChunks(x: ledges[i].maxX + 2, y: ledges[i].y + t.edgeHold, area: spill.right, vx: 12)
            }
        }
        meltClock += dt
        guard meltClock >= 1 else { return }
        let elapsed = meltClock
        meltClock = 0
        let rate = (falling && season != .summer ? t.melt : t.calmMelt) / 60
        for i in ledges.indices {
            ledges[i].melt(depth: rate * elapsed, dry: elapsed / 40)
            growFlowers(i, elapsed)
        }
        meltBalls(elapsed)
    }

    private mutating func growFlowers(_ li: Int, _ elapsed: Double) {
        guard season == .spring else { return }
        var ledge = ledges[li]
        for f in ledge.flowers.indices {
            ledge.flowers[f].age += elapsed
            ledge.flowers[f].growth = min(1, ledge.flowers[f].growth + elapsed / 20)
        }
        ledge.flowers.removeAll { $0.age > 240 }
        // Puddles that have stood a while leave flowers behind once the shower passes.
        if shower <= 0, ledge.y > 0.5, ledge.flowers.count < max(1, ledge.count / 30) {
            for c in stride(from: Int(rng.range(0, 10)), to: ledge.count, by: 10)
            where ledge.water[c] > 0.6 && rng.next() < 0.15 && !ledge.flowers.contains(where: { abs($0.column - c) < 6 }) {
                ledge.flowers.append(WeatherFlower(column: c, tint: UInt8(rng.next() * 4)))
            }
        }
        ledges[li] = ledge
    }
}
