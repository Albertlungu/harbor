import Foundation

/// A flower growing on a ledge after spring rain.
public struct WeatherFlower: Equatable, Sendable {
    public var column: Int
    /// 0 just sprouted, 1 in full bloom.
    public var growth = 0.0
    public var age = 0.0
    public var tint: UInt8
}

/// A horizontal ledge that holds a pile: a height field of fixed-width columns on a grid shared by every
/// ledge, so a rebuilt ledge at the same height finds its old columns by index.
/// Coordinates are local to one screen, y up.
public struct WeatherLedge: Equatable, Sendable {
    public static let column = 2.0

    public var y: Double
    public var firstColumn: Int
    /// Depth of the pile (snow, leaf litter or petals) per column.
    public var heights: [Double]
    /// Depth of rain standing in puddles per column.
    public var water: [Double]
    public var flowers: [WeatherFlower] = []
    /// Set by anything that changes the shape; cleared once the pile has settled.
    public var restless = false

    public init(y: Double, minX: Double, maxX: Double) {
        self.y = y
        firstColumn = Int((minX / Self.column).rounded(.up))
        let count = max(0, Int((maxX / Self.column).rounded(.down)) - firstColumn)
        heights = Array(repeating: 0, count: count)
        water = Array(repeating: 0, count: count)
    }

    public var count: Int { heights.count }
    public var minX: Double { Double(firstColumn) * Self.column }
    public var maxX: Double { Double(firstColumn + count) * Self.column }
    public var isEmpty: Bool { !heights.contains { $0 > 0 } && !water.contains { $0 > 0 } && flowers.isEmpty }

    /// Index into `heights` of the column under `x`, if the ledge spans it.
    public func index(x: Double) -> Int? {
        let i = Int((x / Self.column).rounded(.down)) - firstColumn
        return i >= 0 && i < count ? i : nil
    }

    public func centerX(_ i: Int) -> Double { (Double(firstColumn + i) + 0.5) * Self.column }

    public func height(x: Double) -> Double { index(x: x).map { heights[$0] } ?? 0 }

    /// The top of the pile at `x`, or the bare ledge.
    public func top(x: Double) -> Double { y + height(x: x) }

    public func contains(x: Double) -> Bool { x >= minX && x < maxX }

    public mutating func deposit(x: Double, amount: Double, cap: Double) {
        guard let i = index(x: x) else { return }
        heights[i] = min(cap, heights[i] + amount)
        restless = true
    }

    /// Takes up to `amount` from each column in `x ± radius`; returns the area taken (depth × width).
    public mutating func take(x: Double, radius: Double, amount: Double) -> Double {
        var area = 0.0
        let lo = max(0, Int(((x - radius) / Self.column).rounded(.down)) - firstColumn)
        let hi = min(count - 1, Int(((x + radius) / Self.column).rounded(.down)) - firstColumn)
        guard lo <= hi else { return 0 }
        for i in lo...hi {
            let taken = min(heights[i], amount)
            heights[i] -= taken
            area += taken * Self.column
        }
        if area > 0 { restless = true }
        return area
    }

    /// Lets the pile slump until no step between neighbours is steeper than `slope`. Snow that piles past
    /// `edgeHold` at an open end tips over the edge and is returned as spill (area) for each end.
    @discardableResult
    public mutating func relax(slope: Double, edgeHold: Double) -> (left: Double, right: Double) {
        guard restless, count > 0 else { return (0, 0) }
        let limit = slope * Self.column
        var moved = 0.0
        // Sweeping both ways keeps a heap symmetric instead of creeping in one direction.
        for pass in 0..<2 {
            let indices: StrideThrough<Int> = pass == 0 ? stride(from: 0, through: count - 2, by: 1)
                : stride(from: count - 2, through: 0, by: -1)
            for i in indices {
                let diff = heights[i] - heights[i + 1]
                guard abs(diff) > limit else { continue }
                let shift = (abs(diff) - limit) / 2 * (diff > 0 ? 1 : -1)
                heights[i] -= shift
                heights[i + 1] += shift
                moved += abs(shift)
            }
        }
        var spill = (left: 0.0, right: 0.0)
        if heights[0] > edgeHold {
            spill.left = (heights[0] - edgeHold) * Self.column
            heights[0] = edgeHold
            moved += spill.left
        }
        if heights[count - 1] > edgeHold {
            spill.right = (heights[count - 1] - edgeHold) * Self.column
            heights[count - 1] = edgeHold
            moved += spill.right
        }
        if moved < 0.01 { restless = false }
        return spill
    }

    /// Melts (or blows away) `depth` from every column and dries puddles by `dry`.
    public mutating func melt(depth: Double, dry: Double) {
        for i in heights.indices where heights[i] > 0 { heights[i] = max(0, heights[i] - depth) }
        for i in water.indices where water[i] > 0 { water[i] = max(0, water[i] - dry) }
    }

    /// A lost run of columns, as area to drop back into the air.
    public struct Spill: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var area: Double
    }

    /// Moves piles from the previous ledges onto the rebuilt ones. Columns whose ledge is gone (the window
    /// moved, closed or was covered) come back as spills, grouped into runs of about `run` points.
    public static func carry(from old: [WeatherLedge], into new: inout [WeatherLedge], run: Double = 8) -> [Spill] {
        var spills: [Spill] = []
        for ledge in old where !ledge.isEmpty {
            let targets = new.indices.filter { abs(new[$0].y - ledge.y) < 0.5 }
            var pending: Spill?
            func flush() {
                if let p = pending, p.area > 0.5 { spills.append(p) }
                pending = nil
            }
            for i in 0..<ledge.count {
                let column = ledge.firstColumn + i
                if let t = targets.first(where: { column >= new[$0].firstColumn && column < new[$0].firstColumn + new[$0].count }) {
                    flush()
                    let j = column - new[t].firstColumn
                    new[t].heights[j] += ledge.heights[i]
                    new[t].water[j] += ledge.water[i]
                    if ledge.heights[i] > 0 { new[t].restless = true }
                    for flower in ledge.flowers where flower.column == i {
                        var moved = flower
                        moved.column = j
                        new[t].flowers.append(moved)
                    }
                    continue
                }
                let depth = ledge.heights[i]
                guard depth > 0 else { flush(); continue }
                let x = ledge.centerX(i)
                if var p = pending, x - p.x < run {
                    p.area += depth * Self.column
                    pending = p
                } else {
                    flush()
                    pending = Spill(x: x, y: ledge.y + depth / 2, area: depth * Self.column)
                }
            }
            flush()
        }
        return spills
    }
}
