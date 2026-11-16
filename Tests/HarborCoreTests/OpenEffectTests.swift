import Foundation
import Testing
@testable import HarborCore

@Suite struct OpenEffectTests {
    @Test func everyEffectHasCopyAndSymbol() {
        for effect in OpenEffect.allCases {
            #expect(!effect.title.isEmpty)
            #expect(!effect.summary.isEmpty)
            #expect(!effect.symbolName.isEmpty)
        }
        #expect(Set(OpenEffect.allCases.map(\.title)).count == OpenEffect.allCases.count)
    }

    @Test func soundTableMatchesTheBrief() {
        let plop = OpenEffectSound.spec(for: .plop)
        #expect(plop.partials.first?.startHz == 420 && plop.partials.first?.endHz == 180 && plop.sweep == 0.09)
        #expect(OpenEffectSound.spec(for: .pop).partials.first?.startHz == 900)
        let bounce = OpenEffectSound.spec(for: .bounce)
        #expect(bounce.partials.first?.startHz == 260 && bounce.partials.first?.endHz == 520)
        #expect(OpenEffectSound.spec(for: .ripple).partials.map(\.startHz) == [660, 990])
        let wobble = OpenEffectSound.spec(for: .wobble)
        #expect(wobble.partials.first?.startHz == 400 && wobble.vibratoHz == 18)
        #expect(OpenEffectSound.spec(for: .glow).partials.first?.startHz == 520)
    }

    @Test func samplesAreShortAudibleAndWithinRange() {
        for effect in OpenEffect.allCases {
            let samples = OpenEffectSound.samples(for: effect)
            let seconds = Double(samples.count) / OpenEffectSound.sampleRate
            #expect(seconds > 0.05 && seconds <= 0.3)
            let peak = samples.map { abs($0) }.max() ?? 0
            #expect(peak > 0.5 && peak <= 0.81)
            #expect(abs(samples.last ?? 1) < 0.05)
        }
    }

    @Test func volumeIsClamped() {
        #expect(OpenEffectSound.volume(-1) == 0)
        #expect(OpenEffectSound.volume(2) == 1)
        #expect(OpenEffectSound.volume(0.3) == 0.3)
        #expect(OpenEffectSound.volume(.nan) == OpenEffectSound.defaultVolume)
    }

    @Test func settingsDefaultsAndTolerantDecoding() throws {
        let defaults = AppSettings()
        #expect(defaults.openAnimation && defaults.openEffect == .plop && !defaults.openSound && defaults.openSoundVolume == 0.5)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"openEffect":"nonsense","openSound":true}"#.utf8))
        #expect(old.openEffect == .plop)
        #expect(old.openSound)
        #expect(old.openAnimation)
    }
}
