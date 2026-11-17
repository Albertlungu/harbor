import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

/// Edge finding on synthetic pictures.
@Suite struct RoamVisionTests {
    private struct Picture {
        var width: Int
        var height: Int
        var pixels: [UInt8]

        init(width: Int, height: Int, fill: UInt8 = 20) {
            self.width = width
            self.height = height
            pixels = Array(repeating: fill, count: width * height)
        }

        mutating func rect(x: Int, y: Int, width w: Int, height h: Int, value: UInt8) {
            for row in y..<(y + h) { for column in x..<(x + w) { pixels[row * width + column] = value } }
        }
    }

    @Test func findsTheTopAndBottomOfAPanel() {
        var picture = Picture(width: 200, height: 100)
        picture.rect(x: 30, y: 40, width: 120, height: 30, value: 200)
        let edges = RoamVision.edges(gray: picture.pixels, width: 200, height: 100, minRun: 60)
        #expect(edges == [RoamVision.Edge(y: 40, minX: 30, maxX: 149), RoamVision.Edge(y: 70, minX: 30, maxX: 149)])
    }

    @Test func textMakesNoEdges() {
        var picture = Picture(width: 300, height: 60, fill: 240)
        // Rows of short glyph-like blobs with word gaps.
        for line in 0..<3 {
            for word in stride(from: 4, to: 290, by: 9) {
                picture.rect(x: word, y: 8 + line * 16, width: 5, height: 8, value: 30)
            }
        }
        #expect(RoamVision.edges(gray: picture.pixels, width: 300, height: 60, minRun: 60).isEmpty)
    }

    @Test func bridgesSmallGapsAndMergesBlurredRows() {
        var picture = Picture(width: 200, height: 40)
        // A soft edge over two rows, with a dark notch two pixels wide.
        picture.rect(x: 10, y: 20, width: 150, height: 1, value: 90)
        picture.rect(x: 10, y: 21, width: 150, height: 19, value: 200)
        picture.rect(x: 80, y: 20, width: 2, height: 2, value: 20)
        let edges = RoamVision.edges(gray: picture.pixels, width: 200, height: 40, minRun: 100)
        #expect(edges.count == 1)
        #expect(edges.first?.y == 20)
        #expect(edges.first?.minX == 10)
        #expect(edges.first?.maxX == 159)
    }

    @Test func faintStepsAreIgnored() {
        var picture = Picture(width: 200, height: 40)
        picture.rect(x: 0, y: 20, width: 200, height: 20, value: 30)
        #expect(RoamVision.edges(gray: picture.pixels, width: 200, height: 40, minRun: 60).isEmpty)
    }

    @Test func ledgesAreScaledSkipTheMenuBarAndKnownLedges() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // A quarter-size picture: 250 by 200 pixels.
        let edges = [RoamVision.Edge(y: 50, minX: 25, maxX: 124),   // y 600, x 100 to 500
                     RoamVision.Edge(y: 2, minX: 0, maxX: 249),     // inside the menu bar
                     RoamVision.Edge(y: 100, minX: 0, maxX: 20),    // too short
                     RoamVision.Edge(y: 125, minX: 50, maxX: 149)]  // y 300, already a window top
        let known = [RoamSurface(kind: .window, y: 301, minX: 150, maxX: 700)]
        let rects = RoamVision.ledges(edges, imageWidth: 250, imageHeight: 200, screen: screen, menuBarHeight: 24,
                                      known: known)
        #expect(rects == [CGRect(x: 100, y: 598, width: 400, height: 2)])
        let surfaces = RoamSurfaces.build(screen: screen, menuBarHeight: 24, windows: [], docks: [],
                                          walkOnWindows: true, elements: rects)
        #expect(surfaces.contains(RoamSurface(kind: .element, y: 600, minX: 100, maxX: 500)))
    }

    @Test func aPetDroppedAboveAnElementLandsOnIt() {
        // The whole chain after a scan: element rects become ledges, and a fall stops on one.
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let window = RoamWindow(frame: CGRect(x: 100, y: 100, width: 600, height: 500), isFront: true)
        let field = CGRect(x: 200, y: 300, width: 300, height: 24)
        let surfaces = RoamSurfaces.build(screen: screen, menuBarHeight: 24, windows: [window], docks: [],
                                          walkOnWindows: true, elements: [field])
        let env = RoamEnvironment(surfaces: surfaces, mode: .patrol, home: .zero, pointer: .zero, lively: false,
                                  screenMinX: 0, screenMaxX: 1000, elements: [field])
        var state = RoamState(x: 350, y: 500)
        _ = RoamBrain.release(&state, velocity: .zero, env: env)
        for _ in 0..<240 where state.activity == .falling {
            _ = RoamBrain.step(&state, dt: 1.0 / 120, env: env, roll: { 0.5 })
        }
        #expect(state.y == 324)
        #expect(state.activity == .resting)
    }
}
