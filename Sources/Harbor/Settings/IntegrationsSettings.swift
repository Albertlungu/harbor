import AppKit
import HarborCore
import SwiftUI

struct IntegrationsSettings: View {
    @AppStorage(AssistantAccess.defaultsKey) private var access: String = AssistantAccess.ask.rawValue
    private let bridge = AssistantBridge.shared

    private static let urlExamples: [(title: String, url: String)] = [
        ("Show a dock", "harbor://show?dock=Work"),
        ("Hide a dock", "harbor://hide?dock=Work"),
        ("Toggle a dock", "harbor://toggle?dock=Work"),
        ("Show every dock", "harbor://show"),
        ("Create a dock", "harbor://new?name=Notes"),
        ("Open the Manager", "harbor://manager"),
    ]

    private var mcpPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/harbor-mcp").path
    }

    private var claudeCommand: String { "claude mcp add harbor -- \(shellQuoted(mcpPath))" }

    private var jsonConfig: String {
        let escaped = mcpPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "mcpServers": {
            "harbor": {
              "command": "\(escaped)"
            }
          }
        }
        """
    }

    var body: some View {
        Form {
            Section("URL commands") {
                Text("Run these from the Shortcuts app with the Open URL action, from a script, or from a link. Dock names are not case sensitive, and leaving the name out applies to every dock.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                ForEach(Self.urlExamples, id: \.url) { example in
                    CopyRow(title: example.title, value: example.url)
                }
            }

            Section("Shortcuts and Focus") {
                Text("To make a shortcut, open Shortcuts, add an Open URL action and paste one of the addresses above. To follow a Focus, create a Personal Automation in Shortcuts that runs when the Focus turns on or off, and have it run that shortcut.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                Button("Open Shortcuts") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                }
            }

            Section("AI assistants") {
                Picker("Allow AI assistants to change docks", selection: $access) {
                    Text("Off").tag(AssistantAccess.off.rawValue)
                    Text("Ask each time").tag(AssistantAccess.ask.rawValue)
                    Text("Always").tag(AssistantAccess.always.rawValue)
                }
                LabeledContent("Server") {
                    Text(mcpPath).font(.caption.monospaced()).textSelection(.enabled)
                        .lineLimit(2).truncationMode(.middle)
                }
                CopyRow(title: "Claude Code command", value: claudeCommand)
                CopyRow(title: "JSON configuration", value: jsonConfig)
                Button("Undo Last Assistant Change") { bridge.undoLast() }
                    .disabled(!bridge.canUndo)
            }
        }
    }

    private func shellQuoted(_ path: String) -> String {
        path.contains(" ") ? "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" : path
    }
}

private struct CopyRow: View {
    let title: String
    let value: String
    @State private var copied = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                if !value.contains("\n") {
                    Text(value).font(.caption.monospaced()).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                }
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
            }
        }
    }
}
