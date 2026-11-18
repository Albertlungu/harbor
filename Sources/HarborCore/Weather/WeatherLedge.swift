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
    /// Set by anything that changes the shape; cleared once the pile has settled. Setting it directly
    /// unsettles the whole ledge; `mark` unsettles only a few columns.
    public var restless = false { didSet { unsettled = nil } }
    /// The columns still slumping while `restless`; nil means all of them.
    var unsettled: ClosedRange<Int>?

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
        mark(i, i)
    }

    /// Wakes columns `lo...hi` so the next relaxations look at them and their neighbours.
    mutating func mark(_ lo: Int, _ hi: Int) {
        let whole = restless && unsettled == nil
        let merged = unsettled.map { min($0.lowerBound, lo)...max($0.upperBound, hi) } ?? (lo...hi)
        restless = true
        unsettled = whole ? nil : merged
    }

    /// How much steeper or shallower than the season's slope a column holds, from -1 to 1. Fixed by the
    /// column's place on the shared grid, mixing a fine grain with a coarser one, so a pile settles into the
    /// same lumps and shoulders every time instead of straight-sided heaps.
    static func grain(_ column: Int) -> Double {
        func noise(_ n: Int) -> Double {
            var z = UInt64(bitPattern: Int64(n)) &* 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53) * 2 - 1
        }
        let coarse = Int((Double(column) / 5).rounded(.down))
        return noise(column) * 0.45 + noise(coarse &+ 0x5EED) * 0.55
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
        if area > 0 { mark(lo, hi) }
        return area
    }

    /// Lets the pile slump a step toward the angle of repose, near the columns that were disturbed. Each
    /// pair of columns holds its own slope, `slope` give or take `roughness` of it by the column's grain,
    /// and only `rate` of the excess moves per call, so a pile settles over a few frames into a lumpy
    /// shape rather than snapping into a straight-sided heap. Snow that piles past `edgeHold` at an open
    /// end tips over the edge and is returned as spill (area) for each end.
    @discardableResult
    public mutating func relax(slope: Double, edgeHold: Double, roughness: Double = 0, rate: Double = 1)
        -> (left: Double, right: Double) {
        guard restless, count > 0 else { return (0, 0) }
        let limit = slope * Self.column
        let lo = max(0, (unsettled?.lowerBound ?? 0) - 1)
        let hi = min(count - 2, unsettled?.upperBound ?? count - 1)
        var moved = 0.0
        var movedLo = Int.max, movedHi = -1
        // Sweeping both ways keeps a heap from creeping in one direction.
        if lo <= hi {
            for pass in 0..<2 {
                let indices: StrideThrough<Int> = pass == 0 ? stride(from: lo, through: hi, by: 1)
                    : stride(from: hi, through: lo, by: -1)
                for i in indices {
                    let held = roughness == 0 ? limit : limit * max(0, 1 + roughness * Self.grain(firstColumn + i))
                    let diff = heights[i] - heights[i + 1]
                    guard abs(diff) > held else { continue }
                    let shift = (abs(diff) - held) / 2 * rate * (diff > 0 ? 1 : -1)
                    heights[i] -= shift
                    heights[i + 1] += shift
                    moved += abs(shift)
                    movedLo = min(movedLo, i)
                    movedHi = max(movedHi, i + 1)
                }
            }
        }
        var spill = (left: 0.0, right: 0.0)
        if heights[0] > edgeHold {
            spill.left = (heights[0] - edgeHold) * Self.column
            heights[0] = edgeHold
            moved += spill.left
            movedLo = 0
            movedHi = max(movedHi, min(1, count - 1))
        }
        if heights[count - 1] > edgeHold {
            spill.right = (heights[count - 1] - edgeHold) * Self.column
            heights[count - 1] = edgeHold
            moved += spill.right
            movedLo = min(movedLo, max(0, count - 2))
            movedHi = count - 1
        }
        if moved < 0.01 {
            restless = false
        } else {
            unsettled = movedLo...movedHi
        }
        return spill
    }

    /// Melts (or blows away) `depth` from every column and dries puddles by `dry`.
    public mutating func melt(depth: Double, dry: Double) {
        for i in heights.indices where heights[i] > 0 { heights[i] = max(0, heights[i] - depth) }
        for i in water.indices where water[i] > 0 { water[i] = max(0, water[i] - dry) }
    }

    /// A lost run of columns: the pile, puddle water and flowers that were on it, to drop back into the air.
    public struct Spill: Equatable, Sendable {
        /// Middle and width of the run, and the ledge it sat on.
        public var x: Double
        public var width: Double
        public var y: Double
        /// Area of pile, and the deepest column.
        public var area: Double
        public var depth: Double
        /// Area of standing water.
        public var water: Double
        /// Tints of the flowers that grew there.
        public var blooms: [UInt8]
    }

    /// Moves piles from the previous ledges onto the rebuilt ones. Columns whose ledge is gone (the window
    /// moved, closed or was covered) come back as spills, grouped into runs of about `run` points.
    public static func carry(from old: [WeatherLedge], into new: inout [WeatherLedge], run: Double = 8) -> [Spill] {
        var spills: [Spill] = []
        for ledge in old where !ledge.isEmpty {
            let targets = new.indices.filter { abs(new[$0].y - ledge.y) < 0.5 }
            var pending: Spill?
            func flush() {
                if let p = pending, p.area > 0.5 || p.water > 0.3 || !p.blooms.isEmpty { spills.append(p) }
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
                let blooms = ledge.flowers.filter { $0.column == i && $0.growth > 0.3 }.map(\.tint)
                guard depth > 0 || ledge.water[i] > 0 || !blooms.isEmpty else { flush(); continue }
                let left = ledge.centerX(i) - Self.column / 2
                if var p = pending, left - (p.x - p.width / 2) < run {
                    let start = p.x - p.width / 2
                    p.width = left + Self.column - start
                    p.x = start + p.width / 2
                    p.area += depth * Self.column
                    p.depth = max(p.depth, depth)
                    p.water += ledge.water[i] * Self.column
                    p.blooms += blooms
                    pending = p
                } else {
                    flush()
                    pending = Spill(x: left + Self.column / 2, width: Self.column, y: ledge.y, area: depth * Self.column,
                                    depth: depth, water: ledge.water[i] * Self.column, blooms: blooms)
                }
            }
            flush()
        }
        return spills
    }
}
