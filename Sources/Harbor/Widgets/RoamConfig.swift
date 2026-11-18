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
    var hidesFromRecordings: Bool { bool("roamHideFromRecordings", false) }
    var seesLedges: Bool { bool("roamVision", true) }
    var hidesInFullscreen: Bool { bool("roamHideFullscreen", false) }

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
    /// Walking or climbing speed in points per second, zero while still, for pacing the walk cycle.
    var walkSpeed = 0.0
    /// Holding a wall: climbing, clinging or sliding. The window turns the pet so its feet face the wall.
    var climbing = false
    var sliding = false
    /// How far the whole pet is turned, in degrees clockwise: a quarter on a wall, half under a ceiling.
    var angle = 0.0
    var startleTick = 0
    var landTick = 0
    var landImpact = 0.0
    var landAt = Date.distantPast
    var pointerTick = 0
    /// How the pet looks while it plays in the weather, from `playStart` until `playUntil`; `playBall` is the
    /// radius in points of a snowball in its paws.
    var play: WeatherPetPose = .none
    var playStart = Date.distantPast
    var playUntil = Date.distantPast
    var playBall = 0.0
    /// Set by the window so a touch can pause the walk long enough to be petted.
    @ObservationIgnored var onTouch: (() -> Void)?
    @ObservationIgnored var onCarry: (() -> Void)?

    init(unit: CGFloat) { self.unit = unit }

    /// Side of the window: the pet plus a margin on each side for hearts and crumbs.
    static func side(for unit: CGFloat) -> CGFloat { (unit * 1.6).rounded() }
    var side: CGFloat { Self.side(for: unit) }
}
