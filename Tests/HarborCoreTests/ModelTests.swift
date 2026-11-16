import Foundation
import Testing
@testable import HarborCore

@Suite struct ModelTests {
    @Test func roundTripsFullConfig() throws {
        var config = Config()
        var dock = Dock(name: "Work")
        dock.items = [DockItem(kind: .app, path: "/Applications/Safari.app"), .widget(.clock)]
        dock.style.effects = [.snow]
        dock.behavior.hotkey = Hotkey(keyCode: 2, modifiers: 256, display: "⌘D")
        config.docks = [dock]
        config.settings.clickGestureActions[.shift] = .quit

        let decoded = try ConfigFile.decode(ConfigFile.encode(config))
        #expect(decoded == config)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let json = #"{"docks":[{"name":"Old","items":[{"kind":"app","path":"/A.app"}]}]}"#
        let config = try ConfigFile.decode(Data(json.utf8))
        #expect(config.docks.count == 1)
        #expect(config.docks[0].style.iconSize == 48)
        #expect(config.docks[0].behavior.hideInFullscreen)
        #expect(config.docks[0].items[0].kind == .app)
        #expect(config.settings.magneticSnapping)
    }

    @Test func unknownWidgetSurvivesRoundTrip() throws {
        let json = #"{"docks":[{"name":"D","items":[{"kind":"widget","widget":{"type":"hologram","settings":{"x":1}}}]}]}"#
        let config = try ConfigFile.decode(Data(json.utf8))
        let widget = try #require(config.docks[0].items[0].widget)
        #expect(widget.kind == nil)
        let again = try ConfigFile.decode(ConfigFile.encode(config))
        #expect(again.docks[0].items[0].widget?.type == "hologram")
        #expect(again.docks[0].items[0].widget?.settings["x"] == .number(1))
    }

    @Test func versionOneMovesScrollingToPreviews() throws {
        let json = #"{"schemaVersion":1,"settings":{"scrollGestures":false,"scrollAction":"cycleWindows"}}"#
        let config = try ConfigFile.decode(Data(json.utf8))
        #expect(config.settings.scrollAction == .browsePreviews)
        #expect(config.settings.scrollGestures)
        #expect(config.schemaVersion == Config.currentSchemaVersion)
    }

    @Test func newerSchemaIsRejected() {
        let json = #"{"schemaVersion":99}"#
        #expect(throws: ConfigError.newerVersion(99)) { try ConfigFile.decode(Data(json.utf8)) }
    }

    @Test func garbageIsUnreadable() {
        #expect(throws: ConfigError.unreadable) { try ConfigFile.decode(Data("nope".utf8)) }
    }

    @Test func styleSizesClamp() {
        var style = DockStyle()
        style.iconSizePreset = .custom
        style.customIconSize = 500
        #expect(style.iconSize == 128)
        style.thicknessPreset = .custom
        style.customThickness = 5
        #expect(style.thickness == 24)
    }

    @Test func behaviorDelaysClamp() {
        var b = Behavior()
        b.hidePreset = .custom
        b.customHideDelay = 9
        b.revealPreset = .custom
        b.customRevealDelay = 9
        #expect(b.hideDelay == 5)
        #expect(b.revealDelay == 2)
    }

    @Test func displayNames() {
        var item = DockItem(kind: .file, path: "/tmp/report.pdf")
        #expect(item.displayName == "report.pdf")
        item.hideExtension = true
        #expect(item.displayName == "report")
        item.customName = "Q3"
        #expect(item.displayName == "Q3")
        #expect(DockItem(kind: .app, path: "/Applications/Notes.app").displayName == "Notes")
        #expect(DockItem.widget(.clock).displayName == "Clock")
    }

    @Test func pinnedOrientationFollowsEdge() {
        var dock = Dock(name: "D")
        dock.style.orientation = .horizontal
        dock.position.mode = .pinned
        dock.position.edge = .left
        #expect(dock.effectiveOrientation == .vertical)
        #expect(dock.placementSummary == "Pinned · Left")
    }

    @Test func widgetSearch() {
        #expect(WidgetCatalog.kinds(in: .all, matching: "clo") == [.clock])
        #expect(WidgetCatalog.kinds(in: .system).contains(.cpu))
        #expect(!WidgetCatalog.kinds(in: .system).contains(.clock))
    }

    @Test func arrayMoveMatchesListSemantics() {
        var a = [0, 1, 2, 3, 4]
        a.move(fromOffsets: [0], toOffset: 3)
        #expect(a == [1, 2, 0, 3, 4])
        var b = [0, 1, 2, 3, 4]
        b.move(fromOffsets: [4], toOffset: 1)
        #expect(b == [0, 4, 1, 2, 3])
        var c = [0, 1, 2, 3, 4]
        c.move(fromOffsets: [1, 3], toOffset: 5)
        #expect(c == [0, 2, 4, 1, 3])
    }
}
