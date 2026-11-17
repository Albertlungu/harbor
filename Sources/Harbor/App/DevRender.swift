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
            let suffix = appearance == .aqua ? "light" : "dark"
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
            write(sheet, appearance: appearance, to: out.appendingPathComponent("pet-\(suffix).png"))
            write(speciesSheet, appearance: appearance, to: out.appendingPathComponent("species-\(suffix).png"))
            write(optionsSheet, appearance: appearance, to: out.appendingPathComponent("options-\(suffix).png"))
            write(settingsSheet(scratch: out.appendingPathComponent("config")), appearance: appearance,
                  to: out.appendingPathComponent("settings-\(suffix).png"))
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

    private static func write(_ sheet: some View, appearance: NSAppearance.Name, to url: URL) {
        let framed = sheet.padding(20).background(Tokens.dockSolid)
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: framed.environment(\.colorScheme, appearance == .aqua ? .light : .dark))
            renderer.scale = 2
            if let image = renderer.cgImage,
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }

    private struct Cell: Identifiable {
        let id: String
        var expression: PetExpression = .calm
        var body = PetBodyState()
        var turn = 0.0
    }

    private static let cells: [Cell] = [
        Cell(id: "calm"),
        Cell(id: "happy", expression: .happy),
        Cell(id: "excited", expression: .excited),
        Cell(id: "shy", expression: .shy),
        Cell(id: "nap", expression: .asleep, body: PetBodyState(napping: true)),
        Cell(id: "walk 0", body: PetBodyState(moving: true, phase: 0), turn: PetLocomotion.walkTurn),
        Cell(id: "walk 1", body: PetBodyState(moving: true, phase: .pi / 2), turn: PetLocomotion.walkTurn),
        Cell(id: "walk 2", body: PetBodyState(moving: true, phase: .pi), turn: PetLocomotion.walkTurn),
        Cell(id: "walk 3", body: PetBodyState(moving: true, phase: 1.5 * .pi), turn: PetLocomotion.walkTurn),
        Cell(id: "left", body: PetBodyState(moving: true, facing: -1, phase: .pi / 2), turn: -PetLocomotion.walkTurn),
        Cell(id: "fall", expression: .surprised, body: PetBodyState(falling: true)),
        Cell(id: "carry", expression: .shy, body: PetBodyState(carried: true, time: 0.5)),
        Cell(id: "sit", expression: .happy, body: PetBodyState(sitting: true)),
    ]

    private static func figure(_ look: PetLook, _ cell: Cell, unit: CGFloat) -> some View {
        var pose = PetPose(face: cell.expression.face)
        pose.turn = cell.turn
        PetLocomotion.apply(&pose, cell.body, species: look.species, unit: unit)
        return PetFigure(unit: unit, pose: pose, padBottom: false, look: look).frame(width: unit, height: unit)
    }

    private static var speciesSheet: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                Text("")
                ForEach(cells) { Text($0.id).font(.caption2).foregroundStyle(Tokens.textMuted) }
                Text("24 / 32 / 48").font(.caption2).foregroundStyle(Tokens.textMuted)
            }
            ForEach(PetSpecies.allCases, id: \.self) { species in
                let look = PetLook(PetAppearance(species: species))
                GridRow {
                    Text(species.title).font(.caption).foregroundStyle(Tokens.text)
                    ForEach(cells) { figure(look, $0, unit: 72) }
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach([24.0, 32, 48], id: \.self) { figure(look, cells[0], unit: $0) }
                    }
                }
            }
        }
    }

    /// The appearance settings against a throwaway config, never the user's.
    private static func settingsSheet(scratch: URL) -> some View {
        let model = AppModel(file: ConfigFile(directory: scratch))
        let dock = model.store.createDock(name: "Render")
        let item = DockItem(kind: .widget, widget: WidgetConfig(kind: .pet, settings: [
            "species": .string("fox"), "accessory": .string("scarf"), "pattern": .string("belly")]))
        model.store.addItems([item], to: dock.id)
        // A Form scrolls through AppKit, which ImageRenderer cannot capture, so the rows are stacked plainly.
        return VStack(alignment: .leading, spacing: 10) {
            PetAppearanceSettings(fields: WidgetFields(model: model, itemID: item.id, dockID: dock.id))
        }
        .frame(width: 460)
        .environment(model)
    }

    private static var optionsSheet: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 12) {
            ForEach([PetSpecies.seal, .cat, .dog, .bunny, .penguin, .frog], id: \.self) { species in
                GridRow {
                    ForEach(PetPattern.allCases, id: \.self) { pattern in
                        figure(PetLook(PetAppearance(species: species, pattern: pattern)), cells[0], unit: 56)
                    }
                    ForEach(PetEyeStyle.allCases, id: \.self) { eyes in
                        figure(PetLook(PetAppearance(species: species, eyes: eyes)), cells[0], unit: 56)
                    }
                    ForEach(PetAccessory.allCases.dropFirst(), id: \.self) { accessory in
                        figure(PetLook(PetAppearance(species: species, accessory: accessory)), cells[0], unit: 56)
                    }
                    ForEach(species.swatches.dropFirst(), id: \.id) { swatch in
                        figure(PetLook(PetAppearance(species: species, color: .swatch(swatch.id))), cells[0], unit: 56)
                    }
                }
            }
        }
    }
}
