import AppKit
import HarborCore

/// Finder-style file actions for the folder browser, each undoable through one shared undo manager.
@MainActor
enum FileOperations {
    /// Browsers live in short-lived popovers, so undo history outlives any one window.
    static let undoManager = UndoManager()

    private static var fm: FileManager { .default }

    /// Moves files to the Trash; undo puts them back where they were.
    static func trash(_ urls: [URL]) {
        var moved: [(from: URL, to: URL)] = []
        for url in urls {
            var result: NSURL?
            do {
                try fm.trashItem(at: url, resultingItemURL: &result)
                if let trashed = result as URL? { moved.append((url, trashed)) }
            } catch {
                report(error)
            }
        }
        guard !moved.isEmpty else { return }
        NSSound(named: "dragToTrash")?.play()
        register(moved.count == 1 ? "Move to Trash" : "Move \(moved.count) Items to Trash") {
            restore(moved)
        }
    }

    /// Moves each pair back from `to` to `from` and registers the reverse, so redo works too.
    private static func restore(_ moves: [(from: URL, to: URL)]) {
        var done: [(from: URL, to: URL)] = []
        for move in moves {
            do {
                try fm.moveItem(at: move.to, to: move.from)
                done.append((move.to, move.from))
            } catch {
                report(error)
            }
        }
        register("Move") { restore(done) }
    }

    /// Renames in place and returns the new URL.
    @discardableResult
    static func rename(_ url: URL, to name: String) -> URL? {
        guard FileNaming.isValidName(name), name != url.lastPathComponent else { return nil }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try fm.moveItem(at: url, to: target)
        } catch {
            report(error)
            return nil
        }
        register("Rename") { restore([(url, target)]) }
        return target
    }

    /// Copies or moves files into a folder. Clashing names get Finder's "copy" suffix rather than
    /// replacing anything. Returns the new locations.
    @discardableResult
    static func transfer(_ urls: [URL], into folder: URL, move: Bool) -> [URL] {
        var existing = names(in: folder)
        var made: [(from: URL, to: URL)] = []
        for url in urls {
            // Moving a file onto its own folder is a no-op in Finder; copying it duplicates.
            if move && url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL { continue }
            if move && folder.standardizedFileURL.path.hasPrefix(url.standardizedFileURL.path + "/") { continue }
            let name = FileNaming.copyName(for: url.lastPathComponent, existing: existing)
            let target = folder.appendingPathComponent(name)
            do {
                if move { try fm.moveItem(at: url, to: target) } else { try fm.copyItem(at: url, to: target) }
                existing.insert(name)
                made.append((url, target))
            } catch {
                report(error)
            }
        }
        guard !made.isEmpty else { return [] }
        if move {
            register("Move") { restore(made) }
        } else {
            register(made.count == 1 ? "Copy" : "Copy \(made.count) Items") { trashQuietly(made.map(\.to)) }
        }
        return made.map(\.to)
    }

    static func duplicate(_ urls: [URL]) -> [URL] {
        var created: [URL] = []
        for (folder, group) in Dictionary(grouping: urls, by: { $0.deletingLastPathComponent() }) {
            created += transfer(group, into: folder, move: false)
        }
        return created
    }

    static func newFolder(in folder: URL) -> URL? {
        let target = folder.appendingPathComponent(FileNaming.newFolderName(existing: names(in: folder)))
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
        } catch {
            report(error)
            return nil
        }
        register("New Folder") { trashQuietly([target]) }
        return target
    }

    /// Zips like Finder's Compress: one item becomes "Name.zip", several become "Archive.zip".
    static func compress(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let folder = first.deletingLastPathComponent()
        let base = urls.count == 1 ? first.lastPathComponent : "Archive"
        let target = folder.appendingPathComponent(FileNaming.copyName(for: base + ".zip", existing: names(in: folder)))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        if urls.count == 1 {
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, target.path]
        } else {
            // ditto archives one source, so several items are staged in a folder named like the archive.
            let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Archive")
            do {
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                for url in urls { try fm.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent)) }
            } catch {
                report(error)
                return
            }
            process.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, target.path]
            process.terminationHandler = { _ in try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
        }
        do { try process.run() } catch { report(error) }
    }

    static func copyToPasteboard(_ urls: [URL]) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(urls as [NSURL])
    }

    static func pasteboardFiles() -> [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// Finder's own Get Info window, through its Show Info service so no Automation permission is needed.
    static func showInfo(_ urls: [URL]) {
        let board = NSPasteboard(name: NSPasteboard.Name("Harbor.ShowInfo"))
        board.clearContents()
        board.writeObjects(urls as [NSURL])
        NSPerformService("Finder/Show Info", board)
    }

    static func apps(toOpen url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    static let tagColors = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]

    static func tags(of url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    /// Adds the tag to every file, or removes it when all of them already have it.
    static func toggleTag(_ tag: String, on urls: [URL]) {
        let removing = urls.allSatisfy { tags(of: $0).contains(tag) }
        for url in urls {
            var current = tags(of: url).filter { $0 != tag }
            if !removing { current.append(tag) }
            try? (url as NSURL).setResourceValue(current, forKey: .tagNamesKey)
        }
    }

    private static func names(in folder: URL) -> Set<String> {
        Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    private static func trashQuietly(_ urls: [URL]) {
        var moved: [(from: URL, to: URL)] = []
        for url in urls {
            var result: NSURL?
            if (try? fm.trashItem(at: url, resultingItemURL: &result)) != nil, let trashed = result as URL? {
                moved.append((url, trashed))
            }
        }
        register("Move") { restore(moved) }
    }

    private static func register(_ name: String, _ undo: @escaping @MainActor () -> Void) {
        undoManager.registerUndo(withTarget: NSApplication.shared) { _ in MainActor.assumeIsolated { undo() } }
        undoManager.setActionName(name)
    }

    private static func report(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}
