import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

@Suite struct LayoutTests {
    // 1000x800 screen with a 25pt menu bar.
    let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 775))

    func dock(_ change: (inout Dock) -> Void = { _ in }) -> Dock {
        var d = Dock(name: "T")
        d.style.sidePadding = 10
        d.style.spacing = .normal // 6
        change(&d)
        return d
    }

    @Test func contentLengthSumsSlotsSpacingAndPadding() {
        let d = dock()
        let length: CGFloat = DockLayoutEngine.contentLength(style: d.style, slotLengths: [48, 48, 48])
        #expect(length == CGFloat(48 * 3 + 12 + 20))
    }

    @Test func emptyDockIsAtLeastSquare() {
        let d = dock()
        #expect(DockLayoutEngine.contentLength(style: d.style, slotLengths: []) == CGFloat(d.style.thickness))
    }

    @Test func floatingCentered() {
        let d = dock()
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48], screen: screen)
        #expect(abs(r.midX - 500) < 0.001)
        #expect(abs(r.midY - 387.5) < 0.001)
    }

    @Test func floatingClampsInsideVisibleFrame() {
        let d = dock { $0.position.floatingCenterX = 1.0; $0.position.floatingCenterY = 0 }
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48, 48], screen: screen)
        #expect(r.maxX == 1000)
        #expect(r.minY == 0)
    }

    @Test func pinnedBottomCenterWithGap() {
        let d = dock { $0.position.mode = .pinned; $0.position.edge = .bottom; $0.position.gapPreset = .small }
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48], screen: screen)
        #expect(r.minY == 4)
        #expect(abs(r.midX - 500) < 0.001)
        #expect(r.height == CGFloat(d.style.thickness))
    }

    @Test func pinnedTopSitsBelowMenuBar() {
        let d = dock { $0.position.mode = .pinned; $0.position.edge = .top; $0.position.gapPreset = .flush }
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48], screen: screen)
        #expect(r.maxY == 775)
    }

    @Test func pinnedLeftStartIsTop() {
        let d = dock {
            $0.position.mode = .pinned; $0.position.edge = .left
            $0.position.alignment = .start; $0.position.gapPreset = .flush
        }
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48, 48], screen: screen)
        #expect(r.minX == 0)
        #expect(r.maxY == 775)
        #expect(r.width == CGFloat(d.style.thickness))
    }

    @Test func pinnedEndWithOffsetMovesInward() {
        let d = dock {
            $0.position.mode = .pinned; $0.position.edge = .bottom
            $0.position.alignment = .end; $0.position.offsetAlongEdge = 30
        }
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48], screen: screen)
        #expect(r.maxX == 970)
    }

    @Test func fullWidthSpansEdge() {
        let d = dock { $0.position.mode = .pinned; $0.position.fullWidth = true; $0.position.endPadding = 10 }
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48], screen: screen)
        #expect(r.minX == 10 && r.maxX == 990)
    }

    @Test func hiddenFrameIsOffscreen() {
        let bar = CGRect(x: 400, y: 4, width: 200, height: 64)
        let hidden = DockLayoutEngine.hiddenFrame(for: bar, edge: .bottom, screen: screen)
        #expect(hidden.maxY < 0)
        let zone = DockLayoutEngine.revealZone(for: bar, edge: .bottom, screen: screen, distance: 2)
        #expect(zone.contains(CGPoint(x: 500, y: 1)))
        #expect(!zone.contains(CGPoint(x: 100, y: 1)))
    }

    @Test func floatingCenterSnapsToMiddle() {
        let rect = CGRect(x: 405, y: 300, width: 200, height: 64)
        let c = DockLayoutEngine.floatingCenter(for: rect, screen: screen, snap: true)
        #expect(c.x == 0.5)
        let free = DockLayoutEngine.floatingCenter(for: rect, screen: screen, snap: false)
        #expect(free.x != 0.5)
    }

    @Test func magnificationBell() {
        #expect(DockLayoutEngine.magnification(distance: 0, iconSize: 48, maxScale: 2, falloff: 2) == 2)
        #expect(DockLayoutEngine.magnification(distance: 200, iconSize: 48, maxScale: 2, falloff: 2) == 1)
        let mid = DockLayoutEngine.magnification(distance: 48, iconSize: 48, maxScale: 2, falloff: 2)
        #expect(mid > 1 && mid < 2)
    }

    @Test func resolverPrefersAssignedThenMain() {
        let main = ConnectedScreen(id: "m", name: "Built-in", geometry: screen, isMain: true)
        let ext = ConnectedScreen(id: "e", name: "Studio", geometry: screen, isMain: false)
        var d = dock()
        #expect(ScreenResolver.screens(for: d, connected: [ext, main]).map(\.id) == ["m"])
        d.screens.assignedScreenIDs = ["gone", "e"]
        #expect(ScreenResolver.screens(for: d, connected: [ext, main]).map(\.id) == ["e"])
        d.screens.assignedScreenIDs = ["gone"]
        #expect(ScreenResolver.screens(for: d, connected: [ext, main]).isEmpty)
        d.screens.showOnAllScreens = true
        #expect(ScreenResolver.screens(for: d, connected: [ext, main]).count == 2)
    }

    /// Sleep and a closed lid without an external display briefly report no screens at all.
    @Test func resolverWithNoScreensPlacesNothing() {
        var d = dock()
        #expect(ScreenResolver.screens(for: d, connected: []).isEmpty)
        d.screens.showOnAllScreens = true
        #expect(ScreenResolver.screens(for: d, connected: []).isEmpty)
        d.screens.assignedScreenIDs = ["e"]
        #expect(ScreenResolver.screens(for: d, connected: []).isEmpty)
    }

    /// Screens with no main flag, as during a display reconfiguration, still get the dock.
    @Test func resolverFallsBackToFirstScreenWithoutAMain() {
        let a = ConnectedScreen(id: "a", name: "A", geometry: screen, isMain: false)
        let b = ConnectedScreen(id: "b", name: "B", geometry: screen, isMain: false)
        #expect(ScreenResolver.screens(for: dock(), connected: [a, b]).map(\.id) == ["a"])
    }
}
