import Testing
@testable import HarborCore

@Suite struct MetronomeTests {
    @Test func firstTapIsNotTempo() {
        var seq = MetronomeInput.TapSequence()
        let result = seq.tap(at: 10)
        #expect(result.count == 1)
        #expect(!result.isTempo)
    }

    @Test func secondTapWithinWindowSetsTempo() {
        var seq = MetronomeInput.TapSequence()
        _ = seq.tap(at: 10)
        let result = seq.tap(at: 10.5)
        #expect(result.count == 2)
        #expect(result.bpm == 120)
    }

    @Test func gapPastWindowStartsOver() {
        var seq = MetronomeInput.TapSequence()
        _ = seq.tap(at: 10)
        let result = seq.tap(at: 11.6)
        #expect(result.count == 1)
        #expect(!result.isTempo)
    }

    @Test func gapExactlyAtWindowStillCounts() {
        var seq = MetronomeInput.TapSequence()
        _ = seq.tap(at: 0)
        #expect(seq.tap(at: 1.5).bpm == 40)
    }

    @Test func averagesLastFourTaps() {
        var seq = MetronomeInput.TapSequence()
        // The slow first gap falls out of the four-tap window.
        for time in [0, 1.4, 1.9, 2.4, 2.9] { _ = seq.tap(at: time) }
        #expect(seq.tap(at: 3.4).bpm == 120)
    }

    @Test func tempoIsClamped() {
        var fast = MetronomeInput.TapSequence()
        _ = fast.tap(at: 0)
        #expect(fast.tap(at: 0.05).bpm == 300)
        var slow = MetronomeInput.TapSequence()
        _ = slow.tap(at: 0)
        #expect(slow.tap(at: 1.5).bpm == 40)
        #expect(MetronomeInput.TapSequence.bpm(from: [0, 3]) == 30)
    }

    @Test func identicalTimestampsGiveNoTempo() {
        #expect(MetronomeInput.TapSequence.bpm(from: [1, 1]) == nil)
    }

    @Test func preciseScrollAccumulatesToSteps() {
        var acc = MetronomeInput.ScrollAccumulator()
        #expect(acc.add(delta: 3, precise: true) == 0)
        #expect(acc.add(delta: 3, precise: true) == 0)
        #expect(acc.add(delta: 3, precise: true) == 1)
        #expect(acc.add(delta: 16, precise: true) == 2)
    }

    @Test func preciseScrollDownGivesNegativeSteps() {
        var acc = MetronomeInput.ScrollAccumulator()
        #expect(acc.add(delta: -17, precise: true) == -2)
        #expect(acc.add(delta: -7, precise: true) == -1)
    }

    @Test func wheelNotchIsOneStep() {
        var acc = MetronomeInput.ScrollAccumulator()
        #expect(acc.add(delta: 1, precise: false) == 1)
        #expect(acc.add(delta: -1, precise: false) == -1)
        #expect(acc.add(delta: 0.4, precise: false) == 0)
        #expect(acc.add(delta: 0.7, precise: false) == 1)
    }

    @Test func switchingDeviceDropsRemainder() {
        var acc = MetronomeInput.ScrollAccumulator()
        _ = acc.add(delta: 6, precise: true)
        #expect(acc.add(delta: 0.3, precise: false) == 0)
    }

    @Test func adjustedClampsAndHonorsShift() {
        #expect(MetronomeInput.adjusted(bpm: 100, steps: 3, shift: false) == 103)
        #expect(MetronomeInput.adjusted(bpm: 100, steps: -2, shift: true) == 90)
        #expect(MetronomeInput.adjusted(bpm: 298, steps: 1, shift: true) == 300)
        #expect(MetronomeInput.adjusted(bpm: 32, steps: -1, shift: true) == 30)
    }
}
