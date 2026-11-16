import Foundation

/// Names shared by the app and the MCP helper, which talk over distributed notifications.
public enum AssistantChannel {
    public static let commandName = "io.github.albertlungu.harbor.command"
    public static let replyName = "io.github.albertlungu.harbor.reply"
    /// userInfo key holding the JSON payload.
    public static let payloadKey = "json"
}

public enum AssistantAction: String, Codable, Sendable {
    case show, hide, toggle, create, addApp, removeItem, setStyle
}

/// What a set_style call may change. Nil fields stay as they are.
public struct StyleChange: Codable, Hashable, Sendable {
    public var iconSize: IconSizePreset?
    public var background: BackgroundKind?
    public var autoHide: Bool?
    /// bottom, top, left, right or floating.
    public var position: String?

    public init(iconSize: IconSizePreset? = nil, background: BackgroundKind? = nil,
                autoHide: Bool? = nil, position: String? = nil) {
        self.iconSize = iconSize
        self.background = background
        self.autoHide = autoHide
        self.position = position
    }

    public static let positions = ["bottom", "top", "left", "right", "floating"]

    /// Returns false, changing nothing, when a value is not recognized.
    @discardableResult
    public func apply(to dock: inout Dock) -> Bool {
        if let position, !Self.positions.contains(position) { return false }
        if iconSize == .custom { return false }
        if let iconSize { dock.style.iconSizePreset = iconSize }
        if let background { dock.style.background = background }
        if let autoHide { dock.behavior.autoHide = autoHide }
        if let position {
            if let edge = ScreenEdge(rawValue: position) {
                dock.position.mode = .pinned
                dock.position.edge = edge
                dock.style.orientation = (edge == .left || edge == .right) ? .vertical : .horizontal
            } else {
                dock.position.mode = .floating
            }
        }
        return true
    }
}

public struct AssistantCommand: Codable, Hashable, Sendable {
    public var id: String
    public var action: AssistantAction
    /// Target dock name, or the new dock's name for create.
    public var dock: String?
    /// Absolute path of the app for addApp.
    public var appPath: String?
    public var itemName: String?
    public var style: StyleChange?

    public init(id: String = UUID().uuidString, action: AssistantAction, dock: String? = nil,
                appPath: String? = nil, itemName: String? = nil, style: StyleChange? = nil) {
        self.id = id
        self.action = action
        self.dock = dock
        self.appPath = appPath
        self.itemName = itemName
        self.style = style
    }

    /// True when the command edits the saved configuration rather than runtime visibility.
    public var changesConfig: Bool {
        switch action {
        case .show, .hide, .toggle: false
        default: true
        }
    }

    /// Plain-language description for the approval alert.
    public var summary: String {
        let target = "\"\(dock ?? "")\""
        switch action {
        case .show: return "Show dock \(target)."
        case .hide: return "Hide dock \(target)."
        case .toggle: return "Toggle dock \(target)."
        case .create: return "Create a new dock named \(target)."
        case .addApp:
            let app = appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "an app"
            return "Add \(app) to dock \(target)."
        case .removeItem: return "Remove \"\(itemName ?? "")\" from dock \(target)."
        case .setStyle:
            var parts: [String] = []
            if let v = style?.iconSize { parts.append("icon size \(v.rawValue)") }
            if let v = style?.background { parts.append("background \(v.rawValue)") }
            if let v = style?.autoHide { parts.append("auto-hide \(v ? "on" : "off")") }
            if let v = style?.position { parts.append("position \(v)") }
            return "Change dock \(target): \(parts.joined(separator: ", "))."
        }
    }

    public func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)
    }

    public static func decode(_ json: String) -> AssistantCommand? {
        try? JSONDecoder().decode(AssistantCommand.self, from: Data(json.utf8))
    }
}

public struct AssistantReply: Codable, Hashable, Sendable {
    public var id: String
    public var ok: Bool
    public var message: String

    public init(id: String, ok: Bool, message: String) {
        self.id = id
        self.ok = ok
        self.message = message
    }

    public func encoded() -> String {
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
    }

    public static func decode(_ json: String) -> AssistantReply? {
        try? JSONDecoder().decode(AssistantReply.self, from: Data(json.utf8))
    }
}

public enum AssistantAccess: String, CaseIterable, Sendable {
    case off, ask, always
    public static let defaultsKey = "assistantAccess"
}
