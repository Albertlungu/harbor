// Generates Support/AppIcon.icns, Support/MenuBarIcon*.png and the design previews.
// Run from anywhere: swift Scripts/make-icon.swift
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r / 255, g / 255, b / 255, a])!
}

func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
}

func makeContext(_ px: Int) -> CGContext {
    CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ ctx: CGContext, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// Superellipse approximating Apple's continuous-corner squircle.
func squircle(_ rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func capsule(_ r: CGRect, radius: CGFloat? = nil) -> CGPath {
    let rad = radius ?? r.height / 2
    return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

/// Draws the icon in a 1024-unit space scaled to `px` pixels.
func drawIcon(px: Int) -> CGContext {
    let ctx = makeContext(px)
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = squircle(tileRect)

    // Tile drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 10, 20, 0.35))
    ctx.addPath(tile); ctx.setFillColor(rgb(10, 40, 60)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()

    // Teal to ink-blue background
    ctx.drawLinearGradient(gradient([rgb(28, 138, 148), rgb(18, 84, 120), rgb(12, 36, 78)], [0, 0.5, 1]),
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    // Soft glow behind the docks
    ctx.drawRadialGradient(gradient([rgb(120, 220, 220, 0.22), rgb(120, 220, 220, 0)]),
                           startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])

    // Water-line curves beneath the bottom bar
    ctx.setLineCap(.round)
    for (i, (w, alpha, y)) in [(560.0, 0.36, 250.0), (360.0, 0.2, 204.0)].enumerated() {
        let amp: CGFloat = i == 0 ? 14 : 10
        let path = CGMutablePath()
        let x0 = 512 - w / 2
        path.move(to: CGPoint(x: x0, y: y))
        path.addCurve(to: CGPoint(x: 512, y: y), control1: CGPoint(x: x0 + w * 0.22, y: y + amp * 1.6),
                      control2: CGPoint(x: x0 + w * 0.32, y: y - amp * 1.6))
        path.addCurve(to: CGPoint(x: 512 + w / 2, y: y), control1: CGPoint(x: 512 + w * 0.18, y: y + amp * 1.6),
                      control2: CGPoint(x: 512 + w * 0.28, y: y - amp * 1.6))
        ctx.addPath(path)
        ctx.setStrokeColor(rgb(255, 255, 255, alpha)); ctx.setLineWidth(i == 0 ? 15 : 11)
        ctx.strokePath()
    }

    // Docks: bottom is widest and most opaque
    let h: CGFloat = 124
    let docks: [(w: CGFloat, y: CGFloat, a: CGFloat)] = [(680, 300, 0.85), (540, 450, 0.55), (400, 600, 0.35)]
    for d in docks {
        let r = CGRect(x: 512 - d.w / 2, y: d.y, width: d.w, height: h)
        let path = capsule(r)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0, 20, 40, 0.28))
        ctx.addPath(path); ctx.setFillColor(rgb(255, 255, 255, d.a)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(255, 255, 255, 0.30 * d.a + 0.08), rgb(210, 240, 245, 0.0)]),
                               start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
        // inner highlight
        ctx.addPath(capsule(r.insetBy(dx: 5, dy: 5)))
        ctx.setStrokeColor(rgb(255, 255, 255, min(0.9, d.a + 0.25)))
        ctx.setLineWidth(3); ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(capsule(r.insetBy(dx: 1, dy: 1)))
        ctx.setStrokeColor(rgb(255, 255, 255, 0.5)); ctx.setLineWidth(2); ctx.strokePath()
    }

    // App-icon pills on the top bar
    let colors: [(CGColor, CGColor)] = [
        (rgb(255, 128, 112), rgb(238, 84, 84)),   // coral
        (rgb(255, 208, 92), rgb(246, 160, 40)),   // amber
        (rgb(122, 230, 176), rgb(52, 190, 140)),  // mint
    ]
    let ps: CGFloat = 82, gap: CGFloat = 28
    let total = 3 * ps + 2 * gap
    let top = docks[2]
    for (i, c) in colors.enumerated() {
        let r = CGRect(x: 512 - total / 2 + CGFloat(i) * (ps + gap), y: top.y + (h - ps) / 2, width: ps, height: ps)
        let p = capsule(r, radius: 26)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: rgb(0, 20, 40, 0.3))
        ctx.addPath(p); ctx.setFillColor(c.1); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(p); ctx.clip()
        ctx.drawLinearGradient(gradient([c.0, c.1]), start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
        ctx.restoreGState()
        ctx.addPath(capsule(r.insetBy(dx: 1.5, dy: 1.5), radius: 24.5))
        ctx.setStrokeColor(rgb(255, 255, 255, 0.45)); ctx.setLineWidth(3); ctx.strokePath()
    }

    // Sheen across the top third
    ctx.drawLinearGradient(gradient([rgb(255, 255, 255, 0.34), rgb(255, 255, 255, 0)]),
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 640), options: [])

    // Inner rim light
    ctx.addPath(tile)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.18)); ctx.setLineWidth(3); ctx.strokePath()
    ctx.restoreGState()
    return ctx
}

/// Menu bar glyph: three stacked bars, black on transparent, in an 18-unit space.
func drawGlyph(px: Int) -> CGContext {
    let ctx = makeContext(px)
    ctx.scaleBy(x: CGFloat(px) / 18, y: CGFloat(px) / 18)
    ctx.setFillColor(rgb(0, 0, 0))
    for (w, y) in [(16.0, 2.0), (12.0, 8.0), (8.0, 14.0)] {
        ctx.addPath(capsule(CGRect(x: 9 - w / 2, y: y, width: w, height: 3)))
        ctx.fillPath()
    }
    return ctx
}

let fm = FileManager.default
let support = root.appendingPathComponent("Support")
let design = root.appendingPathComponent("replica/design")
try! fm.createDirectory(at: support, withIntermediateDirectories: true)
try! fm.createDirectory(at: design, withIntermediateDirectories: true)

let iconset = fm.temporaryDirectory.appendingPathComponent("Harbor-\(UUID().uuidString).iconset")
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
        writePNG(drawIcon(px: base * scale), to: iconset.appendingPathComponent(name))
    }
}

let icns = support.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }

writePNG(drawGlyph(px: 18), to: support.appendingPathComponent("MenuBarIcon.png"))
writePNG(drawGlyph(px: 36), to: support.appendingPathComponent("MenuBarIcon@2x.png"))
writePNG(drawIcon(px: 1024), to: design.appendingPathComponent("app-icon-preview.png"))
writePNG(drawIcon(px: 64), to: design.appendingPathComponent("app-icon-preview-64.png"))
print("Wrote icon assets")
