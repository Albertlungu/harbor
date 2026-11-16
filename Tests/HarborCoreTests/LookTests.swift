import Foundation
import Testing
@testable import HarborCore

@Suite struct LookTests {
    @Test func contrastMatchesKnownValues() {
        #expect(abs(Contrast.ratio(0x000000, 0xFFFFFF) - 21) < 0.001)
        #expect(abs(Contrast.ratio(0x777777, 0xFFFFFF) - 4.48) < 0.01)
        #expect(Contrast.ratio(0xFFFFFF, 0xFFFFFF) == 1)
    }

    @Test(arguments: Palette.allCases)
    func accentIsLegibleOnEverySurface(palette: Palette) {
        for dark in [false, true] {
            for surface in PaletteSurfaces.all {
                let ratio = Contrast.ratio(palette.spec.accent.value(dark: dark), surface.value(dark: dark))
                #expect(ratio >= 4.5, "\(palette) accent, dark=\(dark): \(ratio)")
            }
        }
    }

    @Test(arguments: Palette.allCases)
    func categoryHuesStayVisible(palette: Palette) {
        for dark in [false, true] {
            for hue in palette.spec.categories {
                for surface in PaletteSurfaces.all {
                    #expect(Contrast.ratio(hue.value(dark: dark), surface.value(dark: dark)) >= 3, "\(palette) dark=\(dark)")
                }
            }
        }
    }

    @Test func monoIsGreysOnly() {
        let spec = Palette.mono.spec
        for pair in [spec.accent] + spec.categories {
            for hex in [pair.light, pair.dark] {
                // Allow a hair of blue so the greys sit with the cool surface tokens.
                let (r, g, b) = (Int(hex >> 16 & 0xFF), Int(hex >> 8 & 0xFF), Int(hex & 0xFF))
                #expect(max(r, g, b) - min(r, g, b) <= 12)
            }
        }
    }

    @Test func calmBundle() {
        var s = AppSettings()
        Personality.calm.apply(to: &s)
        #expect(s.personality == .calm && s.palette == .system)
        #expect(!s.categoryColors && !s.playfulCopy && !s.celebrations)
        #expect(!s.openAnimation && !s.openSound && !s.roundedType)
        #expect(s.petEnergy == .mellow)
    }

    @Test func balancedBundleIsTheDefault() {
        var s = AppSettings()
        Personality.calm.apply(to: &s)
        Personality.balanced.apply(to: &s)
        #expect(s == AppSettings())
        #expect(s.palette == .pastel && s.openEffect == .plop && s.openAnimation && !s.openSound)
    }

    @Test func playfulBundle() {
        var s = AppSettings()
        Personality.playful.apply(to: &s)
        #expect(s.palette == .sunset && s.paletteGlass && s.categoryColors && s.playfulCopy && s.celebrations)
        #expect(s.openAnimation && s.openSound && s.openSoundVolume == 0.4 && s.roundedType)
        #expect(s.petEnergy == .lively)
    }

    @Test func settingsCanDriftFromTheBundle() {
        var s = AppSettings()
        Personality.playful.apply(to: &s)
        s.palette = .forest
        #expect(s.personality == .playful && s.palette == .forest)
    }

    @Test func oldConfigsDecodeWithDefaults() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"launchAtLogin":true,"palette":"nonsense"}"#.utf8))
        #expect(s.launchAtLogin && s.palette == .pastel && s.personality == .balanced && s.petEnergy == .normal && !s.petQuiet)
    }

    @Test func newSettingsRoundTrip() throws {
        var s = AppSettings()
        Personality.playful.apply(to: &s)
        s.petQuiet = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func confettiCountAndDeterminism() {
        for count in [1, 32, 99] {
            let n = Confetti.burst(count: count).count
            #expect((24...40).contains(n))
        }
        #expect(Confetti.burst(seed: 7) == Confetti.burst(seed: 7))
        #expect(Confetti.burst(seed: 7) != Confetti.burst(seed: 8))
    }

    @Test func confettiRisesThenFallsAndFades() {
        let p = Confetti.burst(seed: 3)[0]
        let start = Confetti.pose(of: p, at: 0)
        #expect(start.opacity == 1 && start.y == p.y0)
        // Launched upward, so it is above the origin shortly after, and below it once gravity wins.
        #expect(Confetti.pose(of: p, at: 0.1).y < 0)
        #expect(Confetti.pose(of: p, at: Confetti.lifetime).y > 0)
        #expect(Confetti.pose(of: p, at: Confetti.holdDuration).opacity == 1)
        #expect(Confetti.pose(of: p, at: Confetti.lifetime).opacity == 0)
        #expect(Confetti.fadeDuration == 1.2)
        #expect(Confetti.pose(of: p, at: 0.5).angle != start.angle || p.spin == 0)
    }
}
