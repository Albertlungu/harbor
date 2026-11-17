import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

@Suite struct RoamAttentionLogicTests {
    private func signal(_ reason: RoamAttentionReason, _ x: Double, _ y: Double = 500) -> RoamAttentionSignal {
        RoamAttentionSignal(reason: reason, point: CGPoint(x: x, y: y))
    }

    /// Offers with dice that always return `dice`; low dice notice everything, high dice ignore mild signals.
    @discardableResult
    private func offer(_ s: RoamAttentionSignal, at now: Double, _ state: inout RoamAttentionState,
                       dice: Double = 0) -> Bool {
        RoamAttentionLogic.offer(s, at: now, state: &state, roll: { dice })
    }

    // MARK: Noticing

    @Test func firstSignalIsNoticed() {
        var state = RoamAttentionState()
        #expect(offer(signal(.caret, 100), at: 0, &state))
        #expect(state.focus == signal(.caret, 100))
    }

    @Test func mildSignalsCanBeIgnoredByTheDice() {
        var state = RoamAttentionState()
        // A dwell pulls 0.45 plus 0.25 curiosity; a roll of 0.8 misses it.
        #expect(!offer(signal(.dwell, 100), at: 0, &state, dice: 0.8))
        #expect(state.focus == nil)
        #expect(offer(signal(.banner, 100), at: 0, &state, dice: 0.99))
    }

    @Test func urgentThingsOutrankCalmOnes() {
        let order: [RoamAttentionReason] = [.banner, .menu, .window, .caret, .typing, .dwell]
        let priorities = order.map(RoamAttentionLogic.priority)
        #expect(priorities == priorities.sorted(by: >))
        #expect(RoamAttentionLogic.priority(.bored) == 0)
    }

    @Test func boredIsNeverOffered() {
        var state = RoamAttentionState()
        #expect(!offer(signal(.bored, 100), at: 0, &state))
    }

    // MARK: Switching

    @Test func strongerSignalTakesOverAfterTheHold() {
        var state = RoamAttentionState()
        offer(signal(.dwell, 100), at: 0, &state)
        #expect(!offer(signal(.menu, 600), at: 0.3, &state))
        #expect(offer(signal(.menu, 600), at: 1, &state))
        #expect(state.focus?.reason == .menu)
    }

    @Test func bannerInterruptsImmediately() {
        var state = RoamAttentionState()
        offer(signal(.window, 100), at: 0, &state)
        #expect(offer(signal(.banner, 900, 1300), at: 0.1, &state))
        #expect(state.focus?.reason == .banner)
    }

    @Test func weakerSignalDoesNotStealAFreshFocus() {
        var state = RoamAttentionState()
        offer(signal(.menu, 100), at: 0, &state)
        #expect(!offer(signal(.dwell, 700), at: 1, &state))
        #expect(state.focus?.reason == .menu)
    }

    @Test func fadingFocusLetsWeakerSignalsIn() {
        var state = RoamAttentionState()
        offer(signal(.menu, 100), at: 0, &state)
        let late = state.boredAt - 0.1
        #expect(offer(signal(.dwell, 700), at: late, &state))
    }

    // MARK: Following

    @Test func movingCaretIsFollowedNotSwitched() {
        var state = RoamAttentionState()
        offer(signal(.caret, 100), at: 0, &state)
        let since = state.boredAt
        #expect(offer(signal(.caret, 130), at: 0.2, &state, dice: 0.99))
        #expect(state.focus?.point.x == 130)
        #expect(state.boredAt == since)
    }

    @Test func typingAndCaretAtTheSameSpotAreOneThing() {
        var state = RoamAttentionState()
        offer(signal(.caret, 100), at: 0, &state)
        #expect(offer(signal(.typing, 150), at: 0.1, &state, dice: 0.99))
        #expect(state.focus?.reason == .typing)
    }

    @Test func tinyMovesAreNotRepublished() {
        var state = RoamAttentionState()
        offer(signal(.caret, 100), at: 0, &state)
        #expect(!offer(signal(.caret, 101), at: 0.1, &state))
    }

    @Test func distantCaretIsANewThing() {
        var state = RoamAttentionState()
        offer(signal(.caret, 100), at: 0, &state)
        #expect(!offer(signal(.caret, 900), at: 0.2, &state))
    }

    // MARK: Boredom and novelty

    @Test func focusTurnsBoring() {
        var state = RoamAttentionState()
        offer(signal(.window, 100), at: 0, &state)
        #expect(!RoamAttentionLogic.tick(at: state.boredAt - 0.01, state: &state))
        #expect(RoamAttentionLogic.tick(at: state.boredAt, state: &state))
        #expect(state.focus == nil)
        #expect(!RoamAttentionLogic.tick(at: state.boredAt + 5, state: &state))
    }

    @Test func boredomRestsBeforeTheNextLook() {
        var state = RoamAttentionState()
        offer(signal(.window, 100), at: 0, &state)
        let bored = state.boredAt
        RoamAttentionLogic.tick(at: bored, state: &state)
        #expect(!offer(signal(.menu, 800), at: bored + 0.5, &state))
        #expect(offer(signal(.banner, 800), at: bored + 0.5, &state))
    }

    @Test func attentionSpanGrowsWithInterestAndDice() {
        var calm = RoamAttentionState()
        var urgent = RoamAttentionState()
        offer(signal(.dwell, 100), at: 0, &calm)
        offer(signal(.banner, 100), at: 0, &urgent)
        #expect(urgent.boredAt > calm.boredAt)
        var lucky = RoamAttentionState()
        offer(signal(.dwell, 100), at: 0, &lucky, dice: 0.1)
        #expect(lucky.boredAt > calm.boredAt)
    }

    @Test func recentPlacesLoseTheirPull() {
        var state = RoamAttentionState()
        let spot = signal(.window, 100).point
        #expect(RoamAttentionLogic.novelty(of: spot, at: 0, state: state) == 1)
        offer(signal(.window, 100), at: 0, &state)
        let once = RoamAttentionLogic.novelty(of: spot, at: 1, state: state)
        #expect(once < 1)
        #expect(RoamAttentionLogic.novelty(of: CGPoint(x: 900, y: 500), at: 1, state: state) == 1)
        #expect(RoamAttentionLogic.novelty(of: spot, at: RoamAttentionLogic.memory + 0.1, state: state) == 1)
    }

    @Test func staleSpotIsIgnoredWhileANewOneIsNot() {
        var state = RoamAttentionState()
        var now = 0.0
        // Look at the same spot three times, growing bored in between.
        for _ in 0..<3 {
            offer(signal(.window, 100), at: now, &state)
            now = state.boredAt
            RoamAttentionLogic.tick(at: now, state: &state)
            now += RoamAttentionLogic.rest
        }
        #expect(!offer(signal(.window, 100), at: now, &state, dice: 0.3))
        #expect(offer(signal(.window, 800), at: now, &state, dice: 0.3))
    }
}
