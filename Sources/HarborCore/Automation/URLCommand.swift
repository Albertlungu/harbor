import Foundation

/// A harbor:// URL, as used by the Shortcuts "Open URL" action and Focus automations.
public enum URLCommand: Hashable, Sendable {
    case show(dock: String?)
    case hide(dock: String?)
    case toggle(dock: String?)
    case new(name: String?)
    case manager

    public static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "harbor", let host = url.host?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first { $0.name == key }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch host {
        case "show": return .show(dock: value("dock"))
        case "hide": return .hide(dock: value("dock"))
        case "toggle": return .toggle(dock: value("dock"))
        case "new": return .new(name: value("name"))
        case "manager": return .manager
        default: return nil
        }
    }
}
