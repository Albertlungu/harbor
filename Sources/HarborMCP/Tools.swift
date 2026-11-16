import Foundation
import HarborCore

/// Final outcome of one tool call, mapped onto an MCP tool result.
struct ToolOutcome {
    var text: String
    var isError = false
}

enum Tools {
    private static func schema(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object(["type": .string("object"), "properties": .object(properties),
                 "required": .array(required.map { .string($0) })])
    }

    private static func string(_ description: String, enum values: [String]? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("string"), "description": .string(description)]
        if let values { o["enum"] = .array(values.map { .string($0) }) }
        return .object(o)
    }

    private static func tool(_ name: String, _ description: String, _ input: JSONValue) -> JSONValue {
        .object(["name": .string(name), "description": .string(description), "inputSchema": input])
    }

    static let list: [JSONValue] = [
        tool("list_docks", "List docks with their names, placement and item names.", schema([:], required: [])),
        tool("show_dock", "Show a dock that is hidden.", schema(["name": string("Dock name")], required: ["name"])),
        tool("hide_dock", "Hide a dock until it is shown again.", schema(["name": string("Dock name")], required: ["name"])),
        tool("toggle_dock", "Toggle a dock's visibility.", schema(["name": string("Dock name")], required: ["name"])),
        tool("create_dock", "Create an empty dock.", schema(["name": string("Name for the new dock")], required: ["name"])),
        tool("add_app", "Add an application to a dock.", schema([
            "dock": string("Dock name"),
            "app": string("Path to the app, or its name as found in /Applications or /System/Applications"),
        ], required: ["dock", "app"])),
        tool("remove_item", "Remove an item from a dock by its name.", schema([
            "dock": string("Dock name"), "item": string("Item name"),
        ], required: ["dock", "item"])),
        tool("set_style", "Change a dock's icon size, background, auto-hide or position.", schema([
            "dock": string("Dock name"),
            "iconSize": string("Icon size", enum: ["small", "medium", "large"]),
            "background": string("Background", enum: ["glass", "blur", "solid", "none"]),
            "autoHide": .object(["type": .string("boolean"), "description": .string("Hide the dock until the pointer reaches it")]),
            "position": string("Screen position", enum: StyleChange.positions),
        ], required: ["dock"])),
    ]

    static func call(_ name: String, _ args: [String: JSONValue]) -> ToolOutcome {
        func arg(_ key: String) -> String? {
            args[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        func need(_ key: String) -> String? { arg(key) }

        let docks = ConfigFile(directory: configDirectory).load().config.docks
        switch name {
        case "list_docks":
            let summaries = docks.map(DockSummary.init)
            let data = (try? JSONEncoder.pretty.encode(summaries)) ?? Data("[]".utf8)
            return ToolOutcome(text: String(decoding: data, as: UTF8.self))
        case "show_dock", "hide_dock", "toggle_dock":
            guard let dock = need("name") else { return fail("name is required.") }
            if let error = requireDock(dock, in: docks) { return error }
            let action: AssistantAction = name == "show_dock" ? .show : name == "hide_dock" ? .hide : .toggle
            return send(AssistantCommand(action: action, dock: dock))
        case "create_dock":
            guard let dock = need("name") else { return fail("name is required.") }
            return send(AssistantCommand(action: .create, dock: dock))
        case "add_app":
            guard let dock = need("dock"), let app = need("app") else { return fail("dock and app are required.") }
            if let error = requireDock(dock, in: docks) { return error }
            guard let path = AppLookup.resolve(app) else { return fail("No app found for \"\(app)\".") }
            return send(AssistantCommand(action: .addApp, dock: dock, appPath: path))
        case "remove_item":
            guard let dock = need("dock"), let item = need("item") else { return fail("dock and item are required.") }
            if let error = requireDock(dock, in: docks) { return error }
            return send(AssistantCommand(action: .removeItem, dock: dock, itemName: item))
        case "set_style":
            guard let dock = need("dock") else { return fail("dock is required.") }
            if let error = requireDock(dock, in: docks) { return error }
            var change = StyleChange()
            if let v = arg("iconSize") {
                guard ["small", "medium", "large"].contains(v), let size = IconSizePreset(rawValue: v) else {
                    return fail("iconSize must be small, medium or large.")
                }
                change.iconSize = size
            }
            if let v = arg("background") {
                guard let bg = BackgroundKind(rawValue: v) else { return fail("background must be glass, blur, solid or none.") }
                change.background = bg
            }
            if let v = args["autoHide"] {
                guard let flag = v.boolValue else { return fail("autoHide must be true or false.") }
                change.autoHide = flag
            }
            if let v = arg("position") {
                guard StyleChange.positions.contains(v) else { return fail("position must be bottom, top, left, right or floating.") }
                change.position = v
            }
            guard change != StyleChange() else { return fail("Nothing to change.") }
            return send(AssistantCommand(action: .setStyle, dock: dock, style: change))
        default:
            return fail("Unknown tool \(name).")
        }
    }

    private static func fail(_ text: String) -> ToolOutcome { ToolOutcome(text: text, isError: true) }

    private static func requireDock(_ name: String, in docks: [Dock]) -> ToolOutcome? {
        DockMatching.matches(name, in: docks).isEmpty ? fail("No dock named \"\(name)\".") : nil
    }

    private static func send(_ command: AssistantCommand) -> ToolOutcome {
        switch Bridge.send(command, timeout: 30) {
        case .reply(let reply): ToolOutcome(text: reply.message, isError: !reply.ok)
        case .timedOut: fail("Harbor did not respond within 30 seconds. Make sure Harbor is running.")
        }
    }
}

enum AppLookup {
    /// Accepts a path, or a name looked up case-insensitively in the standard app folders.
    static func resolve(_ query: String) -> String? {
        let fm = FileManager.default
        if query.contains("/") {
            let path = (query as NSString).expandingTildeInPath
            return fm.fileExists(atPath: path) ? path : nil
        }
        let wanted = query.lowercased().hasSuffix(".app") ? String(query.dropLast(4)) : query
        for folder in ["/Applications", "/System/Applications"] {
            let names = (try? fm.contentsOfDirectory(atPath: folder)) ?? []
            if let hit = names.first(where: { $0.lowercased() == wanted.lowercased() + ".app" }) {
                return folder + "/" + hit
            }
        }
        return nil
    }
}

var configDirectory: URL {
    if let override = ProcessInfo.processInfo.environment["HARBOR_HOME"] {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    return ConfigFile.defaultDirectory
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
