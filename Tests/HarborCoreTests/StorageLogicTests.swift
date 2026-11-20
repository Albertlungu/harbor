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
}
