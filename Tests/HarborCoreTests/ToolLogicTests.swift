import Foundation
import Testing
@testable import HarborCore

@Suite struct ToolLogicTests {
    @Test func clamps() {
        #expect(ToolLogic.clamp(5, 1...3) == 3)
        #expect(ToolLogic.clamp(-1.0, 0...1) == 0)
        #expect(ClickerLogic.step(500) == 100)
        #expect(ClickerLogic.step(0) == 1)
        #expect(TimerLogic.minutes(999) == 180)
        #expect(MetronomeLogic.bpm(10) == 30)
        #expect(MetronomeLogic.beats(40) == 12)
        #expect(MetronomeLogic.volume(2) == 1)
        #expect(PetNeeds.cells(0) == 1)
    }

    @Test func clickerNeverGoesNegative() {
        #expect(ClickerLogic.next(count: 3, step: 5, increase: true) == 8)
        #expect(ClickerLogic.next(count: 3, step: 5, increase: false) == 0)
    }

    @Test func timerRemainingAndProgress() {
        let now = Date(timeIntervalSince1970: 1000)
        let end = now.addingTimeInterval(150)
        #expect(TimerLogic.remaining(end: end, now: now) == 150)
        #expect(TimerLogic.remaining(end: end, now: end.addingTimeInterval(5)) == 0)
        #expect(TimerLogic.progress(end: end, now: now, total: 300) == 0.5)
        #expect(TimerLogic.progress(end: end, now: now.addingTimeInterval(-1000), total: 300) == 1)
        #expect(TimerLogic.progress(end: end, now: now, total: 0) == 0)
    }

    @Test func timerClock() {
        #expect(TimerLogic.clock(300) == "05:00")
        #expect(TimerLogic.clock(0.2) == "00:01")
        #expect(TimerLogic.clock(0) == "00:00")
        #expect(TimerLogic.clock(3599.5) == "60:00")
    }

    @Test func beatInterval() {
        #expect(MetronomeLogic.beatInterval(bpm: 120) == 0.5)
        #expect(MetronomeLogic.beatInterval(bpm: 1) == 2)
    }

    @Test func tapTempoAveragesLastFour() {
        var tap = MetronomeLogic.TapTempo()
        #expect(tap.tap(at: 0) == nil)
        #expect(tap.tap(at: 0.5) == 120)
        #expect(tap.tap(at: 1.0) == 120)
        #expect(tap.tap(at: 1.5) == 120)
        // The first tap falls out of the window; the remaining gaps average 0.6 s.
        #expect(tap.tap(at: 2.3) == 100)
    }

    @Test func tapTempoResetsAfterPause() {
        var tap = MetronomeLogic.TapTempo()
        _ = tap.tap(at: 0)
        _ = tap.tap(at: 0.5)
        #expect(tap.tap(at: 10) == nil)
        #expect(tap.tap(at: 10.6) == 100)
    }

    @Test func petDecay() {
        let needs = PetNeeds(happiness: 50, hunger: 50, energy: 50)
        let later = needs.decayed(by: 180 * 10)
        #expect(abs(later.happiness - 40) < 0.0001)
        #expect(needs.decayed(by: 1_000_000).energy == 0)
        #expect(needs.decayed(by: -50) == needs)
    }

    @Test func petActionsClamp() {
        let full = PetNeeds(happiness: 98, hunger: 90, energy: 5)
        #expect(full.petted().happiness == 100)
        #expect(full.fed().hunger == 100)
        let played = full.played()
        #expect(played.happiness == 100)
        #expect(played.energy == 0)
    }
}
