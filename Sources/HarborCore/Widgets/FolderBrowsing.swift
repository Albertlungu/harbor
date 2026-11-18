import Foundation

/// One file or folder as the folder browser shows it, read once per directory scan.
public struct FolderEntry: Hashable, Sendable {
    public var url: URL
    public var name: String
    /// A folder the browser can step into; packages such as apps count as files, like in Finder.
    public var isFolder: Bool
    public var size: Int64?
    public var kind: String
    public var modified: Date?
    public var created: Date?
    public var added: Date?
    public var lastOpened: Date?

    public init(url: URL, name: String, isFolder: Bool, size: Int64? = nil, kind: String = "",
                modified: Date? = nil, created: Date? = nil, added: Date? = nil, lastOpened: Date? = nil) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.size = size
        self.kind = kind
        self.modified = modified
        self.created = created
        self.added = added
        self.lastOpened = lastOpened
    }

    /// Finder's Date Added, which falls back to the creation date for items without one, such as
    /// files on volumes that don't record when they were added.
    public var dateAdded: Date? { added ?? created }

    /// Search-field match: ignores case and accents, like Finder's name filter.
    public func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension FolderSort {
    public var title: String {
        switch self {
        case .name: "Name"
        case .kind: "Kind"
        case .dateLastOpened: "Date Last Opened"
        case .dateAdded: "Date Added"
        case .dateModified: "Date Modified"
        case .dateCreated: "Date Created"
        case .size: "Size"
        }
    }

    /// Finder's first click on a date or size column puts the newest or largest first.
    public var descendsByDefault: Bool {
        switch self {
        case .name, .kind: false
        case .dateLastOpened, .dateAdded, .dateModified, .dateCreated, .size: true
        }
    }
}

extension FolderLayout {
    public var title: String {
        switch self {
        case .grid: "Icons"
        case .list: "List"
        case .columns: "Columns"
        case .gallery: "Gallery"
        case .fan: "Fan"
        }
    }
}

extension FolderOptions {
    /// Sort direction as Finder shows it. Stored as `reverse` relative to the sort's natural
    /// direction so configs written before this setting keep their order.
    public var ascending: Bool {
        get { sort.descendsByDefault == reverse }
        set { reverse = sort.descendsByDefault == newValue }
    }

    /// Picks a sort key the way clicking a list column header does: a new key starts in its
    /// natural direction, the current key flips.
    public mutating func toggleSort(_ key: FolderSort) {
        if sort == key {
            reverse.toggle()
        } else {
            sort = key
            reverse = false
        }
    }
}

public enum FolderOrdering {
    /// `foldersFirst` only applies to the name sort, like Finder's "Keep folders on top when sorting
    /// by name": by date or size the newest or largest item leads, folder or not.
    public static func sorted(_ entries: [FolderEntry], by sort: FolderSort, ascending: Bool,
                              foldersFirst: Bool) -> [FolderEntry] {
        entries.sorted { a, b in
            if foldersFirst, sort == .name, a.isFolder != b.isFolder { return a.isFolder }
            switch compare(a, b, by: sort) {
            case .orderedAscending: return ascending
            case .orderedDescending: return !ascending
            case .orderedSame: return byName(a, b) == .orderedAscending
            }
        }
    }

    public static func sorted(_ entries: [FolderEntry], options: FolderOptions) -> [FolderEntry] {
        sorted(entries, by: options.sort, ascending: options.ascending, foldersFirst: options.foldersFirst)
    }

    static func compare(_ a: FolderEntry, _ b: FolderEntry, by sort: FolderSort) -> ComparisonResult {
        switch sort {
        case .name: byName(a, b)
        case .kind: a.kind.localizedStandardCompare(b.kind)
        case .dateLastOpened: order(a.lastOpened, b.lastOpened)
        case .dateAdded: order(a.dateAdded, b.dateAdded)
        case .dateModified: order(a.modified, b.modified)
        case .dateCreated: order(a.created, b.created)
        case .size: order(a.size, b.size)
        }
    }

    private static func byName(_ a: FolderEntry, _ b: FolderEntry) -> ComparisonResult {
        a.name.localizedStandardCompare(b.name)
    }

    /// Missing values (never opened, folders without a size) rank lowest.
    private static func order<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedAscending
        case (_, nil): .orderedDescending
        case let (a?, b?): a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        }
    }
}

/// Back and forward through the folders visited in one browser.
public struct FolderHistory: Sendable {
    public private(set) var current: URL
    private var back: [URL] = []
    private var forward: [URL] = []

    public init(root: URL) {
        current = root
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    public mutating func visit(_ url: URL) {
        guard url != current else { return }
        back.append(current)
        forward.removeAll()
        current = url
    }

    public mutating func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        current = previous
    }

    public mutating func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        current = next
    }
}

public enum FileNaming {
    /// Finder's name for a duplicate or a paste that would clash: "Report copy.pdf", then "Report copy 2.pdf".
    public static func copyName(for name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        func make(_ suffix: String) -> String {
            ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
        }
        var candidate = make("copy")
        var n = 2
        while existing.contains(candidate) {
            candidate = make("copy \(n)")
            n += 1
        }
        return candidate
    }

    /// "untitled folder", then "untitled folder 2".
    public static func newFolderName(existing: Set<String>) -> String {
        var candidate = "untitled folder"
        var n = 2
        while existing.contains(candidate) {
            candidate = "untitled folder \(n)"
            n += 1
        }
        return candidate
    }

    /// Whether a typed name can be used as a file name in place.
    public static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != "." && trimmed != ".." && !trimmed.contains("/") && !trimmed.contains(":")
    }
}
