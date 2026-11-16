import Foundation
import Testing
@testable import HarborCore

@Suite struct TimerScrollTests {
    let now = Date(timeIntervalSince1970: 1000)

    @Test func stepsAreOneMinuteOrFiveWithShift() {
        #expect(TimerScroll.adjusted(minutes: 10, steps: 1, shift: false) == 11)
        #expect(TimerScroll.adjusted(minutes: 10, steps: -2, shift: false) == 8)
        #expect(TimerScroll.adjusted(minutes: 10, steps: 1, shift: true) == 15)
        #expect(TimerScroll.adjusted(minutes: 10, steps: -1, shift: true) == 5)
    }

    @Test func durationIsClamped() {
        #expect(TimerScroll.adjusted(minutes: 2, steps: -5, shift: false) == 1)
        #expect(TimerScroll.adjusted(minutes: 178, steps: 5, shift: true) == 180)
    }

    @Test func runningTimerMovesByTheSameAmount() {
        let result = TimerScroll.shifted(end: now.addingTimeInterval(300), total: 600, now: now, byMinutes: 2)
        #expect(result.end == now.addingTimeInterval(420))
        #expect(result.total == 720)
    }

    @Test func remainingNeverDropsBelowFiveSeconds() {
        let result = TimerScroll.shifted(end: now.addingTimeInterval(90), total: 600, now: now, byMinutes: -10)
        #expect(result.end == now.addingTimeInterval(5))
        #expect(result.total >= 5)
    }
}
