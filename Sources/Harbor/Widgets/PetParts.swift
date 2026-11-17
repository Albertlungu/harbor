import AppKit
import HarborCore
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

struct PetHeadShape: Shape {
    /// Cheeks bulge below the middle so the head reads as a soft, chubby dome rather than an ellipse.
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.5, 0))
        path.addCurve(to: point(1, 0.6), control1: point(0.82, 0), control2: point(1, 0.26))
        path.addCurve(to: point(0.5, 1), control1: point(1, 0.86), control2: point(0.78, 1))
        path.addCurve(to: point(0, 0.6), control1: point(0.22, 1), control2: point(0, 0.86))
        path.addCurve(to: point(0.5, 0), control1: point(0, 0.26), control2: point(0.18, 0))
        path.closeSubpath()
        return path
    }
}

/// An arch whose peak touches the top of its frame, or a bowl whose lowest point touches the bottom.
struct PetArc: Shape {
    var up: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = up ? rect.maxY : rect.minY
        path.move(to: CGPoint(x: rect.minX, y: baseline))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: baseline),
                          control: CGPoint(x: rect.midX, y: up ? rect.maxY - rect.height * 2 : rect.minY + rect.height * 2))
        return path
    }
}

/// Two small bowls side by side, the classic cat-like "w" mouth.
struct PetWMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 2))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 2))
        return path
    }
}

struct PetOpenSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 2))
        path.closeSubpath()
        return path
    }
}

struct PetEye: View {
    let unit: CGFloat
    let style: PetEyes
    let gaze: CGSize
    let lid: Double
    let twinkle: Double
    var eyeStyle: PetEyeStyle = .round
    var ink: Color = Tokens.Pet.eye
    var rim = false

    var body: some View {
        let width = unit * 0.17
        let height = unit * 0.19
        let frameWidth = width * 1.15
        let frameHeight = height * 1.15
        let stroke = StrokeStyle(lineWidth: max(unit * 0.03, 1.2), lineCap: .round)
        // A sleepy-eyed pet keeps its lids half down at rest; surprise still opens them most of the way.
        let restingLid = eyeStyle == .sleepy ? (style == .wide ? 0.15 : 0.42) : 0
        ZStack {
            if style == .arcUp || style == .arcDown {
                PetArc(up: style == .arcUp)
                    .stroke(ink, style: stroke)
                    .frame(width: width * 0.9, height: height * 0.3)
            } else if lid > 0.85 {
                // A shut lid is a short bowl so a blink still reads as an eye closing rather than vanishing.
                PetArc(up: false)
                    .stroke(ink, style: stroke)
                    .frame(width: width * 0.9, height: height * 0.14)
            } else {
                openEye(width: width, height: height)
                    .frame(width: frameWidth, height: frameHeight)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: frameHeight * (1 - max(lid, style == .halfLid ? 0.45 : 0, restingLid)))
                    }
                    .offset(x: gaze.width * unit * 0.03, y: gaze.height * unit * 0.035)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
    }

    private func openEye(width: CGFloat, height: CGFloat) -> some View {
        let sparkly = style == .sparkle || (eyeStyle == .sparkly && style == .open)
        let grow: CGFloat = (style == .wide || sparkly) ? 1.15 : 1
        return ZStack {
            if rim {
                Ellipse().stroke(Color.white.opacity(0.8), lineWidth: unit * 0.022)
                    .frame(width: width * grow, height: height * grow)
            }
            Ellipse().fill(Tokens.Pet.eye)
                .frame(width: width * grow, height: height * grow)
            // Two highlights at different sizes are what makes the eye look glossy and alive.
            Circle().fill(Color.white)
                .frame(width: width * 0.42, height: width * 0.42)
                .offset(x: -width * 0.17, y: -height * 0.2)
            Circle().fill(Color.white.opacity(0.9))
                .frame(width: width * 0.18, height: width * 0.18)
                .offset(x: width * 0.2, y: height * 0.22)
            if sparkly {
                Image(systemName: "sparkle")
                    .font(.system(size: unit * 0.07))
                    .foregroundStyle(Color.white)
                    .scaleEffect(0.7 + 0.5 * twinkle)
                    .offset(x: width * 0.12, y: -height * 0.05)
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
                .offset(x: -unit * 0.1, y: -unit * 0.02)
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

struct PetSnoreBubble: View {
    let unit: CGFloat
    let time: Double

    var body: some View {
        let size = unit * (0.04 + 0.07 * PetMotion.breath(at: time))
        Circle().stroke(Tokens.textMuted.opacity(0.7), lineWidth: max(unit * 0.012, 1))
            .background(Circle().fill(Color.white.opacity(0.35)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PetParticle: Identifiable, Equatable {
    enum Kind { case heart, note, crumb, sparkle }

    let id: Int
    let kind: Kind
    let origin: CGSize
    /// Travel as a fraction of the unit, drawn at random so bursts never look stamped.
    let drift: CGSize
}

struct PetParticleView: View {
    let unit: CGFloat
    let particle: PetParticle
    let animated: Bool
    let done: () -> Void

    @State private var gone = false

    var body: some View {
        let travel = animated && gone
        glyph
            .offset(x: (particle.origin.width + (travel ? particle.drift.width : 0)) * unit,
                    y: (particle.origin.height + (travel ? particle.drift.height : 0)) * unit)
            .opacity(gone ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) { gone = true }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(850))
                done()
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch particle.kind {
        case .heart:
            Image(systemName: "heart.fill").font(.system(size: unit * 0.15)).foregroundStyle(Tokens.badge)
        case .note:
            Image(systemName: "music.note").font(.system(size: unit * 0.13, weight: .semibold))
                .foregroundStyle(Tokens.accent)
        case .sparkle:
            Image(systemName: "sparkle").font(.system(size: unit * 0.13)).foregroundStyle(Tokens.warning)
        case .crumb:
            Circle().fill(Tokens.Pet.flipper).frame(width: unit * 0.045, height: unit * 0.045)
        }
    }
}
