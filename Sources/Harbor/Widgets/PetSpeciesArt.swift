import HarborCore
import SwiftUI

/// Where the features sit on each species' head, in unit fractions from the head's center.
struct PetFaceLayout {
    var headWidth: CGFloat = 0.82
    var headHeight: CGFloat = 0.54
    var eyeX: CGFloat = 0.175
    var eyeY: CGFloat = 0.045
    var eyeScale: CGFloat = 1
    var noseY: CGFloat = 0.11
    var mouthY: CGFloat = 0.175
    var mouthScale: CGFloat = 1
    var blushX: CGFloat = 0.23
    var blushY: CGFloat = 0.15

    init(_ species: PetSpecies) {
        switch species {
        case .frog:
            headWidth = 0.9
            headHeight = 0.56
            eyeX = 0.207
            eyeY = -0.13
            noseY = 0.03
            mouthY = 0.1
            mouthScale = 1.5
            blushX = 0.3
            blushY = 0.06
        case .owl:
            eyeX = 0.165
            eyeY = 0.03
            eyeScale = 1.08
            noseY = 0.105
            mouthY = 0.19
            mouthScale = 0.8
        case .penguin:
            mouthY = 0.19
        case .dog:
            noseY = 0.1
        default:
            break
        }
    }
}

/// Head silhouettes: the shared chubby dome, or the frog's wide head with its eye bumps.
struct PetSpeciesHead: Shape {
    let species: PetSpecies

    func path(in rect: CGRect) -> Path {
        guard species == .frog else { return PetHeadShape().path(in: rect) }
        let jaw = CGRect(x: rect.minX, y: rect.minY + rect.height * 0.22, width: rect.width, height: rect.height * 0.78)
        let radius = rect.width * 0.135
        var bumps = Path()
        for x in [0.27, 0.73] {
            bumps.addEllipse(in: CGRect(x: rect.minX + rect.width * x - radius, y: rect.minY + rect.height * 0.27 - radius,
                                        width: radius * 2, height: radius * 2))
        }
        return PetHeadShape().path(in: jaw).union(bumps)
    }
}

/// The species-specific pieces of the head: ears, face markings, noses and whiskers.
struct PetSpeciesArt {
    let unit: CGFloat
    let look: PetLook
    let turn: Double
    let tail: Double

    private var palette: PetPalette { look.palette }

    static func footSize(_ species: PetSpecies) -> CGSize {
        switch species {
        case .bunny: CGSize(width: 0.17, height: 0.085)
        case .penguin: CGSize(width: 0.15, height: 0.065)
        case .owl: CGSize(width: 0.12, height: 0.06)
        case .frog: CGSize(width: 0.17, height: 0.075)
        case .hamster: CGSize(width: 0.1, height: 0.065)
        default: CGSize(width: 0.13, height: 0.085)
        }
    }

    /// Ears drawn behind the head so their bases tuck under its outline.
    @ViewBuilder
    func backEars(outline: Color, line: CGFloat) -> some View {
        let shift = unit * 0.03 * turn
        switch look.species {
        case .cat:
            ears(width: 0.22, height: 0.23, x: 0.24, y: -0.25, tilt: 18, inner: Tokens.Pet.earInner, tip: nil,
                 outline: outline, line: line).offset(x: shift)
        case .fox:
            ears(width: 0.25, height: 0.3, x: 0.24, y: -0.28, tilt: 16, inner: palette.bellyTop, tip: palette.accent,
                 outline: outline, line: line).offset(x: shift)
        case .owl:
            ears(width: 0.15, height: 0.17, x: 0.28, y: -0.23, tilt: 34, inner: nil, tip: nil,
                 outline: outline, line: line).offset(x: shift)
        case .bunny:
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                ZStack {
                    Ellipse().fill(LinearGradient(colors: [palette.furTop, palette.furBottom], startPoint: .top, endPoint: .bottom))
                        .overlay(Ellipse().stroke(outline, lineWidth: line))
                    Ellipse().fill(Tokens.Pet.earInner)
                        .frame(width: unit * 0.065, height: unit * 0.27)
                        .offset(y: -unit * 0.02)
                }
                .frame(width: unit * 0.15, height: unit * 0.4)
                .rotationEffect(.degrees(side * 11 + tail * 0.15), anchor: .bottom)
                .offset(x: side * unit * 0.12 + shift, y: -unit * 0.38)
            }
        case .hamster:
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                Circle().fill(palette.furTop)
                    .overlay(Circle().stroke(outline, lineWidth: line))
                    .overlay(Circle().fill(Tokens.Pet.earInner).padding(unit * 0.03))
                    .frame(width: unit * 0.15, height: unit * 0.15)
                    .offset(x: side * unit * 0.26 + shift, y: -unit * 0.2)
            }
        case .seal, .dog, .penguin, .frog:
            EmptyView()
        }
    }

    private func ears(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, tilt: Double, inner: Color?, tip: Color?,
                      outline: Color, line: CGFloat) -> some View {
        ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
            ZStack {
                PetEarShape().fill(palette.furTop)
                if let tip {
                    Rectangle().fill(tip).frame(height: unit * height * 0.38).frame(maxHeight: .infinity, alignment: .top)
                        .clipShape(PetEarShape())
                }
                if let inner {
                    PetEarShape().fill(inner)
                        .frame(width: unit * width * 0.5, height: unit * height * 0.55)
                        .offset(y: unit * height * 0.14)
                }
                PetEarShape().stroke(outline, lineWidth: line)
            }
            .frame(width: unit * width, height: unit * height)
            .rotationEffect(.degrees(side * tilt + tail * 0.08), anchor: .bottom)
            .offset(x: side * unit * x, y: unit * y)
        }
    }

    /// Ears that hang in front of the head, which only the dog has.
    @ViewBuilder
    func frontEars(outline: Color, line: CGFloat) -> some View {
        if look.species == .dog {
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                Ellipse().fill(LinearGradient(colors: [palette.limb, palette.accent.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(outline, lineWidth: line))
                    .frame(width: unit * 0.16, height: unit * 0.32)
                    .rotationEffect(.degrees(side * 6 - tail * 0.25), anchor: .top)
                    .offset(x: side * unit * 0.37 + unit * 0.03 * turn, y: unit * 0.03)
            }
        }
    }

    /// Lighter areas of the face, drawn inside the head's clip and under the features.
    @ViewBuilder
    func faceMarkings(layout: PetFaceLayout) -> some View {
        let light = palette.bellyTop
        switch look.species {
        case .dog:
            Ellipse().fill(light).frame(width: unit * 0.3, height: unit * 0.2).offset(y: unit * 0.135)
        case .fox:
            ZStack {
                ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                    PetEarShape().fill(light)
                        .frame(width: unit * 0.42, height: unit * 0.34)
                        .rotationEffect(.degrees(180 + Double(side) * 28))
                        .offset(x: side * unit * 0.22, y: unit * 0.19)
                }
                Ellipse().fill(light).frame(width: unit * 0.26, height: unit * 0.2).offset(y: unit * 0.15)
            }
        case .penguin:
            ZStack {
                ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                    Ellipse().fill(light).frame(width: unit * 0.4, height: unit * 0.44).offset(x: side * unit * 0.14, y: unit * 0.07)
                }
                Ellipse().fill(light).frame(width: unit * 0.6, height: unit * 0.3).offset(y: unit * 0.2)
            }
        case .owl:
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                Circle().fill(light)
                    .frame(width: unit * 0.3, height: unit * 0.3)
                    .offset(x: side * unit * layout.eyeX, y: unit * (layout.eyeY + 0.01))
            }
        case .hamster:
            ZStack {
                ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                    Ellipse().fill(light).frame(width: unit * 0.32, height: unit * 0.26).offset(x: side * unit * 0.25, y: unit * 0.15)
                }
                Ellipse().fill(light).frame(width: unit * 0.22, height: unit * 0.16).offset(y: unit * 0.14)
            }
        case .bunny:
            Ellipse().fill(light).frame(width: unit * 0.2, height: unit * 0.13).offset(y: unit * 0.135)
        case .seal, .cat, .frog:
            EmptyView()
        }
    }

    @ViewBuilder
    func nose(layout: PetFaceLayout) -> some View {
        let y = unit * layout.noseY
        switch look.species {
        case .seal:
            Ellipse().fill(palette.nose).frame(width: unit * 0.06, height: unit * 0.04).offset(y: y)
        case .cat, .bunny:
            let size = look.species == .cat ? CGSize(width: 0.065, height: 0.045) : CGSize(width: 0.055, height: 0.038)
            PetTriangle().fill(palette.nose).frame(width: unit * size.width, height: unit * size.height).offset(y: y)
        case .hamster:
            Ellipse().fill(palette.nose).frame(width: unit * 0.05, height: unit * 0.035).offset(y: y)
        case .dog, .fox:
            let big = look.species == .dog
            Ellipse().fill(palette.nose)
                .overlay(Ellipse().fill(Color.white.opacity(0.55))
                    .frame(width: unit * 0.025, height: unit * 0.014)
                    .offset(x: -unit * 0.012, y: -unit * 0.01))
                .frame(width: unit * (big ? 0.1 : 0.07), height: unit * (big ? 0.068 : 0.05))
                .offset(y: y)
        case .penguin, .owl:
            let size = look.species == .penguin ? CGSize(width: 0.12, height: 0.075) : CGSize(width: 0.075, height: 0.09)
            PetTriangle().fill(palette.nose)
                .overlay(PetTriangle().stroke(palette.nose.opacity(0.9), lineWidth: max(unit * 0.008, 0.5)))
                .frame(width: unit * size.width, height: unit * size.height)
                .offset(y: y)
        case .frog:
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                Circle().fill(palette.outline).frame(width: unit * 0.022, height: unit * 0.022)
                    .offset(x: side * unit * 0.04, y: y)
            }
        }
    }

    @ViewBuilder
    func whiskers(side: CGFloat, squeeze: CGFloat) -> some View {
        switch look.species {
        case .seal, .bunny, .hamster:
            ForEach(0..<2, id: \.self) { row in
                Circle().fill(palette.whisker.opacity(0.7))
                    .frame(width: unit * 0.022, height: unit * 0.022)
                    .offset(x: side * unit * (0.315 - 0.01 * Double(row)) * squeeze, y: unit * (0.1 + 0.04 * Double(row)))
            }
        case .cat:
            ForEach(0..<2, id: \.self) { row in
                Capsule().fill(palette.whisker.opacity(0.8))
                    .frame(width: unit * 0.13, height: max(unit * 0.012, 0.75))
                    .rotationEffect(.degrees(side * (row == 0 ? 8 : -8)))
                    .offset(x: side * unit * 0.36 * squeeze, y: unit * (0.11 + 0.045 * Double(row)))
            }
        default:
            EmptyView()
        }
    }
}

struct PetFoot: View {
    let species: PetSpecies
    let palette: PetPalette
    let outline: Color
    let line: CGFloat

    var body: some View {
        switch species {
        case .owl:
            GeometryReader { proxy in
                ForEach(-1...1, id: \.self) { toe in
                    Capsule().fill(palette.feet)
                        .frame(width: proxy.size.width * 0.32, height: proxy.size.height)
                        .rotationEffect(.degrees(Double(toe) * 25), anchor: .top)
                        .position(x: proxy.size.width * (0.5 + 0.28 * Double(toe)), y: proxy.size.height * 0.5)
                }
            }
        case .frog:
            GeometryReader { proxy in
                let toe = proxy.size.height * 0.55
                ZStack {
                    Ellipse().fill(palette.furBottom)
                    ForEach(-1...1, id: \.self) { index in
                        Circle().fill(palette.furBottom)
                            .frame(width: toe, height: toe)
                            .offset(x: proxy.size.width * 0.36 * Double(index), y: proxy.size.height * 0.3)
                    }
                }
                .overlay(Ellipse().stroke(outline, lineWidth: line))
            }
        case .fox:
            Ellipse().fill(palette.accent).overlay(Ellipse().stroke(outline, lineWidth: line))
        case .penguin:
            Ellipse().fill(palette.feet).overlay(Ellipse().stroke(palette.feet.opacity(0.8), lineWidth: line))
        default:
            Ellipse().fill(palette.feet).overlay(Ellipse().stroke(outline, lineWidth: line))
        }
    }
}

/// A rounded triangle pointing up, the shape of pointed ears and ear tufts.
struct PetEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.minY + rect.height * 0.06),
                          control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.3))
        path.addQuadCurve(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.minY + rect.height * 0.06),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.04))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.3))
        path.closeSubpath()
        return path
    }
}

/// A rounded triangle pointing down, for small noses and beaks.
struct PetTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.width * 0.18
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r * 0.6, y: rect.minY + r * 0.9), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - r * 0.4, y: rect.maxY - r * 0.3), control: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r * 0.6, y: rect.minY + r * 0.9), control: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// A lumpy patch for coat markings, irregular enough not to read as a spot.
struct PetBlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.5, 0.02))
        path.addCurve(to: point(0.98, 0.42), control1: point(0.8, 0), control2: point(1, 0.2))
        path.addCurve(to: point(0.62, 0.98), control1: point(0.96, 0.7), control2: point(0.85, 1))
        path.addCurve(to: point(0.04, 0.66), control1: point(0.36, 0.96), control2: point(0.02, 0.9))
        path.addCurve(to: point(0.5, 0.02), control1: point(0.06, 0.36), control2: point(0.2, 0.04))
        path.closeSubpath()
        return path
    }
}

/// A cat's tail rising from the bottom-left corner and curling over at the tip.
struct PetCatTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY - rect.height * 0.05))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.2),
                          control: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.15))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.08),
                          control: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY - rect.height * 0.05))
        return path
    }
}

struct PetScarf: View {
    let unit: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: unit * 0.02).fill(Tokens.Pet.scarf)
                .frame(width: unit * 0.1, height: unit * 0.17)
                .overlay(Capsule().fill(Tokens.Pet.scarfStripe).frame(height: unit * 0.018).offset(y: unit * 0.035))
                .rotationEffect(.degrees(-12), anchor: .top)
                .offset(x: unit * 0.1, y: unit * 0.07)
            Capsule().fill(Tokens.Pet.scarf)
                .overlay(HStack(spacing: unit * 0.05) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(Tokens.Pet.scarfStripe).frame(width: unit * 0.018)
                    }
                }.padding(.vertical, unit * 0.012))
                .frame(width: unit * 0.5, height: unit * 0.1)
        }
        .accessibilityHidden(true)
    }
}

struct PetGlasses: View {
    let unit: CGFloat
    let layout: PetFaceLayout
    let turn: Double

    var body: some View {
        let size = unit * 0.22 * layout.eyeScale
        let stroke = max(unit * 0.018, 1)
        ZStack {
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                let squeeze = side * turn < 0 ? 1 - 0.3 * abs(turn) : 1
                Circle().fill(Color.white.opacity(0.18))
                    .overlay(Circle().stroke(Tokens.Pet.glasses, lineWidth: stroke))
                    .frame(width: size, height: size)
                    .scaleEffect(x: squeeze, y: 1)
                    .offset(x: side * unit * layout.eyeX * squeeze, y: unit * layout.eyeY)
            }
            PetArc(up: true).stroke(Tokens.Pet.glasses, lineWidth: stroke)
                .frame(width: unit * (layout.eyeX * 2 - 0.2 * layout.eyeScale) + stroke, height: unit * 0.02)
                .offset(y: unit * (layout.eyeY - 0.02))
        }
        .accessibilityHidden(true)
    }
}

/// Things worn on the head, placed relative to the top of each species' head.
struct PetHeadAccessory: View {
    let unit: CGFloat
    let accessory: PetAccessory
    let species: PetSpecies
    let height: CGFloat

    var body: some View {
        let top = -height / 2
        switch accessory {
        case .bow:
            let place = species == .bunny ? CGPoint(x: 0.2, y: 0.02) : CGPoint(x: 0.22, y: 0.05)
            bow.offset(x: unit * place.x, y: top + unit * place.y)
        case .hat:
            hat.rotationEffect(.degrees(-10)).offset(x: -unit * 0.03, y: top - unit * (species == .frog ? 0.0 : 0.05))
        case .flowerCrown:
            crown.offset(y: top + unit * (species == .frog ? 0.08 : 0.04))
        case .none, .scarf, .glasses:
            EmptyView()
        }
    }

    private var bow: some View {
        ZStack {
            ForEach([-1.0, 1.0] as [CGFloat], id: \.self) { (side: CGFloat) in
                PetEarShape().fill(Tokens.Pet.bow)
                    .frame(width: unit * 0.15, height: unit * 0.14)
                    .rotationEffect(.degrees(side * 90))
                    .offset(x: side * unit * 0.07)
            }
            Circle().fill(Tokens.Pet.bow).overlay(Circle().fill(Color.white.opacity(0.25)))
                .frame(width: unit * 0.07, height: unit * 0.07)
        }
        .rotationEffect(.degrees(18))
        .accessibilityHidden(true)
    }

    private var hat: some View {
        ZStack {
            Capsule().fill(Tokens.Pet.hat).frame(width: unit * 0.34, height: unit * 0.055).offset(y: unit * 0.075)
            UnevenRoundedRectangle(topLeadingRadius: unit * 0.04, topTrailingRadius: unit * 0.04)
                .fill(Tokens.Pet.hat)
                .frame(width: unit * 0.21, height: unit * 0.18)
                .overlay(Rectangle().fill(Tokens.Pet.hatBand).frame(height: unit * 0.04).offset(y: unit * 0.045))
        }
        .accessibilityHidden(true)
    }

    private var crown: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let x = Double(index - 2) / 2
                let size = unit * (index == 2 ? 0.11 : 0.095)
                ZStack {
                    Ellipse().fill(Tokens.Pet.leaf)
                        .frame(width: size * 0.7, height: size * 0.38)
                        .offset(x: size * 0.45, y: size * 0.3)
                    ForEach(0..<5, id: \.self) { petal in
                        Circle().fill(Tokens.Pet.petals[index % Tokens.Pet.petals.count])
                            .frame(width: size * 0.5, height: size * 0.5)
                            .offset(y: -size * 0.24)
                            .rotationEffect(.degrees(Double(petal) * 72))
                    }
                    Circle().fill(Tokens.Pet.beak).frame(width: size * 0.32, height: size * 0.32)
                }
                .offset(x: unit * 0.29 * x, y: unit * 0.07 * x * x)
            }
        }
        .accessibilityHidden(true)
    }
}
