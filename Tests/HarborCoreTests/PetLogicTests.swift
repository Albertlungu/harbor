import Foundation
import Testing
@testable import HarborCore

@Suite struct PetLogicTests {
    @Test func moodFromNeeds() {
        #expect(PetLogic.mood(for: PetNeeds(happiness: 80, hunger: 80, energy: 80)) == .content)
        #expect(PetLogic.mood(for: PetNeeds(happiness: 95, hunger: 80, energy: 80)) == .happy)
        #expect(PetLogic.mood(for: PetNeeds(happiness: 95, hunger: 10, energy: 10)) == .hungry)
        #expect(PetLogic.mood(for: PetNeeds(happiness: 95, hunger: 80, energy: 10)) == .sleepy)
        #expect(PetLogic.mood(for: PetNeeds(happiness: 95, hunger: 40, energy: 80)) == .content)
    }

    @Test func nightNapsSooner() {
        #expect(PetLogic.napDelay(hour: 14) == 120)
        #expect(PetLogic.napDelay(hour: 22) == 120)
        #expect(PetLogic.napDelay(hour: 23) == PetLogic.nightNapDelay)
        #expect(PetLogic.napDelay(hour: 0) == PetLogic.nightNapDelay)
        #expect(PetLogic.napDelay(hour: 5) == PetLogic.nightNapDelay)
        #expect(PetLogic.napDelay(hour: 6) == 120)
        #expect(!PetLogic.shouldSleep(idle: 60, hour: 12))
        #expect(PetLogic.shouldSleep(idle: 120, hour: 12))
        #expect(PetLogic.shouldSleep(idle: 60, hour: 2))
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
