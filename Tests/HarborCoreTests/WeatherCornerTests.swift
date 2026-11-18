import CoreGraphics
import Testing
@testable import HarborCore

@Suite struct WeatherCornerTests {
    @Test func windowLedgesStopShortOfRoundCorners() {
        let r = WeatherWorld.windowCornerRadius
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        let surfaces = [
            RoamSurface(kind: .window, y: 400, minX: 100, maxX: 500),
            // Cut short on the right by another window: only the left end is a corner.
            RoamSurface(kind: .window, y: 400, minX: 100, maxX: 300),
            RoamSurface(kind: .floor, y: 0, minX: 0, maxX: 1000),
        ]
        let trimmed = WeatherWorld.roundingCorners(surfaces, windows: [window])
        #expect(trimmed[0].minX == 100 + r && trimmed[0].maxX == 500 - r)
        #expect(trimmed[1].minX == 100 + r && trimmed[1].maxX == 300)
        #expect(trimmed[2] == surfaces[2])
    }

    @Test func aLedgeNarrowerThanBothCornersIsDropped() {
        let window = CGRect(x: 100, y: 100, width: 30, height: 300)
        let surfaces = [RoamSurface(kind: .window, y: 400, minX: 100, maxX: 130)]
        #expect(WeatherWorld.roundingCorners(surfaces, windows: [window]).isEmpty)
    }
}
