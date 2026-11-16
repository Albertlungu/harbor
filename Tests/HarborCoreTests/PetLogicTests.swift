import Foundation
import Testing
@testable import HarborCore

@Suite struct PetLogicTests {
    private func context(needs: PetNeeds = PetNeeds(), bond: Double = 0, idle: Double = 0, hour: Int = 14,
                         hover: Double = 0, streak: Int = 0) -> PetContext {
        PetContext(needs: needs, bond: bond, idle: idle, hour: hour, hover: hover, clickStreak: streak)
    }

    @Test func expressionFromNeeds() {
        #expect(PetLogic.expression(context()) == .calm)
        #expect(PetLogic.expression(context(needs: PetNeeds(happiness: 95), bond: 80)) == .happy)
        #expect(PetLogic.expression(context(needs: PetNeeds(happiness: 95), bond: 5)) == .proud)
        #expect(PetLogic.expression(context(needs: PetNeeds(happiness: 95, hunger: 10, energy: 10))) == .hungry)
        #expect(PetLogic.expression(context(needs: PetNeeds(happiness: 95, energy: 10))) == .sleepy)
        #expect(PetLogic.expression(context(needs: PetNeeds(happiness: 95, hunger: 40), bond: 80)) == .calm)
    }

    @Test func hoverWalksFromCuriousToShyToWarm() {
        #expect(PetLogic.expression(context(hover: 0.4)) == .curious)
        #expect(PetLogic.expression(context(hover: 2)) == .shy)
        #expect(PetLogic.expression(context(bond: 50, hover: 6)) == .happy)
        #expect(PetLogic.expression(context(bond: 0, hover: 6)) == .proud)
    }

    @Test func clickStreakExcitesButNeverOverridesSleep() {
        #expect(PetLogic.expression(context(streak: 2)) == .excited)
        #expect(PetLogic.expression(context(streak: 1)) == .calm)
        #expect(PetLogic.expression(context(idle: 500, streak: 2)) == .asleep)
    }

    @Test func boredomThenYawnThenNap() {
        #expect(PetLogic.expression(context(idle: 10)) == .calm)
        #expect(PetLogic.expression(context(idle: PetLogic.boredAfter)) == .sleepy)
        #expect(PetLogic.shouldYawn(idle: 90, hour: 14))
        #expect(!PetLogic.shouldYawn(idle: 40, hour: 14))
        #expect(!PetLogic.shouldYawn(idle: 100, hour: 14))
        #expect(PetLogic.expression(context(idle: 100)) == .asleep)
    }

    @Test func hungerOutranksTiredness() {
        let needs = PetNeeds(hunger: 10, energy: 10)
        #expect(PetLogic.expression(context(needs: needs)) == .hungry)
    }

    @Test func morningIsGroggy() {
        #expect(PetLogic.expression(context(idle: 12, hour: 7)) == .sleepy)
        #expect(PetLogic.expression(context(idle: 12, hour: 14)) == .calm)
    }

    @Test func everyExpressionHasAFace() {
        for expression in PetExpression.allCases { _ = expression.face }
        #expect(PetExpression.curious.face.tilt >= 8 && PetExpression.curious.face.tilt <= 10)
        #expect(PetExpression.asleep.face.eyes == .arcDown)
        #expect(PetExpression.hungry.face.gaze == .down)
        #expect(PetExpression.shy.face.blush > PetExpression.calm.face.blush)
    }

    @Test func napThresholdFollowsTheClock() {
        #expect(PetLogic.napDelay(hour: 12) > PetLogic.napDelay(hour: 17))
        #expect(PetLogic.napDelay(hour: 17) > PetLogic.napDelay(hour: 7))
        #expect(PetLogic.napDelay(hour: 23) == PetLogic.napDelay(hour: 0))
        #expect(PetLogic.napDelay(hour: 5) < PetLogic.napDelay(hour: 7))
        #expect(PetLogic.napDelay(hour: 6) == PetLogic.napDelay(hour: 8))
        #expect(PetLogic.napDelay(hour: 22) == PetLogic.napDelay(hour: 17))
        #expect(!PetLogic.shouldSleep(idle: 30, hour: 12))
        #expect(PetLogic.shouldSleep(idle: 40, hour: 2))
        #expect(!PetLogic.shouldSleep(idle: 39, hour: 2))
    }

    @Test func bondRisesAndStaysInRange() {
        #expect(PetLogic.bond(10, afterPetting: true) == 12)
        #expect(PetLogic.bond(10, afterPetting: false) == 14)
        #expect(PetLogic.bond(99, afterPetting: false) == 100)
    }

    @Test func bondDecaysSlowlyOverDays() {
        #expect(PetLogic.decayedBond(50, elapsed: 3600) > 49.9)
        #expect(abs(PetLogic.decayedBond(50, elapsed: 86_400) - (50 - PetLogic.bondDecayPerDay)) < 1e-9)
        #expect(PetLogic.decayedBond(1, elapsed: 86_400 * 30) == 0)
        #expect(PetLogic.decayedBond(50, elapsed: -100) == 50)
    }

    @Test func hoverHeartNeedsBond() {
        #expect(!PetLogic.showsHoverHeart(bond: 10))
        #expect(PetLogic.showsHoverHeart(bond: 80))
    }

    @Test func idleNeverRepeatsTheLastOne() {
        for previous in PetIdle.allCases {
            for step in 0..<200 {
                let pick = PetLogic.pickIdle(previous: previous, bond: 50, hour: 14, roll: Double(step) / 200)
                #expect(pick != previous)
            }
        }
    }

    @Test func idleSelectionIsWeighted() {
        var counts: [PetIdle: Int] = [:]
        for step in 0..<1000 {
            counts[PetLogic.pickIdle(previous: nil, bond: 50, hour: 14, roll: Double(step) / 1000), default: 0] += 1
        }
        #expect(PetIdle.allCases.allSatisfy { counts[$0, default: 0] > 0 })
        #expect(counts[.lookAround, default: 0] > counts[.chaseTail, default: 0] * 5)
    }

    @Test func bondTiltsIdlesTowardHappyOnes() {
        let low = PetLogic.idleWeight(.wave, bond: 0, hour: 14)
        let high = PetLogic.idleWeight(.wave, bond: 100, hour: 14)
        #expect(high > low * 3)
        #expect(PetLogic.idleWeight(.yawn, bond: 50, hour: 7) > PetLogic.idleWeight(.yawn, bond: 50, hour: 14))
    }

    @Test func idleDelayTightensAtMidday() {
        #expect(PetLogic.idleDelay(hour: 14, roll: 0) == 4)
        #expect(PetLogic.idleDelay(hour: 18, roll: 0) == 5)
        #expect(PetLogic.idleDelay(hour: 18, roll: 1) == 10)
    }

    @Test func blinkGapsAreJitteredWithinRange() {
        let shortest = PetLogic.blinkPlan(delayRoll: 0, doubleRoll: 0.5)
        let longest = PetLogic.blinkPlan(delayRoll: 1, doubleRoll: 0.5)
        #expect(shortest.delay == 2.5)
        #expect(longest.delay == 6)
        #expect(!shortest.double)
        #expect(PetLogic.blinkPlan(delayRoll: 0.5, doubleRoll: 0.05).double)
        #expect(PetLogic.blinkDuration == 0.13)
    }

    @Test func surprisesAreRare() {
        #expect(PetLogic.surpriseProbability(visibleFor: 0) == 0)
        let perTick = PetLogic.surpriseProbability(visibleFor: 5)
        #expect(perTick > 0 && perTick < 0.002)
        #expect(Set((0..<30).map { PetSurprise.pick(roll: Double($0) / 30) }).count == 3)
        #expect(PetSurprise.pick(roll: 1) == .gift)
    }

    @Test func breathingInhalesSlowerThanItExhales() {
        #expect(PetMotion.breath(at: 0) == 0)
        let peak = PetMotion.breath(at: PetMotion.breathPeriod * PetMotion.inhaleShare)
        #expect(abs(peak - 1) < 1e-9)
        #expect(PetMotion.breath(at: PetMotion.breathPeriod) < 1e-9)
        let quarterInhale = PetMotion.breathPeriod * PetMotion.inhaleShare / 2
        #expect(abs(PetMotion.breath(at: quarterInhale) - 0.5) < 1e-9)
        #expect(PetMotion.inhaleShare > 0.5)
    }

    @Test func springOvershootsThenSettles() {
        #expect(PetMotion.spring(0) == 0)
        let peak = (1..<100).map { PetMotion.spring(Double($0) * 0.01) }.max() ?? 0
        #expect(peak > 1)
        #expect(abs(PetMotion.spring(3) - 1) < 1e-3)
        #expect(abs(PetMotion.spring(5, damping: 1) - 1) < 1e-3)
    }

    @Test func hopSquatsThenLeapsThenSettles() {
        #expect(PetMotion.hop(elapsed: 0).lift == 0)
        #expect(PetMotion.hop(elapsed: PetMotion.hopAnticipation - 0.001).squash > 0.1)
        let apex = PetMotion.hop(elapsed: PetMotion.hopAnticipation + PetMotion.hopAir / 2)
        #expect(abs(apex.lift - 1) < 1e-9)
        #expect(apex.squash < 0)
        let landed = PetMotion.hop(elapsed: PetMotion.hopAnticipation + PetMotion.hopAir + 0.02)
        #expect(landed.lift == 0 && landed.squash > 0)
        #expect(abs(PetMotion.hop(elapsed: PetMotion.hopDuration + 1).squash) < 0.01)
    }

    @Test func rapidTapsTriggerOnce() {
        var tracker = PetTapTracker()
        let r0 = tracker.tap(at: 0); #expect(!r0)
        let r0_5 = tracker.tap(at: 0.5); #expect(!r0_5)
        let r1_0 = tracker.tap(at: 1.0); #expect(r1_0)
        let r1_2 = tracker.tap(at: 1.2); #expect(!r1_2)
    }

    @Test func slowTapsDoNotTrigger() {
        var tracker = PetTapTracker()
        let r0 = tracker.tap(at: 0); #expect(!r0)
        let r1 = tracker.tap(at: 1); #expect(!r1)
        let r2 = tracker.tap(at: 2); #expect(!r2)
        let r3 = tracker.tap(at: 3); #expect(!r3)
        let r4 = tracker.tap(at: 4); #expect(!r4)
    }

    @Test func streakCountsRecentTaps() {
        var tracker = PetTapTracker()
        _ = tracker.tap(at: 0)
        _ = tracker.tap(at: 0.5)
        #expect(tracker.streak(at: 0.6) == 2)
        #expect(tracker.streak(at: 3) == 0)
    }

    @Test func gazeStaysInsideTheEye() throws {
        let far = try #require(PetLogic.gaze(dx: 500, dy: 0))
        #expect(far == PetVector(x: 1, y: 0))
        let near = try #require(PetLogic.gaze(dx: 30, dy: 0))
        #expect(abs(near.x - 0.25) < 1e-9)
        let diagonal = try #require(PetLogic.gaze(dx: 300, dy: -300))
        #expect(diagonal.x * diagonal.x + diagonal.y * diagonal.y <= 1 + 1e-9)
        #expect(PetLogic.gaze(dx: 0, dy: 0) == .zero)
    }

    @Test func gazeStopsBeyondRange() {
        #expect(PetLogic.gaze(dx: 601, dy: 0) == nil)
        #expect(PetLogic.gaze(dx: 500, dy: 500) == nil)
        #expect(PetLogic.gaze(dx: 600, dy: 0) != nil)
    }

    @Test func clampPullsVectorIntoDisc() {
        #expect(PetLogic.clampGaze(PetVector(x: 3, y: 4)) == PetVector(x: 0.6, y: 0.8))
        #expect(PetLogic.clampGaze(PetVector(x: 0.3, y: 0.2)) == PetVector(x: 0.3, y: 0.2))
    }

    @Test func feedingRaisesHungerOnly() {
        let fed = PetLogic.fed(PetNeeds(happiness: 50, hunger: 40, energy: 30))
        #expect(fed == PetNeeds(happiness: 50, hunger: 60, energy: 30))
        #expect(PetLogic.fed(PetNeeds(hunger: 95)).hunger == 100)
    }
}
