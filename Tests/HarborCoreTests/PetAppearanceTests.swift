import Foundation
import Testing
@testable import HarborCore

@Suite struct PetAppearanceTests {
    @Test func oldConfigWithoutAppearanceKeysIsTheClassicSeal() throws {
        let json = #"{"type":"pet","settings":{"name":"Pup","cells":1,"needs":true},"state":{"happiness":80}}"#
        let widget = try JSONDecoder().decode(WidgetConfig.self, from: Data(json.utf8))
        let look = PetAppearance(widget)
        #expect(look == PetAppearance())
        #expect(look.species == .seal)
        #expect(look.pattern == .belly)
        #expect(look.eyes == .round)
        #expect(look.accessory == .none)
        #expect(look.isClassicSeal)
    }

    @Test func roundTripsThroughSettings() {
        let look = PetAppearance(species: .fox, color: .custom(PetRGB(red: 0.2, green: 0.4, blue: 0.6)),
                                 pattern: .stripes, eyes: .sparkly, accessory: .flowerCrown)
        var widget = WidgetConfig(kind: .pet)
        for (key, value) in look.settings { widget.settings[key] = value }
        #expect(PetAppearance(widget) == look)

        let swatched = PetAppearance(species: .owl, color: .swatch("snowy"))
        for (key, value) in swatched.settings { widget.settings[key] = value }
        #expect(widget.settings["customColor"] == nil)
        #expect(PetAppearance(widget) == swatched)
    }

    @Test func unknownValuesFallBack() {
        var widget = WidgetConfig(kind: .pet)
        widget.settings = ["species": .string("dragon"), "pattern": .string("plaid"), "color": .string("ginger")]
        #expect(PetAppearance(widget) == PetAppearance())
        widget.settings = ["species": .string("dog"), "color": .string("ginger")]
        #expect(PetAppearance(widget).color == .swatch("golden"))
    }

    @Test func everySpeciesHasDistinctSwatches() {
        for species in PetSpecies.allCases {
            #expect(!species.swatches.isEmpty)
            #expect(Set(species.swatches.map(\.id)).count == species.swatches.count)
            #expect(PetAppearance(species: species).color == .swatch(species.swatches[0].id))
        }
        #expect(PetAppearance(species: .cat).fur == PetRGB(hex: 0xF2B37A))
    }

    @Test func randomStaysWithinTheOptions() {
        let low = PetAppearance.random { 0 }
        #expect(low == PetAppearance(species: .seal, pattern: .plain))
        let high = PetAppearance.random { 0.9999 }
        #expect(high.species == PetSpecies.allCases.last)
        #expect(high.accessory == PetAccessory.allCases.last)
        #expect(high.color == .swatch(high.species.swatches.last!.id))
    }

    @Test func strideRateScalesWithSpeedWithinLimits() {
        #expect(PetGait.strideRate(speed: 0, unit: 32) == 0)
        let slow = PetGait.strideRate(speed: 20, unit: 32)
        let fast = PetGait.strideRate(speed: 45, unit: 32)
        #expect(fast > slow)
        #expect(PetGait.strideRate(speed: 1000, unit: 32) == 4.5)
        #expect(PetGait.strideRate(speed: 1, unit: 32) == 1.2)
    }

    @Test func footLiftsOnlyWhileSwingingForward() {
        let start = PetGait.foot(phase: 0)
        let mid = PetGait.foot(phase: .pi / 2)
        let end = PetGait.foot(phase: .pi)
        let planted = PetGait.foot(phase: 1.5 * .pi)
        #expect(start.x < 0 && end.x > 0)
        #expect(mid.y < 0)
        #expect(planted.y == 0)
    }

    @Test func turnEasesBetweenTargets() {
        #expect(PetGait.turn(from: 1, to: -1, elapsed: 0) == 1)
        #expect(abs(PetGait.turn(from: 1, to: -1, elapsed: 0.14)) < 1e-9)
        #expect(PetGait.turn(from: 1, to: -1, elapsed: 5) == -1)
    }
}
