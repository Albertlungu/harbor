import AppKit
import HarborCore
import SwiftUI

extension Tokens {
    /// Colors for the classic seal pup. They are fixed warm tones rather than UI roles, so the pet keeps its look in both appearances.
    enum Pet {
        private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }

        static let furTop = dynamic(0xEDE8E0, 0xC4BFB7)
        static let furBottom = dynamic(0xCDC7BE, 0x9F9A93)
        static let bellyTop = dynamic(0xFAF7F1, 0xDAD5CC)
        static let bellyBottom = dynamic(0xEEE9E0, 0xC3BEB5)
        static let flipper = dynamic(0xC2BBB1, 0x8F8A83)
        static let outline = dynamic(0xA39D93, 0x7A766F)
        static let eye = Color(red: 0.12, green: 0.10, blue: 0.14)
        static let blush = dynamic(0xF28C9F, 0xF28C9F)
        static let nose = dynamic(0x6B5F66, 0x3E363B)
        static let whisker = dynamic(0x8E877D, 0x6A655E)

        static let pinkNose = dynamic(0xEE8E9E, 0xD27A8A)
        static let beak = dynamic(0xF4A646, 0xD38B33)
        static let earInner = dynamic(0xF7B5C2, 0xD898A5)
        static let bow = dynamic(0xF0647E, 0xD9566F)
        static let scarf = dynamic(0xD9534F, 0xBF4744)
        static let scarfStripe = dynamic(0xF6EFE6, 0xD8D1C8)
        static let hat = dynamic(0x4A4458, 0x3A3546)
        static let hatBand = dynamic(0xF0647E, 0xD9566F)
        static let glasses = dynamic(0x3A3138, 0x221C21)
        static let leaf = dynamic(0x7DBF6A, 0x62A052)
        static let petals: [Color] = [dynamic(0xF59AB0, 0xDA8399), dynamic(0xF7D35E, 0xDDB94B),
                                      dynamic(0xA9C8F5, 0x8DADD9), dynamic(0xFFFFFF, 0xE6E6E6)]
    }
}

/// Every colour one pet is drawn with, derived from its fur so custom colours keep the shading of the swatches.
struct PetPalette {
    var furTop: Color
    var furBottom: Color
    var bellyTop: Color
    var bellyBottom: Color
    var limb: Color
    var outline: Color
    var marking: Color
    /// Ear tips and fox socks.
    var accent: Color
    var feet: Color
    var nose: Color
    var whisker: Color
    /// Mouth, brows and closed eyes; light on dark faces so they still read.
    var ink: Color
    /// Dark faces get a pale ring around the eyes so the pupils do not vanish into the fur.
    var eyeRim: Bool

    static let classic = PetPalette(furTop: Tokens.Pet.furTop, furBottom: Tokens.Pet.furBottom,
                                    bellyTop: Tokens.Pet.bellyTop, bellyBottom: Tokens.Pet.bellyBottom,
                                    limb: Tokens.Pet.flipper, outline: Tokens.Pet.outline, marking: Tokens.Pet.flipper,
                                    accent: Tokens.Pet.flipper, feet: Tokens.Pet.flipper, nose: Tokens.Pet.nose,
                                    whisker: Tokens.Pet.whisker, ink: Tokens.Pet.eye, eyeRim: false)

    init(furTop: Color, furBottom: Color, bellyTop: Color, bellyBottom: Color, limb: Color, outline: Color,
         marking: Color, accent: Color, feet: Color, nose: Color, whisker: Color, ink: Color, eyeRim: Bool) {
        self.furTop = furTop
        self.furBottom = furBottom
        self.bellyTop = bellyTop
        self.bellyBottom = bellyBottom
        self.limb = limb
        self.outline = outline
        self.marking = marking
        self.accent = accent
        self.feet = feet
        self.nose = nose
        self.whisker = whisker
        self.ink = ink
        self.eyeRim = eyeRim
    }

    init(_ appearance: PetAppearance) {
        let fur = appearance.fur
        let species = appearance.species
        let black = PetRGB(hex: 0x2A2226)
        let cream = PetRGB(hex: 0xFBF8F2)
        let light = fur.luminance > 0.55
        let belly = switch species {
        case .penguin: cream
        case .frog: fur.mixed(PetRGB(hex: 0xFFF6D8), 0.6)
        default: fur.mixed(cream, 0.72)
        }
        furTop = Self.color(fur)
        furBottom = Self.color(fur.mixed(black, 0.13))
        bellyTop = Self.color(belly)
        bellyBottom = Self.color(belly.mixed(black, 0.06))
        limb = Self.color(fur.mixed(black, 0.2))
        outline = Self.color(fur.mixed(black, 0.36))
        marking = Self.color(light ? fur.mixed(PetRGB(hex: 0x4A3328), 0.42) : fur.mixed(cream, 0.4))
        accent = Self.color(fur.mixed(black, 0.62))
        whisker = Self.color(fur.mixed(black, 0.42))
        switch species {
        case .penguin, .owl:
            feet = Tokens.Pet.beak
            nose = Tokens.Pet.beak
        case .cat, .bunny, .hamster:
            feet = Self.color(fur.mixed(black, 0.08))
            nose = Tokens.Pet.pinkNose
        default:
            feet = Self.color(fur.mixed(black, 0.08))
            nose = Self.color(fur.luminance < 0.3 ? fur.mixed(black, 0.55) : PetRGB(hex: 0x4E4248))
        }
        // The penguin's eyes sit on its white mask and the owl's on pale discs, so only the fur behind them matters.
        let faceIsDark = fur.luminance < 0.36 && species != .penguin && species != .owl
        ink = faceIsDark ? Self.color(PetRGB(hex: 0xF3EDF0)) : Tokens.Pet.eye
        eyeRim = faceIsDark
    }

    /// The dark appearance dims every colour a little, as the classic seal's hand-picked pairs do.
    private static func color(_ rgb: PetRGB) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let scale = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.83 : 1
            return NSColor(srgbRed: rgb.red * scale, green: rgb.green * scale, blue: rgb.blue * scale, alpha: 1)
        })
    }
}

/// An appearance resolved into colours, built once per render rather than per part.
struct PetLook {
    let appearance: PetAppearance
    let palette: PetPalette

    init(_ appearance: PetAppearance) {
        self.appearance = appearance
        palette = appearance.isClassicSeal ? .classic : PetPalette(appearance)
    }

    static let classic = PetLook(PetAppearance())

    var species: PetSpecies { appearance.species }
}

extension PetRGB {
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    func mixed(_ other: PetRGB, _ amount: Double) -> PetRGB {
        PetRGB(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount,
               blue: blue + (other.blue - blue) * amount)
    }
}
