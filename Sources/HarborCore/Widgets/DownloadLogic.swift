import Foundation

/// What a folder scan records about one entry.
public struct FileSnapshot: Hashable, Sendable {
    public var size: Int64
    public var modified: Date

    public init(size: Int64, modified: Date) {
        self.size = size
        self.modified = modified
    }
}

/// Spots downloads that have finished arriving in a folder, from successive scans of it.
///
/// Browsers write to a temporary name (.crdownload, .download, .part) and rename it when done,
/// but some create the final name early and fill it in, so a new file only counts once it is not
/// a partial name, has no partial sibling, and has the same size and date on two scans in a row.
public struct DownloadTracker: Sendable {
    /// Names present when watching began or already reported; never reported again.
    private var known: Set<String>
    /// New names waiting to settle, with what the latest scan saw.
    private var pending: [String: FileSnapshot] = [:]

    public static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload", "tmp"]

    public init(existing: some Sequence<String>) {
        known = Set(existing)
    }

    /// True while some new file is still settling, so the caller should scan again shortly.
    public var hasPending: Bool { !pending.isEmpty }

    public static func isPartial(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return partialExtensions.contains(ext)
    }

    /// Feeds one scan of the folder and returns the names that finished arriving since the last one.
    public mutating func update(_ listing: [String: FileSnapshot]) -> [String] {
        known.formIntersection(listing.keys)
        let partialStems = Set(listing.keys.filter(Self.isPartial).map { ($0 as NSString).deletingPathExtension })
        var finished: [String] = []
        var stillPending: [String: FileSnapshot] = [:]
        for (name, snapshot) in listing where !known.contains(name) && !Self.isPartial(name) {
            let settling = snapshot.size == 0 || partialStems.contains(name)
            if !settling, let previous = pending[name], previous == snapshot {
                finished.append(name)
                known.insert(name)
            } else {
                // A settling file needs one more matching scan after it stops settling.
                stillPending[name] = settling ? FileSnapshot(size: -1, modified: snapshot.modified) : snapshot
            }
        }
        pending = stillPending
        return finished.sorted()
    }
}
