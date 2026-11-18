import Foundation
import Testing
@testable import HarborCore

@Suite struct FolderBrowsingTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func entry(_ name: String, folder: Bool = false, size: Int64? = nil, kind: String = "",
                       modified: Double? = nil, created: Double? = nil, added: Double? = nil,
                       opened: Double? = nil) -> FolderEntry {
        FolderEntry(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, isFolder: folder, size: size, kind: kind,
                    modified: modified.map { t0.addingTimeInterval($0) }, created: created.map { t0.addingTimeInterval($0) },
                    added: added.map { t0.addingTimeInterval($0) },
                    lastOpened: opened.map { t0.addingTimeInterval($0) })
    }

    private func names(_ entries: [FolderEntry]) -> [String] { entries.map(\.name) }

    @Test func nameSortIsNumericAware() {
        let list = [entry("file10"), entry("file2"), entry("File1")]
        #expect(names(FolderOrdering.sorted(list, by: .name, ascending: true, foldersFirst: false)) == ["File1", "file2", "file10"])
        #expect(names(FolderOrdering.sorted(list, by: .name, ascending: false, foldersFirst: false)) == ["file10", "file2", "File1"])
    }

    @Test func foldersFirstHoldsInBothDirections() {
        let list = [entry("b"), entry("a", folder: true), entry("c", folder: true)]
        #expect(names(FolderOrdering.sorted(list, by: .name, ascending: true, foldersFirst: true)) == ["a", "c", "b"])
        #expect(names(FolderOrdering.sorted(list, by: .name, ascending: false, foldersFirst: true)) == ["c", "a", "b"])
        #expect(names(FolderOrdering.sorted(list, by: .name, ascending: true, foldersFirst: false)) == ["a", "b", "c"])
    }

    @Test func dateSortPutsMissingDatesLowestAndBreaksTiesByName() {
        let list = [entry("old", modified: 1), entry("new", modified: 9), entry("none"), entry("also", modified: 9)]
        #expect(names(FolderOrdering.sorted(list, by: .dateModified, ascending: false, foldersFirst: false)) == ["also", "new", "old", "none"])
        #expect(names(FolderOrdering.sorted(list, by: .dateModified, ascending: true, foldersFirst: false)) == ["none", "old", "also", "new"])
    }

    @Test func sizeKindAddedAndOpenedSorts() {
        let list = [entry("a", size: 5, kind: "PDF", added: 3, opened: 1), entry("b", size: 50, kind: "Folder", added: 1),
                    entry("c", size: 1, kind: "Image", added: 2, opened: 7)]
        #expect(names(FolderOrdering.sorted(list, by: .size, ascending: false, foldersFirst: false)) == ["b", "a", "c"])
        #expect(names(FolderOrdering.sorted(list, by: .kind, ascending: true, foldersFirst: false)) == ["b", "c", "a"])
        #expect(names(FolderOrdering.sorted(list, by: .dateAdded, ascending: false, foldersFirst: false)) == ["a", "c", "b"])
        #expect(names(FolderOrdering.sorted(list, by: .dateLastOpened, ascending: false, foldersFirst: false)) == ["c", "a", "b"])
    }

    @Test func dateAddedFallsBackToCreationAndRanksMissingDatesLowest() {
        // "copied" has no added date, as on volumes that don't record one, so its creation date stands in.
        let list = [entry("old", created: 0, added: 2), entry("copied", created: 5), entry("none"),
                    entry("new", created: 1, added: 8), entry("tie", added: 5)]
        #expect(names(FolderOrdering.sorted(list, by: .dateAdded, ascending: false, foldersFirst: false))
            == ["new", "copied", "tie", "old", "none"])
        #expect(names(FolderOrdering.sorted(list, by: .dateAdded, ascending: true, foldersFirst: false))
            == ["none", "old", "copied", "tie", "new"])
        #expect(entry("x", created: 3).dateAdded == t0.addingTimeInterval(3))
        #expect(entry("x").dateAdded == nil)
    }

    @Test func foldersOnlyStayOnTopWhenSortingByName() {
        let list = [entry("file", added: 9), entry("Folder", folder: true, added: 1), entry("mid", added: 5)]
        #expect(names(FolderOrdering.sorted(list, by: .dateAdded, ascending: false, foldersFirst: true)) == ["file", "mid", "Folder"])
        #expect(names(FolderOrdering.sorted(list, by: .name, ascending: true, foldersFirst: true)) == ["Folder", "file", "mid"])
        var options = FolderOptions()
        options.sort = .dateAdded
        #expect(options.foldersFirst && !options.ascending)
        #expect(names(FolderOrdering.sorted(list, options: options)) == ["file", "mid", "Folder"])
    }

    @Test func ascendingMapsOntoReverseRelativeToNaturalDirection() {
        var options = FolderOptions()
        #expect(options.sort == .name && options.ascending)
        options.sort = .dateModified
        #expect(!options.ascending)
        options.ascending = true
        #expect(options.reverse)
        options.toggleSort(.size)
        #expect(options.sort == .size && !options.reverse && !options.ascending)
        options.toggleSort(.size)
        #expect(options.ascending)
        options.toggleSort(.name)
        #expect(options.sort == .name && options.ascending)
    }

    @Test func searchIgnoresCaseAndAccents() {
        #expect(entry("Résumé.pdf").matches("resume"))
        #expect(entry("Notes.txt").matches(" NOTE "))
        #expect(entry("Notes.txt").matches(""))
        #expect(!entry("Notes.txt").matches("pdf"))
    }

    @Test func historyGoesBackAndForwardAndForgetsForwardOnVisit() {
        let root = URL(fileURLWithPath: "/a")
        let b = URL(fileURLWithPath: "/a/b"), c = URL(fileURLWithPath: "/a/b/c")
        var history = FolderHistory(root: root)
        #expect(!history.canGoBack && !history.canGoForward)
        history.visit(b)
        history.visit(c)
        history.goBack()
        #expect(history.current == b && history.canGoForward)
        history.goBack()
        #expect(history.current == root && !history.canGoBack)
        history.goForward()
        #expect(history.current == b)
        history.visit(URL(fileURLWithPath: "/a/d"))
        #expect(!history.canGoForward)
        history.visit(URL(fileURLWithPath: "/a/d"))
        history.goBack()
        #expect(history.current == b)
    }

    @Test func copyNamesFollowFinder() {
        #expect(FileNaming.copyName(for: "a.pdf", existing: []) == "a.pdf")
        #expect(FileNaming.copyName(for: "a.pdf", existing: ["a.pdf"]) == "a copy.pdf")
        #expect(FileNaming.copyName(for: "a.pdf", existing: ["a.pdf", "a copy.pdf"]) == "a copy 2.pdf")
        #expect(FileNaming.copyName(for: "Makefile", existing: ["Makefile"]) == "Makefile copy")
        #expect(FileNaming.newFolderName(existing: ["untitled folder"]) == "untitled folder 2")
        #expect(FileNaming.isValidName("ok name.txt"))
        #expect(!FileNaming.isValidName("  "))
        #expect(!FileNaming.isValidName("a/b"))
    }

    @Test func oldConfigsKeepTheirFolderSettingsAndUnknownValuesFallBack() throws {
        let old = #"{"layout":"fan","sort":"dateModified","reverse":false,"columns":4}"#
        let options = try JSONDecoder().decode(FolderOptions.self, from: Data(old.utf8))
        #expect(options.layout == .fan && options.sort == .dateModified && options.columns == 4 && !options.ascending)
        let future = #"{"layout":"coverFlow","sort":"tags"}"#
        let fallback = try JSONDecoder().decode(FolderOptions.self, from: Data(future.utf8))
        #expect(fallback.layout == .grid && fallback.sort == .name)
        var new = FolderOptions()
        new.layout = .gallery
        new.sort = .size
        let round = try JSONDecoder().decode(FolderOptions.self, from: JSONEncoder().encode(new))
        #expect(round.layout == .gallery && round.sort == .size)
    }
}
