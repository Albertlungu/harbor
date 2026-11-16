import AppKit
import HarborCore
import Observation

/// Where a roaming pet calls home: a point on a screen, in AppKit coordinates.
struct RoamHome: Equatable {
    var point: CGPoint
    var screenID: String
}

extension WidgetConfig {
    var isRoaming: Bool { state["roaming"]?.boolValue ?? false }
    var roamMode: RoamMode { state["roamMode"]?.stringValue.flatMap(RoamMode.init(rawValue:)) ?? .patrol }
    var roamSize: Double { min(max(stateDouble("roamSize") ?? 32, 24), 48) }
    var walksOnWindows: Bool { bool("roamWindows", true) }
    var staysOnOwnScreen: Bool { string("roamScreens", "all") == "own" }

    var roamHome: RoamHome? {
        guard case .object(let fields)? = state["roamHome"], let x = fields["x"]?.doubleValue,
              let y = fields["y"]?.doubleValue, let screen = fields["screen"]?.stringValue else { return nil }
        return RoamHome(point: CGPoint(x: x, y: y), screenID: screen)
    }
}

extension RoamHome {
    var json: JSONValue {
        .object(["x": .number(point.x), "y": .number(point.y), "screen": .string(screenID)])
    }
}

/// What the roaming window tells the pet's view, so the view reuses all of the dock pet's personality
/// and only adds locomotion on top.
@MainActor
@Observable
final class RoamDriver {
    var unit: CGFloat
    var facing = 1.0
    var moving = false
    var sitting = false
    var napping = false
    var carried = false
    var falling = false
    var hovering = false
    var lively = false
    var startleTick = 0
    var landTick = 0
    var landImpact = 0.0
    var landAt = Date.distantPast
    var pointerTick = 0
    /// Set by the window so a touch can pause the walk long enough to be petted.
    @ObservationIgnored var onTouch: (() -> Void)?
    @ObservationIgnored var onCarry: (() -> Void)?

    init(unit: CGFloat) { self.unit = unit }

    /// Side of the window: the pet plus a margin on each side for hearts and crumbs.
    static func side(for unit: CGFloat) -> CGFloat { (unit * 1.6).rounded() }
    var side: CGFloat { Self.side(for: unit) }
}
