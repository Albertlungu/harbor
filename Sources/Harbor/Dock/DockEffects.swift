import HarborCore
import SwiftUI

extension EffectKind {
    var title: String {
        switch self {
        case .snow: "Snow"
        case .rays: "Rays"
        case .fireworks: "Fireworks"
        case .fireflies: "Fireflies"
        case .leaves: "Leaves"
        case .petals: "Petals"
        case .rain: "Rain"
        case .bubbles: "Bubbles"
        case .aurora: "Aurora"
        case .stars: "Stars"
        case .hearts: "Hearts"
        case .sparkles: "Sparkles"
        case .waves: "Waves"
        case .sky: "Sky"
        case .ripples: "Ripples"
        case .trail: "Trail"
        case .seasonal: "Seasonal"
        }
    }

    var symbol: String {
        switch self {
        case .snow: "snowflake"
        case .rays: "sun.max"
        case .fireworks: "fireworks"
        case .fireflies: "lightbulb.min"
        case .leaves: "leaf"
        case .petals: "camera.macro"
        case .rain: "cloud.rain"
        case .bubbles: "bubbles.and.sparkles"
        case .aurora: "rainbow"
        case .stars: "star"
        case .hearts: "heart"
        case .sparkles: "sparkle"
        case .waves: "water.waves"
        case .sky: "sun.horizon"
        case .ripples: "dot.radiowaves.left.and.right"
        case .trail: "wand.and.sparkles"
        case .seasonal: "calendar"
        }
    }
}

/// Ambient overlays drawn behind the icons.
struct EffectsView: View {
    let effects: Set<EffectKind>
    let intensity: Double
    var edge: ScreenEdge = .bottom
    /// Pointer position along the dock axis in this view's coordinates, while hovering.
    var pointer: CGFloat? = nil
    var paused = false
    /// Drives pointer effects with a synthetic pointer, for previews.
    var demo = false
    var frameRate = 30.0
    @State private var trail = PointerTrail(spacing: 3, lifetime: 0.9)
    @State private var ripples = PointerTrail(spacing: 36, lifetime: 1.4)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = EffectPainter.paletteColors()
        TimelineView(.animation(minimumInterval: 1 / frameRate, paused: paused || reduceMotion)) { context in
            let painter = EffectPainter(effects: EffectKind.resolve(effects, on: context.date), intensity: intensity,
                                        edge: edge, palette: palette, hour: EffectMath.hour(of: context.date),
                                        pointer: pointer, trail: trail, ripples: ripples, demo: demo,
                                        still: reduceMotion)
            Canvas { ctx, size in
                painter.draw(ctx, size: size, t: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .onChange(of: pointer) { _, p in
            guard let p, effects.contains(where: \.followsPointer) else { return }
            let now = Date().timeIntervalSinceReferenceDate
            trail.record(Double(p), at: now)
            ripples.record(Double(p), at: now)
        }
    }
}

/// Draws every ambient effect as a pure function of time, so frames need no stored particles.
struct EffectPainter {
    var effects: Set<EffectKind>
    var intensity: Double
    var edge: ScreenEdge
    var palette: [Color]
    var hour: Double
    var pointer: CGFloat?
    var trail: PointerTrail
    var ripples: PointerTrail
    var demo: Bool
    /// Reduce Motion: pointer effects are left out since they only exist as motion.
    var still: Bool

    @MainActor
    static func paletteColors() -> [Color] {
        let look = Appearance.shared
        return [look.accent] + look.palette.spec.categories.map { Appearance.color($0) }
    }

    func draw(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let (band, bandSize) = bandFrame(ctx, size: size)
        if effects.contains(.sky) { drawSky(band, size: bandSize, t: t) }
        if effects.contains(.aurora) { drawAurora(band, size: bandSize, t: t) }
        if effects.contains(.stars) { drawStars(band, size: bandSize, t: t) }
        if effects.contains(.rays) { drawRays(band, size: bandSize, t: t) }
        if effects.contains(.waves) { drawWaves(band, size: bandSize, t: t) }
        if effects.contains(.rain) { drawRain(ctx, size: size, t: t) }
        if effects.contains(.snow) { drawSnow(ctx, size: size, t: t) }
        if effects.contains(.leaves) { drawLeaves(ctx, size: size, t: t) }
        if effects.contains(.petals) { drawPetals(ctx, size: size, t: t) }
        if effects.contains(.bubbles) { drawBubbles(ctx, size: size, t: t) }
        if effects.contains(.fireflies) { drawFireflies(ctx, size: size, t: t) }
        if effects.contains(.hearts) { drawHearts(ctx, size: size, t: t) }
        if effects.contains(.sparkles) { drawSparkles(ctx, size: size, t: t) }
        if effects.contains(.fireworks) { drawFireworks(ctx, size: size, t: t) }
        if !still, effects.contains(.ripples) { drawRipples(band, size: bandSize, t: t) }
        if !still, effects.contains(.trail) { drawTrail(band, size: bandSize, t: t) }
    }

    private var count: Int { Int(10 + intensity * 40) }
    private func scaled(_ base: Double, _ extra: Double) -> Int { Int(base + intensity * extra) }
    private func fract(_ x: Double) -> Double { EffectMath.fract(x) }
    private func hash(_ x: Double) -> Double { EffectMath.hash(x) }
    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    private func dot(_ p: CGPoint, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }

    /// Effects with a horizon (waves, sky, aurora) are drawn along the dock's length with their bottom
    /// toward the screen edge, so a vertical dock gets them turned on their side rather than squashed.
    private func bandFrame(_ ctx: GraphicsContext, size: CGSize) -> (GraphicsContext, CGSize) {
        var band = ctx
        switch edge {
        case .bottom, .top:
            return (ctx, size)
        case .left:
            band.translateBy(x: size.width, y: 0)
            band.rotate(by: bandAngle)
        case .right:
            band.translateBy(x: 0, y: size.height)
            band.rotate(by: bandAngle)
        }
        return (band, CGSize(width: size.height, height: size.width))
    }

    private var bandAngle: Angle {
        switch edge {
        case .left: .degrees(90)
        case .right: .degrees(-90)
        case .bottom, .top: .zero
        }
    }

    /// Pointer marks in the band frame, where the right edge runs bottom to top.
    private func along(_ p: Double, length: Double) -> Double { edge == .right ? length - p : p }

    // MARK: Falling and drifting

    private func drawSnow(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<count {
            let seed = Double(i) * 12.9898
            let speed = 6 + fract(sin(seed) * 43758.5453) * 10
            let x = fract(sin(seed * 1.7) * 9631.1) * size.width + sin(t + seed) * 4
            let y = fract(t * speed / max(size.height, 1) + fract(sin(seed * 3.1) * 1234.5)) * size.height
            let r = 1 + fract(sin(seed * 2.3) * 777.7) * 1.5
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.8)))
        }
    }

    private func drawRain(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let drops = scaled(14, 46)
        let slant = 0.22
        let color = rgb(0.72, 0.84, 1)
        for i in 0..<drops {
            let s = Double(i) + 0.5
            let speed = 130 + hash(s * 3) * 70
            let length = 7 + hash(s * 5) * 6
            let y = EffectMath.travel(seed: s * 7, t: t, speed: speed, span: size.height, margin: length)
            let x = hash(s * 11) * (size.width + size.height * slant) - y * slant
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x - length * slant, y: y + length))
            ctx.stroke(streak, with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(0.75)]),
                                                     startPoint: CGPoint(x: x, y: y),
                                                     endPoint: CGPoint(x: x - length * slant, y: y + length)),
                       lineWidth: 1.1)
        }
        // Splashes along the bottom sell the rain as landing on the dock.
        for i in 0..<scaled(3, 7) {
            let s = Double(i) + 0.3
            let period = 0.9 + hash(s) * 0.6
            let phase = fract(t / period + hash(s * 2))
            let cycle = floor(t / period + hash(s * 2))
            let x = hash(cycle * 7.3 + s) * size.width
            let w = 2 + phase * 8
            ctx.stroke(Path(ellipseIn: CGRect(x: x - w / 2, y: size.height - 4 - w * 0.15, width: w, height: w * 0.3)),
                       with: .color(color.opacity((1 - phase) * 0.6)), lineWidth: 0.8)
        }
    }

    private func drawLeaves(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let colors = [rgb(0.93, 0.52, 0.16), rgb(0.82, 0.27, 0.15), rgb(0.96, 0.76, 0.22), rgb(0.66, 0.38, 0.16)]
        for i in 0..<scaled(5, 15) {
            let s = Double(i) + 0.7
            let r = 3.5 + hash(s * 3) * 2.5
            let speed = 9 + hash(s * 5) * 10
            let y = EffectMath.travel(seed: s * 7, t: t, speed: speed, span: size.height, margin: r * 2)
            let x = hash(s * 11) * size.width + sin(t * 0.9 + s * 4) * 9
            var leaf = ctx
            leaf.translateBy(x: x, y: y)
            leaf.rotate(by: .radians(sin(t * 1.3 + s * 2) * 1.1 + s))
            var shape = Path()
            shape.move(to: CGPoint(x: 0, y: -r))
            shape.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: r * 0.95, y: 0))
            shape.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -r * 0.95, y: 0))
            let color = colors[i % colors.count]
            leaf.fill(shape, with: .color(color.opacity(0.92)))
            var vein = Path()
            vein.move(to: CGPoint(x: 0, y: -r * 0.8))
            vein.addLine(to: CGPoint(x: 0, y: r * 1.25))
            leaf.stroke(vein, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        }
    }

    private func drawPetals(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let colors = [rgb(1, 0.78, 0.86), rgb(1, 0.88, 0.92), rgb(0.97, 0.66, 0.79)]
        for i in 0..<scaled(6, 18) {
            let s = Double(i) + 0.2
            let r = 3.4 + hash(s * 3) * 2
            let y = EffectMath.travel(seed: s * 7, t: t, speed: 7 + hash(s * 5) * 7, span: size.height, margin: r * 2)
                + sin(t * 1.7 + s * 3) * 3
            // Petals ride a breeze along the dock so they read as blown rather than dropped.
            let x = EffectMath.travel(seed: s * 13, t: t, speed: 10 + hash(s * 17) * 10, span: size.width, margin: r * 2)
            var petal = ctx
            petal.translateBy(x: x, y: y)
            petal.rotate(by: .radians(t * (0.6 + hash(s) * 0.8) + s))
            let flip = cos(t * 2.2 + s * 5)
            petal.scaleBy(x: 1, y: max(abs(flip), 0.25))
            var shape = Path()
            shape.move(to: CGPoint(x: -r, y: 0))
            shape.addQuadCurve(to: CGPoint(x: r, y: -r * 0.25), control: CGPoint(x: 0, y: -r * 1.1))
            shape.addLine(to: CGPoint(x: r * 0.7, y: 0))
            shape.addLine(to: CGPoint(x: r, y: r * 0.25))
            shape.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: 0, y: r * 1.1))
            petal.fill(shape, with: .color(colors[i % colors.count].opacity(flip > 0 ? 0.95 : 0.75)))
        }
    }

    private func drawBubbles(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<scaled(5, 15) {
            let s = Double(i) + 0.9
            let r = 2 + hash(s * 3) * 3.5
            let rise = EffectMath.travel(seed: s * 7, t: t, speed: 9 + hash(s * 5) * 9, span: size.height, margin: r * 2)
            let y = size.height - rise
            let x = hash(s * 11) * size.width + sin(t * 1.6 + s * 4) * 3
            // Fade in from the bottom and out near the top, as if popping at the surface.
            let life = min(max(rise / max(size.height, 1), 0), 1)
            let alpha = min(life * 4, 1) * min((1 - life) * 3, 1)
            let color = palette[i % palette.count]
            let c = CGPoint(x: x, y: y)
            ctx.fill(dot(c, r), with: .color(color.opacity(0.14 * alpha)))
            ctx.stroke(dot(c, r), with: .color(color.opacity(0.75 * alpha)), lineWidth: 0.8)
            ctx.fill(dot(CGPoint(x: x - r * 0.35, y: y - r * 0.4), r * 0.28), with: .color(.white.opacity(0.85 * alpha)))
        }
    }

    private func drawFireflies(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let glow = rgb(0.85, 1, 0.45)
        for i in 0..<scaled(6, 18) {
            let s = Double(i) + 0.4
            let x = hash(s * 3) * size.width + sin(t * (0.25 + hash(s) * 0.3) + s * 3) * size.width * 0.06
                + sin(t * 0.9 + s) * 4
            let y = size.height * (0.15 + 0.7 * hash(s * 5)) + sin(t * (0.5 + hash(s * 7) * 0.5) + s * 2) * size.height * 0.15
            let pulse = pow(max(0, sin(t * (0.9 + hash(s * 9) * 0.9) + s * 5)), 2)
            let c = CGPoint(x: x, y: y)
            let halo = 5 + pulse * 3
            ctx.fill(dot(c, halo), with: .radialGradient(Gradient(colors: [glow.opacity(0.55 * pulse), glow.opacity(0)]),
                                                         center: c, startRadius: 0, endRadius: halo))
            ctx.fill(dot(c, 1.2), with: .color(rgb(1, 1, 0.75).opacity(0.25 + 0.75 * pulse)))
        }
    }

    private func drawHearts(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let colors = [rgb(1, 0.38, 0.55), rgb(1, 0.58, 0.72), rgb(0.94, 0.27, 0.4)]
        for i in 0..<scaled(3, 9) {
            let s = Double(i) + 0.6
            let r = 4.5 + hash(s * 3) * 2.5
            let rise = EffectMath.travel(seed: s * 7, t: t, speed: 8 + hash(s * 5) * 6, span: size.height, margin: r * 2)
            let life = min(max(rise / max(size.height, 1), 0), 1)
            let alpha = min(life * 4, 1) * min((1 - life) * 2.5, 1)
            var heart = ctx
            heart.translateBy(x: hash(s * 11) * size.width + sin(t * 1.4 + s * 4) * 5, y: size.height - rise)
            heart.rotate(by: .radians(sin(t * 1.4 + s * 4) * 0.25))
            heart.scaleBy(x: r, y: r)
            heart.fill(Self.heart, with: .color(colors[i % colors.count].opacity(0.9 * alpha)))
        }
    }

    /// A unit heart centred on the origin, about 2 wide.
    private static let heart: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0.95))
        p.addCurve(to: CGPoint(x: -1, y: -0.2), control1: CGPoint(x: -0.55, y: 0.55), control2: CGPoint(x: -1, y: 0.2))
        p.addArc(center: CGPoint(x: -0.5, y: -0.3), radius: 0.51, startAngle: .degrees(169), endAngle: .degrees(-15), clockwise: false)
        p.addArc(center: CGPoint(x: 0.5, y: -0.3), radius: 0.51, startAngle: .degrees(195), endAngle: .degrees(11), clockwise: false)
        p.addCurve(to: CGPoint(x: 0, y: 0.95), control1: CGPoint(x: 1, y: 0.2), control2: CGPoint(x: 0.55, y: 0.55))
        return p
    }()

    /// A four-pointed glint with concave sides, unit radius.
    private static let glint: Path = {
        var p = Path()
        let k = 0.18
        p.move(to: CGPoint(x: 0, y: -1))
        p.addQuadCurve(to: CGPoint(x: 1, y: 0), control: CGPoint(x: k, y: -k))
        p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: k, y: k))
        p.addQuadCurve(to: CGPoint(x: -1, y: 0), control: CGPoint(x: -k, y: k))
        p.addQuadCurve(to: CGPoint(x: 0, y: -1), control: CGPoint(x: -k, y: -k))
        return p
    }()

    private func drawGlint(_ ctx: GraphicsContext, at c: CGPoint, radius: Double, angle: Double, color: Color, alpha: Double) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(angle))
        g.fill(dot(.zero, radius * 0.9), with: .radialGradient(Gradient(colors: [color.opacity(0.4 * alpha), color.opacity(0)]),
                                                                center: .zero, startRadius: 0, endRadius: radius * 0.9))
        g.scaleBy(x: radius, y: radius)
        g.fill(Self.glint, with: .color(color.opacity(alpha)))
        g.fill(dot(.zero, 0.22), with: .color(.white.opacity(alpha)))
    }

    private func drawSparkles(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<scaled(6, 16) {
            let s = Double(i) + 0.8
            let period = 1.4 + hash(s) * 1.2
            let shifted = t / period + hash(s * 2)
            let phase = fract(shifted)
            let cycle = floor(shifted)
            // Each twinkle lands somewhere new so the sparkles never settle into a pattern.
            let c = CGPoint(x: hash(cycle * 3.7 + s * 19) * size.width,
                            y: size.height * (0.12 + 0.76 * hash(cycle * 5.3 + s * 23)))
            let grow = pow(sin(phase * .pi), 1.2)
            drawGlint(ctx, at: c, radius: (3.5 + hash(s * 3) * 3.5) * grow, angle: phase * 0.9,
                      color: palette[i % palette.count], alpha: grow)
        }
    }

    private func drawFireworks(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let bursts = 1 + Int(intensity * 3)
        for b in 0..<bursts {
            let period = 2.5 + Double(b) * 0.7
            let phase = fract(t / period + Double(b) * 0.37)
            let cycle = floor(t / period + Double(b) * 0.37)
            let cx = fract(sin(cycle * 91.3 + Double(b)) * 4375.85) * size.width
            let cy = size.height * (0.3 + 0.4 * fract(sin(cycle * 17.1) * 999.1))
            let hue = fract(sin(cycle * 3.3 + Double(b)) * 77.7)
            for s in 0..<14 {
                let a = Double(s) / 14 * .pi * 2
                let d = phase * min(size.height, 40)
                let p = CGPoint(x: cx + cos(a) * d, y: cy + sin(a) * d)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)),
                         with: .color(Color(hue: hue, saturation: 0.8, brightness: 1).opacity(1 - phase)))
            }
        }
    }

    // MARK: Banded, drawn along the dock

    private func drawRays(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height * 1.5)
        let rays = 8 + Int(intensity * 8)
        for i in 0..<rays {
            let angle = Double(i) / Double(rays) * .pi * 2 + t * 0.2
            var path = Path()
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(angle - 0.06) * size.width, y: center.y + sin(angle - 0.06) * size.width))
            path.addLine(to: CGPoint(x: center.x + cos(angle + 0.06) * size.width, y: center.y + sin(angle + 0.06) * size.width))
            path.closeSubpath()
            ctx.fill(path, with: .color(.white.opacity(0.06 + intensity * 0.08)))
        }
    }

    private func drawStars(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<scaled(12, 36) {
            let s = Double(i) + 0.1
            let c = CGPoint(x: hash(s * 3) * size.width, y: hash(s * 5) * size.height)
            let twinkle = 0.25 + 0.75 * pow(0.5 + 0.5 * sin(t * (0.8 + hash(s * 7) * 2.2) + s * 7), 3)
            if hash(s * 9) > 0.86 {
                drawGlint(ctx, at: c, radius: 2.6 + twinkle, angle: 0, color: rgb(1, 0.96, 0.82), alpha: twinkle)
            } else {
                ctx.fill(dot(c, 0.6 + hash(s * 11) * 0.7), with: .color(.white.opacity(0.9 * twinkle)))
            }
        }
        // An occasional shooting star, kept rare so it stays a small surprise.
        let period = 6.0
        let shifted = t / period
        let phase = fract(shifted) / 0.14
        guard phase < 1 else { return }
        let cycle = floor(shifted)
        let start = CGPoint(x: hash(cycle * 1.3) * size.width * 0.7, y: size.height * 0.1 + hash(cycle * 2.9) * size.height * 0.3)
        let travel = min(size.width * 0.3, 140)
        let head = CGPoint(x: start.x + travel * phase, y: start.y + travel * 0.18 * phase)
        let tail = CGPoint(x: head.x - 26, y: head.y - 26 * 0.18)
        var streak = Path()
        streak.move(to: tail)
        streak.addLine(to: head)
        let fade = sin(phase * .pi)
        ctx.stroke(streak, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.9 * fade)]),
                                                 startPoint: tail, endPoint: head), lineWidth: 1.2)
    }

    private func drawAurora(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let colors = [rgb(0.3, 1, 0.62), rgb(0.66, 0.45, 1), rgb(0.22, 0.86, 0.92)]
        var layer = ctx
        layer.addFilter(.blur(radius: 3))
        let step = 6.0
        let curtains = 2 + Int(intensity * 1.5)
        for j in 0..<curtains {
            let jj = Double(j)
            var top: [CGPoint] = []
            var bottom: [CGPoint] = []
            var u = -step
            while u <= size.width + step {
                let mid = size.height * (0.42 + 0.1 * jj) + sin(u * 0.012 + t * (0.25 + 0.1 * jj) + jj * 2) * size.height * 0.16
                let reach = size.height * (0.28 + 0.14 * sin(u * 0.021 - t * 0.45 + jj * 3))
                top.append(CGPoint(x: u, y: mid - reach))
                bottom.append(CGPoint(x: u, y: mid + size.height * 0.1))
                u += step
            }
            var path = Path()
            path.addLines(top)
            path.addLines(bottom.reversed())
            path.closeSubpath()
            let color = colors[j % colors.count]
            let alpha = 0.5 + 0.3 * intensity
            // Curtains glow brightest along their lower hem and fade upward, like the real thing.
            layer.fill(path, with: .linearGradient(Gradient(stops: [.init(color: color.opacity(0), location: 0),
                                                                    .init(color: color.opacity(alpha * 0.6), location: 0.55),
                                                                    .init(color: color.opacity(alpha), location: 0.85),
                                                                    .init(color: color.opacity(0), location: 1)]),
                                                   startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            var hem = Path()
            hem.addLines(bottom.map { CGPoint(x: $0.x, y: $0.y - size.height * 0.06) })
            layer.stroke(hem, with: .color(color.opacity(alpha * 0.7)), lineWidth: 1.5)
        }
    }

    private func drawWaves(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let colors = [rgb(0.36, 0.66, 1), rgb(0.24, 0.78, 0.95), rgb(0.18, 0.5, 0.92)]
        let step = 4.0
        for j in 0..<3 {
            let jj = Double(j)
            let base = size.height * (0.56 + 0.13 * jj)
            let amp = size.height * (0.07 - 0.015 * jj) * (0.6 + intensity * 0.8)
            let k = 2 * .pi / (90 - 18 * jj)
            let speed = (j % 2 == 0 ? 1.0 : -1.0) * (0.9 + 0.35 * jj)
            var crest: [CGPoint] = []
            var u = 0.0
            while u <= size.width + step {
                let y = base + sin(u * k + t * speed + jj) * amp + sin(u * k * 2.3 - t * speed * 0.7) * amp * 0.3
                crest.append(CGPoint(x: u, y: y))
                u += step
            }
            var water = Path()
            water.addLines(crest)
            water.addLine(to: CGPoint(x: size.width + step, y: size.height))
            water.addLine(to: CGPoint(x: 0, y: size.height))
            water.closeSubpath()
            let color = colors[j]
            ctx.fill(water, with: .linearGradient(Gradient(colors: [color.opacity(0.42), color.opacity(0.22)]),
                                                  startPoint: CGPoint(x: 0, y: base - amp), endPoint: CGPoint(x: 0, y: size.height)))
            var foam = Path()
            foam.addLines(crest)
            ctx.stroke(foam, with: .color(.white.opacity(0.35 - 0.08 * jj)), lineWidth: 1)
        }
    }

    private func drawSky(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let day = EffectMath.daylight(hour: hour)
        let warm = max(0, 1 - abs(day - 0.5) * 2.4)
        func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ f: Double) -> (Double, Double, Double) {
            (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
        }
        let top = mix((0.04, 0.06, 0.22), (0.3, 0.6, 0.98), day)
        let low = mix(mix((0.16, 0.13, 0.38), (0.66, 0.85, 1), day), (1, 0.58, 0.38), warm)
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [rgb(top.0, top.1, top.2).opacity(0.62),
                                                                     rgb(low.0, low.1, low.2).opacity(0.62)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        // Night stars fade with the light.
        if day < 1 {
            for i in 0..<18 {
                let s = Double(i) + 0.5
                let c = CGPoint(x: hash(s * 3) * size.width, y: hash(s * 5) * size.height * 0.75)
                let tw = 0.5 + 0.5 * sin(t * (1 + hash(s * 7)) + s * 9)
                ctx.fill(dot(c, 0.7), with: .color(.white.opacity((1 - day) * (0.35 + 0.55 * tw))))
            }
        }
        // The sun crosses the dock from 6 to 18 and the moon from 18 to 6, arcing up to the middle.
        let sunUp = hour >= 6 && hour < 18
        let progress = fract(((sunUp ? hour - 6 : hour - 18) + 24) / 12)
        let body = CGPoint(x: size.width * (0.06 + 0.88 * progress),
                           y: size.height * (0.85 - 0.6 * sin(progress * .pi)))
        let r = min(size.height * 0.13, 9)
        if sunUp {
            let sun = rgb(1, 0.86 + 0.1 * day, 0.45 + 0.35 * day)
            ctx.fill(dot(body, r * 2.6), with: .radialGradient(Gradient(colors: [sun.opacity(0.55), sun.opacity(0)]),
                                                               center: body, startRadius: r * 0.8, endRadius: r * 2.6))
            ctx.fill(dot(body, r), with: .color(sun))
        } else {
            let moon = dot(body, r * 0.85).subtracting(dot(CGPoint(x: body.x + r * 0.45, y: body.y - r * 0.2), r * 0.8))
            ctx.fill(dot(body, r * 2), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)]),
                                                             center: body, startRadius: 0, endRadius: r * 2))
            ctx.fill(moon, with: .color(rgb(1, 0.97, 0.86)))
        }
        // Clouds drift by in daylight.
        guard day > 0 else { return }
        for i in 0..<3 {
            let s = Double(i) + 0.25
            let w = size.height * (0.5 + 0.3 * hash(s * 3))
            let x = EffectMath.travel(seed: s * 7, t: t, speed: 3 + hash(s * 5) * 3, span: size.width, margin: w)
            let y = size.height * (0.2 + 0.35 * hash(s * 9))
            var cloud = Path()
            cloud.addEllipse(in: CGRect(x: -w / 2, y: 0, width: w, height: w * 0.32))
            cloud.addEllipse(in: CGRect(x: -w * 0.3, y: -w * 0.16, width: w * 0.42, height: w * 0.36))
            cloud.addEllipse(in: CGRect(x: -w * 0.05, y: -w * 0.1, width: w * 0.36, height: w * 0.3))
            // Undo the band turn so clouds stay upright on a vertical dock.
            var puff = ctx
            puff.translateBy(x: x + w / 2, y: y)
            puff.rotate(by: -bandAngle)
            puff.fill(cloud, with: .color(.white.opacity(0.7 * day)))
        }
    }

    // MARK: Pointer

    private func drawRipples(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let accent = palette.first ?? .white
        // Quiet rings like rain on a pond, so the effect still shows when the pointer is elsewhere.
        for i in 0..<scaled(2, 4) {
            let s = Double(i) + 0.35
            let period = 2.4 + hash(s) * 1.4
            let shifted = t / period + hash(s * 2)
            let phase = fract(shifted)
            let cycle = floor(shifted)
            let c = CGPoint(x: hash(cycle * 3.1 + s * 13) * size.width, y: size.height * (0.3 + 0.4 * hash(cycle * 4.7 + s)))
            ring(ctx, at: c, radius: 2 + phase * size.height * 0.45, color: palette[(i + 1) % palette.count],
                 alpha: pow(1 - phase, 1.5) * 0.55)
        }
        var marks = ripples.live(at: t).map { (pos: $0.mark.position, age: $0.age) }
        if demo {
            for k in 0..<2 {
                let phase = fract(t / 1.4 + Double(k) * 0.5)
                let at = floor(t / 1.4 + Double(k) * 0.5)
                marks.append((size.width * (0.2 + 0.6 * hash(at * 1.7 + Double(k))), phase))
            }
        } else if let pointer {
            marks.append((Double(pointer), fract(t / 1.1)))
        }
        for m in marks {
            let c = CGPoint(x: demo ? m.pos : along(m.pos, length: size.width), y: size.height / 2)
            for lag in [0.0, 0.22] where m.age > lag {
                let a = (m.age - lag) / (1 - lag)
                ring(ctx, at: c, radius: 3 + a * size.height * 0.9, color: accent, alpha: pow(1 - a, 1.4) * 0.85)
            }
        }
    }

    private func ring(_ ctx: GraphicsContext, at c: CGPoint, radius: Double, color: Color, alpha: Double) {
        ctx.stroke(dot(c, radius), with: .color(color.opacity(alpha)), lineWidth: 1.4)
        ctx.stroke(dot(c, radius + 1.2), with: .color(.white.opacity(alpha * 0.4)), lineWidth: 0.8)
    }

    private func drawTrail(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        var marks: [(pos: Double, age: Double, seed: Double)]
        var head: Double?
        if demo {
            // A pointer sweeping back and forth along the dock.
            let path = { (time: Double) in size.width * (0.5 + 0.42 * sin(time * 1.1)) }
            marks = (0..<28).map { k in
                let back = Double(k) * 0.03
                return (path(t - back), back / 0.9, floor((t - back) * 33))
            }
            head = path(t)
        } else {
            marks = trail.live(at: t).map { ($0.mark.position, $0.age, $0.mark.time * 37) }
            head = pointer.map { Double($0) }
        }
        if let head {
            let c = CGPoint(x: demo ? head : along(head, length: size.width), y: size.height / 2)
            let accent = palette.first ?? .white
            ctx.fill(dot(c, size.height * 0.4), with: .radialGradient(Gradient(colors: [accent.opacity(0.3), accent.opacity(0)]),
                                                                       center: c, startRadius: 0, endRadius: size.height * 0.4))
        }
        let per = 1 + Int(intensity * 2.5)
        for (n, m) in marks.enumerated() {
            for k in 0..<per {
                let s = m.seed + Double(k) * 7.1
                let x = (demo ? m.pos : along(m.pos, length: size.width)) + (hash(s) - 0.5) * 10 * m.age
                // Sparks drift away from the pointer and settle slightly, like embers off a wand.
                let y = size.height / 2 + (hash(s * 3) - 0.5) * size.height * 0.75 * m.age + m.age * m.age * 6
                drawGlint(ctx, at: CGPoint(x: x, y: y), radius: (1 - m.age) * (2 + hash(s * 5) * 2.5),
                          angle: m.age * 2, color: palette[(n + k) % palette.count], alpha: 1 - m.age)
            }
        }
    }
}
