import Foundation

public struct Snowball: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case held, flying, resting
        /// Rolled along in front of a roaming pet.
        case pushed(String)
    }

    public static let startRadius = 4.0
    public static let maxRadius = 32.0
    /// How much a ball sinks into whatever it sits on, as a fraction of its radius.
    public static let seat = 0.82

    public var id: Int
    public var x: Double
    public var y: Double
    public var r: Double
    public var vx = 0.0
    public var vy = 0.0
    public var state: State
    /// The ball this one sits on.
    public var below: Int?
    /// The ledge a ball at the bottom of a stack sits on.
    public var groundY: Double?
    public var snowman = false
    /// Turns as it rolls, so the drawing can show it.
    public var spin = 0.0

    public init(id: Int, x: Double, y: Double, r: Double, state: State) {
        self.id = id
        self.x = x
        self.y = y
        self.r = r
        self.state = state
    }

    /// Radius after rolling up `area` of snow; some of it packs down rather than adding size.
    public static func grown(_ r: Double, area: Double) -> Double {
        min(maxRadius, (r * r + area * 0.6 / .pi).squareRoot())
    }

    /// Where a ball of radius `r` sits on top of `base`.
    public static func perch(_ r: Double, on base: Snowball) -> Double { base.y + base.r + r * seat }

    /// Balls in stacks of three whose sizes shrink going up, by id. Each one is part of a snowman.
    public static func snowmen(_ balls: [Snowball]) -> Set<Int> {
        let byID = Dictionary(uniqueKeysWithValues: balls.map { ($0.id, $0) })
        var result: Set<Int> = []
        for head in balls where head.state == .resting {
            guard let middle = head.below.flatMap({ byID[$0] }), let base = middle.below.flatMap({ byID[$0] }),
                  base.below == nil, middle.state == .resting, base.state == .resting,
                  head.r < middle.r * 0.97, middle.r < base.r * 0.97,
                  !balls.contains(where: { $0.below == head.id }) else { continue }
            result.formUnion([head.id, middle.id, base.id])
        }
        return result
    }
}
