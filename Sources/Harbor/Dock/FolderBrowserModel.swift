import AppKit
import CoreServices
import HarborCore
import Observation
import QuickLookUI

/// State and commands for one folder popover: the folder shown, its entries, the selection, and
/// the Finder actions the views and the keyboard trigger.
@MainActor
@Observable
final class FolderBrowserModel {
    let root: URL
    private(set) var history: FolderHistory
    private(set) var options: FolderOptions
    /// Sorted entries of the current folder.
    private(set) var entries: [FolderEntry] = []
    /// `entries` narrowed by the search field.
    private(set) var visible: [FolderEntry] = []
    var query = "" {
        didSet { refilter() }
    }
    private(set) var selection: Set<URL> = []
    /// Bumped when the model picks the selection itself, so views apply it and scroll to it.
    private(set) var selectionRevision = 0
    /// The entry whose name is being edited in place.
    var renaming: URL?
    private(set) var denied = false
    private(set) var loaded = false
    /// Bumped on every reload so views holding their own caches (the column view) refresh too.
    private(set) var contentRevision = 0

    @ObservationIgnored private let persist: (FolderOptions) -> Void
    @ObservationIgnored let close: () -> Void
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var selectAfterLoad: [URL] = []
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored weak var window: NSWindow?

    var current: URL { history.current }

    init(root: URL, options: FolderOptions, persist: @escaping (FolderOptions) -> Void, close: @escaping () -> Void) {
        self.root = root
        self.options = options
        self.persist = persist
        self.close = close
        history = FolderHistory(root: root)
    }

    // MARK: Loading

    func start() {
        if let newest = FolderWatcher.shared.takeNewest(for: root) { selectAfterLoad = [newest] }
        FolderWatcher.shared.markSeen(root)
        show(current)
    }

    func stop() {
        source?.cancel()
        source = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func show(_ url: URL) {
        source?.cancel()
        source = FolderWatcher.makeSource(url.path) { [weak self] in self?.reload() }
        loaded = false
        reload()
    }

    /// Reads the folder off the main thread, prefetching every value the views and sorts need.
    func reload() {
        generation += 1
        let token = generation
        let folder = current
        let showHidden = options.showHidden
        let wantsLastOpened = options.sort == .dateLastOpened
        Task.detached(priority: .userInitiated) {
            let read = Self.read(folder, showHidden: showHidden, lastOpened: wantsLastOpened)
            await MainActor.run { [weak self] in
                guard let self, self.generation == token else { return }
                self.denied = read == nil
                self.entries = FolderOrdering.sorted(read ?? [], options: self.options)
                self.loaded = true
                self.contentRevision += 1
                self.refilter()
                if !self.selectAfterLoad.isEmpty {
                    self.select(self.selectAfterLoad)
                    self.selectAfterLoad = []
                } else {
                    let present = Set(self.visible.map(\.url))
                    if !self.selection.isSubset(of: present) { self.selection.formIntersection(present) }
                }
            }
        }
    }

    private nonisolated static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .fileSizeKey, .localizedNameKey, .localizedTypeDescriptionKey,
        .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
    ]

    private nonisolated static func read(_ folder: URL, showHidden: Bool, lastOpened: Bool) -> [FolderEntry]? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: showHidden ? [] : [.skipsHiddenFiles]) else { return nil }
        return urls.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = v?.isDirectory == true && v?.isPackage != true
            return FolderEntry(
                url: url, name: v?.localizedName ?? url.lastPathComponent, isFolder: isFolder,
                size: isFolder ? nil : v?.fileSize.map(Int64.init), kind: v?.localizedTypeDescription ?? "",
                modified: v?.contentModificationDate, created: v?.creationDate, added: v?.addedToDirectoryDate,
                // Finder's "Date Last Opened" is Spotlight's last-used date; only read when sorting by it.
                lastOpened: lastOpened ? lastUsed(url) : nil)
        }
    }

    private nonisolated static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    private func refilter() {
        visible = query.isEmpty ? entries : entries.filter { $0.matches(query) }
    }

    func entry(for url: URL) -> FolderEntry? { visible.first { $0.url == url } }

    // MARK: Options

    /// Applies an options change and saves it on the dock item straight away.
    func updateOptions(_ change: (inout FolderOptions) -> Void) {
        let before = options
        change(&options)
        guard options != before else { return }
        persist(options)
        if options.showHidden != before.showHidden || (options.sort == .dateLastOpened && before.sort != .dateLastOpened) {
            reload()
        } else {
            entries = FolderOrdering.sorted(entries, options: options)
            contentRevision += 1
            refilter()
        }
    }

    /// Saves a hand-picked popover size; nothing listed changes, so the entries aren't re-sorted.
    func saveSize(_ size: CGSize) {
        options.browserWidth = Double(size.width.rounded())
        options.browserHeight = Double(size.height.rounded())
        persist(options)
    }

    /// Takes options edited elsewhere, such as the item's settings sheet.
    func adopt(_ new: FolderOptions) {
        guard new != options else { return }
        updateOptions { $0 = new }
    }

    // MARK: Navigation

    func navigate(to url: URL) {
        history.visit(url)
        didNavigate(from: nil)
    }

    func goBack() {
        let from = current
        history.goBack()
        didNavigate(from: from)
    }

    func goForward() {
        history.goForward()
        didNavigate(from: nil)
    }

    func goUp() {
        let parent = current.deletingLastPathComponent()
        guard parent.path != current.path else { return }
        let from = current
        history.visit(parent)
        didNavigate(from: from)
    }

    var canGoUp: Bool { current.path != "/" }

    /// Going back or up selects the folder just left, as Finder does.
    private func didNavigate(from: URL?) {
        query = ""
        selection = []
        selectAfterLoad = from.map { [$0] } ?? []
        show(current)
    }

    // MARK: Selection

    func selectionChanged(_ urls: Set<URL>) {
        if urls != selection { selection = urls }
        QuickLook.shared.follow(selectedURLs)
    }

    func select(_ urls: [URL]) {
        selection = Set(urls)
        selectionRevision += 1
    }

    /// The selection in display order.
    var selectedURLs: [URL] { visible.map(\.url).filter(selection.contains) }

    // MARK: Actions

    func open(_ urls: [URL]) {
        guard let first = urls.first else { return }
        if urls.count == 1, entry(for: first)?.isFolder ?? isFolder(first) {
            navigate(to: first)
            return
        }
        for url in urls { NSWorkspace.shared.open(url) }
        close()
    }

    private func isFolder(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return v?.isDirectory == true && v?.isPackage != true
    }

    func openSelection() { open(selectedURLs) }

    func quickLook() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        QuickLook.shared.toggle(urls)
    }

    func beginRename() {
        guard selection.count == 1, let url = selection.first else { return }
        renaming = url
    }

    func commitRename(_ url: URL, to name: String) {
        renaming = nil
        if let renamed = FileOperations.rename(url, to: name) { selectAfterLoad = [renamed] }
    }

    func trashSelection() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        FileOperations.trash(urls)
    }

    func duplicateSelection() {
        let made = FileOperations.duplicate(selectedURLs)
        if !made.isEmpty { selectAfterLoad = made }
    }

    func newFolder() {
        guard let made = FileOperations.newFolder(in: current) else { return }
        selectAfterLoad = [made]
        renaming = made
    }

    func compressSelection() { FileOperations.compress(selectedURLs) }

    func copySelection() {
        guard !selection.isEmpty else { return }
        FileOperations.copyToPasteboard(selectedURLs)
    }

    func paste() {
        let made = FileOperations.transfer(FileOperations.pasteboardFiles(), into: current, move: false)
        if !made.isEmpty { selectAfterLoad = made }
    }

    func showInfo() {
        let urls = selection.isEmpty ? [current] : selectedURLs
        FileOperations.showInfo(urls)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(selection.isEmpty ? [current] : selectedURLs)
        close()
    }

    func openCurrentInFinder() {
        NSWorkspace.shared.open(current)
        close()
    }

    func undo() { if FileOperations.undoManager.canUndo { FileOperations.undoManager.undo() } }
    func redo() { if FileOperations.undoManager.canRedo { FileOperations.undoManager.redo() } }

    // MARK: Drops

    /// Finder's modifiers: Option copies, Command moves. Without either a drop copies, except when
    /// the files come from this browser, where it moves them into the folder they were dropped on.
    func dropOperation(_ info: NSDraggingInfo, fromSelf: Bool) -> NSDragOperation {
        let mask = info.draggingSourceOperationMask
        let flags = NSEvent.modifierFlags
        if flags.contains(.option), mask.contains(.copy) { return .copy }
        if flags.contains(.command), mask.contains(.move) || mask.contains(.generic) { return .move }
        if fromSelf, mask.contains(.move) || mask.contains(.generic) { return .move }
        return mask.contains(.copy) ? .copy : (mask.contains(.move) ? .move : [])
    }

    func acceptDrop(_ info: NSDraggingInfo, into folder: URL?, fromSelf: Bool) -> Bool {
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                        options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let target = folder ?? current
        guard !urls.isEmpty, !urls.contains(target) else { return false }
        let made = FileOperations.transfer(urls, into: target, move: dropOperation(info, fromSelf: fromSelf) == .move)
        if target == current, !made.isEmpty { selectAfterLoad = made }
        return !made.isEmpty
    }

    func draggedOut() {
        if options.closeAfterDragOut { close() }
    }

    // MARK: Keyboard

    /// Routes Finder's shortcuts for the popover's window. A local monitor sees keys before the
    /// table, collection and browser views do, so every view gets the same shortcuts.
    func installKeyMonitor(for window: NSWindow) {
        self.window = window
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // Text being typed (search field, rename) keeps its own keys, apart from Escape.
        if window?.firstResponder is NSText {
            return false
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, event.keyCode) {
        case ([], 49): quickLook()
        case ([], 36), ([], 76): beginRename()
        case ([], 53): close()
        case ([.command], 125): openSelection()
        case ([.command], 126): goUp()
        case ([.command], 51): trashSelection()
        default:
            switch (flags, chars) {
            case ([.command], "o"): openSelection()
            case ([.command], "d"): duplicateSelection()
            case ([.command], "c"): copySelection()
            case ([.command], "v"): paste()
            case ([.command], "z"): undo()
            case ([.command, .shift], "z"): redo()
            case ([.command, .shift], "n"): newFolder()
            case ([.command], "i"): showInfo()
            case ([.command], "["): goBack()
            case ([.command], "]"): goForward()
            case ([.command], "a"): select(visible.map(\.url))
            default: return false
            }
        }
        return true
    }

    // MARK: Menus

    /// The right-click menu for the clicked entry, or for the folder's background when `clicked` is nil.
    func contextMenu(clicked: URL?) -> NSMenu {
        if let clicked, !selection.contains(clicked) { select([clicked]) }
        let menu = NSMenu()
        let urls = clicked == nil ? [] : selectedURLs
        if urls.isEmpty {
            menu.addItem(action("New Folder") { [weak self] in self?.newFolder() })
            menu.addItem(action("Get Info") { [weak self] in self?.showInfo() })
            if !FileOperations.pasteboardFiles().isEmpty {
                menu.addItem(action("Paste") { [weak self] in self?.paste() })
            }
            menu.addItem(.separator())
            menu.addItem(submenu("View", items: [FolderLayout.grid, .list, .columns, .gallery].map { layout in
                let item = action(layout.title) { [weak self] in self?.updateOptions { $0.layout = layout } }
                item.state = options.layout == layout ? .on : .off
                return item
            }))
            menu.addItem(submenu("Sort By", items: sortItems()))
            menu.addItem(.separator())
            menu.addItem(action("Open in Finder") { [weak self] in self?.openCurrentInFinder() })
            return menu
        }
        menu.addItem(action("Open") { [weak self] in self?.open(urls) })
        if urls.count == 1, let url = urls.first {
            menu.addItem(openWithMenu(url))
        }
        menu.addItem(.separator())
        menu.addItem(action("Move to Trash") { [weak self] in self?.trashSelection() })
        menu.addItem(.separator())
        menu.addItem(action("Get Info") { [weak self] in self?.showInfo() })
        if urls.count == 1 { menu.addItem(action("Rename") { [weak self] in self?.beginRename() }) }
        menu.addItem(action(urls.count == 1 ? "Compress \"\(urls[0].lastPathComponent)\"" : "Compress \(urls.count) Items") {
            [weak self] in self?.compressSelection()
        })
        menu.addItem(action("Duplicate") { [weak self] in self?.duplicateSelection() })
        menu.addItem(action("Quick Look") { [weak self] in self?.quickLook() })
        menu.addItem(.separator())
        menu.addItem(action(urls.count == 1 ? "Copy" : "Copy \(urls.count) Items") { [weak self] in self?.copySelection() })
        menu.addItem(.separator())
        menu.addItem(tagsMenu(urls))
        menu.addItem(.separator())
        menu.addItem(action("Show in Finder") { [weak self] in self?.revealInFinder() })
        return menu
    }

    func sortItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = FolderSort.allCases.map { key in
            let item = action(key.title) { [weak self] in
                self?.updateOptions { $0.sort = key; $0.reverse = false }
            }
            item.state = options.sort == key ? .on : .off
            return item
        }
        items.append(.separator())
        let ascending = action("Ascending") { [weak self] in self?.updateOptions { $0.ascending = true } }
        ascending.state = options.ascending ? .on : .off
        let descending = action("Descending") { [weak self] in self?.updateOptions { $0.ascending = false } }
        descending.state = options.ascending ? .off : .on
        let folders = action("Folders First") { [weak self] in self?.updateOptions { $0.foldersFirst.toggle() } }
        folders.state = options.foldersFirst ? .on : .off
        // Only the name sort keeps folders on top; menu autoenabling greys out an item without an action.
        if options.sort != .name { folders.action = nil }
        items += [ascending, descending, .separator(), folders]
        return items
    }

    private func openWithMenu(_ url: URL) -> NSMenuItem {
        let apps = FileOperations.apps(toOpen: url)
        let items = apps.prefix(12).enumerated().map { index, app in
            let name = FileManager.default.displayName(atPath: app.path) + (index == 0 ? " (default)" : "")
            let item = action(name) { [weak self] in
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                self?.close()
            }
            let icon = IconProvider.icon(forPath: app.path).copy() as? NSImage
            icon?.size = NSSize(width: 16, height: 16)
            item.image = icon
            return item
        }
        return submenu("Open With", items: Array(items))
    }

    private func tagsMenu(_ urls: [URL]) -> NSMenuItem {
        let items = FileOperations.tagColors.map { tag in
            let item = action(tag) { FileOperations.toggleTag(tag, on: urls) }
            item.state = urls.allSatisfy { FileOperations.tags(of: $0).contains(tag) } ? .on : .off
            return item
        }
        return submenu("Tags", items: items)
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    private func action(_ title: String, _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, run: run)
    }
}

/// A menu item that runs a closure, so menus can be built without a target object per action.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}

/// Drives the shared Quick Look panel for the browser's selection.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var urls: [URL] = []

    func preview(_ url: URL) { show([url]) }

    func toggle(_ urls: [URL]) {
        if let panel = QLPreviewPanel.shared(), panel.isVisible, panel.dataSource === self {
            panel.orderOut(nil)
        } else {
            show(urls)
        }
    }

    /// Keeps an open panel on the current selection, like Finder while arrowing through files.
    func follow(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared(), panel.isVisible, panel.dataSource === self else { return }
        self.urls = urls
        panel.reloadData()
    }

    private func show(_ urls: [URL]) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let url: NSURL? = MainActor.assumeIsolated { urls.indices.contains(index) ? urls[index] as NSURL : nil }
        return url
    }
}
