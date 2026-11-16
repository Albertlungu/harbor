import Foundation

public enum DockMatching {
    /// Docks whose name equals the query, ignoring case and surrounding spaces.
    /// A nil or blank query matches every dock.
    public static func matches(_ query: String?, in docks: [Dock]) -> [Dock] {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return docks }
        return docks.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(query) == .orderedSame }
    }

    /// First item in the dock whose display name equals the query, ignoring case.
    public static func item(named query: String, in dock: Dock) -> DockItem? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return dock.items.first { $0.displayName.caseInsensitiveCompare(q) == .orderedSame }
    }
}

/// What list_docks reports for each dock.
public struct DockSummary: Codable, Hashable, Sendable {
    public var name: String
    public var enabled: Bool
    public var placement: String
    public var items: [String]

    public init(_ dock: Dock) {
        name = dock.name
        enabled = dock.enabled
        placement = dock.position.mode == .floating ? "floating" : dock.position.edge.rawValue
        items = dock.items.map(\.displayName)
    }
}
