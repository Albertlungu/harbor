import HarborCore
import SwiftUI

/// Everything the drawing needs for one frame, so the figure stays a pure function of its inputs.
struct PetPose {
    var face: PetFace = PetExpression.calm.face
    var offset: CGSize = .zero
    var rotation: Double = 0
    var scale: CGSize = CGSize(width: 1, height: 1)
    var headTilt: Double = 0
    var flipperLeft: Double = 0
    var flipperRight: Double = 0
    var rightFlipperOffset: CGSize = .zero
    /// Displacement of the flippers relative to the body, so they trail it a beat behind.
    var lag: CGSize = .zero
    var tail: Double = 0
    var gaze: CGSize = .zero
    var lid: Double = 0
    var mouthOpen: Double = 0
    var twinkle: Double = 0
    /// How far the head is turned toward the direction of travel, -1 left to 1 right; 0 faces the viewer.
    var turn: Double = 0
    /// Feet displacement in points, for stepping, dangling and splaying.
    var footLeft: CGSize = .zero
    var footRight: CGSize = .zero
    /// Feet folded away under the body, as when curled up asleep.
    var tucked = false
}

/// Proportions follow the baby schema: a head about two thirds of the height, a tiny body, and big low-set eyes.
struct PetFigure: View {
    let unit: CGFloat
    let pose: PetPose
    let padBottom: Bool
    var look: PetLook = .classic

    var body: some View {
        let palette = look.palette
        let outline = palette.outline.opacity(0.6)
        let line = max(unit * 0.012, 0.75)
        let layout = PetFaceLayout(look.species)
        let face = pose.face
        // The tail sits behind whichever side the pet is walking away from.
        let tailSide: CGFloat = pose.turn > 0.15 ? -1 : 1
        ZStack {
            tail(outline: outline, line: line)
                .scaleEffect(x: tailSide, y: 1)
                .offset(x: pose.lag.width, y: pose.lag.height)
            Ellipse()
                .fill(LinearGradient(colors: [palette.furTop, palette.furBottom], startPoint: .top, endPoint: .bottom))
                .overlay(bodyMarkings.clipShape(Ellipse()))
                .overlay(Ellipse().stroke(outline, lineWidth: line))
                .frame(width: unit * 0.54, height: unit * 0.42)
                .offset(y: unit * 0.29)
            if look.appearance.pattern != .plain {
                Ellipse()
                    .fill(LinearGradient(colors: [palette.bellyTop, palette.bellyBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: unit * 0.34, height: unit * 0.28)
                    .offset(y: unit * 0.33)
            }
            if !pose.tucked {
                feet(outline: outline, line: line)
            }
            if look.appearance.accessory == .scarf {
                PetScarf(unit: unit).offset(x: unit * 0.02 * pose.turn, y: unit * 0.215)
            }
            head(width: unit * layout.headWidth, height: unit * layout.headHeight, layout: layout,
                 outline: outline, line: line)
                .rotationEffect(.degrees(pose.headTilt + face.tilt), anchor: .bottom)
                .offset(x: unit * 0.02 * pose.turn, y: -unit * 0.04)
            arms(outline: outline, line: line)
        }
        .frame(width: unit, height: unit)
        .scaleEffect(x: pose.scale.width * (1 + 0.03 * face.squish), y: pose.scale.height * (1 - 0.04 * face.squish),
                     anchor: .bottom)
        .rotationEffect(.degrees(pose.rotation))
        .offset(pose.offset)
        .padding(.bottom, padBottom ? unit * 0.06 : 0)
    }

    private func head(width: CGFloat, height: CGFloat, layout: PetFaceLayout, outline: Color, line: CGFloat) -> some View {
        let face = pose.face
        let palette = look.palette
        let lift = face.chinUp ? -unit * 0.02 : 0
        let blush = min(0.25 * face.blush, 0.6)
        let shape = PetSpeciesHead(species: look.species)
        // Turning slides the features toward the travel side and narrows the far eye, a cheap three-quarter view.
        let shift = unit * 0.075 * pose.turn
        let speciesArt = PetSpeciesArt(unit: unit, look: look, turn: pose.turn, tail: pose.tail)
        return ZStack {
            speciesArt.backEars(outline: outline, line: line)
            shape
                .fill(LinearGradient(colors: [palette.furTop, palette.furBottom], startPoint: .top, endPoint: .bottom))
                .overlay(ZStack {
                    headMarkings
                    speciesArt.faceMarkings(layout: layout).offset(x: shift * 0.7)
                }
                .frame(width: width, height: height)
                .clipShape(shape))
                .overlay(shape.stroke(outline, lineWidth: line))
            Group {
                ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                    let far = side * pose.turn < 0
                    let squeeze = far ? 1 - 0.3 * abs(pose.turn) : 1
                    Ellipse().fill(Tokens.Pet.blush.opacity(blush))
                        .frame(width: unit * 0.13 * squeeze, height: unit * 0.07)
                        .offset(x: side * unit * layout.blushX * squeeze, y: unit * layout.blushY)
                    PetEye(unit: unit * layout.eyeScale, style: face.eyes, gaze: pose.gaze, lid: pose.lid,
                           twinkle: pose.twinkle, eyeStyle: look.appearance.eyes, ink: palette.ink, rim: palette.eyeRim)
                        .scaleEffect(x: squeeze, y: 1)
                        .offset(x: side * unit * layout.eyeX * squeeze, y: unit * layout.eyeY)
                    brow(side: side)
                        .offset(x: side * unit * layout.eyeX * squeeze,
                                y: unit * (layout.eyeY - 0.13 * layout.eyeScale))
                    speciesArt.whiskers(side: side, squeeze: squeeze)
                }
                speciesArt.nose(layout: layout)
                mouth.scaleEffect(layout.mouthScale).offset(y: unit * layout.mouthY)
                if look.appearance.accessory == .glasses {
                    PetGlasses(unit: unit, layout: layout, turn: pose.turn)
                }
            }
            .offset(x: shift, y: lift)
            speciesArt.frontEars(outline: outline, line: line)
            PetHeadAccessory(unit: unit, accessory: look.appearance.accessory, species: look.species, height: height)
                .offset(x: shift * 0.4)
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var headMarkings: some View {
        let color = look.palette.marking
        switch look.appearance.pattern {
        case .plain, .belly:
            EmptyView()
        case .spots:
            ZStack {
                spot(color, x: -0.24, y: -0.14, size: 0.12)
                spot(color, x: 0.26, y: -0.07, size: 0.1)
                spot(color, x: 0.05, y: -0.21, size: 0.075)
                spot(color, x: -0.33, y: 0.06, size: 0.06)
            }
        case .stripes:
            ZStack {
                ForEach([-1.0, 0, 1.0], id: \.self) { (step: Double) in
                    Capsule().fill(color)
                        .frame(width: unit * 0.035, height: unit * (step == 0 ? 0.13 : 0.1))
                        .rotationEffect(.degrees(step * 14))
                        .offset(x: unit * 0.07 * step, y: -unit * 0.24)
                }
                ForEach([-1.0, 1.0], id: \.self) { (side: Double) in
                    ForEach([0.0, 1.0], id: \.self) { (row: Double) in
                        Capsule().fill(color)
                            .frame(width: unit * 0.1, height: unit * 0.03)
                            .rotationEffect(.degrees(side * (8 - 16 * row)))
                            .offset(x: side * unit * 0.38, y: unit * (-0.02 + 0.07 * row))
                    }
                }
            }
        case .patches:
            ZStack {
                PetBlobShape().fill(color)
                    .frame(width: unit * 0.3, height: unit * 0.26)
                    .offset(x: -unit * 0.19, y: -unit * 0.02)
                PetBlobShape().fill(color)
                    .frame(width: unit * 0.22, height: unit * 0.16)
                    .rotationEffect(.degrees(150))
                    .offset(x: unit * 0.3, y: -unit * 0.2)
            }
        }
    }

    @ViewBuilder
    private var bodyMarkings: some View {
        let color = look.palette.marking
        switch look.appearance.pattern {
        case .plain, .belly:
            EmptyView()
        case .spots:
            ZStack {
                spot(color, x: -0.2, y: -0.06, size: 0.1)
                spot(color, x: 0.21, y: 0.04, size: 0.09)
                spot(color, x: 0.12, y: -0.15, size: 0.06)
            }
        case .stripes:
            ZStack {
                ForEach([-1.0, 1.0], id: \.self) { (side: Double) in
                    ForEach([0.0, 1.0, 2.0], id: \.self) { (row: Double) in
                        Capsule().fill(color)
                            .frame(width: unit * 0.11, height: unit * 0.032)
                            .rotationEffect(.degrees(side * (-20 + 14 * row)))
                            .offset(x: side * unit * 0.22, y: unit * (-0.1 + 0.08 * row))
                    }
                }
            }
        case .patches:
            PetBlobShape().fill(color)
                .frame(width: unit * 0.24, height: unit * 0.2)
                .offset(x: unit * 0.17, y: -unit * 0.08)
        }
    }

    private func spot(_ color: Color, x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        Circle().fill(color).frame(width: unit * size, height: unit * size).offset(x: unit * x, y: unit * y)
    }

    @ViewBuilder
    private func tail(outline: Color, line: CGFloat) -> some View {
        let palette = look.palette
        switch look.species {
        case .seal:
            Ellipse().fill(palette.limb)
                .overlay(Ellipse().stroke(outline, lineWidth: line))
                .frame(width: unit * 0.15, height: unit * 0.08)
                .rotationEffect(.degrees(20 + pose.tail), anchor: .leading)
                .offset(x: unit * 0.22, y: unit * 0.43)
        case .cat:
            ZStack {
                PetCatTail().stroke(outline, style: StrokeStyle(lineWidth: unit * 0.075 + line * 2, lineCap: .round))
                PetCatTail().stroke(palette.furBottom, style: StrokeStyle(lineWidth: unit * 0.075, lineCap: .round))
            }
            .frame(width: unit * 0.22, height: unit * 0.34)
            .rotationEffect(.degrees(pose.tail * 0.7), anchor: .bottomLeading)
            .offset(x: unit * 0.28, y: unit * 0.26)
        case .dog:
            Capsule().fill(palette.furBottom)
                .overlay(Capsule().stroke(outline, lineWidth: line))
                .frame(width: unit * 0.075, height: unit * 0.19)
                .rotationEffect(.degrees(40 + pose.tail * 1.6), anchor: .bottom)
                .offset(x: unit * 0.24, y: unit * 0.28)
        case .fox:
            ZStack {
                Ellipse().fill(LinearGradient(colors: [palette.furTop, palette.furBottom], startPoint: .bottom, endPoint: .top))
                Ellipse().fill(palette.bellyTop)
                    .frame(width: unit * 0.13, height: unit * 0.12)
                    .offset(y: -unit * 0.13)
            }
            .clipShape(Ellipse())
            .overlay(Ellipse().stroke(outline, lineWidth: line))
            .frame(width: unit * 0.2, height: unit * 0.38)
            .rotationEffect(.degrees(48 + pose.tail * 0.6), anchor: .bottom)
            .offset(x: unit * 0.29, y: unit * 0.24)
        case .bunny:
            Circle().fill(palette.bellyTop)
                .overlay(Circle().stroke(outline, lineWidth: line))
                .frame(width: unit * 0.14, height: unit * 0.14)
                .offset(x: unit * 0.26 + unit * 0.004 * pose.tail, y: unit * 0.4)
        case .owl:
            ForEach([-1.0, 0, 1.0], id: \.self) { (step: Double) in
                Ellipse().fill(palette.limb)
                    .overlay(Ellipse().stroke(outline, lineWidth: line))
                    .frame(width: unit * 0.07, height: unit * 0.14)
                    .rotationEffect(.degrees(step * 22 + pose.tail * 0.3), anchor: .top)
                    .offset(x: unit * 0.04 * step, y: unit * 0.47)
            }
        case .penguin, .frog, .hamster:
            EmptyView()
        }
    }

    @ViewBuilder
    private func feet(outline: Color, line: CGFloat) -> some View {
        if look.species.gait != .galumph {
            let size = PetSpeciesArt.footSize(look.species)
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                let step = side < 0 ? pose.footLeft : pose.footRight
                PetFoot(species: look.species, palette: look.palette, outline: outline, line: line)
                    .frame(width: unit * size.width, height: unit * size.height)
                    .offset(x: side * unit * 0.11 * (1 - 0.35 * abs(pose.turn)) + unit * 0.03 * pose.turn + step.width,
                            y: unit * 0.475 + step.height)
            }
        }
    }

    @ViewBuilder
    private func arms(outline: Color, line: CGFloat) -> some View {
        switch look.species {
        case .seal, .penguin:
            let length = look.species == .penguin ? 0.19 : 0.17
            let color = look.species == .penguin ? look.palette.furBottom : look.palette.limb
            flipper(angle: -28 + pose.flipperLeft, anchor: .trailing, length: length, color: color)
                .offset(x: -unit * 0.305 + pose.lag.width, y: unit * 0.27 + pose.lag.height)
            flipper(angle: 28 - pose.flipperRight, anchor: .leading, length: length, color: color)
                .offset(x: unit * 0.305 + pose.lag.width + pose.rightFlipperOffset.width,
                        y: unit * 0.27 + pose.lag.height + pose.rightFlipperOffset.height)
        default:
            let wing = look.species == .owl
            let size = wing ? CGSize(width: 0.12, height: 0.24) : CGSize(width: 0.105, height: 0.14)
            let color = wing ? look.palette.limb : look.palette.furBottom
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                let raise = side < 0 ? pose.flipperLeft : pose.flipperRight
                let extra = side < 0 ? .zero : pose.rightFlipperOffset
                Ellipse().fill(color)
                    .overlay(Ellipse().stroke(outline, lineWidth: line))
                    .frame(width: unit * size.width, height: unit * size.height)
                    .rotationEffect(.degrees(side * -(wing ? 8 : 18) - side * raise), anchor: .top)
                    .offset(x: side * unit * (wing ? 0.25 : 0.215) + pose.lag.width + extra.width,
                            y: unit * (wing ? 0.17 : 0.2) + unit * size.height / 2 + pose.lag.height + extra.height)
            }
        }
    }

    @ViewBuilder
    private func brow(side: Double) -> some View {
        let stroke = StrokeStyle(lineWidth: max(unit * 0.016, 1), lineCap: .round)
        let ink = look.appearance.isClassicSeal ? Tokens.Pet.outline : look.palette.ink.opacity(0.7)
        switch pose.face.brow {
        case .none:
            EmptyView()
        case .raised:
            PetArc(up: true).stroke(ink, style: stroke).frame(width: unit * 0.1, height: unit * 0.025)
        case .worried:
            Capsule().fill(ink).frame(width: unit * 0.09, height: max(unit * 0.016, 1))
                .rotationEffect(.degrees(-6 * side))
        }
    }

    private func flipper(angle: Double, anchor: UnitPoint, length: Double, color: Color) -> some View {
        Ellipse().fill(color)
            .overlay(Ellipse().stroke(look.palette.outline.opacity(0.6), lineWidth: max(unit * 0.012, 0.75)))
            .frame(width: unit * length, height: unit * 0.095)
            .rotationEffect(.degrees(angle), anchor: anchor)
    }

    @ViewBuilder
    private var mouth: some View {
        let stroke = StrokeStyle(lineWidth: max(unit * 0.014, 1), lineCap: .round)
        let ink = look.palette.ink
        if pose.mouthOpen > 0.05 {
            Ellipse().fill(Tokens.Pet.eye)
                .frame(width: unit * 0.1 * (0.7 + pose.mouthOpen * 0.3), height: unit * 0.1 * pose.mouthOpen)
        } else {
            switch pose.face.mouth {
            case .w:
                PetWMouth().stroke(ink, style: stroke).frame(width: unit * 0.11, height: unit * 0.03)
            case .smile:
                PetSmile(depth: 0.8).stroke(ink, style: stroke).frame(width: unit * 0.09, height: unit * 0.03)
            case .openSmile:
                PetOpenSmile().fill(Tokens.Pet.eye)
                    .overlay(Ellipse().fill(Tokens.Pet.blush).frame(width: unit * 0.05, height: unit * 0.03)
                        .offset(y: unit * 0.025))
                    .clipShape(PetOpenSmile())
                    .frame(width: unit * 0.11, height: unit * 0.06)
            case .o:
                Ellipse().fill(Tokens.Pet.eye).frame(width: unit * 0.045, height: unit * 0.055)
            case .flat:
                PetSmile(depth: 0.1).stroke(ink, style: stroke).frame(width: unit * 0.07, height: unit * 0.02)
            }
        }
    }
}
