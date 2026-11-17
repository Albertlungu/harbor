import CoreGraphics
import Foundation
import Testing
@testable import HarborCore

@Suite struct RoamElementsTests {
    private let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    /// An element `inset` points below the window top, spanning `width` from the window's left edge plus `x`.
    private func element(_ role: String, subrole: String? = nil, x: Double = 0, inset: Double = 80,
                         width: Double = 500, height: Double = 300, depth: Int = 3,
                         window: CGRect? = nil) -> RoamElementCandidate {
        let w = window ?? self.window
        let top = w.maxY - inset
        return RoamElementCandidate(role: role, subrole: subrole,
                                    frame: CGRect(x: w.minX + x, y: top - height, width: width, height: height),
                                    windowFrame: w, depth: depth)
    }

    // MARK: Roles

    @Test func mainRolesAreAccepted() {
        for role in ["AXTextArea", "AXScrollArea", "AXTable", "AXOutline", "AXList", "AXWebArea", "AXToolbar",
                     "AXTabGroup", "AXSplitGroup", "AXGroup", "AXSheet", "AXPopover", "AXMenu"] {
            #expect(RoamElements.score(element(role)) != nil, "\(role)")
        }
    }

    @Test func controlsAndContentPiecesAreRejected() {
        for role in ["AXButton", "AXStaticText", "AXImage", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
                     "AXSlider", "AXLink", "AXRow", "AXCell", "AXMenuItem", "AXUnknown"] {
            #expect(RoamElements.score(element(role)) == nil, "\(role)")
        }
    }

    @Test func textAreaOutranksPlainGroup() throws {
        let text = try #require(RoamElements.score(element("AXTextArea")))
        let group = try #require(RoamElements.score(element("AXGroup")))
        #expect(text > group)
    }

    @Test func landmarkGroupsOutrankPlainGroups() throws {
        let landmark = try #require(RoamElements.score(element("AXGroup", subrole: "AXLandmarkMain")))
        let plain = try #require(RoamElements.score(element("AXGroup")))
        #expect(landmark > plain)
    }

    @Test func shortGroupsAreLayoutWrappers() {
        #expect(RoamElements.score(element("AXGroup", height: 40)) == nil)
    }

    // MARK: Size

    @Test func narrowElementsAreRejected() {
        #expect(RoamElements.score(element("AXTextArea", width: 100)) == nil)
    }

    @Test func narrowShareOfAWideWindowIsRejected() {
        let wide = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        // 200 pt clears the absolute minimum but is under 15% of a 2000 pt window.
        #expect(RoamElements.score(element("AXScrollArea", width: 200, window: wide)) == nil)
        #expect(RoamElements.score(element("AXScrollArea", width: 320, window: wide)) != nil)
    }

    @Test func thinElementsAreRejected() {
        #expect(RoamElements.score(element("AXScrollArea", height: 10)) == nil)
    }

    @Test func thinPanesAreStripsNotMainAreas() {
        #expect(RoamElements.score(element("AXList", height: 30)) == nil)
        #expect(RoamElements.score(element("AXToolbar", height: 30)) != nil)
    }

    @Test func onlyWideTextFieldsCount() {
        #expect(RoamElements.score(element("AXTextField", width: 160, height: 22)) == nil)
        #expect(RoamElements.score(element("AXTextField", width: 400, height: 22)) != nil)
    }

    @Test func widerElementsScoreHigher() throws {
        let wide = try #require(RoamElements.score(element("AXScrollArea", width: 780)))
        let narrow = try #require(RoamElements.score(element("AXScrollArea", width: 200)))
        #expect(wide > narrow)
    }

    @Test func deeperElementsScoreSlightlyLower() throws {
        let shallow = try #require(RoamElements.score(element("AXScrollArea", depth: 2)))
        let deep = try #require(RoamElements.score(element("AXScrollArea", depth: 9)))
        #expect(shallow > deep)
    }

    @Test func spanCountsOnlyThePartInsideTheWindow() {
        // 300 pt wide but only 100 pt of it inside the window.
        #expect(RoamElements.score(element("AXScrollArea", x: -200, width: 300)) == nil)
    }

    // MARK: Position

    @Test func topAtTheWindowTopIsRejected() {
        #expect(RoamElements.score(element("AXToolbar", inset: 0, height: 50)) == nil)
        #expect(RoamElements.score(element("AXToolbar", inset: 2, height: 50)) == nil)
    }

    @Test func topInsideTheTitleStripIsRejected() {
        #expect(RoamElements.score(element("AXScrollArea", inset: 12)) == nil)
    }

    @Test func topJustBelowTheTitleBarIsAccepted() {
        #expect(RoamElements.score(element("AXScrollArea", inset: RoamSurfaces.titleBarHeight)) != nil)
    }

    @Test func topOutsideTheWindowIsRejected() {
        #expect(RoamElements.score(element("AXScrollArea", inset: 700, height: 50)) == nil)
    }

    @Test func wholeWindowSpansAreRejected() {
        let full = RoamElementCandidate(role: "AXSplitGroup", frame: CGRect(x: 100, y: 100, width: 800, height: 572),
                                        windowFrame: window, depth: 1)
        #expect(RoamElements.score(full) == nil)
    }

    @Test func fullWidthPaneBelowAToolbarIsAccepted() {
        #expect(RoamElements.score(element("AXScrollArea", inset: 60, width: 800, height: 500)) != nil)
    }

    @Test func fullPaneJustUnderABrowserToolbarIsAccepted() {
        // A page area filling the window below a 65 pt toolbar is a real edge, not a wrapper.
        #expect(RoamElements.score(element("AXGroup", inset: 65, width: 800, height: 535)) != nil)
    }

    @Test func menusStandOnTheirOwnFrame() {
        let menu = CGRect(x: 300, y: 400, width: 220, height: 180)
        let candidate = RoamElementCandidate(role: "AXMenu", frame: menu, windowFrame: menu, depth: 0)
        #expect(RoamElements.score(candidate) != nil)
        #expect(RoamElements.ledges([candidate]) == [menu])
    }

    // MARK: Ledges

    @Test func duplicateTopsKeepTheBetterElement() {
        let scroll = element("AXScrollArea", width: 600)
        let table = element("AXTable", width: 590)
        let ledges = RoamElements.ledges([table, scroll])
        #expect(ledges == [scroll.frame])
    }

    @Test func listJustUnderItsScrollAreaTopIsADuplicate() {
        let scroll = element("AXScrollArea", inset: 52, width: 780)
        let outline = element("AXOutline", inset: 79, width: 780, height: 270, depth: 4)
        #expect(RoamElements.ledges([outline, scroll]) == [scroll.frame])
    }

    @Test func sideBySidePanesAtTheSameTopAreBothKept() {
        let sidebar = element("AXScrollArea", x: 0, width: 220)
        let content = element("AXScrollArea", x: 230, width: 560)
        #expect(Set(RoamElements.ledges([sidebar, content]).map(\.minX)) == [100, 330])
    }

    @Test func differentTopsAreBothKept() {
        let toolbar = element("AXTabGroup", inset: 40, width: 700, height: 400)
        let pane = element("AXTextArea", inset: 120, width: 700, height: 300)
        #expect(RoamElements.ledges([toolbar, pane]).count == 2)
    }

    @Test func eachWindowIsCapped() {
        let many = (0..<10).map { element("AXScrollArea", inset: 40 + Double($0) * 40, height: 100) }
        #expect(RoamElements.ledges(many, maxPerWindow: 4).count == 4)
    }

    @Test func capIsPerWindow() {
        let other = CGRect(x: 1000, y: 100, width: 800, height: 600)
        let first = (0..<3).map { element("AXScrollArea", inset: 40 + Double($0) * 50, height: 100) }
        let second = (0..<3).map { element("AXScrollArea", inset: 40 + Double($0) * 50, height: 100, window: other) }
        #expect(RoamElements.ledges(first + second, maxPerWindow: 2).count == 4)
    }

    @Test func capKeepsTheBestScores() {
        let group = element("AXGroup", inset: 60, height: 100)
        let text = element("AXTextArea", inset: 200, height: 100)
        #expect(RoamElements.ledges([group, text], maxPerWindow: 1) == [text.frame])
    }

    @Test func ledgesAreClippedToTheirWindow() {
        let overhang = element("AXScrollArea", x: 600, width: 400)
        let ledge = RoamElements.ledges([overhang]).first
        #expect(ledge?.minX == 700)
        #expect(ledge?.maxX == window.maxX)
        #expect(ledge?.maxY == overhang.frame.maxY)
    }

    @Test func rejectedCandidatesProduceNoLedges() {
        #expect(RoamElements.ledges([element("AXButton"), element("AXStaticText")]).isEmpty)
    }
}
