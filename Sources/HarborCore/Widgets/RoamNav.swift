import CoreGraphics
import Foundation

/// Where a pet can be: standing on a ledge with its feet at `x`, or holding a wall with its middle at `y`.
public enum RoamSpot: Equatable, Sendable {
    case ledge(RoamSurface, x: Double)
    case wall(RoamWall, y: Double)

    /// The feet on a ledge, the middle of the body on a wall.
    public func point(half: Double) -> CGPoint {
        switch self {
        case .ledge(let ledge, let x): CGPoint(x: x, y: ledge.y)
        case .wall(let wall, let y): CGPoint(x: wall.x + wall.normal * half, y: y)
        }
    }
}

/// One leg of a route.
public enum RoamMove: Equatable, Sendable {
    /// Walk along the current ledge to `x`.
    case walk(to: Double)
    /// Climb along the current wall until the middle of the body is at `y`.
    case climb(to: Double)
    /// Step between a ledge and a wall that meet.
    case transfer(RoamSpot)
    /// Jump or drop with this launch velocity, expecting to come down on `onto`.
    case leap(vx: Double, vy: Double, onto: RoamSpot)
}

/// Every way across one screen's ledges and walls, built once per change of surfaces and searched with
/// Dijkstra. Leaps are found by flying the same physics the pet uses, so a planned jump lands where the
/// plan says unless the windows move mid-flight.
public struct RoamNav: Sendable {
    public let ledges: [RoamSurface]
    public let walls: [RoamWall]
    /// Half the pet's size: how far its middle sits from a wall, and the margin it keeps from a wall's ends.
    public let half: Double
    private let screenMinX: Double
    private let screenMaxX: Double
    private var links: [Link] = []
    private var outgoing: [Node: [Link]] = [:]
    /// Where links meet each segment; routes walk or climb between neighbouring points.
    private var basePoints: [Set<Double>] = []

    /// A point on a segment: ledges first, then walls. `at` is x on a ledge and y on a wall.
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

    /// Speeds the planner assumes, so routes favour walking over long climbs.
    private static let walkPace = 45.0
    private static let climbPace = 30.0
    /// Fixed overheads that keep routes from hopping when walking is nearly as quick.
    private static let leapPenalty = 0.6
    private static let transferPenalty = 0.3

    public init(ledges: [RoamSurface], walls: [RoamWall], half: Double, screenMinX: Double, screenMaxX: Double) {
        self.ledges = ledges
        self.walls = walls.filter { $0.maxY - $0.minY >= half * 2 }
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

    private var count: Int { ledges.count + walls.count }

    private func range(_ segment: Int) -> ClosedRange<Double> {
        if segment < ledges.count {
            let ledge = ledges[segment]
            return max(ledge.minX, screenMinX)...max(min(ledge.maxX, screenMaxX), max(ledge.minX, screenMinX))
        }
        let wall = walls[segment - ledges.count]
        return (wall.minY + half)...(wall.maxY - half)
    }

    private func spot(_ node: Node) -> RoamSpot {
        node.segment < ledges.count
            ? .ledge(ledges[node.segment], x: node.at)
            : .wall(walls[node.segment - ledges.count], y: node.at)
    }

    private func node(_ spot: RoamSpot) -> Node? {
        switch spot {
        case .ledge(let ledge, let x):
            ledges.firstIndex(of: ledge).map { Node(segment: $0, at: x) }
        case .wall(let wall, let y):
            walls.firstIndex(of: wall).map { Node(segment: ledges.count + $0, at: y) }
        }
    }

    /// Whether `spot` is one of this screen's segments; a route through a missing one is stale.
    public func contains(_ spot: RoamSpot) -> Bool { node(spot) != nil }

    // MARK: Links

    private func buildLinks() -> [Link] {
        var result: [Link] = []
        let ledgeCount = ledges.count

        func add(_ from: Node, _ to: Node, _ move: RoamMove, _ cost: Double) {
            result.append(Link(from: from, to: to, move: move, cost: cost))
        }

        func leap(from: Node, start: CGPoint, vx: Double, vy: Double, aim: RoamWall?, expect: Int? = nil) {
            guard let (flight, time) = simulate(from: start, vx: vx, vy: vy, aim: aim) else { return }
            let target: Node
            if let wall = flight.grabbed, let index = walls.firstIndex(of: wall) {
                target = Node(segment: ledgeCount + index, at: flight.y)
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
            for (wi, wall) in walls.enumerated() {
                let span = range(li)
                let gap = max(span.lowerBound - wall.x, wall.x - span.upperBound, 0)
                guard gap <= 1.5, ledge.y >= wall.minY - 2, ledge.y <= wall.maxY + 2 else { continue }
                let x = min(max(wall.x + wall.normal * half, span.lowerBound), span.upperBound)
                let wallRange = range(ledgeCount + wi)
                let y = min(max(ledge.y + half, wallRange.lowerBound), wallRange.upperBound)
                let onLedge = Node(segment: li, at: x)
                let onWall = Node(segment: ledgeCount + wi, at: y)
                add(onLedge, onWall, .transfer(.wall(wall, y: y)), Self.transferPenalty)
                add(onWall, onLedge, .transfer(.ledge(ledge, x: x)), Self.transferPenalty)
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
                    guard abs(landing - x0) <= 420,
                          let launch = RoamPhysics.launch(dx: landing - x0, dy: rise, clearance: 14) else { continue }
                    leap(from: Node(segment: li, at: x0), start: CGPoint(x: x0, y: from.y), vx: launch.vx, vy: launch.vy,
                         aim: nil, expect: ti)
                }
            }
        }

        // Jumps from a ledge onto a wall it does not touch.
        for (li, ledge) in ledges.enumerated() {
            let span = range(li)
            for (wi, wall) in walls.enumerated() {
                let wallRange = range(ledgeCount + wi)
                let line = wall.x + wall.normal * half
                let cy = min(max(ledge.y + half + 20, wallRange.lowerBound), wallRange.upperBound)
                let rise = cy - half - ledge.y
                guard rise <= RoamPhysics.maxJumpHeight - 12, rise >= -160 else { continue }
                let x0 = min(max(line + wall.normal * 50, span.lowerBound), span.upperBound)
                guard (x0 - line) * wall.normal >= 8, abs(x0 - line) <= 260,
                      let launch = RoamPhysics.launch(dx: line - x0, dy: rise, clearance: 10) else { continue }
                leap(from: Node(segment: li, at: x0), start: CGPoint(x: x0, y: ledge.y), vx: launch.vx, vy: launch.vy,
                     aim: wall, expect: ledgeCount + wi)
            }
        }

        // Pushing off a wall near its bottom or top falls to whatever is below.
        for (wi, wall) in walls.enumerated() {
            let wallRange = range(ledgeCount + wi)
            for y in [wallRange.lowerBound, wallRange.upperBound] {
                leap(from: Node(segment: ledgeCount + wi, at: y),
                     start: CGPoint(x: wall.x + wall.normal * half, y: y - half),
                     vx: wall.normal * 90, vy: 120, aim: nil)
            }
        }
        return result
    }

    /// Flies a launch through the pet's own physics. Planned leaps grab only the wall they aim for.
    private func simulate(from start: CGPoint, vx: Double, vy: Double,
                          aim: RoamWall?) -> (RoamPhysics.Flight, Double)? {
        var flight = RoamPhysics.Flight(x: start.x, y: start.y, vx: vx, vy: vy)
        let dt = 1.0 / 60
        for tick in 1...240 {
            flight = RoamPhysics.fly(flight, dt: dt, surfaces: ledges, walls: aim.map { [$0] } ?? [], half: half,
                                     minX: screenMinX, maxX: screenMaxX)
            if flight.hitSide { return nil }
            if flight.landedOn != nil || flight.grabbed != nil { return (flight, Double(tick) * dt) }
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
        for segment in 0..<count {
            let span = range(segment)
            if segment < ledges.count {
                guard ledges[segment].y <= target.y + 20 else { continue }
                goals.append(Node(segment: segment, at: min(max(target.x, span.lowerBound), span.upperBound)))
            } else {
                goals.append(Node(segment: segment, at: min(max(target.y, span.lowerBound), span.upperBound)))
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
                let pace = current.segment < ledges.count ? Self.walkPace : Self.climbPace
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
            let move: RoamMove = node.segment < ledges.count ? .walk(to: node.at) : .climb(to: node.at)
            // Consecutive steps along one segment become one walk or climb.
            switch (result.last, move) {
            case (.walk?, .walk), (.climb?, .climb): result[result.count - 1] = move
            default: result.append(move)
            }
        }
        return result
    }
}
