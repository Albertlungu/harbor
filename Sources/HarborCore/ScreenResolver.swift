import Foundation

/// A connected display as seen by the resolver.
public struct ConnectedScreen: Equatable, Sendable {
    public var id: String
    public var name: String
    public var geometry: ScreenGeometry
    public var isMain: Bool

    public init(id: String, name: String, geometry: ScreenGeometry, isMain: Bool) {
        self.id = id
        self.name = name
        self.geometry = geometry
        self.isMain = isMain
    }
}

/// Decides which connected screens a dock appears on.
public enum ScreenResolver {
    /// Screens for `dock`: every screen when mirrored; otherwise the first connected
    /// assigned screen in assignment order; with no assignments, the main screen.
    /// Empty when every assigned screen is disconnected.
    public static func screens(for dock: Dock, connected: [ConnectedScreen]) -> [ConnectedScreen] {
        guard !connected.isEmpty else { return [] }
        if dock.screens.showOnAllScreens { return connected }
        let assigned = dock.screens.assignedScreenIDs
        if assigned.isEmpty {
            return [connected.first(where: \.isMain) ?? connected[0]]
        }
        for id in assigned {
            if let screen = connected.first(where: { $0.id == id }) { return [screen] }
        }
        return []
    }

    /// The placement for a dock on a given screen, honoring per-screen overrides.
    public static func position(for dock: Dock, on screenID: String) -> Position {
        dock.perScreenPositions[screenID] ?? dock.position
    }

    /// Builds a stable identity from hardware numbers; falls back to the name when the
    /// display reports no serial, so two identical unnamed panels still differ by slot.
    public static func identity(vendor: UInt32, model: UInt32, serial: UInt32, name: String, slot: Int) -> String {
        if serial != 0 { return "\(vendor)-\(model)-\(serial)" }
        return "\(vendor)-\(model)-\(name)-\(slot)"
    }
}
