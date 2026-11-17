import CoreGraphics
import Foundation

/// Where a pet can be: standing on a ledge with its feet at `x`, holding a wall with its middle at `y`, or
/// hanging upside down from a ceiling with its feet at `x`.
public enum RoamSpot: Equatable, Sendable {
    case ledge(RoamSurface, x: Double)
    case wall(RoamWall, y: Double)
    case ceiling(RoamSurface, x: Double)

    /// The feet on a ledge, the middle of the body on a wall or under a ceiling.
    public func point(half: Double) -> CGPoint {
        switch self {
        case .ledge(let ledge, let x): CGPoint(x: x, y: ledge.y)
        case .wall(let wall, let y): CGPoint(x: wall.x + wall.normal * half, y: y)
        case .ceiling(let ceiling, let x): CGPoint(x: x, y: ceiling.y - half)
        }
    }
}

/// One leg of a route.
public enum RoamMove: Equatable, Sendable {
    /// Walk along the current ledge, or crawl along the current ceiling, to `x`.
    case walk(to: Double)
    /// Climb along the current wall until the middle of the body is at `y`.
    case climb(to: Double)
    /// Step between a ledge or ceiling and a wall that meet.
    case transfer(RoamSpot)
    /// Jump or drop with this launch velocity, expecting to come down on (or catch) `onto`.
    case leap(vx: Double, vy: Double, onto: RoamSpot)
}

/// Every way across one screen's ledges, walls and ceilings, built once per change of surfaces and searched
/// with Dijkstra. Leaps are found by flying the same physics the pet uses, so a planned jump lands where the
/// plan says unless the windows move mid-flight.
public struct RoamNav: Sendable {
    public let ledges: [RoamSurface]
    public let walls: [RoamWall]
    public let ceilings: [RoamSurface]
    /// Half the pet's size: how far its middle sits from a wall, and the margin it keeps from a wall's ends.
    public let half: Double
    private let screenMinX: Double
    private let screenMaxX: Double
    private var links: [Link] = []
    private var outgoing: [Node: [Link]] = [:]
    /// Where links meet each segment; routes walk or climb between neighbouring points.
    private var basePoints: [Set<Double>] = []

    /// A point on a segment: ledges first, then walls, then ceilings. `at` is x on a ledge or ceiling and
    /// y on a wall.
    private struct Node: Hashable {
        var segment: Int
        var at: Double
    }

    private struct Link {
        var from: Node
        var to: Node
        var move: RoamMove
        var cost: Double
    }

    private enum Segment {
        case ledge(RoamSurface)
        case wall(RoamWall)
        case ceiling(RoamSurface)
    }

    /// Speeds the planner assumes, so routes favour walking over long climbs.
    private static let walkPace = 45.0
    private static let climbPace = 30.0
    /// Fixed overheads that keep routes from hopping when walking is nearly as quick.
    private static let leapPenalty = 0.6
    private static let transferPenalty = 0.3
    /// Furthest a planned leap travels sideways.
    private static let leapReach = 560.0

    public init(ledges: [RoamSurface], walls: [RoamWall], ceilings: [RoamSurface] = [], half: Double,
                screenMinX: Double, screenMaxX: Double) {
        self.ledges = ledges
        self.walls = walls.filter { $0.maxY - $0.minY >= half * 2 }
        self.ceilings = ceilings
        self.half = half
        self.screenMinX = screenMinX
        self.screenMaxX = screenMaxX
        links = buildLinks()
        basePoints = Array(repeating: [], count: count)
        for link in links {
            outgoing[link.from, default: []].append(link)
            basePoints[link.from.segment].insert(link.from.at)
            basePoints[link.to.segment].insert(link.to.at)
        }
    }

    // MARK: Segments

    private var count: Int { ledges.count + walls.count + ceilings.count }
    private var wallBase: Int { ledges.count }
    private var ceilingBase: Int { ledges.count + walls.count }

    private func segment(_ index: Int) -> Segment {
        if index < wallBase { return .ledge(ledges[index]) }
        if index < ceilingBase { return .wall(walls[index - wallBase]) }
        return .ceiling(ceilings[index - ceilingBase])
    }

    private func span(_ line: RoamSurface) -> ClosedRange<Double> {
        max(line.minX, screenMinX)...max(min(line.maxX, screenMaxX), max(line.minX, screenMinX))
    }

    private func range(_ index: Int) -> ClosedRange<Double> {
        switch segment(index) {
        case .ledge(let ledge): span(ledge)
        case .wall(let wall): (wall.minY + half)...(wall.maxY - half)
        case .ceiling(let ceiling): span(ceiling)
        }
    }

    private func spot(_ node: Node) -> RoamSpot {
        switch segment(node.segment) {
        case .ledge(let ledge): .ledge(ledge, x: node.at)
        case .wall(let wall): .wall(wall, y: node.at)
        case .ceiling(let ceiling): .ceiling(ceiling, x: node.at)
        }
    }

    private func node(_ spot: RoamSpot) -> Node? {
        switch spot {
        case .ledge(let ledge, let x):
            ledges.firstIndex(of: ledge).map { Node(segment: $0, at: x) }
        case .wall(let wall, let y):
            walls.firstIndex(of: wall).map { Node(segment: wallBase + $0, at: y) }
        case .ceiling(let ceiling, let x):
            ceilings.firstIndex(of: ceiling).map { Node(segment: ceilingBase + $0, at: x) }
        }
    }

    /// Whether `spot` is one of this screen's segments; a route through a missing one is stale.
    public func contains(_ spot: RoamSpot) -> Bool { node(spot) != nil }

    // MARK: Links

    private func buildLinks() -> [Link] {
        var result: [Link] = []

        func add(_ from: Node, _ to: Node, _ move: RoamMove, _ cost: Double) {
            result.append(Link(from: from, to: to, move: move, cost: cost))
        }

        func leap(from: Node, start: CGPoint, vx: Double, vy: Double, aim: RoamSpot?, expect: Int? = nil) {
            guard let (flight, time) = simulate(from: start, vx: vx, vy: vy, aim: aim) else { return }
            let target: Node
            if let wall = flight.grabbed, let index = walls.firstIndex(of: wall) {
                target = Node(segment: wallBase + index, at: flight.y)
            } else if let ceiling = flight.grabbedCeiling, let index = ceilings.firstIndex(of: ceiling) {
                target = Node(segment: ceilingBase + index, at: flight.x)
            } else if let ledge = flight.landedOn, let index = ledges.firstIndex(of: ledge) {
                target = Node(segment: index, at: flight.x)
            } else {
                return
            }
            guard target.segment != from.segment, expect.map({ $0 == target.segment }) ?? true else { return }
            add(from, target, .leap(vx: vx, vy: vy, onto: spot(target)), time + Self.leapPenalty)
        }

        // Ledges and walls that touch: step on or off, both ways.
        for (li, ledge) in ledges.enumerated() {
            for (wi, wall) in walls.enumerated() where touches(span(ledge), y: ledge.y, wall) {
                let x = min(max(wall.x + wall.normal * half, range(li).lowerBound), range(li).upperBound)
                let wallRange = range(wallBase + wi)
                let y = min(max(ledge.y + half, wallRange.lowerBound), wallRange.upperBound)
                let onLedge = Node(segment: li, at: x)
                let onWall = Node(segment: wallBase + wi, at: y)
                add(onLedge, onWall, .transfer(.wall(wall, y: y)), Self.transferPenalty)
                add(onWall, onLedge, .transfer(.ledge(ledge, x: x)), Self.transferPenalty)
            }
        }

        // Ceilings and walls that meet, at a wall's top (an inside corner) or bottom (around the outside).
        for (ci, ceiling) in ceilings.enumerated() {
            let ceilingRange = range(ceilingBase + ci)
            for (wi, wall) in walls.enumerated() where touches(span(ceiling), y: ceiling.y, wall) {
                let x = min(max(wall.x + wall.normal * half, ceilingRange.lowerBound), ceilingRange.upperBound)
                let wallRange = range(wallBase + wi)
                let y = min(max(ceiling.y - half, wallRange.lowerBound), wallRange.upperBound)
                let under = Node(segment: ceilingBase + ci, at: x)
                let onWall = Node(segment: wallBase + wi, at: y)
                add(under, onWall, .transfer(.wall(wall, y: y)), Self.transferPenalty)
                add(onWall, under, .transfer(.ceiling(ceiling, x: x)), Self.transferPenalty)
            }
        }

        // Stepping or leaping off a ledge's ends lands wherever gravity takes it.
        for (li, ledge) in ledges.enumerated() {
            let span = range(li)
            for (end, direction) in [(span.lowerBound, -1.0), (span.upperBound, 1.0)] {
                guard end + direction * 4 > screenMinX, end + direction * 4 < screenMaxX else { continue }
                for (speed, hop) in [(70.0, 4.0), (220.0, 24.0)] {
                    leap(from: Node(segment: li, at: end), start: CGPoint(x: end, y: ledge.y),
                         vx: direction * speed, vy: (2 * RoamPhysics.gravity * hop).squareRoot(), aim: nil)
                }
            }
        }

        // Aimed jumps up or across onto the near end of another ledge.
        for (li, from) in ledges.enumerated() {
            let span = range(li)
            for (ti, to) in ledges.enumerated() where ti != li {
                let rise = to.y - from.y
                guard rise <= RoamPhysics.maxJumpHeight - 12, rise >= -80 else { continue }
                let target = range(ti)
                let inset = min(14, (target.upperBound - target.lowerBound) / 2)
                for (landing, takeoff) in [(target.lowerBound + inset, target.lowerBound - 40),
                                           (target.upperBound - inset, target.upperBound + 40)] {
                    let x0 = min(max(takeoff, span.lowerBound), span.upperBound)
                    guard abs(landing - x0) <= Self.leapReach,
                          let launch = RoamPhysics.launch(dx: landing - x0, dy: rise, clearance: 14) else { continue }
                    leap(from: Node(segment: li, at: x0), start: CGPoint(x: x0, y: from.y), vx: launch.vx, vy: launch.vy,
                         aim: .ledge(to, x: landing), expect: ti)
                }
            }
        }

        // Jumps from a ledge onto a wall it does not touch.
        for (li, ledge) in ledges.enumerated() {
            let span = range(li)
            for (wi, wall) in walls.enumerated() where !touches(span, y: ledge.y, wall) {
                let wallRange = range(wallBase + wi)
                let line = wall.x + wall.normal * half
                let cy = min(max(ledge.y + half + 20, wallRange.lowerBound), wallRange.upperBound)
                let rise = cy - half - ledge.y
                guard rise <= RoamPhysics.maxJumpHeight - 12, rise >= -160 else { continue }
                let x0 = min(max(line + wall.normal * 60, span.lowerBound), span.upperBound)
                guard (x0 - line) * wall.normal >= 8, abs(x0 - line) <= 360,
                      let launch = RoamPhysics.launch(dx: line - x0, dy: rise, clearance: 10) else { continue }
                leap(from: Node(segment: li, at: x0), start: CGPoint(x: x0, y: ledge.y), vx: launch.vx, vy: launch.vy,
                     aim: .wall(wall, y: cy), expect: wallBase + wi)
            }
        }

        // Straight up from a ledge to catch a ceiling overhead.
        for (li, ledge) in ledges.enumerated() {
            let span = range(li)
            for (ci, ceiling) in ceilings.enumerated() {
                let rise = ceiling.y - half * 2 - ledge.y
                guard rise >= 6, rise <= RoamPhysics.maxJumpHeight - 10 else { continue }
                let over = range(ceilingBase + ci)
                let low = max(span.lowerBound, over.lowerBound + half)
                let high = min(span.upperBound, over.upperBound - half)
                guard high >= low else { continue }
                let x0 = (low + high) / 2
                leap(from: Node(segment: li, at: x0), start: CGPoint(x: x0, y: ledge.y), vx: 0,
                     vy: (2 * RoamPhysics.gravity * (rise + 10)).squareRoot(), aim: .ceiling(ceiling, x: x0),
                     expect: ceilingBase + ci)
            }
        }

        // Pushing off a wall near its bottom or top falls to whatever is below.
        for (wi, wall) in walls.enumerated() {
            let wallRange = range(wallBase + wi)
            for y in [wallRange.lowerBound, wallRange.upperBound] {
                leap(from: Node(segment: wallBase + wi, at: y),
                     start: CGPoint(x: wall.x + wall.normal * half, y: y - half),
                     vx: wall.normal * 90, vy: 120, aim: nil)
            }
        }

        // Letting go of a ceiling drops the pet, turned upright, onto whatever is below.
        for (ci, ceiling) in ceilings.enumerated() {
            let span = range(ceilingBase + ci)
            for x in [span.lowerBound + half, (span.lowerBound + span.upperBound) / 2, span.upperBound - half]
            where span.contains(x) {
                leap(from: Node(segment: ceilingBase + ci, at: x), start: CGPoint(x: x, y: ceiling.y - half * 2),
                     vx: 0, vy: 0, aim: nil)
            }
        }
        return result
    }

    /// Whether a horizontal line at `y` across `span` meets a wall closely enough to step between them.
    private func touches(_ span: ClosedRange<Double>, y: Double, _ wall: RoamWall) -> Bool {
        let gap = max(span.lowerBound - wall.x, wall.x - span.upperBound, 0)
        return gap <= 1.5 && y >= wall.minY - 2 && y <= wall.maxY + 2
    }

    /// Flies a launch through the pet's own physics. Planned leaps catch only the wall or ceiling they aim for.
    private func simulate(from start: CGPoint, vx: Double, vy: Double,
                          aim: RoamSpot?) -> (RoamPhysics.Flight, Double)? {
        var flight = RoamPhysics.Flight(x: start.x, y: start.y, vx: vx, vy: vy)
        let walls = aim?.wall.map { [$0] } ?? []
        let ceilings = aim?.ceiling.map { [$0] } ?? []
        let dt = 1.0 / 60
        for tick in 1...240 {
            flight = RoamPhysics.fly(flight, dt: dt, surfaces: ledges, walls: walls, ceilings: ceilings, half: half,
                                     minX: screenMinX, maxX: screenMaxX)
            if flight.hitSide { return nil }
            if flight.landedOn != nil || flight.grabbed != nil || flight.grabbedCeiling != nil {
                return (flight, Double(tick) * dt)
            }
        }
        return nil
    }

    // MARK: Search

    /// The cheapest route from `start` to wherever scores best, weighing closeness to `target` against
    /// `effort` points per second of travel. Empty when staying put is best; nil when `start` is not on
    /// this screen's segments.
    public func route(from start: RoamSpot, toward target: CGPoint, effort: Double = 10) -> [RoamMove]? {
        guard let origin = node(start) else { return nil }
        var goals: [Node] = []
        for index in 0..<count {
            let span = range(index)
            switch segment(index) {
            case .ledge(let ledge):
                guard ledge.y <= target.y + 20 else { continue }
                goals.append(Node(segment: index, at: min(max(target.x, span.lowerBound), span.upperBound)))
            case .wall:
                goals.append(Node(segment: index, at: min(max(target.y, span.lowerBound), span.upperBound)))
            case .ceiling:
                goals.append(Node(segment: index, at: min(max(target.x, span.lowerBound), span.upperBound)))
            }
        }
        let search = dijkstra(from: origin, extra: goals)
        var best: (node: Node, score: Double)?
        for goal in goals {
            guard let time = search.cost[goal] else { continue }
            let point = spot(goal).point(half: half)
            let score = Double(hypot(point.x - target.x, point.y - target.y)) + effort * time
            if best == nil || score < best!.score - 0.001 { best = (goal, score) }
        }
        guard let best else { return [] }
        return moves(to: best.node, previous: search.previous)
    }

    /// Spots on other segments that can be reached from `start`, for picking somewhere to explore.
    public func reachable(from start: RoamSpot) -> [RoamSpot] {
        guard let origin = node(start) else { return [] }
        let search = dijkstra(from: origin, extra: [])
        return search.cost.keys.filter { $0.segment != origin.segment }
            .sorted { ($0.segment, $0.at) < ($1.segment, $1.at) }
            .map(spot)
    }

    private struct Search {
        var cost: [Node: Double]
        var previous: [Node: (node: Node, link: Link?)]
    }

    private func dijkstra(from origin: Node, extra: [Node]) -> Search {
        var points = basePoints
        points[origin.segment].insert(origin.at)
        for node in extra { points[node.segment].insert(node.at) }
        let sorted = points.map { $0.sorted() }

        var cost: [Node: Double] = [origin: 0]
        var previous: [Node: (node: Node, link: Link?)] = [:]
        var done: Set<Node> = []
        var frontier: [Node] = [origin]
        while !frontier.isEmpty {
            let index = frontier.indices.min { cost[frontier[$0]]! < cost[frontier[$1]]! }!
            let current = frontier.remove(at: index)
            guard done.insert(current).inserted else { continue }
            let base = cost[current]!
            var steps: [(Node, Double, Link?)] = []
            let line = sorted[current.segment]
            if let at = line.firstIndex(of: current.at) {
                let pace = current.segment < wallBase ? Self.walkPace : Self.climbPace
                for neighbor in [at - 1, at + 1] where line.indices.contains(neighbor) {
                    steps.append((Node(segment: current.segment, at: line[neighbor]),
                                  abs(line[neighbor] - current.at) / pace, nil))
                }
            }
            for link in outgoing[current] ?? [] { steps.append((link.to, link.cost, link)) }
            for (next, stepCost, link) in steps where !done.contains(next) {
                let total = base + stepCost
                if total < cost[next] ?? .infinity {
                    cost[next] = total
                    previous[next] = (current, link)
                    frontier.append(next)
                }
            }
        }
        return Search(cost: cost, previous: previous)
    }

    private func moves(to goal: Node, previous: [Node: (node: Node, link: Link?)]) -> [RoamMove] {
        var chain: [(node: Node, link: Link?)] = []
        var current = goal
        while let step = previous[current] {
            chain.append((current, step.link))
            current = step.node
        }
        var result: [RoamMove] = []
        for (node, link) in chain.reversed() {
            if let link {
                result.append(link.move)
                continue
            }
            let move: RoamMove
            switch segment(node.segment) {
            case .ledge, .ceiling: move = .walk(to: node.at)
            case .wall: move = .climb(to: node.at)
            }
            // Consecutive steps along one segment become one walk or climb.
            switch (result.last, move) {
            case (.walk?, .walk), (.climb?, .climb): result[result.count - 1] = move
            default: result.append(move)
            }
        }
        return result
    }
}
