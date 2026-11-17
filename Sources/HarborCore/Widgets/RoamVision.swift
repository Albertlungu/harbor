import CoreGraphics
import Foundation

/// Finds long horizontal edges in a grayscale picture of the screen, so the pet can stand on lines that
/// Accessibility does not report, such as the edges of panes drawn by apps without accessible elements.
public enum RoamVision {
    /// A horizontal edge in image pixels: the boundary above row `y`, from column `minX` through `maxX`.
    public struct Edge: Equatable, Sendable {
        public var y: Int
        public var minX: Int
        public var maxX: Int

        public init(y: Int, minX: Int, maxX: Int) {
            self.y = y
            self.minX = minX
            self.maxX = maxX
        }

        public var length: Int { maxX - minX + 1 }
    }

    /// Shortest edge worth standing on, in points; text and icons make only short runs.
    public static let minLength = 120.0
    /// Smallest brightness step, out of 255, that counts as an edge.
    public static let threshold = 22

    /// Rows where the brightness steps by at least `threshold` the same way along at least `minRun`
    /// pixels, bridging gaps of up to `maxGap`. Edges blurred over neighbouring rows merge into the top one.
    public static func edges(gray: [UInt8], width: Int, height: Int, threshold: Int = threshold, minRun: Int,
                             maxGap: Int = 2) -> [Edge] {
        guard width > 0, height > 1, gray.count >= width * height else { return [] }
        var found: [Edge] = []
        for y in 1..<height {
            let above = (y - 1) * width
            let below = y * width
            var start = -1
            var last = -1
            var sign = 0
            func close() {
                if start >= 0, last - start + 1 >= minRun { found.append(Edge(y: y, minX: start, maxX: last)) }
                start = -1
                sign = 0
            }
            for x in 0..<width {
                let step = Int(gray[below + x]) - Int(gray[above + x])
                let strong = abs(step) >= threshold
                if strong {
                    let s = step > 0 ? 1 : -1
                    if start >= 0, s != sign || x - last - 1 > maxGap { close() }
                    if start < 0 {
                        start = x
                        sign = s
                    }
                    last = x
                } else if start >= 0, x - last > maxGap {
                    close()
                }
            }
            close()
        }
        return merge(found)
    }

    /// Joins runs one or two rows apart that overlap by at least half the shorter, keeping the top row.
    private static func merge(_ runs: [Edge]) -> [Edge] {
        var result: [Edge] = []
        for run in runs {
            if let index = result.lastIndex(where: { other in
                run.y - other.y <= 2 && min(run.maxX, other.maxX) - max(run.minX, other.minX) + 1
                    >= min(run.length, other.length) / 2
            }) {
                result[index].minX = min(result[index].minX, run.minX)
                result[index].maxX = max(result[index].maxX, run.maxX)
            } else {
                result.append(run)
            }
        }
        return result
    }

    /// Turns edges in a picture of `screen` into thin rects in AppKit coordinates whose tops are the
    /// edges, the shape element ledges take. Edges in the menu bar or on the floor, and edges already
    /// covered by one of `known` (window tops and Accessibility ledges), are left out.
    public static func ledges(_ edges: [Edge], imageWidth: Int, imageHeight: Int, screen: CGRect,
                              menuBarHeight: Double, known: [RoamSurface]) -> [CGRect] {
        guard imageWidth > 0, imageHeight > 0 else { return [] }
        let sx = screen.width / Double(imageWidth)
        let sy = screen.height / Double(imageHeight)
        let top = screen.maxY - menuBarHeight
        var result: [CGRect] = []
        for edge in edges {
            let y = screen.maxY - Double(edge.y) * sy
            let minX = screen.minX + Double(edge.minX) * sx
            let maxX = screen.minX + Double(edge.maxX + 1) * sx
            guard maxX - minX >= minLength, y < top - 4, y > screen.minY + 8 else { continue }
            let half: Double = (maxX - minX) / 2
            let duplicate = known.contains { abs($0.y - y) <= 4 && min($0.maxX, maxX) - max($0.minX, minX) >= half }
                || result.contains { abs(Double($0.maxY) - y) <= 4 && min(Double($0.maxX), maxX) - max(Double($0.minX), minX) >= half }
            guard !duplicate else { continue }
            result.append(CGRect(x: minX, y: y - 2, width: maxX - minX, height: 2))
        }
        return result
    }
}
