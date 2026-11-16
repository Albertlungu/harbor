import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

@Suite struct ReserveTests {
    let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 775))

    @Test func stripCoversThicknessPlusGap() {
        let bar = CGRect(x: 400, y: 10, width: 200, height: 64)
        let strip = DockLayoutEngine.reservedStrip(bar: bar, edge: .bottom, fullWidth: false, screen: screen)
        #expect(strip.rect == CGRect(x: 400, y: 0, width: 200, height: 74))
    }

    @Test func fullWidthStripSpansTheEdge() {
        let bar = CGRect(x: 0, y: 4, width: 1000, height: 64)
        let strip = DockLayoutEngine.reservedStrip(bar: bar, edge: .bottom, fullWidth: true, screen: screen)
        #expect(strip.rect.width == 1000)
        let side = DockLayoutEngine.reservedStrip(bar: CGRect(x: 936, y: 100, width: 64, height: 300), edge: .right,
                                                  fullWidth: false, screen: screen)
        #expect(side.rect == CGRect(x: 936, y: 100, width: 64, height: 300))
    }

    @Test func windowIsMovedUpBeforeItIsShrunk() {
        let strip = DockLayoutEngine.reservedStrip(bar: CGRect(x: 0, y: 4, width: 1000, height: 64), edge: .bottom,
                                                   fullWidth: true, screen: screen)
        let moved = DockLayoutEngine.fit(window: CGRect(x: 100, y: 20, width: 400, height: 300), avoiding: strip)
        #expect(moved == CGRect(x: 100, y: 68, width: 400, height: 300))
    }

    @Test func tallWindowIsShrunkAndOtherAxisUntouched() {
        let strip = DockLayoutEngine.reservedStrip(bar: CGRect(x: 0, y: 4, width: 1000, height: 64), edge: .bottom,
                                                   fullWidth: true, screen: screen)
        let fitted = DockLayoutEngine.fit(window: CGRect(x: -50, y: 0, width: 600, height: 775), avoiding: strip)
        #expect(fitted == CGRect(x: -50, y: 68, width: 600, height: 707))
    }

    @Test func windowClearOfStripIsUnchanged() {
        let strip = DockLayoutEngine.reservedStrip(bar: CGRect(x: 400, y: 4, width: 200, height: 64), edge: .bottom,
                                                   fullWidth: false, screen: screen)
        let w = CGRect(x: 0, y: 100, width: 300, height: 300)
        #expect(DockLayoutEngine.fit(window: w, avoiding: strip) == w)
        let beside = CGRect(x: 0, y: 0, width: 300, height: 300)
        #expect(DockLayoutEngine.fit(window: beside, avoiding: strip) == beside)
    }

    @Test func leftStripPushesWindowRight() {
        let strip = DockLayoutEngine.reservedStrip(bar: CGRect(x: 4, y: 100, width: 64, height: 400), edge: .left,
                                                   fullWidth: false, screen: screen)
        let r = DockLayoutEngine.fit(window: CGRect(x: 0, y: 200, width: 300, height: 200), avoiding: strip)
        #expect(r.minX == 68)
    }
}
