import AppKit
import HarborCore
import Observation

/// Watches the folders pinned on docks so their browsers refresh live, and notices downloads
/// finishing in the real Downloads folder so its dock item can react. Browsers animate toward the
/// macOS Dock's Downloads stack, which deep hide keeps out of sight, so Harbor answers instead.
@MainActor
@Observable
final class FolderWatcher {
    static let shared = FolderWatcher()

    /// Bumped when a watched folder's entries change; keyed by resolved path.
    private(set) var revisions: [String: Int] = [:]
    /// Downloads finished recently and not yet looked at, keyed by resolved path.
    private(set) var arrivals: [String: Int] = [:]
    /// Bumped on every arrival so an item can bounce even when the count stays the same.
    private(set) var pulses: [String: Int] = [:]

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var sources: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var tracker: DownloadTracker?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    /// The latest finished download per folder, selected when its browser next opens.
    @ObservationIgnored private var newest: [String: URL] = [:]

    /// The latest arrival in a folder without consuming it, for the drop-in animation.
    func peekNewest(for key: String) -> URL? { newest[key] }

    static let downloadsPath: String = {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return key(for: url)
    }()

    static func key(for url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    /// Matches the watched set to the folder items currently on docks.
    func sync(model: AppModel) {
        self.model = model
        let wanted = Set(model.store.docks.flatMap(\.items).filter { $0.kind == .folder }.compactMap { $0.url.map(Self.key) })
        for (path, source) in sources where !wanted.contains(path) {
            source.cancel()
            sources[path] = nil
        }
        for path in wanted where sources[path] == nil {
            sources[path] = watch(path)
        }
        if wanted.contains(Self.downloadsPath) {
            if tracker == nil { tracker = DownloadTracker(existing: listing(Self.downloadsPath).keys) }
        } else {
            tracker = nil
            rescanTask?.cancel()
        }
    }

    /// Clears the arrival badge once the person has opened the folder.
    func markSeen(_ url: URL) {
        let path = Self.key(for: url)
        if arrivals[path] != nil { arrivals[path] = nil }
    }

    /// The download to highlight in a browser that is opening on `url`, handed out once.
    func takeNewest(for url: URL) -> URL? {
        newest.removeValue(forKey: Self.key(for: url))
    }

    func revision(for url: URL) -> Int { revisions[Self.key(for: url)] ?? 0 }

    private func watch(_ path: String) -> DispatchSourceFileSystemObject? {
        Self.makeSource(path) { [weak self] in self?.changed(path) }
    }

    /// A live source for one directory; the folder browser uses it for subfolders it steps into.
    static func makeSource(_ path: String, onChange: @escaping @MainActor () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        // Directory write events fire when entries are added, renamed or removed, not while a file grows.
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { onChange() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func changed(_ path: String) {
        revisions[path, default: 0] += 1
        if path == Self.downloadsPath { scanDownloads(attempts: 40) }
    }

    /// Scans now and, while a new file is still settling, again every second and a half.
    private func scanDownloads(attempts: Int) {
        guard var tracker else { return }
        let finished = tracker.update(listing(Self.downloadsPath))
        self.tracker = tracker
        if let last = finished.last { arrived(finished.count, newest: last) }
        rescanTask?.cancel()
        guard tracker.hasPending, attempts > 0 else { return }
        rescanTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.scanDownloads(attempts: attempts - 1)
        }
    }

    /// Long enough to see the file drop in, short enough not to get in the way.
    static let peekDuration = 1.3

    /// The badge stays until the folder is opened, so a download finished while away is still noticed.
    private func arrived(_ count: Int, newest name: String) {
        let path = Self.downloadsPath
        arrivals[path, default: 0] += count
        pulses[path, default: 0] += 1
        revisions[path, default: 0] += 1
        newest[path] = URL(fileURLWithPath: path).appendingPathComponent(name)
        guard let model, model.store.settings.peekOnDownload else { return }
        for dock in model.store.docks where dock.items.contains(where: { $0.kind == .folder && $0.url.map(Self.key) == path }) {
            for controller in model.dockController.controllers(for: dock.id) {
                controller.peek(duration: Self.peekDuration)
            }
        }
    }

    private func listing(_ path: String) -> [String: FileSnapshot] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys)) ?? []
        var result: [String: FileSnapshot] = [:]
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            // Folders (an unpacked archive) have no size of their own; any nonzero stand-in lets them settle.
            let size = values?.isDirectory == true ? 1 : Int64(values?.fileSize ?? 0)
            result[url.lastPathComponent] = FileSnapshot(size: size, modified: values?.contentModificationDate ?? .distantPast)
        }
        return result
    }
}
