import AppKit
import HarborCore
import SwiftUI

/// Renders views straight to image files and quits, so artwork can be reviewed without
/// putting anything on screen. Launch with HARBOR_RENDER_PET=<folder> or HARBOR_RENDER_EFFECTS=<folder>.
@MainActor
enum DevRender {
    static func runIfRequested() -> Bool {
        if let folder = ProcessInfo.processInfo.environment["HARBOR_RENDER_EFFECTS"] {
            renderEffects(into: URL(fileURLWithPath: folder, isDirectory: true))
            return true
        }
        guard let folder = ProcessInfo.processInfo.environment["HARBOR_RENDER_PET"] else { return false }
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let sheet = HStack(spacing: 18) {
                ForEach(PetExpression.allCases, id: \.self) { expression in
                    VStack(spacing: 6) {
                        ForEach([32.0, 48, 96], id: \.self) { unit in
                            PetFigure(unit: unit, pose: PetPose(face: expression.face), padBottom: false)
                                .frame(width: unit, height: unit)
                        }
                        Text(expression.rawValue).font(.caption2).foregroundStyle(Tokens.textMuted)
                    }
                }
            }
            .padding(20)
            .background(Tokens.dockSolid)
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                let renderer = ImageRenderer(content: sheet.environment(\.colorScheme, appearance == .aqua ? .light : .dark))
                renderer.scale = 2
                if let image = renderer.cgImage,
                   let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try? data.write(to: out.appendingPathComponent("pet-\(appearance == .aqua ? "light" : "dark").png"))
                }
            }
        }
        return true
    }

    /// One sheet per effect: dock-sized strips at a few moments, horizontal and vertical, light and dark.
    private static func renderEffects(into out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let palette = EffectPainter.paletteColors()
        let times = [100.0, 101.35, 102.8]
        let hours = [3.0, 7.0, 12.0, 19.0]
        for dark in [false, true] {
            let picker = LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), spacing: 6), count: 5), spacing: 6) {
                ForEach(EffectKind.allCases, id: \.self) { effect in
                    EffectTile(effect: effect, on: [.snow, .aurora, .ripples].contains(effect), intensity: 0.6) {}
                }
            }
            .padding(20)
            .background(dark ? Color(white: 0.12) : Color(white: 0.96))
            .environment(\.colorScheme, dark ? .dark : .light)
            write(picker, dark: dark, to: out.appendingPathComponent("picker-\(dark ? "dark" : "light").png"))
        }
        for effect in EffectKind.allCases where effect != .seasonal {
            for dark in [false, true] {
                let strip = { (edge: ScreenEdge, t: Double, hour: Double) in
                    let painter = EffectPainter(effects: [effect], intensity: 0.6, edge: edge, palette: palette, hour: hour,
                                                pointer: nil, trail: PointerTrail(spacing: 3, lifetime: 0.9),
                                                ripples: PointerTrail(spacing: 36, lifetime: 1.4), demo: true, still: false)
                    let vertical = edge == .left || edge == .right
                    return Canvas { ctx, size in painter.draw(ctx, size: size, t: t) }
                        .frame(width: vertical ? 64 : 520, height: vertical ? 300 : 64)
                        .background(Tokens.dockSolid)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                let moments: [(Double, Double)] = effect == .sky ? hours.map { (100, $0) } : times.map { ($0, 12) }
                let sheet = HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(effect.title).font(.headline).foregroundStyle(Tokens.text)
                        ForEach(moments.indices, id: \.self) { i in strip(.bottom, moments[i].0, moments[i].1) }
                    }
                    ForEach(moments.indices, id: \.self) { i in strip(i % 2 == 0 ? .left : .right, moments[i].0, moments[i].1) }
                }
                .padding(20)
                .background(dark ? Color(white: 0.12) : Color(white: 0.96))
                .environment(\.colorScheme, dark ? .dark : .light)
                write(sheet, dark: dark, to: out.appendingPathComponent("\(effect.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    private static func write(_ view: some View, dark: Bool, to url: URL) {
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.cgImage,
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }
}
