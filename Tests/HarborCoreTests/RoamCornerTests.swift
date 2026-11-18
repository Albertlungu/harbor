import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

/// Keeping the pet out of the screen's masked round corners.
@Suite struct RoamCornerTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let half = 16.0

    private func surfaces(menuBar: Double, windows: [RoamWindow] = []) -> [RoamSurface] {
        RoamSurfaces.build(screen: screen, menuBarHeight: menuBar, windows: windows, docks: [], walkOnWindows: true)
    }

    @Test func noCornersLeavesEverything() {
        let built = surfaces(menuBar: 24)
        #expect(RoamSurfaces.avoiding(.none, screen: screen, half: half, surfaces: built) == built)
    }

    @Test func bottomCornersShortenTheFloorOnly() {
        let corners = RoamCorners(radius: 14, bottom: true, top: false)
        let result = RoamSurfaces.avoiding(corners, screen: screen, half: half, surfaces: surfaces(menuBar: 24))
        let floor = try! #require(result.first { $0.kind == .floor })
        #expect(floor.minX == 14 && floor.maxX == 986)
        let menu = try! #require(result.first { $0.kind == .menuBar })
        #expect(menu.minX == 0 && menu.maxX == 1000)
    }

    @Test func aLargeRadiusStillLeavesFloorUnderAScreenSide() {
        let corners = RoamCorners(radius: 40, bottom: true, top: false)
        let result = RoamSurfaces.avoiding(corners, screen: screen, half: half, surfaces: surfaces(menuBar: 24))
        let floor = try! #require(result.first { $0.kind == .floor })
        // A pet dropping off the left side has its feet at the screen edge plus half its width.
        #expect(floor.contains(x: screen.minX + half) && floor.contains(x: screen.maxX - half))
    }

    @Test func topCornersShortenTheTopEdge() {
        let corners = RoamCorners(radius: 14, bottom: true, top: true)
        let ceilings = RoamSurfaces.ceilings(screen: screen, menuBarHeight: 0, windows: [], walkOnWindows: true)
        let top = try! #require(RoamSurfaces.avoiding(corners, screen: screen, half: half, surfaces: ceilings).first)
        #expect(top.minX == 14 && top.maxX == 986)
    }

    @Test func windowLedgesAwayFromCornersStay() {
        let window = RoamWindow(frame: CGRect(x: 0, y: 200, width: 400, height: 300))
        let corners = RoamCorners(radius: 14, bottom: true, top: true)
        let result = RoamSurfaces.avoiding(corners, screen: screen, half: half,
                                           surfaces: surfaces(menuBar: 24, windows: [window]))
        #expect(result.contains { $0.kind == .window && $0.minX == 0 && $0.maxX == 400 })
    }

    @Test func screenSidesStopShortOfRoundEnds() {
        let walls = RoamSurfaces.walls(screen: screen, menuBarHeight: 0, windows: [], walkOnWindows: true)
        let corners = RoamCorners(radius: 14, bottom: true, top: false)
        let result = RoamSurfaces.avoiding(corners, screen: screen, walls: walls)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.minY == 14 && $0.maxY == 800 })
    }
}
