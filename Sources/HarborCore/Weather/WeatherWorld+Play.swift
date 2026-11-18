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

    /// The ledge with a puddle under a point.
    private func puddle(at x: Double, _ y: Double) -> Int? {
        ledges.indices.first { i in
            guard let c = ledges[i].index(x: x) else { return false }
            let wet = ledges[i].water[c]
            return wet >= 0.3 && y >= ledges[i].y - 1 && y <= ledges[i].y + ledges[i].heights[c] + wet + 4
        }
    }

    /// A grown flower whose head is under a point: its ledge and its place in that ledge's flowers.
    private func flower(at x: Double, _ y: Double) -> (ledge: Int, index: Int)? {
        for li in ledges.indices {
            for (f, flower) in ledges[li].flowers.enumerated() where flower.growth > 0.3 {
                let head = ledges[li].y + 9 * flower.growth
                if abs(x - ledges[li].centerX(flower.column)) < 5, y > ledges[li].y - 1, y < head + 5 { return (li, f) }
            }
        }
        return nil
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

    private func fireflies(near x: Double, _ y: Double, within r: Double) -> [Int] {
        particles.indices.filter { i in
            let p = particles[i]
            return p.kind == .firefly && (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) <= r * r
        }
    }

    /// Whether a click at this point belongs to the weather rather than to whatever is underneath.
    public func hitTest(x: Double, y: Double) -> Bool {
        guard interactions else { return false }
        switch season {
        case .winter: return ballIndex(at: x, y) != nil || pile(at: x, y, minDepth: 2.5) != nil
        case .autumn: return pile(at: x, y, minDepth: 2.5) != nil
        case .spring: return flower(at: x, y) != nil || pile(at: x, y, minDepth: 1.2) != nil || puddle(at: x, y) != nil
        case .summer: return bubbleIndex(at: x, y) != nil || !fireflies(near: x, y, within: 26).isEmpty
        }
    }

    /// The pointer as it moves anywhere on the screen. Fast passes blow particles about and brush the tops
    /// off piles; a bubble it touches drifts away from it.
    public mutating func pointerMoved(x: Double, y: Double, vx: Double, vy: Double) {
        pointer = (x, y, vx, vy)
        if season == .summer {
            for i in particles.indices where particles[i].kind == .bubble {
                let dx = particles[i].x - x, dy = particles[i].y - y
                let reach = particles[i].size + 10
                guard dx * dx + dy * dy < reach * reach else { continue }
                particles[i].vx += max(-200, min(200, vx * 0.25))
                particles[i].vy += max(-200, min(200, vy * 0.25))
            }
        }
        let speed = (vx * vx + vy * vy).squareRoot()
        guard speed > 450, hold == nil, season != .summer, let li = pile(at: x, y, minDepth: 1) else { return }
        let area = ledges[li].take(x: x, radius: 5, amount: min(3, speed / 600))
        let top = ledges[li].top(x: x)
        let count = min(8, Int(area / (tuning.deposit * WeatherLedge.column) * (season == .winter ? 0.5 : 1)) + 1)
        for _ in 0..<count {
            kick(x: x + rng.range(-4, 4), y: top + 1, vx: vx * rng.range(0.3, 0.6), vy: abs(vy) * 0.3 + rng.range(40, 120),
                 mass: season == .winter ? 0 : area / Double(count))
        }
    }

    public mutating func pointerLeft() { pointer = nil }

    /// A press on the weather: scoops or picks up a snowball, starts raking or grabbing a handful, picks a
    /// flower, takes hold of a bubble or cups fireflies. A click (press and let go without moving) kicks
    /// the pile or splashes a puddle instead, and holding still on snow lies down in it.
    /// Returns whether the press was used.
    @discardableResult
    public mutating func pointerDown(x: Double, y: Double) -> Bool {
        guard interactions else { return false }
        press = Press(x: x, y: y, time: time)
        grip = (x, y)
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
            guard let li = pile(at: x, y, minDepth: 2.5) else { return cancelPress() }
            let area = ledges[li].take(x: x, radius: 3, amount: 3)
            let r = max(Snowball.startRadius, Snowball.grown(0, area: area))
            balls.append(Snowball(id: nextBallID, x: x, y: y, r: r, state: .held))
            hold = .ball(nextBallID)
            press?.scooped = true
            nextBallID += 1
            return true
        case .autumn, .spring:
            if season == .spring, let hit = flower(at: x, y) {
                let picked = ledges[hit.ledge].flowers.remove(at: hit.index)
                carried = [WeatherParticle(kind: .blossom, x: x, y: y, size: 2.2, phase: rng.range(0, 6.28),
                                           tint: picked.tint)]
                hold = .flower
                return true
            }
            guard let li = pile(at: x, y, minDepth: 1) ?? puddle(at: x, y) else {
                return cancelPress()
            }
            hold = .rake(ledgeY: ledges[li].y, lastX: x)
            return true
        case .summer:
            if let i = bubbleIndex(at: x, y) {
                carried = [particles.remove(at: i)]
                hold = .bubble
                return true
            }
            let near = fireflies(near: x, y, within: 30)
            guard !near.isEmpty else { return cancelPress() }
            // Cupping the hands catches the ones close by as well.
            let caught = fireflies(near: x, y, within: 70).prefix(14)
            for i in caught.sorted(by: >) {
                var fly = particles.remove(at: i)
                fly.life = rng.range(5, 13)
                carried.append(fly)
            }
            hold = .jar
            return true
        }
    }

    private mutating func cancelPress() -> Bool {
        press = nil
        return false
    }

    public mutating func pointerDragged(x: Double, y: Double) {
        let last = grip
        grip = (x, y)
        if var p = press, !p.moved, (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) > 16 {
            p.moved = true
            press = p
        }
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
                  y >= ledgeY - 30 else {
                hold = nil
                return
            }
            // Lifting up out of the pile instead of sweeping along it takes a handful.
            if y > ledges[li].top(x: x) + 22 {
                grab(from: li, x: press?.x ?? x)
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
        case .bubble?:
            guard !carried.isEmpty else { hold = nil; return }
            // Blowing it bigger: it grows with every bit the pointer moves, until it bursts.
            let moved = ((x - last.x) * (x - last.x) + (y - last.y) * (y - last.y)).squareRoot()
            carried[0].size += min(moved, 30) * 0.07
            if carried[0].size > 64 {
                var bubble = carried[0]
                bubble.x = x
                bubble.y = y + bubble.size * 0.8
                carried = []
                hold = nil
                pop(bubble)
            }
        case .handful?, .jar?, .flower?, .angel?, nil:
            break
        }
        placeCarried(0)
    }

    /// A handful of leaves or petals out of the pile at `x`, carried with the pointer.
    private mutating func grab(from li: Int, x: Double) {
        let area = ledges[li].take(x: x, radius: 6, amount: 4)
        guard area > 0.5 else {
            hold = nil
            return
        }
        let count = min(10, Int(area / (tuning.deposit * WeatherLedge.column)) + 2)
        for _ in 0..<count {
            var p = WeatherParticle(kind: season == .autumn ? .leaf : .petal, x: grip.x, y: grip.y,
                                    size: season == .autumn ? rng.range(5, 8) : rng.range(3, 4.5),
                                    angle: rng.range(0, 6.28), phase: rng.range(0, 6.28),
                                    tint: UInt8(rng.next() * (season == .autumn ? 5 : 3)), mass: area / Double(count))
            // While held, `life` is how far the piece sits from the middle of the handful.
            p.life = rng.range(1, 6)
            carried.append(p)
        }
        hold = .handful
    }

    /// Lets go: a held ball is thrown with the pointer's velocity, a handful tossed so it flutters apart,
    /// fireflies freed, a flower dropped to replant where it lands, a blown bubble set adrift. A click
    /// without moving kicks the pile or splashes the puddle that was pressed.
    public mutating func pointerUp(vx: Double, vy: Double) {
        let click = press.map { !$0.moved && time - $0.time < 0.35 } ?? false
        let speed = (vx * vx + vy * vy).squareRoot()
        switch hold {
        case .ball(let id)?:
            guard let b = balls.firstIndex(where: { $0.id == id }) else { break }
            if click, press?.scooped == true, let p = press, let li = pile(at: p.x, p.y, minDepth: 0) ?? ledgeBelow(x: p.x, y: p.y) {
                // A click on snow is a kick, not a tiny ball.
                let r = balls[b].r
                balls.remove(at: b)
                mound(on: li, x: p.x, area: .pi * r * r * 0.6, halfWidth: 3)
                burst(on: li, x: p.x, power: 1)
                break
            }
            let scale = speed > 1600 ? 1600 / speed : 1
            balls[b].state = .flying
            balls[b].vx = vx * scale
            balls[b].vy = vy * scale
        case .rake(let ledgeY, _)?:
            guard let li = ledges.firstIndex(where: { abs($0.y - ledgeY) < 0.5 }) else { break }
            let x = press?.x ?? grip.x
            if click {
                if season == .spring, let c = ledges[li].index(x: x), ledges[li].water[c] >= 0.3 {
                    splashPuddle(on: li, x: x)
                } else {
                    burst(on: li, x: x, power: 1)
                }
            } else if speed > 700, ledges[li].contains(x: grip.x) {
                // Let go mid-flick: whatever was under the rake is flung the way it was going.
                let area = ledges[li].take(x: grip.x, radius: 6, amount: 3)
                let count = max(1, min(10, Int(area / 3) + 1))
                for _ in 0..<count {
                    kick(x: grip.x + rng.range(-4, 4), y: ledges[li].top(x: grip.x) + 1, vx: vx * rng.range(0.25, 0.5),
                         vy: rng.range(60, 160), mass: area / Double(count))
                }
            }
        case .handful?:
            for var p in carried where particles.count < Self.maxParticles {
                p.vx = vx * rng.range(0.4, 0.8) + rng.range(-70, 70)
                p.vy = vy * rng.range(0.4, 0.8) + rng.range(20, 110)
                p.life = 0
                particles.append(p)
            }
        case .jar?:
            release()
        case .flower?:
            for var p in carried {
                p.vx = vx * 0.4
                p.vy = vy * 0.4
                particles.append(p)
            }
        case .bubble?:
            guard var bubble = carried.first else { break }
            if click {
                pop(bubble)
            } else {
                bubble.vx = vx * 0.3
                bubble.vy = vy * 0.3
                bubble.life = max(bubble.life, 8)
                particles.append(bubble)
            }
        case .angel?, nil:
            break
        }
        carried = []
        hold = nil
        press = nil
    }

    /// Lets cupped fireflies go, scattering.
    private mutating func release() {
        for var fly in carried {
            let a = rng.range(0, 2 * .pi)
            fly.vx = cos(a) * 30
            fly.vy = sin(a) * 30
            fly.life = rng.range(8, 16)
            particles.append(fly)
        }
        carried = []
        hold = nil
    }

    public var isHolding: Bool { hold != nil }

    /// Something is being held, thrown or rolled, which deserves a brisker frame rate than drifting weather.
    public var isPlaying: Bool { hold != nil || balls.contains { $0.state != .resting } }

    /// Moves what the pointer carries along with it, and turns a long still press on snow into an angel.
    mutating func stepCarried(_ dt: Double) {
        if case .ball(let id)? = hold, let p = press, p.scooped, !p.moved, time - p.time > 0.7,
           let b = balls.firstIndex(where: { $0.id == id }), let li = pile(at: p.x, p.y, minDepth: 0) {
            let r = balls[b].r
            balls.remove(at: b)
            mound(on: li, x: p.x, area: .pi * r * r * 0.6, halfWidth: 3)
            angel(on: li, x: p.x)
            hold = .angel
            return
        }
        placeCarried(dt)
        // Cupped fireflies slip out after a few seconds.
        if case .jar? = hold, carried.contains(where: { $0.life <= 0 }) { release() }
    }

    /// Puts what the pointer carries where the pointer is now.
    private mutating func placeCarried(_ dt: Double) {
        for i in carried.indices {
            var p = carried[i]
            switch hold {
            case .handful?:
                p.x = grip.x + cos(p.phase) * p.life * 1.4
                p.y = grip.y + sin(p.phase) * p.life * 0.8
                p.angle = p.phase + sin(time * 3 + p.phase) * 0.3
            case .jar?:
                // They circle about inside cupped hands, glowing.
                p.phase += dt * (1.5 + Double(i % 3) * 0.6)
                let r = 5 + Double(i % 4) * 2.5
                p.x = grip.x + cos(p.phase) * r
                p.y = grip.y + sin(p.phase * 1.3) * r * 0.7
                p.life -= dt
            case .flower?:
                p.x = grip.x
                p.y = grip.y - 2
                p.angle = sin(time * 4 + p.phase) * 0.25
            case .bubble?:
                p.x = grip.x
                p.y = grip.y + p.size * 0.8
                p.phase += dt * 6
            default:
                break
            }
            carried[i] = p
        }
    }

    /// Lying down in the snow and sweeping arms and legs: a body-shaped hollow with scalloped wings, the
    /// snow pushed out to rims either side.
    private mutating func angel(on li: Int, x: Double) {
        guard let mid = ledges[li].index(x: x) else { return }
        var moved = 0.0
        let span = 7
        for k in -span...span {
            let i = mid + k
            guard i >= 0, i < ledges[li].count else { continue }
            let d = Double(abs(k))
            let share = d < 2 ? 0.7 : 0.35 + 0.2 * cos(d * 1.3)
            let taken = ledges[li].heights[i] * share
            ledges[li].heights[i] -= taken
            moved += taken * WeatherLedge.column
        }
        ledges[li].mark(max(0, mid - span), min(ledges[li].count - 1, mid + span))
        let rim = Double(span + 2) * WeatherLedge.column
        mound(on: li, x: x - rim, area: moved / 2, halfWidth: 3)
        mound(on: li, x: x + rim, area: moved / 2, halfWidth: 3)
        let top = ledges[li].y + ledges[li].height(x: x)
        for _ in 0..<8 { kick(x: x + rng.range(-12, 12), y: top + 1, vx: rng.range(-50, 50), vy: rng.range(30, 90)) }
    }

    /// A click in a puddle: water jumps out and some of the puddle with it.
    private mutating func splashPuddle(on li: Int, x: Double) {
        guard let c = ledges[li].index(x: x) else { return }
        for i in max(0, c - 3)...min(ledges[li].count - 1, c + 3) { ledges[li].water[i] *= 0.7 }
        splash(x: x, y: ledges[li].y + ledges[li].water[c] + 1, count: 16)
    }

    /// Drops a falling flower into the ledge it lands on, in bloom.
    mutating func replant(_ p: WeatherParticle, on li: Int) {
        guard season == .spring, let c = ledges[li].index(x: p.x) else { return }
        ledges[li].flowers.append(WeatherFlower(column: c, growth: 1, age: 0, tint: p.tint))
        kick(x: p.x, y: ledges[li].top(x: p.x) + 1, vx: rng.range(-30, 30), vy: rng.range(30, 70))
    }

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
        if accumulation { impact(on: li, x: ball.x, area: .pi * ball.r * ball.r * 0.8, radius: ball.r, vx: ball.vx) }
        for _ in 0..<Int(4 + ball.r / 3) {
            kick(x: ball.x + rng.range(-ball.r, ball.r), y: top + 1, vx: ball.vx * 0.15 + rng.range(-70, 70),
                 vy: rng.range(60, 160))
        }
        events.append(.splat(x: ball.x, y: top))
    }

    /// A ball bursting on a pile. It digs a shallow crater where it strikes and throws what it digs out,
    /// along with its own snow, into a few clods of different sizes, most of them carried on the way it was
    /// going. Nothing is spread evenly, so the pile stays lumpy instead of slumping into a neat heap.
    mutating func impact(on li: Int, x: Double, area: Double, radius: Double, vx: Double) {
        let dir = vx >= 0 ? 1.0 : -1.0
        let dug = ledges[li].take(x: x, radius: radius * 0.5, amount: min(radius * 0.3, 4))
        let budget = area + dug
        let lumps = 2 + Int(rng.next() * 3)
        var weights = (0..<lumps).map { _ in rng.range(0.3, 1) }
        let total = weights.reduce(0, +)
        weights = weights.map { $0 / total }
        for w in weights {
            let offset = dir * rng.range(0, radius * 1.5) + rng.range(-radius * 0.6, radius * 0.6)
            mound(on: li, x: x + offset, area: budget * w, halfWidth: rng.range(radius * 0.3, radius * 0.8))
        }
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
                        let area = ledges[li].take(x: pet.x, radius: pet.unit * 0.35, amount: 2)
                        for _ in 0..<n {
                            kick(x: pet.x + rng.range(-pet.unit * 0.3, pet.unit * 0.3), y: ledge.y + depth,
                                 vx: rng.range(-90, 90), vy: rng.range(70, 190), mass: area / Double(n))
                        }
                    }
                    if wet > 0.3 { splash(x: pet.x, y: ledge.y + wet, count: 8) }
                }
                // Walking through a pile leaves footprints and kicks a little of it back; leaves go flying.
                if abs(pet.vx) > 12, depth > 0.6 || wet > 0.3 {
                    memory.stride += abs(pet.vx) * dt
                    if memory.stride > pet.unit * 0.28 {
                        memory.stride = 0
                        let back = pet.vx > 0 ? -1.0 : 1.0
                        let foot = pet.x + back * pet.unit * 0.1
                        if depth > 0.6 {
                            let leaves = season == .autumn
                            let area = ledges[li].take(x: foot, radius: 1.5, amount: depth * (leaves ? 0.3 : 0.45))
                            // Snow packs down underfoot; litter is only pushed about.
                            let mass = season == .winter ? 0 : area
                            let n = leaves ? 2 : 1
                            for _ in 0..<n where rng.next() < 0.8 {
                                kick(x: foot, y: ledge.y + depth, vx: back * rng.range(30, leaves ? 140 : 80),
                                     vy: rng.range(50, leaves ? 170 : 120), mass: mass / Double(n))
                            }
                        }
                        if wet > 0.3 { splash(x: foot, y: ledge.y + wet, count: 2) }
                    }
                }
                pushBall(pet, &memory, li: li, depth: depth, dt: dt)
            } else {
                pushBall(pet, &memory, li: nil, depth: 0, dt: dt)
            }
            play(pet, &memory, li: li, dt: dt)
            memory.vy = pet.vy
            petMemory[pet.id] = memory
        }
        let present = Set(pets.map(\.id))
        for (id, memory) in petMemory where !present.contains(id) {
            if let ball = memory.ball, let b = balls.firstIndex(where: { $0.id == ball }) { balls[b].state = .flying }
            petMemory[id] = nil
        }
    }

    mutating func splash(x: Double, y: Double, count: Int) {
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
            // A ball just started waits a moment for its pet to set off.
            let waiting = memory.still < (memory.plan?.kind == .scoop ? 1.2 : 0.4)
            guard let li, waiting, !turned || abs(pet.vx) < 8, ledges[li].contains(x: wantX), r < pet.unit * 0.45 else {
                if let li, ledges[li].contains(x: balls[b].x) {
                    balls[b].state = .resting
                    balls[b].groundY = ledges[li].y
                } else {
                    balls[b].state = .flying
                }
                memory.ball = nil
                return
            }
            guard abs(pet.vx) >= 8 else { return }
            let dx = wantX - balls[b].x
            let area = ledges[li].take(x: wantX, radius: r * 0.6, amount: min(2, abs(dx) * 0.3))
            balls[b].r = Snowball.grown(r, area: area)
            balls[b].x = wantX
            balls[b].y = ledges[li].top(x: wantX) + balls[b].r * Snowball.seat
            balls[b].spin += dx / r
            return
        }
        guard memory.plan == nil, season == .winter, accumulation, let li, depth >= 3, abs(pet.vx) > 15,
              rng.next() < dt * 0.06 else { return }
        _ = startPush(pet, &memory, li: li, dir: dir)
    }

    /// Starts a snowball in front of a pet for it to push along.
    mutating func startPush(_ pet: WeatherPet, _ memory: inout PetMemory, li: Int, dir: Double) -> Bool {
        let x = pet.x + dir * (pet.unit * 0.42 + Snowball.startRadius)
        guard ledges[li].contains(x: x) else { return false }
        _ = ledges[li].take(x: x, radius: 3, amount: 2)
        var ball = Snowball(id: nextBallID, x: x, y: ledges[li].top(x: x) + Snowball.startRadius * Snowball.seat,
                            r: Snowball.startRadius, state: .pushed(pet.id))
        ball.groundY = ledges[li].y
        balls.append(ball)
        memory.ball = nextBallID
        memory.still = 0
        nextBallID += 1
        return true
    }
}
