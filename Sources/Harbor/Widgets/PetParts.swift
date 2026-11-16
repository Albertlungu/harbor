import AppKit
import SwiftUI

/// Hands the hosting window to SwiftUI, which has no direct way to ask for it.
@MainActor
final class PetWindowBox {
    weak var window: NSWindow?
}

struct PetWindowReader: NSViewRepresentable {
    let box: PetWindowBox

    final class Anchor: NSView {
        var box: PetWindowBox?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
        }
    }

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.box = box
        return view
    }

    func updateNSView(_ view: Anchor, context: Context) { view.box = box }
}

struct PetSmile: Shape {
    /// 0 is a flat line, 1 a full smile.
    var depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 2 * depth))
        return path
    }
}

struct PetEye: View {
    let unit: CGFloat
    let gaze: CGSize
    let lid: Double
    let sparkle: Bool
    let twinkle: Double

    var body: some View {
        let width = unit * 0.12
        let height = unit * 0.13
        ZStack {
            Ellipse().fill(Color.white)
                .overlay(Ellipse().stroke(Tokens.textMuted.opacity(0.5), lineWidth: 0.75))
            Circle().fill(Color.black)
                .frame(width: unit * 0.07, height: unit * 0.07)
                .overlay {
                    if sparkle {
                        Image(systemName: "sparkle")
                            .font(.system(size: unit * 0.045))
                            .foregroundStyle(Color.white)
                            .scaleEffect(0.8 + 0.3 * twinkle)
                    }
                }
                .offset(x: gaze.width * unit * 0.025, y: gaze.height * unit * 0.03)
            VStack(spacing: 0) {
                Rectangle().fill(Tokens.surface).frame(height: height * lid)
                Spacer(minLength: 0)
            }
        }
        .frame(width: width, height: height)
        .clipShape(Ellipse())
        .overlay {
            // A fully closed lid reads as a sleeping line rather than an empty patch.
            if lid > 0.95 {
                PetSmile(depth: 0.5)
                    .stroke(Tokens.text, style: StrokeStyle(lineWidth: max(unit * 0.012, 1), lineCap: .round))
                    .frame(width: width * 0.8, height: height * 0.12)
            }
        }
    }
}

struct PetFishBubble: View {
    let unit: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Tokens.dockSolid)
                .overlay(Circle().stroke(Tokens.textMuted.opacity(0.5), lineWidth: 1))
                .frame(width: unit * 0.2, height: unit * 0.2)
            Image(systemName: "fish.fill")
                .font(.system(size: unit * 0.1))
                .foregroundStyle(Tokens.accent)
            Circle().fill(Tokens.dockSolid)
                .frame(width: unit * 0.04, height: unit * 0.04)
                .offset(x: unit * 0.07, y: unit * 0.12)
        }
        .accessibilityHidden(true)
    }
}

struct PetSleepLetters: View {
    let unit: CGFloat
    let time: Double
    let animated: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let phase = animated
                    ? (time * 0.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    : Double(index) / 3 + 0.2
                Text("z")
                    .font(.system(size: unit * (0.09 + 0.06 * phase), weight: .semibold, design: .rounded))
                    .foregroundStyle(Tokens.textMuted)
                    .offset(x: unit * (0.2 + 0.04 * sin(phase * 2 * .pi)), y: -unit * (0.12 + 0.28 * phase))
                    .opacity(sin(phase * .pi))
            }
        }
        .accessibilityHidden(true)
    }
}

struct PetHeart: View {
    let unit: CGFloat
    let reduceMotion: Bool
    let done: () -> Void

    @State private var risen = false
    @State private var xOffset = CGFloat.random(in: -0.15...0.15)

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: unit * 0.16))
            .foregroundStyle(Tokens.accent)
            .offset(x: xOffset * unit, y: risen && !reduceMotion ? -unit * 0.4 : -unit * 0.1)
            .opacity(risen ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) { risen = true } completion: { done() }
            }
            .accessibilityHidden(true)
    }
}
