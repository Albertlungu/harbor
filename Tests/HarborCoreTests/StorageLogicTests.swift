import Foundation
import Testing
@testable import HarborCore

@Suite struct StorageLogicTests {
    @Test func addsHTTPSWhenSchemeIsMissing() {
        #expect(StorageLogic.normalizedURL("example.com/a")?.absoluteString == "https://example.com/a")
        #expect(StorageLogic.normalizedURL("  http://example.com ")?.absoluteString == "http://example.com")
        #expect(StorageLogic.normalizedURL("") == nil)
        #expect(StorageLogic.normalizedURL("   ") == nil)
    }

    @Test func faviconCandidateUsesHost() {
        let urls = StorageLogic.faviconCandidates(for: URL(string: "https://example.com/some/page")!)
        #expect(urls.map(\.absoluteString) == ["https://example.com/favicon.ico"])
    }

    @Test func findsAppleTouchIcon() {
        let html = #"<html><head><link rel="stylesheet" href="/a.css"><link rel="apple-touch-icon" sizes="180x180" href="/icons/t.png"></head>"#
        let icon = StorageLogic.appleTouchIcon(inHTML: html, base: URL(string: "https://example.com/page")!)
        #expect(icon?.absoluteString == "https://example.com/icons/t.png")
        #expect(StorageLogic.appleTouchIcon(inHTML: "<html></html>", base: URL(string: "https://example.com")!) == nil)
    }

    @Test func uniqueNamesAreNumbered() {
        #expect(StorageLogic.uniqueName("a.txt", existing: []) == "a.txt")
        #expect(StorageLogic.uniqueName("a.txt", existing: ["a.txt"]) == "a 2.txt")
        #expect(StorageLogic.uniqueName("a.txt", existing: ["a.txt", "a 2.txt"]) == "a 3.txt")
        #expect(StorageLogic.uniqueName("folder", existing: ["folder"]) == "folder 2")
    }

    @Test func columnsAreClamped() {
        #expect(StorageLogic.clampedColumns(1) == 3)
        #expect(StorageLogic.clampedColumns(5.4) == 5)
        #expect(StorageLogic.clampedColumns(20) == 8)
    }

    @Test func trashSorting() {
        let now = Date()
        let a = TrashEntry(name: "b.txt", added: now, size: 10, kind: "Text")
        let b = TrashEntry(name: "a.png", added: now.addingTimeInterval(-60), size: 500, kind: "Image")
        let c = TrashEntry(name: "c.md", added: now.addingTimeInterval(-30), size: 5, kind: "Document")
        let all = [a, b, c]
        #expect(StorageLogic.sortTrash(all, by: .date).map(\.name) == ["b.txt", "c.md", "a.png"])
        #expect(StorageLogic.sortTrash(all, by: .name).map(\.name) == ["a.png", "b.txt", "c.md"])
        #expect(StorageLogic.sortTrash(all, by: .size).map(\.name) == ["a.png", "b.txt", "c.md"])
        #expect(StorageLogic.sortTrash(all, by: .kind).map(\.name) == ["c.md", "a.png", "b.txt"])
    }

    @Test func trashFilter() {
        let entries = [TrashEntry(name: "Report.pdf", added: .now, size: 1, kind: "PDF"),
                       TrashEntry(name: "photo.png", added: .now, size: 1, kind: "Image")]
        #expect(StorageLogic.filterTrash(entries, query: "rep").map(\.name) == ["Report.pdf"])
        #expect(StorageLogic.filterTrash(entries, query: " ").count == 2)
    }
}
