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
}

/// Proportions follow the baby schema: a head about two thirds of the height, a tiny body, and big low-set eyes.
struct PetFigure: View {
    let unit: CGFloat
    let pose: PetPose
    let padBottom: Bool

    var body: some View {
        let outline = Tokens.Pet.outline.opacity(0.6)
        let line = max(unit * 0.012, 0.75)
        let headWidth = unit * 0.82
        let headHeight = unit * 0.54
        let face = pose.face
        ZStack {
            Ellipse().fill(Tokens.Pet.flipper)
                .overlay(Ellipse().stroke(outline, lineWidth: line))
                .frame(width: unit * 0.15, height: unit * 0.08)
                .rotationEffect(.degrees(20 + pose.tail), anchor: .leading)
                .offset(x: unit * 0.22 + pose.lag.width, y: unit * 0.43 + pose.lag.height)
            Ellipse()
                .fill(LinearGradient(colors: [Tokens.Pet.furTop, Tokens.Pet.furBottom], startPoint: .top, endPoint: .bottom))
                .overlay(Ellipse().stroke(outline, lineWidth: line))
                .frame(width: unit * 0.54, height: unit * 0.42)
                .offset(y: unit * 0.29)
            Ellipse()
                .fill(LinearGradient(colors: [Tokens.Pet.bellyTop, Tokens.Pet.bellyBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: unit * 0.34, height: unit * 0.28)
                .offset(y: unit * 0.33)
            head(width: headWidth, height: headHeight, outline: outline, line: line)
                .rotationEffect(.degrees(pose.headTilt + face.tilt), anchor: .bottom)
                .offset(y: -unit * 0.04)
            flipper(angle: -28 + pose.flipperLeft, anchor: .trailing)
                .offset(x: -unit * 0.305 + pose.lag.width, y: unit * 0.27 + pose.lag.height)
            flipper(angle: 28 - pose.flipperRight, anchor: .leading)
                .offset(x: unit * 0.305 + pose.lag.width + pose.rightFlipperOffset.width,
                        y: unit * 0.27 + pose.lag.height + pose.rightFlipperOffset.height)
        }
        .frame(width: unit, height: unit)
        .scaleEffect(x: pose.scale.width * (1 + 0.03 * face.squish), y: pose.scale.height * (1 - 0.04 * face.squish),
                     anchor: .bottom)
        .rotationEffect(.degrees(pose.rotation))
        .offset(pose.offset)
        .padding(.bottom, padBottom ? unit * 0.06 : 0)
    }

    private func head(width: CGFloat, height: CGFloat, outline: Color, line: CGFloat) -> some View {
        let face = pose.face
        let lift = face.chinUp ? -unit * 0.02 : 0
        let blush = min(0.25 * face.blush, 0.6)
        return ZStack {
            PetHeadShape()
                .fill(LinearGradient(colors: [Tokens.Pet.furTop, Tokens.Pet.furBottom], startPoint: .top, endPoint: .bottom))
                .overlay(PetHeadShape().stroke(outline, lineWidth: line))
            Group {
                ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                    Ellipse().fill(Tokens.Pet.blush.opacity(blush))
                        .frame(width: unit * 0.13, height: unit * 0.07)
                        .offset(x: side * unit * 0.23, y: unit * 0.15)
                    PetEye(unit: unit, style: face.eyes, gaze: pose.gaze, lid: pose.lid, twinkle: pose.twinkle)
                        .offset(x: side * unit * 0.175, y: unit * 0.045)
                    brow(side: side).offset(x: side * unit * 0.175, y: -unit * 0.085)
                    ForEach(0..<2, id: \.self) { row in
                        Circle().fill(Tokens.Pet.whisker.opacity(0.7))
                            .frame(width: unit * 0.022, height: unit * 0.022)
                            .offset(x: side * unit * (0.315 - 0.01 * Double(row)), y: unit * (0.1 + 0.04 * Double(row)))
                    }
                }
                Ellipse().fill(Tokens.Pet.nose)
                    .frame(width: unit * 0.06, height: unit * 0.04)
                    .offset(y: unit * 0.11)
                mouth.offset(y: unit * 0.175)
            }
            .offset(y: lift)
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func brow(side: Double) -> some View {
        let stroke = StrokeStyle(lineWidth: max(unit * 0.016, 1), lineCap: .round)
        switch pose.face.brow {
        case .none:
            EmptyView()
        case .raised:
            PetArc(up: true).stroke(Tokens.Pet.outline, style: stroke).frame(width: unit * 0.1, height: unit * 0.025)
        case .worried:
            Capsule().fill(Tokens.Pet.outline).frame(width: unit * 0.09, height: max(unit * 0.016, 1))
                .rotationEffect(.degrees(-12 * side))
        }
    }

    private func flipper(angle: Double, anchor: UnitPoint) -> some View {
        Ellipse().fill(Tokens.Pet.flipper)
            .overlay(Ellipse().stroke(Tokens.Pet.outline.opacity(0.6), lineWidth: max(unit * 0.012, 0.75)))
            .frame(width: unit * 0.17, height: unit * 0.095)
            .rotationEffect(.degrees(angle), anchor: anchor)
    }

    @ViewBuilder
    private var mouth: some View {
        let stroke = StrokeStyle(lineWidth: max(unit * 0.014, 1), lineCap: .round)
        if pose.mouthOpen > 0.05 {
            Ellipse().fill(Tokens.Pet.eye)
                .frame(width: unit * 0.1 * (0.7 + pose.mouthOpen * 0.3), height: unit * 0.1 * pose.mouthOpen)
        } else {
            switch pose.face.mouth {
            case .w:
                PetWMouth().stroke(Tokens.Pet.eye, style: stroke).frame(width: unit * 0.11, height: unit * 0.03)
            case .smile:
                PetSmile(depth: 0.8).stroke(Tokens.Pet.eye, style: stroke).frame(width: unit * 0.09, height: unit * 0.03)
            case .openSmile:
                PetOpenSmile().fill(Tokens.Pet.eye)
                    .overlay(Ellipse().fill(Tokens.Pet.blush).frame(width: unit * 0.05, height: unit * 0.03)
                        .offset(y: unit * 0.025))
                    .clipShape(PetOpenSmile())
                    .frame(width: unit * 0.11, height: unit * 0.06)
            case .o:
                Ellipse().fill(Tokens.Pet.eye).frame(width: unit * 0.045, height: unit * 0.055)
            case .flat:
                PetSmile(depth: 0.1).stroke(Tokens.Pet.eye, style: stroke).frame(width: unit * 0.07, height: unit * 0.02)
            }
        }
    }
}
