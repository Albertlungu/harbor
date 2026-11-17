import Foundation
import Testing
@testable import HarborCore

@Suite struct AmbientEffectTests {
    private func style(_ json: String) throws -> DockStyle {
        try JSONDecoder().decode(DockStyle.self, from: Data(json.utf8))
    }

    @Test func oldEffectsStillDecode() throws {
        #expect(try style(#"{"effects":["snow","fireworks"]}"#).effects == [.snow, .fireworks])
    }

    @Test func unknownEffectDropsOutAlone() throws {
        let decoded = try style(#"{"effects":["rays","glitter-cannon","petals"],"effectIntensity":0.8}"#)
        #expect(decoded.effects == [.rays, .petals])
        #expect(decoded.effectIntensity == 0.8)
    }

    @Test func malformedEffectsFallBackToNone() throws {
        #expect(try style(#"{"effects":"snow"}"#).effects.isEmpty)
    }

    @Test func effectsRoundTrip() throws {
        var s = DockStyle()
        s.effects = Set(EffectKind.allCases)
        let back = try JSONDecoder().decode(DockStyle.self, from: JSONEncoder().encode(s))
        #expect(back.effects == s.effects)
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    @Test(arguments: [
        (1, 15, EffectKind.snow), (4, 10, .petals), (7, 20, .fireflies), (10, 5, .leaves),
        (12, 31, .fireworks), (1, 1, .fireworks), (2, 14, .hearts), (2, 15, .snow), (11, 30, .leaves), (12, 1, .snow),
    ])
    func seasonalPicksByDate(month: Int, day: Int, expected: EffectKind) {
        #expect(EffectKind.seasonal(on: date(month, day), calendar: utc) == expected)
    }

    @Test func resolveSwapsOnlySeasonal() {
        #expect(EffectKind.resolve([.seasonal, .stars], on: date(4, 1), calendar: utc) == [.petals, .stars])
        #expect(EffectKind.resolve([.rain], on: date(4, 1), calendar: utc) == [.rain])
    }

    @Test func hashIsStableAndInRange() {
        for i in 0..<500 {
            let v = EffectMath.hash(Double(i))
            #expect(v >= 0 && v < 1)
            #expect(v == EffectMath.hash(Double(i)))
        }
    }

    @Test func travelWrapsWithinMargins() {
        for i in 0..<50 {
            let p = EffectMath.travel(seed: 3, t: Double(i) * 0.73, speed: 20, span: 60, margin: 5)
            #expect(p >= -5 && p < 65)
        }
        let a = EffectMath.travel(seed: 1, t: 0, speed: 10, span: 100)
        let b = EffectMath.travel(seed: 1, t: 1, speed: 10, span: 100)
        #expect(abs(EffectMath.fract((b - a) / 100) - 0.1) < 1e-9)
    }

    @Test func daylightFollowsTheSun() {
        #expect(EffectMath.daylight(hour: 0) == 0)
        #expect(EffectMath.daylight(hour: 3) == 0)
        #expect(EffectMath.daylight(hour: 12) == 1)
        let dawn = EffectMath.daylight(hour: 6)
        #expect(dawn > 0.3 && dawn < 0.7)
        #expect(EffectMath.daylight(hour: 9) > EffectMath.daylight(hour: 6.5))
        #expect(EffectMath.daylight(hour: 24) == EffectMath.daylight(hour: 0))
    }

    @Test func trailSpacesAndExpiresMarks() {
        var trail = PointerTrail(spacing: 4, lifetime: 1)
        trail.record(10, at: 0)
        trail.record(12, at: 0.1)
        trail.record(20, at: 0.2)
        #expect(trail.marks.map(\.position) == [10, 20])
        #expect(trail.live(at: 0.5).count == 2)
        #expect(trail.live(at: 1.1).map(\.mark.position) == [20])
        trail.record(40, at: 1.5)
        #expect(trail.marks.map(\.position) == [40])
    }
}
