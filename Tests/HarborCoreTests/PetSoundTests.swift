import Foundation
import Testing
@testable import HarborCore

@Suite struct PetSoundTests {
    @Test func everyTakeIsShortAndNeverClips() {
        for cue in PetSoundCue.allCases {
            for variant in 0..<PetSoundSynth.variants(for: cue) {
                let samples = PetSoundSynth.samples(for: cue, variant: variant)
                let peak = samples.reduce(0) { max($0, abs($1)) }
                #expect(!samples.isEmpty, "\(cue)")
                #expect(Double(samples.count) / PetSoundSynth.sampleRate <= 0.65, "\(cue)")
                #expect(peak <= 0.6, "\(cue)")
                #expect(abs(peak - PetSoundSynth.peak(for: cue)) < 0.001, "\(cue)")
                #expect(samples.allSatisfy { $0.isFinite }, "\(cue)")
            }
        }
    }

    @Test func takesFadeOutWithoutAClick() {
        for cue in PetSoundCue.allCases {
            let samples = PetSoundSynth.samples(for: cue)
            #expect(abs(samples.last ?? 1) < 0.01, "\(cue)")
        }
    }

    @Test func frequentCuesAreTheQuietest() {
        let step = PetSoundSynth.peak(for: .step)
        for cue in PetSoundCue.allCases where cue != .step && cue != .climb {
            #expect(PetSoundSynth.peak(for: cue) > step, "\(cue)")
        }
    }

    @Test func rendersAreRepeatable() {
        #expect(PetSoundSynth.samples(for: .slide) == PetSoundSynth.samples(for: .slide))
    }

    @Test func stepTakesDiffer() {
        #expect(PetSoundSynth.samples(for: .step, variant: 0) != PetSoundSynth.samples(for: .step, variant: 1))
    }

    // MARK: Gate

    /// Which of the timed plays a fresh gate lets through.
    private func admitted(_ plays: [(PetSoundCue, Double)]) -> [Bool] {
        var gate = PetSoundGate()
        return plays.map { gate.admit($0.0, at: $0.1) }
    }

    @Test func soundsTooCloseTogetherAreDropped() {
        #expect(admitted([(.hop, 0), (.grab, 0.03), (.grab, 0.1)]) == [true, false, true])
    }

    @Test func aCueWaitsOutItsOwnInterval() {
        #expect(admitted([(.purr, 0), (.purr, 2), (.purr, 3.1)]) == [true, false, true])
    }

    @Test func aLongWalkStaysSparse() {
        // Footfalls every 0.15 s for ten seconds.
        let played = admitted(stride(from: 0.0, to: 10, by: 0.15).map { (.step, $0) }).filter { $0 }.count
        #expect(played <= 16)
        #expect(played >= 8)
    }

    @Test func stepsLeaveRoomForMeaningfulSounds() {
        let steps: [(PetSoundCue, Double)] = stride(from: 0.0, to: 1.9, by: 0.3).map { (.step, $0) }
        #expect(admitted(steps + [(.chirp, 1.95)]).last == true)
    }

    @Test func burstsAreCapped() {
        let cues: [PetSoundCue] = [.hop, .land, .grab, .chirp, .startle, .slide, .sigh, .purr]
        let plays = cues.enumerated().map { ($0.element, Double($0.offset) * 0.1) }
        #expect(admitted(plays).filter { $0 }.count == PetSoundGate.maxPerWindow)
    }
}
