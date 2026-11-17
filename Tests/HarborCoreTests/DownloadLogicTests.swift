import Foundation
import Testing
@testable import HarborCore

@Suite struct DownloadLogicTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func snap(_ size: Int64, _ seconds: Double = 0) -> FileSnapshot {
        FileSnapshot(size: size, modified: t0.addingTimeInterval(seconds))
    }

    @Test func existingFilesAreNeverReported() {
        var tracker = DownloadTracker(existing: ["old.zip"])
        #expect(tracker.update(["old.zip": snap(10)]).isEmpty)
        #expect(tracker.update(["old.zip": snap(10)]).isEmpty)
        #expect(!tracker.hasPending)
    }

    @Test func newFileReportsOnceItSettles() {
        var tracker = DownloadTracker(existing: [])
        #expect(tracker.update(["a.pdf": snap(100)]).isEmpty)
        #expect(tracker.hasPending)
        #expect(tracker.update(["a.pdf": snap(100)]) == ["a.pdf"])
        #expect(!tracker.hasPending)
        #expect(tracker.update(["a.pdf": snap(100)]).isEmpty)
    }

    @Test func growingFileWaits() {
        var tracker = DownloadTracker(existing: [])
        _ = tracker.update(["a.iso": snap(100, 1)])
        #expect(tracker.update(["a.iso": snap(500, 2)]).isEmpty)
        #expect(tracker.update(["a.iso": snap(500, 2)]) == ["a.iso"])
    }

    @Test func chromeRenameIsReportedOnlyForTheFinalName() {
        var tracker = DownloadTracker(existing: [])
        #expect(tracker.update(["a.zip.crdownload": snap(50)]).isEmpty)
        #expect(tracker.update(["a.zip.crdownload": snap(90)]).isEmpty)
        #expect(!tracker.hasPending)
        _ = tracker.update(["a.zip": snap(100)])
        #expect(tracker.update(["a.zip": snap(100)]) == ["a.zip"])
    }

    @Test func firefoxPlaceholderWaitsForItsPartFile() {
        var tracker = DownloadTracker(existing: [])
        let busy = ["b.dmg": snap(0), "b.dmg.part": snap(400)]
        #expect(tracker.update(busy).isEmpty)
        #expect(tracker.update(busy).isEmpty)
        // A filled placeholder still waits while its .part sibling exists.
        #expect(tracker.update(["b.dmg": snap(800), "b.dmg.part": snap(800)]).isEmpty)
        #expect(tracker.update(["b.dmg": snap(800), "b.dmg.part": snap(800)]).isEmpty)
        _ = tracker.update(["b.dmg": snap(800)])
        #expect(tracker.update(["b.dmg": snap(800)]) == ["b.dmg"])
    }

    @Test func partialAndHiddenNamesAreIgnored() {
        #expect(DownloadTracker.isPartial("x.crdownload"))
        #expect(DownloadTracker.isPartial("x.download"))
        #expect(DownloadTracker.isPartial("x.PART"))
        #expect(DownloadTracker.isPartial(".DS_Store"))
        #expect(!DownloadTracker.isPartial("report.pdf"))
    }

    @Test func removedAndReaddedFileCountsAgain() {
        var tracker = DownloadTracker(existing: ["a.pdf"])
        _ = tracker.update([:])
        _ = tracker.update(["a.pdf": snap(5)])
        #expect(tracker.update(["a.pdf": snap(5)]) == ["a.pdf"])
    }
}
