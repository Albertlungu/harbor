import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

@Suite struct NotchTests {
    let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 775))

    func notch(edge: ScreenEdge, alignment: EdgeAlignment = .center) -> Dock {
        var d = Dock(name: "N")
        d.layout = .notch
        d.position.mode = .pinned
        d.position.edge = edge
        d.position.alignment = alignment
        return d
    }

    @Test func topCenterIsFlushToScreenTop() {
        let d = notch(edge: .top)
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48], screen: screen)
        #expect(r.maxY == 800)
    }

    @Test func topCornerStaysBelowMenuBar() {
        let d = notch(edge: .top, alignment: .start)
        let r = DockLayoutEngine.barFrame(dock: d, position: d.position, slotLengths: [48], screen: screen)
        #expect(r.maxY == 775)
    }

    @Test func pillIsFlushAndCentered() {
        let bar = CGRect(x: 400, y: 736, width: 200, height: 64)
        let pill = DockLayoutEngine.notchPillFrame(for: bar, edge: .top)
        #expect(pill == CGRect(x: 440, y: 792, width: 120, height: 8))
        let side = DockLayoutEngine.notchPillFrame(for: CGRect(x: 0, y: 300, width: 64, height: 200), edge: .left)
        #expect(side == CGRect(x: 0, y: 340, width: 8, height: 120))
    }

    @Test func pillNeverExceedsShortBar() {
        let bar = CGRect(x: 0, y: 0, width: 70, height: 64)
        #expect(DockLayoutEngine.notchPillFrame(for: bar, edge: .bottom).width == 70)
    }

    @Test func hiddenFrameIsOffScreenAndRevealZoneTouchesEdge() {
        let bar = CGRect(x: 400, y: 736, width: 200, height: 64)
        let hidden = DockLayoutEngine.notchHiddenFrame(for: bar, edge: .top, area: screen.frame)
        #expect(hidden.minY > 800)
        let zone = DockLayoutEngine.notchRevealZone(for: bar, edge: .top, area: screen.frame, distance: 2)
        #expect(zone == CGRect(x: 400, y: 798, width: 200, height: 2))
    }

    @Test func onlyInwardCornersRound() {
        #expect(DockLayoutEngine.notchCorners(edge: .top) == .init(bottomLeft: true, bottomRight: true))
        #expect(DockLayoutEngine.notchCorners(edge: .right) == .init(topLeft: true, bottomLeft: true))
    }
}
