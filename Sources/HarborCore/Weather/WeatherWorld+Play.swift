import Foundation

/// The pointer, snowballs and the pets: everything that plays with the weather rather than just falls.
extension WeatherWorld {
    // MARK: Pointer

    /// The pile column under a point, when the point is in the pile itself.
    private func pile(at x: Double, _ y: Double, minDepth: Double) -> Int? {
        ledges.indices.first { i in
            let depth = ledges[i].height(x: x)
            return depth >= minDepth && y >= ledges[i].y - 1 && y <= ledges[i].y + depth + 3
        }
    }

    private func ballIndex(at x: Double, _ y: Double) -> Int? {
        balls.indices.last { i in
            let b = balls[i]
            return b.state == .resting && (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) <= (b.r + 2) * (b.r + 2)
        }
    }

    private func bubbleIndex(at x: Double, _ y: Double) -> Int? {
        particles.indices.first { i in
            let p = particles[i]
            return p.kind == .bubble && (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) <= (p.size + 3) * (p.size + 3)
        }
    }

    /// Whether a click at this point belongs to the weather rather than to whatever is underneath.
    public func hitTest(x: Double, y: Double) -> Bool {
        guard interactions else { return false }
        switch season {
        case .winter: return ballIndex(at: x, y) != nil || pile(at: x, y, minDepth: 2.5) != nil
        case .autumn, .spring: return pile(at: x, y, minDepth: season == .autumn ? 2.5 : 1.2) != nil
        case .summer: return bubbleIndex(at: x, y) != nil
        }
    }

    /// The pointer as it moves anywhere on the screen. Fast passes blow particles about and brush the tops
    /// off piles.
    public mutating func pointerMoved(x: Double, y: Double, vx: Double, vy: Double) {
        pointer = (x, y, vx, vy)
        let speed = (vx * vx + vy * vy).squareRoot()
        guard speed > 450, season != .summer, let li = pile(at: x, y, minDepth: 1) else { return }
        let area = ledges[li].take(x: x, radius: 5, amount: min(3, speed / 600))
        let top = ledges[li].top(x: x)
        let count = min(8, Int(area / (tuning.deposit * WeatherLedge.column) * (season == .winter ? 0.5 : 1)) + 1)
        for _ in 0..<count {
            kick(x: x + rng.range(-4, 4), y: top + 1, vx: vx * rng.range(0.3, 0.6), vy: abs(vy) * 0.3 + rng.range(40, 120))
        }
    }

    public mutating func pointerLeft() { pointer = nil }

    /// A press on the weather: scoops a snowball, picks one up, starts raking or pops a bubble.
    /// Returns whether the press was used.
    @discardableResult
    public mutating func pointerDown(x: Double, y: Double) -> Bool {
        guard interactions else { return false }
        switch season {
        case .winter:
            if let b = ballIndex(at: x, y) {
                let id = balls[b].id
                balls[b].state = .held
                balls[b].below = nil
                balls[b].groundY = nil
                hold = .ball(id)
                refreshSnowmen()
                return true
            }
            guard let li = pile(at: x, y, minDepth: 2.5) else { return false }
            let area = ledges[li].take(x: x, radius: 3, amount: 3)
            let r = max(Snowball.startRadius, Snowball.grown(0, area: area))
            balls.append(Snowball(id: nextBallID, x: x, y: y, r: r, state: .held))
            hold = .ball(nextBallID)
            nextBallID += 1
            return true
        case .autumn, .spring:
            guard let li = pile(at: x, y, minDepth: 1) else { return false }
            hold = .rake(ledgeY: ledges[li].y, lastX: x)
            return true
        case .summer:
            guard let i = bubbleIndex(at: x, y) else { return false }
            let bubble = particles.remove(at: i)
            pop(bubble)
            return true
        }
    }

    public mutating func pointerDragged(x: Double, y: Double) {
        switch hold {
        case .ball(let id)?:
            guard let b = balls.firstIndex(where: { $0.id == id }) else { hold = nil; return }
            let dx = x - balls[b].x
            balls[b].x = x
            balls[b].y = y
            balls[b].spin += dx / balls[b].r
            let r = balls[b].r
            // Rolling the ball along a drift picks the drift up.
            if abs(dx) > 0.2, let li = ledges.firstIndex(where: {
                $0.contains(x: x) && y - r <= $0.top(x: x) + 1.5 && y - r >= $0.y - r
            }) {
                let area = ledges[li].take(x: x, radius: r * 0.7, amount: min(3, abs(dx) * 0.25))
                balls[b].r = Snowball.grown(r, area: area)
            }
        case .rake(let ledgeY, let lastX)?:
            guard let li = ledges.firstIndex(where: { abs($0.y - ledgeY) < 0.5 }), ledges[li].contains(x: x),
                  y <= ledges[li].top(x: x) + 30, y >= ledgeY - 30 else {
                hold = nil
                return
            }
            let dir = x >= lastX ? 1.0 : -1.0
            let span = abs(x - lastX)
            guard span >= WeatherLedge.column else { return }
            // Most of what the rake passes over is pushed ahead of it, so a sweep gathers a heap.
            let gathered = ledges[li].take(x: (x + lastX) / 2, radius: span / 2 + 1, amount: .infinity) * 0.85
            let rest = gathered / 0.85 * 0.15
            depositArea(on: li, x: (x + lastX) / 2, area: rest, radius: span / 2 + 1)
            depositArea(on: li, x: x + dir * 4, area: gathered, radius: 4)
            hold = .rake(ledgeY: ledgeY, lastX: x)
        case nil:
            break
        }
    }

    /// Lets go: a held ball is thrown with the pointer's velocity.
    public mutating func pointerUp(vx: Double, vy: Double) {
        if case .ball(let id)? = hold, let b = balls.firstIndex(where: { $0.id == id }) {
            let speed = (vx * vx + vy * vy).squareRoot()
            let scale = speed > 1600 ? 1600 / speed : 1
            balls[b].state = .flying
            balls[b].vx = vx * scale
            balls[b].vy = vy * scale
        }
        hold = nil
    }

    public var isHolding: Bool { hold != nil }

    /// Something is being held, thrown or rolled, which deserves a brisker frame rate than drifting weather.
    public var isPlaying: Bool { hold != nil || balls.contains { $0.state != .resting } }

    // MARK: Snowballs

    mutating func stepBalls(_ dt: Double) {
        guard !balls.isEmpty else { return }
        var removed: Set<Int> = []
        var changed = false
        for i in balls.indices where !removed.contains(balls[i].id) {
            switch balls[i].state {
            case .held, .pushed:
                continue
            case .resting:
                if let below = balls[i].below {
                    if let b = balls.firstIndex(where: { $0.id == below }), balls[b].state == .resting,
                       !removed.contains(below) {
                        balls[i].x = balls[b].x
                        balls[i].y = Snowball.perch(balls[i].r, on: balls[b])
                    } else {
                        balls[i].state = .flying
                        balls[i].below = nil
                        changed = true
                    }
                } else if let ground = balls[i].groundY,
                          let li = ledges.firstIndex(where: { abs($0.y - ground) < 0.5 && $0.contains(x: balls[i].x) }) {
                    balls[i].y = ledges[li].top(x: balls[i].x) + balls[i].r * Snowball.seat
                }
            case .flying:
                var ball = balls[i]
                let prevBottom = ball.y - ball.r
                ball.vy -= Self.gravity * dt
                ball.x += ball.vx * dt
                ball.y += ball.vy * dt
                ball.spin += ball.vx * dt / ball.r
                var done = false
                for j in balls.indices where j != i && balls[j].state == .resting && !removed.contains(balls[j].id) {
                    let other = balls[j]
                    let dx = ball.x - other.x, dy = ball.y - other.y
                    let dist = max(0.01, (dx * dx + dy * dy).squareRoot())
                    guard dist < ball.r + other.r else { continue }
                    let speed = (ball.vx * ball.vx + ball.vy * ball.vy).squareRoot()
                    if speed > 650 {
                        // A hard throw knocks over whatever it hits and bursts.
                        knock(other.id, push: ball.vx)
                        spawnChunks(x: ball.x, y: ball.y, area: .pi * ball.r * ball.r * 0.7, vx: ball.vx * 0.2)
                        events.append(.splat(x: ball.x, y: ball.y))
                        removed.insert(ball.id)
                        done = true
                    } else if dy > 0, abs(dx) < other.r * 0.7, !balls.contains(where: { $0.below == other.id }) {
                        ball.x = other.x
                        ball.y = Snowball.perch(ball.r, on: other)
                        ball.vx = 0
                        ball.vy = 0
                        ball.state = .resting
                        ball.below = other.id
                        done = true
                    } else {
                        let nx = dx / dist, ny = dy / dist
                        ball.x = other.x + nx * (ball.r + other.r)
                        ball.y = other.y + ny * (ball.r + other.r)
                        let along = ball.vx * nx + ball.vy * ny
                        if along < 0 {
                            ball.vx -= 1.4 * along * nx
                            ball.vy -= 1.4 * along * ny
                        }
                    }
                    changed = true
                    break
                }
                if !done, ball.vy < 0, let li = ledgeBelow(x: ball.x, y: prevBottom),
                   ledges[li].top(x: ball.x) >= ball.y - ball.r {
                    let speed = (ball.vx * ball.vx + ball.vy * ball.vy).squareRoot()
                    if speed > 520 {
                        splat(ball, on: li)
                        removed.insert(ball.id)
                    } else {
                        ball.y = ledges[li].top(x: ball.x) + ball.r * Snowball.seat
                        ball.vx = 0
                        ball.vy = 0
                        ball.state = .resting
                        ball.groundY = ledges[li].y
                    }
                    changed = true
                }
                if ball.y < -60 || ball.x < -80 || ball.x > width + 80 { removed.insert(ball.id) }
                balls[i] = ball
            }
        }
        if !removed.isEmpty { balls.removeAll { removed.contains($0.id) } }
        if changed || !removed.isEmpty { refreshSnowmen() }
    }

    private mutating func splat(_ ball: Snowball, on li: Int) {
        let top = ledges[li].top(x: ball.x)
        if accumulation { depositArea(on: li, x: ball.x, area: .pi * ball.r * ball.r * 0.8, radius: ball.r) }
        for _ in 0..<Int(4 + ball.r / 3) {
            kick(x: ball.x + rng.range(-ball.r, ball.r), y: top + 1, vx: ball.vx * 0.15 + rng.range(-70, 70),
                 vy: rng.range(60, 160))
        }
        events.append(.splat(x: ball.x, y: top))
    }

    /// Sends a ball and everything stacked on it tumbling.
    private mutating func knock(_ id: Int, push: Double) {
        var current: Int? = id
        while let c = current, let i = balls.firstIndex(where: { $0.id == c }) {
            balls[i].state = .flying
            balls[i].below = nil
            balls[i].groundY = nil
            balls[i].vx = push * 0.35 + rng.range(-40, 40)
            balls[i].vy = rng.range(80, 220)
            current = balls.first(where: { $0.below == c })?.id
        }
    }

    /// Removes a ball and every ball stacked on top of it.
    mutating func removeStack(_ id: Int) {
        var current: Int? = id
        while let c = current {
            current = balls.first(where: { $0.below == c })?.id
            balls.removeAll { $0.id == c }
        }
    }

    mutating func meltBalls(_ elapsed: Double) {
        guard !balls.isEmpty else { return }
        let perMinute = season == .winter ? (falling ? 0.05 : 0.35) : 3
        var gone: [Int] = []
        for i in balls.indices where balls[i].state == .resting {
            balls[i].r -= perMinute / 60 * elapsed
            if balls[i].r < 2.5 { gone.append(balls[i].id) }
        }
        if !gone.isEmpty {
            balls.removeAll { gone.contains($0.id) }
            refreshSnowmen()
        }
    }

    private mutating func refreshSnowmen() {
        let members = Snowball.snowmen(balls)
        for i in balls.indices {
            let now = members.contains(balls[i].id)
            if now, !balls[i].snowman, balls[i].below != nil, !balls.contains(where: { $0.below == balls[i].id }) {
                events.append(.snowman(x: balls[i].x, y: balls[i].y))
            }
            balls[i].snowman = now
        }
    }

    // MARK: Pets

    mutating func stepPets(_ dt: Double, _ pets: [WeatherPet]) {
        for pet in pets {
            var memory = petMemory[pet.id] ?? PetMemory(vy: pet.vy)
            let li = ledges.firstIndex { abs($0.y - pet.y) < 1.5 && $0.contains(x: pet.x) }
            if let li {
                let ledge = ledges[li]
                let depth = ledge.height(x: pet.x)
                let wet = ledge.index(x: pet.x).map { ledge.water[$0] } ?? 0
                // Landing in a pile throws up a puff of it.
                if memory.vy < -250, abs(pet.vy) < 60 {
                    if depth > 0.5 {
                        let n = min(14, 4 + Int(depth * 1.5))
                        _ = ledges[li].take(x: pet.x, radius: pet.unit * 0.35, amount: 2)
                        for _ in 0..<n {
                            kick(x: pet.x + rng.range(-pet.unit * 0.3, pet.unit * 0.3), y: ledge.y + depth,
                                 vx: rng.range(-90, 90), vy: rng.range(70, 190))
                        }
                    }
                    if wet > 0.3 { splash(x: pet.x, y: ledge.y + wet, count: 8) }
                }
                // Walking through a pile leaves footprints and kicks a little of it back.
                if abs(pet.vx) > 12, depth > 0.6 || wet > 0.3 {
                    memory.stride += abs(pet.vx) * dt
                    if memory.stride > pet.unit * 0.28 {
                        memory.stride = 0
                        let back = pet.vx > 0 ? -1.0 : 1.0
                        let foot = pet.x + back * pet.unit * 0.1
                        if depth > 0.6 {
                            _ = ledges[li].take(x: foot, radius: 1.5, amount: depth * 0.45)
                            if rng.next() < 0.8 {
                                kick(x: foot, y: ledge.y + depth, vx: back * rng.range(30, 80), vy: rng.range(50, 120))
                            }
                        }
                        if wet > 0.3 { splash(x: foot, y: ledge.y + wet, count: 2) }
                    }
                }
                pushBall(pet, &memory, li: li, depth: depth, dt: dt)
                memory.cooldown -= dt
                if memory.cooldown <= 0, abs(pet.vy) < 1 {
                    if let hop = playTarget(pet, li: li) {
                        events.append(.nudge(pet: pet.id, dx: hop.dx, dy: hop.dy))
                        memory.cooldown = rng.range(8, 16)
                    } else {
                        memory.cooldown = 2
                    }
                }
            } else {
                pushBall(pet, &memory, li: nil, depth: 0, dt: dt)
            }
            memory.vy = pet.vy
            petMemory[pet.id] = memory
        }
        let present = Set(pets.map(\.id))
        for (id, memory) in petMemory where !present.contains(id) {
            if let ball = memory.ball, let b = balls.firstIndex(where: { $0.id == ball }) { balls[b].state = .flying }
            petMemory[id] = nil
        }
    }

    private mutating func splash(x: Double, y: Double, count: Int) {
        for _ in 0..<count where particles.count < Self.maxParticles {
            particles.append(WeatherParticle(kind: .splash, x: x + rng.range(-3, 3), y: y + 1, vx: rng.range(-60, 60),
                                             vy: rng.range(60, 140), size: 0.9, life: 0.4))
        }
    }

    /// A pet wading through deep snow sometimes starts a ball rolling ahead of it, which grows until the pet
    /// stops, turns round or runs out of ledge.
    private mutating func pushBall(_ pet: WeatherPet, _ memory: inout PetMemory, li: Int?, depth: Double, dt: Double) {
        let dir = pet.vx >= 0 ? 1.0 : -1.0
        if let id = memory.ball {
            guard let b = balls.firstIndex(where: { $0.id == id }) else { memory.ball = nil; return }
            memory.still = abs(pet.vx) < 8 ? memory.still + dt : 0
            let r = balls[b].r
            let wantX = pet.x + dir * (pet.unit * 0.42 + r)
            let turned = (balls[b].x - pet.x) * dir < 0
            guard let li, memory.still < 0.4, !turned, ledges[li].contains(x: wantX), r < pet.unit * 0.45 else {
                if let li, ledges[li].contains(x: balls[b].x) {
                    balls[b].state = .resting
                    balls[b].groundY = ledges[li].y
                } else {
                    balls[b].state = .flying
                }
                memory.ball = nil
                return
            }
            let dx = wantX - balls[b].x
            let area = ledges[li].take(x: wantX, radius: r * 0.6, amount: min(2, abs(dx) * 0.3))
            balls[b].r = Snowball.grown(r, area: area)
            balls[b].x = wantX
            balls[b].y = ledges[li].top(x: wantX) + balls[b].r * Snowball.seat
            balls[b].spin += dx / r
            return
        }
        guard season == .winter, accumulation, let li, depth >= 3, abs(pet.vx) > 15, rng.next() < dt * 0.06 else { return }
        let x = pet.x + dir * (pet.unit * 0.42 + Snowball.startRadius)
        guard ledges[li].contains(x: x) else { return }
        var ball = Snowball(id: nextBallID, x: x, y: ledges[li].top(x: x) + Snowball.startRadius * Snowball.seat,
                            r: Snowball.startRadius, state: .pushed(pet.id))
        ball.groundY = ledges[li].y
        balls.append(ball)
        memory.ball = nextBallID
        nextBallID += 1
    }

    /// Something worth hopping toward: a bubble or firefly overhead, a deep leaf pile, a puddle, a snowdrift.
    private mutating func playTarget(_ pet: WeatherPet, li: Int) -> (dx: Double, dy: Double)? {
        guard rng.next() < 0.5 else { return nil }
        let ledge = ledges[li]
        func nearby(_ values: [Double], minimum: Double) -> Double? {
            var best: Double?
            for c in stride(from: 0, to: ledge.count, by: 3) where values[c] >= minimum {
                let dx = ledge.centerX(c) - pet.x
                if abs(dx) > 20, abs(dx) < 120, best.map({ abs(dx) < abs($0) }) ?? true { best = dx }
            }
            return best
        }
        switch season {
        case .summer:
            let target = particles.first { p in
                (p.kind == .bubble || p.kind == .firefly) && abs(p.x - pet.x) < 160 && p.y > pet.y && p.y - pet.y < 140
            }
            return target.map { (($0.x - pet.x), 320) }
        case .autumn:
            return nearby(ledge.heights, minimum: 6).map { ($0, 240) }
        case .spring:
            return nearby(ledge.water, minimum: 0.8).map { ($0, 220) }
        case .winter:
            if let ball = balls.first(where: { $0.state == .resting && abs($0.x - pet.x) < 90 && abs($0.x - pet.x) > 20 }) {
                return (ball.x - pet.x, 200)
            }
            return ledge.height(x: pet.x) >= 6 ? (0, 200) : nil
        }
    }
}
