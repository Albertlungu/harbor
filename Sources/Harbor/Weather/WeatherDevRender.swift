import AppKit
import HarborCore
import SwiftUI

/// Renders weather scenes straight to image files through the real Metal shader, so falling piles, impacts,
/// pointer play and pet play can be looked at without putting anything on screen. Launch with
/// HARBOR_RENDER_WEATHER=<folder>.
@MainActor
enum WeatherDevRender {
    private static let size = CGSize(width: 900, height: 560)
    private static let screen = CGRect(x: 0, y: 0, width: 900, height: 560)
    private static let upper = CGRect(x: 250, y: 220, width: 400, height: 200)
    private static let lower = CGRect(x: 360, y: 60, width: 360, height: 110)

    private static func surfaces(_ windows: [CGRect]) -> [RoamSurface] {
        let built = RoamSurfaces.build(screen: screen, menuBarHeight: 0, windows: windows.map { RoamWindow(frame: $0) },
                                       docks: [], walkOnWindows: true)
        return WeatherWorld.roundingCorners(built, windows: windows)
    }

    private static func world(_ season: Season, _ windows: [CGRect], evening: Bool = false) -> WeatherWorld {
        var w = WeatherWorld(width: size.width, height: size.height, season: season, intensity: 0, evening: evening, seed: 11)
        w.setSurfaces(surfaces(windows))
        return w
    }

    private static func run(_ w: inout WeatherWorld, _ seconds: Double) {
        for _ in 0..<max(1, Int(seconds * 60)) { _ = w.step(dt: 1.0 / 60) }
    }

    static func render(into out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func save(_ name: String, _ w: WeatherWorld, windows: [CGRect], pet: (x: Double, y: Double, spin: Double)? = nil) {
            write(w, windows: windows, pet: pet, to: out.appendingPathComponent("\(name).png"))
        }

        // A window closes under a drift; the pile falls onto the window below and the floor.
        var fall = world(.winter, [upper, lower])
        fall.fill(depth: 9)
        run(&fall, 3)
        save("fall-0-before", fall, windows: [upper, lower])
        fall.setSurfaces(surfaces([lower]))
        var elapsed = 0.0
        for t in [0.05, 0.15, 0.3, 0.45, 0.7, 1.2, 4] {
            run(&fall, t - elapsed)
            elapsed = t
            save("fall-\(Int(t * 100))", fall, windows: [lower])
        }

        // A hard throw into a drift.
        var hit = world(.winter, [upper])
        hit.fill(depth: 6)
        run(&hit, 3)
        save("impact-0-before", hit, windows: [upper])
        hit.throwSnowball(x: 300, y: 520, r: 11, vx: 520, vy: -420)
        elapsed = 0
        for t in [0.15, 0.25, 0.5, 1.5, 4] {
            run(&hit, t - elapsed)
            elapsed = t
            save("impact-\(Int(t * 100))", hit, windows: [upper])
        }

        // Pointer play in each season.
        var angel = world(.winter, [upper])
        angel.fill(depth: 8)
        run(&angel, 2)
        angel.pointerDown(x: 450, y: 424)
        run(&angel, 1)
        angel.pointerUp(vx: 0, vy: 0)
        angel.pointerDown(x: 330, y: 424)
        angel.pointerUp(vx: 0, vy: 0)
        run(&angel, 0.15)
        save("winter-angel-and-kick", angel, windows: [upper])

        var leaves = world(.autumn, [upper])
        leaves.fill(depth: 9)
        run(&leaves, 2)
        leaves.pointerDown(x: 400, y: 426)
        leaves.pointerDragged(x: 405, y: 460)
        leaves.pointerDragged(x: 420, y: 500)
        run(&leaves, 0.1)
        save("autumn-handful", leaves, windows: [upper])
        leaves.pointerUp(vx: 500, vy: 350)
        run(&leaves, 0.6)
        save("autumn-tossed", leaves, windows: [upper])
        leaves.pointerDown(x: 560, y: 426)
        leaves.pointerUp(vx: 0, vy: 0)
        run(&leaves, 0.2)
        save("autumn-kicked", leaves, windows: [upper])

        var spring = world(.spring, [upper])
        spring.fill(depth: 5)
        run(&spring, 1)
        if let li = spring.ledges.firstIndex(where: { $0.y == upper.maxY }), let flower = spring.ledges[li].flowers.first {
            let x = spring.ledges[li].centerX(flower.column)
            spring.pointerDown(x: x, y: upper.maxY + 8)
            spring.pointerDragged(x: x + 60, y: upper.maxY + 80)
            run(&spring, 0.1)
            save("spring-picked-flower", spring, windows: [upper])
            spring.pointerUp(vx: 0, vy: 0)
            run(&spring, 2)
            save("spring-replanted", spring, windows: [upper])
        }
        spring.pointerDown(x: 280, y: upper.maxY + 1)
        spring.pointerUp(vx: 0, vy: 0)
        run(&spring, 0.12)
        save("spring-splash", spring, windows: [upper])

        var summer = world(.summer, [upper])
        summer.fill(depth: 0)
        if let bubble = summer.particles.first(where: { $0.kind == .bubble }) {
            summer.pointerDown(x: bubble.x, y: bubble.y)
            for k in 1...24 { summer.pointerDragged(x: bubble.x + Double(k % 2) * 30, y: bubble.y) }
            run(&summer, 0.1)
            save("summer-big-bubble", summer, windows: [upper])
        }
        var night = world(.summer, [upper], evening: true)
        run(&night, 30)
        if let fly = night.particles.first(where: { $0.kind == .firefly }) {
            night.pointerDown(x: fly.x, y: fly.y)
            run(&night, 0.5)
            save("summer-jar", night, windows: [upper])
        }

        petPlay(.autumn, depth: 10, into: out)
        petPlay(.winter, depth: 9, into: out)
        poses(into: out)
    }

    /// A pet on the window top left to the play brain, moved the way the roaming pet would be: walking where
    /// it is sent and hopping when nudged. Frames are saved around each pose it is given.
    private static func petPlay(_ season: Season, depth: Double, into out: URL) {
        var w = world(season, [upper])
        w.fill(depth: depth)
        run(&w, 2)
        var x = 420.0, y = Double(upper.maxY), vx = 0.0, vy = 0.0, target: Double?
        var spin = 0.0, rollUntil = 0.0, time = 0.0
        var shots: [Double] = []
        let dt = 1.0 / 60
        for _ in 0..<(60 * 14) {
            time += dt
            let pet = WeatherPet(id: "pup", x: x, y: y, vx: vx, vy: vy, unit: 32)
            for event in w.step(dt: dt, pets: [pet]) {
                switch event {
                case .walk(_, let to): target = to
                case .nudge(_, let dx, let dy): vx = dx; vy = dy; target = nil
                case .pose(_, let pose, let seconds, _):
                    if pose == .roll { rollUntil = time + seconds }
                    shots += [time + 0.05, time + seconds * 0.6]
                default: break
                }
            }
            if vy != 0 || y > upper.maxY + 0.01 {
                vy -= 1500 * dt
                x += vx * dt
                y += vy * dt
                if y <= upper.maxY { y = upper.maxY; vy = 0; vx = 0 }
            } else if let to = target {
                let step = min(abs(to - x), 60 * dt)
                vx = to > x ? 60 : -60
                x += to > x ? step : -step
                if abs(to - x) < 0.5 { target = nil; vx = 0 }
            } else {
                vx = 0
            }
            if time < rollUntil { spin += 360 * 1.4 * dt * (vx >= 0 ? 1 : -1) }
            if let next = shots.first, time >= next {
                shots.removeFirst()
                write(w, windows: [upper], pet: (x, y, time < rollUntil ? spin : 0),
                      to: out.appendingPathComponent("pet-\(season.rawValue)-\(String(format: "%05.2f", time)).png"))
            }
        }
        write(w, windows: [upper], pet: (x, y, 0.0), to: out.appendingPathComponent("pet-\(season.rawValue)-end.png"))
    }

    /// Each play pose over the real pet figure, early and midway through.
    private static func poses(into out: URL) {
        let unit: CGFloat = 64
        let driver = RoamDriver(unit: unit)
        var cells: [AnyView] = []
        for pose in [WeatherPetPose.roll, .carry, .toss, .pounce, .shake, .sniff] {
            for t in [0.12, 0.35] {
                driver.play = pose
                driver.playStart = Date.now.addingTimeInterval(-t)
                driver.playUntil = driver.playStart.addingTimeInterval(0.8)
                driver.playBall = 10
                let view = PetFigure(unit: unit, pose: PetPose(), padBottom: false)
                    .frame(width: driver.side, height: driver.side)
                    .modifier(RoamPlayEffect(driver: driver))
                    .overlay(alignment: .bottom) { Text("\(pose.rawValue) \(t)").font(.caption2) }
                let renderer = ImageRenderer(content: view.background(Color(white: 0.92)))
                renderer.scale = 2
                if let image = renderer.cgImage { cells.append(AnyView(Image(decorative: image, scale: 2))) }
            }
        }
        let sheet = LazyVGrid(columns: Array(repeating: GridItem(.fixed(driver.side), spacing: 8), count: 4), spacing: 8) {
            ForEach(cells.indices, id: \.self) { cells[$0] }
        }
        .padding(12)
        .background(Color.white)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        if let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? data.write(to: out.appendingPathComponent("poses.png"))
        }
    }

    /// A desktop-ish backdrop, the windows, the weather from the real shader and a marker where the pet is.
    private static func write(_ w: WeatherWorld, windows: [CGRect], pet: (x: Double, y: Double, spin: Double)?, to url: URL) {
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        let colors = [CGColor(red: 0.35, green: 0.45, blue: 0.62, alpha: 1), CGColor(red: 0.62, green: 0.68, blue: 0.78, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        for window in windows {
            ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
            ctx.addPath(CGPath(roundedRect: window, cornerWidth: 20, cornerHeight: 20, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(CGColor(gray: 0.24, alpha: 1))
            ctx.fill(CGRect(x: window.minX + 14, y: window.maxY - 26, width: window.width - 28, height: 18))
        }
        if let pet {
            ctx.saveGState()
            ctx.translateBy(x: pet.x, y: pet.y + 14)
            ctx.rotate(by: -pet.spin * .pi / 180)
            ctx.setFillColor(CGColor(red: 0.55, green: 0.38, blue: 0.25, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -14, y: -14, width: 28, height: 28))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 4, y: 2, width: 6, height: 6))
            ctx.restoreGState()
        }
        var sprites: [WeatherSprite] = []
        w.pileSprites(into: &sprites)
        w.liveSprites(into: &sprites)
        if let weather = WeatherRenderer.image(sprites, points: size, scale: scale) {
            ctx.draw(weather, in: CGRect(origin: .zero, size: size))
        }
        if let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
