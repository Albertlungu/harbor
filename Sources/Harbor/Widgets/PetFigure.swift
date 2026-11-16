import HarborCore
import SwiftUI

/// Everything the drawing needs for one frame, so the figure stays a pure function of its inputs.
struct PetPose {
    var mood: PetMood = .content
    var offset: CGSize = .zero
    var rotation: Double = 0
    var scale: CGSize = CGSize(width: 1, height: 1)
    var flipperLeft: Double = 0
    var flipperRight: Double = 0
    var tail: Double = 0
    var gaze: CGSize = .zero
    var lid: Double = 0
    var mouthOpen: Double = 0
    var twinkle: Double = 0
}

struct PetFigure: View {
    let unit: CGFloat
    let pose: PetPose
    let padBottom: Bool

    var body: some View {
        let bodyWidth = unit * 0.78
        let bodyHeight = unit * 0.62
        let outline = Tokens.textMuted.opacity(0.5)
        ZStack {
            // The tail peeks out behind the body so it can wag without a front view of the hind end.
            Ellipse().fill(Tokens.dockSolid)
                .overlay(Ellipse().stroke(outline, lineWidth: 1))
                .frame(width: unit * 0.16, height: unit * 0.09)
                .rotationEffect(.degrees(15 + pose.tail), anchor: .leading)
                .offset(x: bodyWidth * 0.42, y: bodyHeight * 0.4)
            flipper(angle: -25 + pose.flipperLeft, anchor: .trailing)
                .offset(x: -bodyWidth * 0.5, y: bodyHeight * 0.18)
            flipper(angle: 25 - pose.flipperRight, anchor: .leading)
                .offset(x: bodyWidth * 0.5, y: bodyHeight * 0.18)
            RoundedRectangle(cornerRadius: bodyHeight * 0.5, style: .continuous)
                .fill(Tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: bodyHeight * 0.5, style: .continuous)
                    .strokeBorder(outline, lineWidth: 1))
                .frame(width: bodyWidth, height: bodyHeight)
            // Soft cheeks are the single accent.
            Circle().fill(Tokens.accent.opacity(0.28))
                .frame(width: unit * 0.1, height: unit * 0.1)
                .offset(x: -unit * 0.2, y: unit * 0.06)
            Circle().fill(Tokens.accent.opacity(0.28))
                .frame(width: unit * 0.1, height: unit * 0.1)
                .offset(x: unit * 0.2, y: unit * 0.06)
            PetEye(unit: unit, gaze: pose.gaze, lid: pose.lid, sparkle: pose.mood == .happy, twinkle: pose.twinkle)
                .offset(x: -unit * 0.13, y: -unit * 0.03)
            PetEye(unit: unit, gaze: pose.gaze, lid: pose.lid, sparkle: pose.mood == .happy, twinkle: pose.twinkle)
                .offset(x: unit * 0.13, y: -unit * 0.03)
            Ellipse().fill(Tokens.text)
                .frame(width: unit * 0.07, height: unit * 0.045)
                .offset(y: unit * 0.06)
            mouth.offset(y: unit * 0.115)
        }
        .scaleEffect(x: pose.scale.width, y: pose.scale.height, anchor: .bottom)
        .rotationEffect(.degrees(pose.rotation))
        .offset(pose.offset)
        .padding(.bottom, padBottom ? unit * 0.06 : 0)
    }

    private func flipper(angle: Double, anchor: UnitPoint) -> some View {
        Ellipse().fill(Tokens.dockSolid)
            .overlay(Ellipse().stroke(Tokens.textMuted.opacity(0.5), lineWidth: 1))
            .frame(width: unit * 0.2, height: unit * 0.12)
            .rotationEffect(.degrees(angle), anchor: anchor)
    }

    @ViewBuilder
    private var mouth: some View {
        if pose.mouthOpen > 0.05 {
            Ellipse().fill(Tokens.text)
                .frame(width: unit * 0.08 * (0.6 + pose.mouthOpen * 0.4), height: unit * 0.07 * pose.mouthOpen)
        } else {
            PetSmile(depth: depth)
                .stroke(Tokens.text, style: StrokeStyle(lineWidth: max(unit * 0.012, 1), lineCap: .round))
                .frame(width: unit * 0.1, height: unit * 0.03)
        }
    }

    private var depth: CGFloat {
        switch pose.mood {
        case .happy: 1
        case .content: 0.6
        case .sleepy: 0.2
        case .hungry: 0
        }
    }
}
