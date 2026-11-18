import Foundation

/// How a playing pet is drawn for a moment, on top of whatever its body is doing.
public enum WeatherPetPose: String, Equatable, Sendable {
    case none
    /// Rolling over and over through a pile.
    case roll
    /// A snowball held in its paws.
    case carry
    /// The flick of a throw.
    case toss
    /// A crouch and spring at something.
    case pounce
    /// Shaking itself off.
    case shake
    /// Nose down to a flower.
    case sniff
}

/// Things a pet can go and play with.
public enum WeatherPlayKind: Equatable, Sendable {
    /// Jump into a deep pile, roll about in it and shake off.
    case dive
    /// Push a snowball along a drift so it grows.
    case scoop
    /// Pick up a small snowball, then throw it or stack it on a bigger one.
    case fetch
    case chaseLeaf, chasePetal
    /// Jump into a puddle.
    case splash
    case sniff
    case chaseBubble, chaseFirefly
    case snapSeed
}

/// Something worth going to, found near a pet: where it is, how tempting, and which ball for `.fetch`.
public struct WeatherPlayOption: Equatable, Sendable {
    public var kind: WeatherPlayKind
    public var x: Double
    public var y: Double
    public var weight: Double
    public var ball: Int?

    public init(kind: WeatherPlayKind, x: Double, y: Double, weight: Double, ball: Int? = nil) {
        self.kind = kind
        self.x = x
        self.y = y
        self.weight = weight
        self.ball = ball
    }
}

/// The choices behind a pet's play, kept apart from the world so they can be tried with chosen dice.
public enum WeatherPlayBrain {
    /// One of `options` picked in proportion to its weight by `dice` in 0..<1; nil when there are none.
    public static func pick(_ options: [WeatherPlayOption], dice: Double) -> WeatherPlayOption? {
        let total = options.reduce(0) { $0 + max(0, $1.weight) }
        guard total > 0 else { return nil }
        var left = dice * total
        for option in options where option.weight > 0 {
            left -= option.weight
            if left < 0 { return option }
        }
        return options.last { $0.weight > 0 }
    }

    /// Seconds before a pet looks for something to play with again: a while, so play stays a treat, and
    /// sooner for a livelier pet.
    public static func pause(playful: Double, dice: Double) -> Double {
        (14 + dice * 22) / min(max(playful, 0.25), 2)
    }

    /// How often a free pet looks around when it found nothing to play with.
    public static let recheck = 3.0
}

/// What a pet is in the middle of playing at.
struct PetPlan: Sendable {
    enum Step: Sendable {
        /// Walking over to it.
        case approach
        /// In the air, jumping in or pouncing.
        case leap
        case roll
        case shake
        /// Holding a ball, sniffing a flower, pushing a ball: a while in place or on the move.
        case hold
        /// Carrying a ball over to a bigger one to stack it.
        case carry
        /// Running after something it threw.
        case chase
        case push
    }

    var kind: WeatherPlayKind
    var step: Step = .approach
    /// Where it is headed, and for a chase the height of what it is after.
    var x: Double
    var y: Double
    var clock = 0.0
    var total = 0.0
    var walkAsked = -10.0
    var dir = 1.0
    /// Radius of a ball in its paws.
    var ball = 0.0
    var target: Int?
}

extension WeatherWorld {
    /// What a pet standing on a ledge could go and play with now, for this season.
    public func playOptions(for pet: WeatherPet) -> [WeatherPlayOption] {
        guard let li = ledges.firstIndex(where: { abs($0.y - pet.y) < 1.5 && $0.contains(x: pet.x) }) else { return [] }
        let ledge = ledges[li]
        var options: [WeatherPlayOption] = []
        let reach = 220.0

        /// The nearest column within reach holding at least `minimum`.
        func nearest(_ values: [Double], minimum: Double) -> Double? {
            var best: Double?
            for c in stride(from: 0, to: ledge.count, by: 2) where values[c] >= minimum {
                let dx = ledge.centerX(c) - pet.x
                if abs(dx) < reach, best.map({ abs(dx) < abs($0 - pet.x) }) ?? true { best = ledge.centerX(c) }
            }
            return best
        }

        /// The nearest particle of `kind` within reach, above the pet's feet but not far above.
        func particle(_ kind: WeatherParticleKind, above: ClosedRange<Double>) -> WeatherParticle? {
            var best: WeatherParticle?
            for p in particles where p.kind == kind && abs(p.x - pet.x) < reach && above.contains(p.y - pet.y) {
                if best.map({ abs(p.x - pet.x) < abs($0.x - pet.x) }) ?? true { best = p }
            }
            return best
        }

        switch season {
        case .winter:
            if let x = nearest(ledge.heights, minimum: 5) { options.append(.init(kind: .dive, x: x, y: ledge.y, weight: 1)) }
            if accumulation, let x = nearest(ledge.heights, minimum: 3) {
                options.append(.init(kind: .scoop, x: x, y: ledge.y, weight: 1))
            }
            let small = balls.filter { b in
                b.state == .resting && b.below == nil && !b.snowman && b.r <= pet.unit * 0.35
                    && b.groundY.map { abs($0 - ledge.y) < 0.5 } == true && abs(b.x - pet.x) < reach
                    && !balls.contains { $0.below == b.id }
            }
            if let b = small.min(by: { abs($0.x - pet.x) < abs($1.x - pet.x) }) {
                options.append(.init(kind: .fetch, x: b.x, y: b.y, weight: 1.2, ball: b.id))
            }
        case .autumn:
            if let x = nearest(ledge.heights, minimum: 5) { options.append(.init(kind: .dive, x: x, y: ledge.y, weight: 1.5)) }
            if let leaf = particle(.leaf, above: 0...260) {
                options.append(.init(kind: .chaseLeaf, x: leaf.x, y: leaf.y, weight: 1))
            }
        case .spring:
            if let x = nearest(ledge.water, minimum: 0.6) { options.append(.init(kind: .splash, x: x, y: ledge.y, weight: 1.2)) }
            if let flower = ledge.flowers.filter({ $0.growth > 0.5 })
                .min(by: { abs(ledge.centerX($0.column) - pet.x) < abs(ledge.centerX($1.column) - pet.x) }),
               abs(ledge.centerX(flower.column) - pet.x) < reach {
                options.append(.init(kind: .sniff, x: ledge.centerX(flower.column), y: ledge.y, weight: 1))
            }
            if let petal = particle(.petal, above: 0...220) {
                options.append(.init(kind: .chasePetal, x: petal.x, y: petal.y, weight: 0.8))
            }
            if let x = nearest(ledge.heights, minimum: 3) { options.append(.init(kind: .dive, x: x, y: ledge.y, weight: 0.6)) }
        case .summer:
            if let bubble = particle(.bubble, above: 0...220) {
                options.append(.init(kind: .chaseBubble, x: bubble.x, y: bubble.y, weight: 1.2))
            }
            if let fly = particle(.firefly, above: 0...200) {
                options.append(.init(kind: .chaseFirefly, x: fly.x, y: fly.y, weight: 1))
            }
            if let seed = particle(.seed, above: 0...140) {
                options.append(.init(kind: .snapSeed, x: seed.x, y: seed.y, weight: 0.8))
            }
        }
        return options
    }

    /// What a pet is playing at, if anything.
    public func playing(_ pet: String) -> WeatherPlayKind? { petMemory[pet]?.plan?.kind }

    /// Looks for something to play with when the pet has been free long enough, and otherwise carries on
    /// with whatever it is playing at. `li` is the ledge it stands on, if any.
    mutating func play(_ pet: WeatherPet, _ memory: inout PetMemory, li: Int?, dt: Double) {
        guard pet.playful > 0 else {
            memory.plan = nil
            return
        }
        if var plan = memory.plan {
            plan.clock += dt
            plan.total += dt
            memory.plan = advance(plan, pet, &memory, li: li, dt: dt)
            if memory.plan == nil { memory.cooldown = WeatherPlayBrain.pause(playful: pet.playful, dice: rng.next()) }
            return
        }
        memory.cooldown -= dt
        guard memory.cooldown <= 0, li != nil, abs(pet.vy) < 1, memory.ball == nil else { return }
        guard let option = WeatherPlayBrain.pick(playOptions(for: pet), dice: rng.next()) else {
            memory.cooldown = WeatherPlayBrain.recheck
            return
        }
        var plan = PetPlan(kind: option.kind, x: option.x, y: option.y)
        plan.dir = option.x >= pet.x ? 1 : -1
        plan.target = option.ball
        memory.plan = plan
    }

    private mutating func say(_ pet: WeatherPet, _ pose: WeatherPetPose, _ seconds: Double, ball: Double = 0) {
        events.append(.pose(pet: pet.id, pose: pose, seconds: seconds, ball: ball))
    }

    /// The nearest particle of `kind` to where a chased one was last seen.
    private func find(_ kind: WeatherParticleKind, near x: Double, _ y: Double, within: Double) -> Int? {
        var best: Int?
        var bestD = within * within
        for i in particles.indices where particles[i].kind == kind {
            let dx = particles[i].x - x, dy = particles[i].y - y
            if dx * dx + dy * dy < bestD {
                bestD = dx * dx + dy * dy
                best = i
            }
        }
        return best
    }

    private var chased: [WeatherPlayKind: WeatherParticleKind] {
        [.chaseLeaf: .leaf, .chasePetal: .petal, .chaseBubble: .bubble, .chaseFirefly: .firefly, .snapSeed: .seed]
    }

    /// One step of a plan; nil once it is over.
    private mutating func advance(_ plan: PetPlan, _ pet: WeatherPet, _ memory: inout PetMemory, li: Int?,
                                  dt: Double) -> PetPlan? {
        var plan = plan
        guard plan.total < 16 else { return nil }
        let unit = pet.unit
        switch plan.step {
        case .approach:
            if let kind = chased[plan.kind] {
                guard let i = find(kind, near: plan.x, plan.y, within: 80) else { return nil }
                plan.x = particles[i].x
                plan.y = particles[i].y
            }
            if plan.kind == .fetch {
                guard let id = plan.target, let b = balls.firstIndex(where: { $0.id == id }), balls[b].state == .resting
                else { return nil }
                plan.x = balls[b].x
            }
            guard plan.clock < 9, li != nil else { return plan.clock < 9 && abs(pet.vy) > 1 ? plan : nil }
            let dx = plan.x - pet.x
            plan.dir = dx >= 0 ? 1 : -1
            let reach = plan.kind == .dive || plan.kind == .splash ? unit * 1.3 : unit * 0.7
            if abs(dx) > reach {
                // Asked again only if the pet stopped short or is wandering off.
                if plan.total - plan.walkAsked > 2.5 || (plan.total - plan.walkAsked > 0.8 && abs(pet.vx) < 5) {
                    events.append(.walk(pet: pet.id, x: plan.x - plan.dir * reach * 0.6))
                    plan.walkAsked = plan.total
                }
                return plan
            }
            return act(plan, pet, &memory, li: li)
        case .leap:
            if let kind = chased[plan.kind], let i = find(kind, near: pet.x, pet.y + unit * 0.6, within: unit * 0.8) {
                caught(i, by: pet)
            }
            guard plan.clock > 0.2, abs(pet.vy) < 1, let li else { return plan.clock < 3 ? plan : nil }
            switch plan.kind {
            case .dive:
                burst(on: li, x: pet.x, power: 1.6)
                say(pet, .roll, 1.8)
                events.append(.walk(pet: pet.id, x: pet.x + plan.dir * unit * 1.8))
                plan.step = .roll
            case .splash:
                splash(x: pet.x, y: ledges[li].y + 1, count: 10)
                say(pet, .shake, 0.7)
                plan.step = .shake
            default:
                // Now and then it shakes itself off after a pounce, mostly it just carries on.
                guard rng.next() < 0.3 else { return nil }
                say(pet, .shake, 0.6)
                plan.step = .shake
            }
            plan.clock = 0
            return plan
        case .roll:
            if let li, let c = ledges[li].index(x: pet.x) {
                // Rolling ploughs a trough and banks what it moves up either side.
                let depth = ledges[li].heights[c]
                let area = ledges[li].take(x: pet.x, radius: unit * 0.25, amount: depth * 1.2 * dt)
                if area > 0 {
                    mound(on: li, x: pet.x - unit * 0.5, area: area * 0.5, halfWidth: unit * 0.2)
                    mound(on: li, x: pet.x + unit * 0.5, area: area * 0.5, halfWidth: unit * 0.2)
                }
                if depth > 1, rng.next() < dt * 12 {
                    kick(x: pet.x + rng.range(-unit * 0.3, unit * 0.3), y: ledges[li].y + depth,
                         vx: rng.range(-90, 90), vy: rng.range(60, 160))
                }
            }
            guard plan.clock > 1.8 else { return plan }
            say(pet, .shake, 0.7)
            plan.step = .shake
            plan.clock = 0
            return plan
        case .shake:
            if rng.next() < dt * 30 { shakeOff(pet) }
            return plan.clock > 0.7 ? nil : plan
        case .hold:
            switch plan.kind {
            case .sniff:
                guard plan.clock > 1.6 else { return plan }
                for _ in 0..<2 {
                    kick(x: pet.x + plan.dir * unit * 0.4, y: pet.y + unit * 0.3, vx: rng.range(-20, 20),
                         vy: rng.range(40, 80))
                }
                return nil
            case .fetch:
                guard plan.clock > 1.2 else { return plan }
                if let li, let base = stackBase(for: plan.ball, near: pet.x, on: ledges[li].y) {
                    plan.target = base
                    plan.step = .carry
                    plan.clock = 0
                    plan.walkAsked = -10
                    return plan
                }
                toss(&plan, pet)
                return plan
            default:
                return nil
            }
        case .carry:
            guard let id = plan.target, let b = balls.firstIndex(where: { $0.id == id }), balls[b].state == .resting,
                  !balls.contains(where: { $0.below == id }), plan.clock < 8 else {
                toss(&plan, pet)
                return plan
            }
            let dx = balls[b].x - pet.x
            if abs(dx) > unit * 0.9 {
                if plan.total - plan.walkAsked > 1.5 {
                    events.append(.walk(pet: pet.id, x: balls[b].x - (dx > 0 ? 1 : -1) * unit * 0.6))
                    say(pet, .carry, 2, ball: plan.ball)
                    plan.walkAsked = plan.total
                }
                return plan
            }
            // Set down on top, where it settles and maybe makes a snowman.
            var ball = Snowball(id: nextBallID, x: balls[b].x, y: balls[b].y + balls[b].r + plan.ball + 4,
                                r: plan.ball, state: .flying)
            ball.vy = -20
            balls.append(ball)
            nextBallID += 1
            say(pet, .toss, 0.35)
            return nil
        case .chase:
            if plan.total - plan.walkAsked > 1 {
                events.append(.walk(pet: pet.id, x: plan.x))
                plan.walkAsked = plan.total
            }
            return plan.clock > 2.5 ? nil : plan
        case .push:
            return memory.ball == nil || plan.clock > 6 ? nil : plan
        }
    }

    /// The pet has reached what it was after.
    private mutating func act(_ plan: PetPlan, _ pet: WeatherPet, _ memory: inout PetMemory, li: Int?) -> PetPlan? {
        var plan = plan
        plan.clock = 0
        let unit = pet.unit
        switch plan.kind {
        case .dive, .splash:
            events.append(.nudge(pet: pet.id, dx: plan.dir * 90, dy: 290))
            say(pet, .pounce, 0.4)
            plan.step = .leap
        case .scoop:
            guard let li, startPush(pet, &memory, li: li, dir: plan.dir) else { return nil }
            events.append(.walk(pet: pet.id, x: pet.x + plan.dir * unit * 5))
            plan.step = .push
        case .fetch:
            guard let id = plan.target, let b = balls.firstIndex(where: { $0.id == id }) else { return nil }
            plan.ball = balls[b].r
            removeStack(id)
            say(pet, .carry, 1.5, ball: plan.ball)
            plan.step = .hold
        case .sniff:
            say(pet, .sniff, 1.6)
            plan.step = .hold
        case .snapSeed:
            say(pet, .pounce, 0.3)
            if let i = find(.seed, near: pet.x, pet.y + unit * 0.6, within: unit * 2) { caught(i, by: pet) }
            return nil
        case .chaseLeaf, .chasePetal, .chaseBubble, .chaseFirefly:
            // Wait underneath until it is low enough to reach with a jump.
            guard plan.y - pet.y < unit * 3 else { return plan.clock < 9 ? plan : nil }
            events.append(.nudge(pet: pet.id, dx: plan.dir * 50, dy: plan.kind == .chaseLeaf || plan.kind == .chasePetal ? 280 : 330))
            say(pet, .pounce, 0.45)
            plan.step = .leap
        }
        return plan
    }

    /// A bigger free ball on the same ledge to stack a ball of radius `r` on.
    private func stackBase(for r: Double, near x: Double, on ledgeY: Double) -> Int? {
        balls.filter { b in
            b.state == .resting && b.r * 0.97 > r && abs(b.x - x) < 300 && !b.snowman
                && !balls.contains { $0.below == b.id }
                && (b.groundY.map { abs($0 - ledgeY) < 0.5 } ?? (b.below != nil))
        }.min { abs($0.x - x) < abs($1.x - x) }?.id
    }

    /// Throws the ball in its paws in a long arc and runs after it.
    private mutating func toss(_ plan: inout PetPlan, _ pet: WeatherPet) {
        let vx = plan.dir * rng.range(260, 420), vy = rng.range(260, 400)
        var ball = Snowball(id: nextBallID, x: pet.x + plan.dir * pet.unit * 0.4, y: pet.y + pet.unit * 0.8,
                            r: max(Snowball.startRadius, plan.ball), state: .flying)
        ball.vx = vx
        ball.vy = vy
        balls.append(ball)
        nextBallID += 1
        say(pet, .toss, 0.4)
        plan.ball = 0
        plan.x = pet.x + vx * 2 * vy / Self.gravity
        plan.step = .chase
        plan.clock = 0
        plan.walkAsked = -10
    }

    /// A pounce that got what it was after.
    private mutating func caught(_ i: Int, by pet: WeatherPet) {
        var p = particles[i]
        switch p.kind {
        case .leaf, .petal:
            // Batted back down and away; it still lands as part of the pile.
            p.vx = rng.range(-120, 120)
            p.vy = -rng.range(60, 140)
            particles[i] = p
        case .bubble:
            particles.remove(at: i)
            pop(p)
        case .firefly:
            let away = p.x >= pet.x ? 1.0 : -1.0
            p.vx = away * 30
            p.vy = 30
            particles[i] = p
        case .seed:
            particles.remove(at: i)
            events.append(.popped(x: p.x, y: p.y))
        default:
            break
        }
    }

    /// Bits of the season fly off a pet shaking itself.
    private mutating func shakeOff(_ pet: WeatherPet) {
        let x = pet.x + rng.range(-pet.unit * 0.35, pet.unit * 0.35), y = pet.y + rng.range(pet.unit * 0.2, pet.unit * 0.7)
        let vx = (x >= pet.x ? 1 : -1) * rng.range(60, 160), vy = rng.range(20, 120)
        switch season {
        case .spring where particles.count < Self.maxParticles:
            particles.append(WeatherParticle(kind: .splash, x: x, y: y, vx: vx, vy: vy, size: 0.9, life: 0.45))
        case .summer:
            break
        default:
            kick(x: x, y: y, vx: vx, vy: vy)
        }
    }

    /// Something landing hard in a pile throws a burst of it up into the air: the snow, leaves or petals
    /// leave the pile and come back down, so it ends up scattered rather than lost.
    mutating func burst(on li: Int, x: Double, power: Double) {
        let area = ledges[li].take(x: x, radius: 6 * power, amount: 2.5 * power)
        guard area > 0.2 else { return }
        let top = ledges[li].top(x: x)
        let count = max(1, min(Int(10 * power), Int(area / 3) + 2))
        for _ in 0..<count {
            kick(x: x + rng.range(-5, 5) * power, y: top + 1, vx: rng.range(-110, 110) * power,
                 vy: rng.range(90, 220) * power, mass: area / Double(count))
        }
        if season == .winter {
            for _ in 0..<Int(4 * power) { kick(x: x + rng.range(-6, 6), y: top + 1, vx: rng.range(-80, 80), vy: rng.range(50, 150)) }
        }
    }
}
