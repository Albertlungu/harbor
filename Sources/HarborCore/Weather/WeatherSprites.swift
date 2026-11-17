import Foundation
import simd

/// One textured quad for the weather renderer; the layout matches the Metal shader's `Sprite`.
public struct WeatherSprite: Equatable, Sendable {
    /// Center x, center y, half width, half height, in points.
    public var rect: SIMD4<Float>
    /// Straight (not premultiplied) RGBA.
    public var color: SIMD4<Float>
    /// Rotation in radians, shape, and two shape-specific values.
    public var params: SIMD4<Float>

    public init(x: Double, y: Double, halfWidth: Double, halfHeight: Double, color: SIMD4<Float>,
                shape: WeatherShape, angle: Double = 0, a: Float = 0, b: Float = 0) {
        rect = SIMD4(Float(x), Float(y), Float(halfWidth), Float(halfHeight))
        self.color = color
        params = SIMD4(Float(angle), shape.rawValue, a, b)
    }
}

/// What the fragment shader draws inside a sprite's quad.
public enum WeatherShape: Float, Sendable {
    /// `a` adds a faint grey rim so white flakes still read over white windows.
    case disc = 0
    case glow = 1
    case leaf = 2
    case petal = 3
    /// A shaded snowball.
    case ball = 4
    /// A pile segment whose top runs from `a` (left) to `b` (right), as fractions of the quad's height.
    case slope = 5
    case bubble = 6
    case rect = 7
    /// Points along +x.
    case triangle = 8
    case seed = 9
}

private enum Ink {
    static let snow = SIMD4<Float>(0.97, 0.98, 1, 1)
    static let leaves: [SIMD4<Float>] = [
        SIMD4(0.80, 0.22, 0.12, 1), SIMD4(0.93, 0.50, 0.12, 1), SIMD4(0.93, 0.72, 0.20, 1),
        SIMD4(0.55, 0.32, 0.15, 1), SIMD4(0.62, 0.12, 0.15, 1),
    ]
    static let litter = SIMD4<Float>(0.40, 0.24, 0.12, 1)
    static let petals: [SIMD4<Float>] = [SIMD4(1, 0.80, 0.86, 1), SIMD4(0.98, 0.70, 0.80, 1), SIMD4(1, 0.89, 0.93, 1)]
    static let petalBed = SIMD4<Float>(0.98, 0.83, 0.88, 1)
    static let water = SIMD4<Float>(0.42, 0.62, 0.95, 0.5)
    static let drop = SIMD4<Float>(0.62, 0.76, 0.96, 0.6)
    static let froth = SIMD4<Float>(0.9, 0.95, 1, 0.85)
    static let seed = SIMD4<Float>(1, 1, 1, 0.9)
    static let firefly = SIMD4<Float>(0.86, 1, 0.38, 1)
    static let bubble = SIMD4<Float>(1, 1, 1, 1)
    static let blooms: [SIMD4<Float>] = [
        SIMD4(0.98, 0.45, 0.60, 1), SIMD4(0.97, 0.84, 0.30, 1), SIMD4(0.70, 0.55, 0.95, 1), SIMD4(1, 1, 1, 1),
    ]
    static let heart = SIMD4<Float>(0.98, 0.82, 0.25, 1)
    static let stem = SIMD4<Float>(0.33, 0.63, 0.30, 1)
    static let coal = SIMD4<Float>(0.12, 0.12, 0.14, 1)
    static let carrot = SIMD4<Float>(0.95, 0.50, 0.12, 1)
    static let twig = SIMD4<Float>(0.42, 0.28, 0.16, 1)

    static func pick(_ list: [SIMD4<Float>], _ tint: UInt8) -> SIMD4<Float> { list[Int(tint) % list.count] }

    static func faded(_ c: SIMD4<Float>, _ alpha: Double) -> SIMD4<Float> {
        SIMD4(c.x, c.y, c.z, c.w * Float(min(1, max(0, alpha))))
    }

    static func shaded(_ c: SIMD4<Float>, _ k: Float) -> SIMD4<Float> { SIMD4(c.x * k, c.y * k, c.z * k, c.w) }
}

extension WeatherWorld {
    /// Everything settled on the ledges: piles, puddles and flowers.
    public func pileSprites(into out: inout [WeatherSprite]) {
        for ledge in ledges where !ledge.isEmpty {
            switch season {
            case .winter:
                slopes(ledge, ledge.heights, scale: 1, color: Ink.snow, into: &out)
            case .autumn:
                slopes(ledge, ledge.heights, scale: 0.7, color: Ink.litter, into: &out)
                litter(ledge, into: &out)
            case .spring:
                slopes(ledge, ledge.heights, scale: 0.6, color: Ink.petalBed, into: &out)
                petalBed(ledge, into: &out)
                slopes(ledge, ledge.water, scale: 1, color: Ink.water, into: &out)
                flowers(ledge, into: &out)
            case .summer:
                break
            }
        }
    }

    /// The pile's surface as straight segments between column centers; runs of equal slope share a quad.
    private func slopes(_ ledge: WeatherLedge, _ depth: [Double], scale: Double, color: SIMD4<Float>,
                        into out: inout [WeatherSprite]) {
        let n = ledge.count
        guard n > 1 else { return }
        var points: [(x: Double, h: Double)] = [(ledge.minX, depth[0] * scale)]
        points.reserveCapacity(n + 2)
        for i in 0..<n { points.append((ledge.centerX(i), depth[i] * scale)) }
        points.append((ledge.maxX, depth[n - 1] * scale))
        var start = 0
        while start < points.count - 1 {
            var end = start + 1
            let slope = (points[end].h - points[start].h) / (points[end].x - points[start].x)
            while end + 1 < points.count {
                let next = (points[end + 1].h - points[end].h) / (points[end + 1].x - points[end].x)
                guard abs(next - slope) < 0.02 else { break }
                end += 1
            }
            let a = points[start], b = points[end]
            let top = max(a.h, b.h)
            if top > 0.15 {
                out.append(WeatherSprite(x: (a.x + b.x) / 2, y: ledge.y + top / 2, halfWidth: (b.x - a.x) / 2 + 0.3,
                                         halfHeight: top / 2, color: color, shape: .slope,
                                         a: Float(a.h / top), b: Float(b.h / top)))
            }
            start = end
        }
    }

    /// Leaves drawn over the top few points of a litter pile, placed by a hash of the column so they hold still.
    private func litter(_ ledge: WeatherLedge, into out: inout [WeatherSprite]) {
        for c in stride(from: 0, to: ledge.count, by: 2) {
            let depth = ledge.heights[c]
            guard depth > 0.8 else { continue }
            let layers = min(3, Int(depth / 2.5) + 1)
            for k in 0..<layers {
                let hash = Self.hash(ledge.firstColumn + c, k)
                let y = max(ledge.y + 1.5, ledge.y + depth - Double(k) * 2.5 - 1.2)
                let size = 3.5 + Double(hash & 7) * 0.35
                out.append(WeatherSprite(x: ledge.centerX(c) + Double(Int(hash >> 3 & 7) - 3) * 0.6, y: y,
                                         halfWidth: size, halfHeight: size * 0.5,
                                         color: Ink.shaded(Ink.pick(Ink.leaves, UInt8(hash >> 6 & 255)), 1 - Float(k) * 0.15),
                                         shape: .leaf, angle: Double(hash >> 14 & 63) / 10))
            }
        }
    }

    private func petalBed(_ ledge: WeatherLedge, into out: inout [WeatherSprite]) {
        for c in stride(from: 0, to: ledge.count, by: 2) where ledge.heights[c] > 0.3 {
            let hash = Self.hash(ledge.firstColumn + c, 0)
            out.append(WeatherSprite(x: ledge.centerX(c), y: ledge.y + ledge.heights[c] * 0.6, halfWidth: 3,
                                     halfHeight: 2, color: Ink.pick(Ink.petals, UInt8(hash & 255)), shape: .petal,
                                     angle: Double(hash >> 8 & 63) / 10))
        }
    }

    private func flowers(_ ledge: WeatherLedge, into out: inout [WeatherSprite]) {
        for flower in ledge.flowers {
            let g = flower.growth
            // Wilting over the last minute of its life.
            let droop = max(0, min(1, (flower.age - 180) / 60))
            let x = ledge.centerX(flower.column)
            let stem = 9 * g * (1 - droop * 0.4)
            out.append(WeatherSprite(x: x, y: ledge.y + stem / 2, halfWidth: 0.7, halfHeight: stem / 2,
                                     color: Ink.stem, shape: .rect))
            guard g > 0.3 else { continue }
            let head = SIMD2(x + droop * 2, ledge.y + stem)
            let petal = 2.2 * g
            let color = Ink.faded(Ink.pick(Ink.blooms, flower.tint), 1 - droop * 0.5)
            for k in 0..<5 {
                let a = Double(k) / 5 * 2 * .pi + droop
                out.append(WeatherSprite(x: head.x + cos(a) * petal, y: head.y + sin(a) * petal, halfWidth: petal,
                                         halfHeight: petal, color: color, shape: .disc))
            }
            out.append(WeatherSprite(x: head.x, y: head.y, halfWidth: petal * 0.7, halfHeight: petal * 0.7,
                                     color: Ink.heart, shape: .disc))
        }
    }

    /// Everything that moves: particles, snowballs and snowmen.
    public func liveSprites(into out: inout [WeatherSprite]) {
        for p in particles {
            switch p.kind {
            case .flake:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: p.size,
                                         color: Ink.faded(Ink.snow, 0.95), shape: .disc, a: 1))
            case .puff:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: p.size,
                                         color: Ink.faded(Ink.snow, p.life * 1.6), shape: .disc, a: 1))
            case .chunk:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: p.size, color: Ink.snow,
                                         shape: .ball))
            case .leaf:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: p.size * 0.5,
                                         color: Ink.pick(Ink.leaves, p.tint), shape: .leaf, angle: p.angle))
            case .petal:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: p.size * 0.65,
                                         color: Ink.pick(Ink.petals, p.tint), shape: .petal, angle: p.angle))
            case .drop:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: 6, color: Ink.drop,
                                         shape: .disc, angle: atan2(p.vx, -p.vy)))
            case .splash:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: p.size,
                                         color: Ink.faded(p.tint == 1 ? Ink.froth : Ink.drop, p.life * 3), shape: .disc))
            case .seed:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: p.size,
                                         color: Ink.faded(Ink.seed, min(1, p.life / 3)), shape: .seed, angle: p.angle))
            case .firefly:
                let pulse = 0.25 + 0.75 * max(0, sin(time * 2.4 + p.phase))
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size * 3.5, halfHeight: p.size * 3.5,
                                         color: Ink.faded(Ink.firefly, pulse * min(1, p.life / 2)), shape: .glow))
            case .bubble:
                out.append(WeatherSprite(x: p.x, y: p.y, halfWidth: p.size, halfHeight: p.size,
                                         color: Ink.faded(Ink.bubble, min(1, p.life)), shape: .bubble))
            }
        }
        for ball in balls {
            out.append(WeatherSprite(x: ball.x, y: ball.y, halfWidth: ball.r, halfHeight: ball.r, color: Ink.snow,
                                     shape: .ball))
            guard ball.snowman else { continue }
            let r = ball.r
            let isHead = ball.below != nil && !balls.contains { $0.below == ball.id }
            let isBase = ball.below == nil
            if isHead {
                for side in [-1.0, 1.0] {
                    out.append(WeatherSprite(x: ball.x + side * r * 0.32, y: ball.y + r * 0.22, halfWidth: max(1, r * 0.11),
                                             halfHeight: max(1, r * 0.11), color: Ink.coal, shape: .disc))
                }
                out.append(WeatherSprite(x: ball.x + r * 0.5, y: ball.y - r * 0.02, halfWidth: r * 0.5,
                                         halfHeight: max(1, r * 0.12), color: Ink.carrot, shape: .triangle))
                for k in -2...2 {
                    let t = Double(k) / 2
                    out.append(WeatherSprite(x: ball.x + t * r * 0.38, y: ball.y - r * 0.4 + t * t * r * 0.12,
                                             halfWidth: max(0.7, r * 0.06), halfHeight: max(0.7, r * 0.06),
                                             color: Ink.coal, shape: .disc))
                }
            } else if !isBase {
                for k in -1...1 {
                    out.append(WeatherSprite(x: ball.x, y: ball.y + Double(k) * r * 0.42, halfWidth: max(1, r * 0.09),
                                             halfHeight: max(1, r * 0.09), color: Ink.coal, shape: .disc))
                }
                for side in [-1.0, 1.0] {
                    let length = r * 0.9
                    let angle = side * 0.45
                    out.append(WeatherSprite(x: ball.x + side * (r * 0.85 + length * 0.45), y: ball.y + r * 0.2 + length * 0.2,
                                             halfWidth: length / 2, halfHeight: max(0.8, r * 0.05), color: Ink.twig,
                                             shape: .rect, angle: angle))
                }
            }
        }
    }

    static func hash(_ column: Int, _ layer: Int) -> UInt64 {
        var z = UInt64(bitPattern: Int64(column)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(layer) &* 0xBF58_476D_1CE4_E5B9
        z ^= z >> 29
        z = z &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 32)
    }
}
