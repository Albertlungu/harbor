import Foundation
import Testing
@testable import HarborCore

@Suite struct AutomationTests {
    @Test func parsesRequestAndNotification() {
        guard case .request(let r) = JSONRPC.parse(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#) else {
            Issue.record("expected request"); return
        }
        #expect(r.method == "tools/list")
        #expect(!r.isNotification)
        guard case .request(let n) = JSONRPC.parse(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) else {
            Issue.record("expected request"); return
        }
        #expect(n.isNotification)
    }

    @Test func rejectsBadInput() {
        guard case .failure(_, let code, _) = JSONRPC.parse("not json") else { Issue.record("expected failure"); return }
        #expect(code == JSONRPCError.parse)
        guard case .failure(let id, let code2, _) = JSONRPC.parse(#"{"jsonrpc":"1.0","id":7,"method":"x"}"#) else {
            Issue.record("expected failure"); return
        }
        #expect(code2 == JSONRPCError.invalidRequest)
        #expect(id == .number(7))
    }

    @Test func responsesAreSingleLine() {
        let text = JSONRPC.result(id: .string("a"), .object(["ok": .bool(true)]))
        #expect(!text.contains("\n"))
        #expect(text.contains(#""id":"a""#))
        #expect(JSONRPC.error(id: nil, code: -32601, message: "no").contains(#""id":null"#))
    }

    @Test func commandRoundTrips() {
        let command = AssistantCommand(id: "x", action: .setStyle, dock: "Work",
                                       style: StyleChange(iconSize: .large, autoHide: true, position: "left"))
        #expect(AssistantCommand.decode(command.encoded()) == command)
        #expect(AssistantCommand.decode("{}") == nil)
        let reply = AssistantReply(id: "x", ok: true, message: "done")
        #expect(AssistantReply.decode(reply.encoded()) == reply)
    }

    @Test func styleChangeApplies() {
        var dock = Dock(name: "A")
        #expect(StyleChange(iconSize: .small, background: .solid, autoHide: true, position: "right").apply(to: &dock))
        #expect(dock.style.iconSizePreset == .small)
        #expect(dock.style.background == .solid)
        #expect(dock.behavior.autoHide)
        #expect(dock.position.edge == .right && dock.position.mode == .pinned)
        #expect(dock.style.orientation == .vertical)
        #expect(StyleChange(position: "floating").apply(to: &dock))
        #expect(dock.position.mode == .floating)
        #expect(!StyleChange(position: "middle").apply(to: &dock))
    }

    @Test func nameMatchingIgnoresCase() {
        let docks = [Dock(name: "Work"), Dock(name: "work "), Dock(name: "Play")]
        #expect(DockMatching.matches("WORK", in: docks).count == 2)
        #expect(DockMatching.matches(nil, in: docks).count == 3)
        #expect(DockMatching.matches("none", in: docks).isEmpty)
    }

    @Test func itemMatching() {
        var dock = Dock(name: "A")
        dock.items = [DockItem(kind: .app, path: "/Applications/Safari.app")]
        #expect(DockMatching.item(named: "safari", in: dock) != nil)
        #expect(DockMatching.item(named: "mail", in: dock) == nil)
        #expect(DockSummary(dock).items == ["Safari"])
    }

    @Test func urlCommands() {
        func parse(_ s: String) -> URLCommand? { URLCommand.parse(URL(string: s)!) }
        #expect(parse("harbor://show?dock=Work%20Dock") == .show(dock: "Work Dock"))
        #expect(parse("harbor://hide") == .hide(dock: nil))
        #expect(parse("harbor://toggle?dock=") == .toggle(dock: nil))
        #expect(parse("harbor://new?name=Notes") == .new(name: "Notes"))
        #expect(parse("harbor://manager") == .manager)
        #expect(parse("harbor://bogus") == nil)
        #expect(parse("other://show") == nil)
    }
}
