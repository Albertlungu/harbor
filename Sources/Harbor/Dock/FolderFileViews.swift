import AppKit
import HarborCore
import QuickLookUI
import SwiftUI

// The browser's file views are AppKit's own: NSCollectionView for icons and the gallery strip,
// NSTableView for the list and NSBrowser for columns. They recycle cells, so folders with
// thousands of entries scroll smoothly, and they bring Finder's selection model (Command and
// Shift clicks, rubber-band selection, arrow keys, type-select) and multi-item drags without
// reimplementing them, which SwiftUI's List and LazyVGrid can't do.

private let fileURLType = NSPasteboard.PasteboardType.fileURL

// MARK: Icons and gallery strip

struct FolderIconsView: NSViewRepresentable {
    let model: FolderBrowserModel
    /// The gallery's single row of small thumbnails without names.
    var strip = false

    func makeCoordinator() -> FolderCollectionCoordinator { FolderCollectionCoordinator(model: model, strip: strip) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let collection = FolderCollectionView()
        collection.coordinator = coordinator
        collection.collectionViewLayout = coordinator.makeLayout()
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.backgroundColors = [.clear]
        collection.register(FolderIconItem.self, forItemWithIdentifier: FolderIconItem.identifier)
        collection.dataSource = coordinator
        collection.delegate = coordinator
        collection.registerForDraggedTypes([fileURLType])
        collection.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        collection.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        coordinator.collection = collection

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = !strip
        scroll.hasHorizontalScroller = strip
        scroll.autohidesScrollers = true
        coordinator.sync()
        DispatchQueue.main.async { collection.window?.makeFirstResponder(collection) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.sync()
    }
}

@MainActor
final class FolderCollectionCoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let model: FolderBrowserModel
    let strip: Bool
    weak var collection: NSCollectionView?
    private var shown: [FolderEntry] = []
    private var layoutKey: [CGFloat] = []
    private var appliedSelection = -1

    init(model: FolderBrowserModel, strip: Bool) {
        self.model = model
        self.strip = strip
    }

    var iconSide: CGFloat { strip ? 48 : CGFloat(model.options.iconSize) }
    var showNames: Bool { !strip && model.options.showNames }

    func makeLayout() -> NSCollectionViewFlowLayout {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = strip ? .horizontal : .vertical
        layout.itemSize = NSSize(width: iconSide + 28, height: iconSide + (showNames ? 44 : 14))
        layout.minimumInteritemSpacing = strip ? 2 : 6
        layout.minimumLineSpacing = strip ? 2 : 10
        layout.sectionInset = strip ? NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            : NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        return layout
    }

    /// Pushes model changes into the view: entries, sizes and selection.
    func sync() {
        guard let collection else { return }
        let key = [iconSide, showNames ? 1 : 0]
        if key != layoutKey {
            layoutKey = key
            collection.collectionViewLayout = makeLayout()
        }
        if shown != model.visible {
            shown = model.visible
            collection.reloadData()
            appliedSelection = -1
        }
        if appliedSelection != model.selectionRevision || Set(collection.selectionIndexPaths) != indexPaths(model.selection) {
            appliedSelection = model.selectionRevision
            let paths = indexPaths(model.selection)
            collection.selectionIndexPaths = paths
            if let first = paths.min() { collection.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge.union(.nearestVerticalEdge)) }
        }
        if let renaming = model.renaming, let index = shown.firstIndex(where: { $0.url == renaming }),
           let item = collection.item(at: IndexPath(item: index, section: 0)) as? FolderIconItem {
            item.beginEditing { [weak self] name in self?.model.commitRename(renaming, to: name) }
        }
    }

    private func indexPaths(_ urls: Set<URL>) -> Set<IndexPath> {
        Set(shown.indices.filter { urls.contains(shown[$0].url) }.map { IndexPath(item: $0, section: 0) })
    }

    func entry(at indexPath: IndexPath) -> FolderEntry? {
        shown.indices.contains(indexPath.item) ? shown[indexPath.item] : nil
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { shown.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: FolderIconItem.identifier, for: indexPath)
        if let item = item as? FolderIconItem, let entry = entry(at: indexPath) {
            item.configure(entry, side: iconSide, showName: showNames, previews: model.options.showPreviews)
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { pushSelection() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { pushSelection() }

    private func pushSelection() {
        guard let collection else { return }
        model.selectionChanged(Set(collection.selectionIndexPaths.compactMap { entry(at: $0)?.url }))
    }

    // Dragging out
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { true }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        entry(at: indexPath)?.url as NSURL?
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        if !operation.isEmpty { model.draggedOut() }
    }

    // Dropping in: onto a folder puts files inside it, anywhere else into the folder shown.
    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let fromSelf = draggingInfo.draggingSource as? NSCollectionView === collectionView
        if dropOperation.pointee == .on, let target = entry(at: proposedIndexPath.pointee as IndexPath), target.isFolder {
            if fromSelf, model.selection.contains(target.url) { return [] }
            return model.dropOperation(draggingInfo, fromSelf: fromSelf)
        }
        if fromSelf { return [] }
        dropOperation.pointee = .before
        proposedIndexPath.pointee = NSIndexPath(forItem: shown.count, inSection: 0)
        return model.dropOperation(draggingInfo, fromSelf: false)
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let fromSelf = draggingInfo.draggingSource as? NSCollectionView === collectionView
        let folder = dropOperation == .on ? entry(at: indexPath).flatMap { $0.isFolder ? $0.url : nil } : nil
        return model.acceptDrop(draggingInfo, into: folder, fromSelf: fromSelf)
    }
}

/// Adds double-click and the right-click menu, which NSCollectionView leaves to its owner.
final class FolderCollectionView: NSCollectionView {
    weak var coordinator: FolderCollectionCoordinator?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2, let coordinator else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let path = indexPathForItem(at: point), let entry = coordinator.entry(at: path) {
            coordinator.model.open(entry.isFolder ? [entry.url] : coordinator.model.selectedURLs)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let clicked = indexPathForItem(at: point).flatMap { coordinator.entry(at: $0)?.url }
        return coordinator.model.contextMenu(clicked: clicked)
    }
}

/// One icon with its name, highlighted like Finder's icon view when selected.
final class FolderIconItem: NSCollectionViewItem, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("FolderIconItem")

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let iconBackground = NSView()
    private var url: URL?
    private var onRename: ((String) -> Void)?

    override func loadView() {
        let root = NSView()
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 6
        icon.imageScaling = .scaleProportionallyUpOrDown
        name.alignment = .center
        name.font = .systemFont(ofSize: 11)
        name.maximumNumberOfLines = 2
        name.lineBreakMode = .byTruncatingMiddle
        name.cell?.truncatesLastVisibleLine = true
        name.wantsLayer = true
        name.layer?.cornerRadius = 4
        name.delegate = self
        for view in [iconBackground, icon, name] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            icon.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            icon.widthAnchor.constraint(equalTo: icon.heightAnchor),
            icon.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
            iconBackground.topAnchor.constraint(equalTo: icon.topAnchor, constant: -4),
            iconBackground.bottomAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            iconBackground.leadingAnchor.constraint(equalTo: icon.leadingAnchor, constant: -4),
            iconBackground.trailingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 5),
            name.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 1),
            name.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -1),
        ])
        view = root
    }

    func configure(_ entry: FolderEntry, side: CGFloat, showName: Bool, previews: Bool) {
        url = entry.url
        name.stringValue = entry.name
        name.isHidden = !showName
        name.isEditable = false
        let fallback = IconProvider.icon(forPath: entry.url.path)
        icon.image = Thumbnails.cached(entry.url, side: side, modified: entry.modified) ?? fallback
        if previews, !entry.isFolder {
            let url = entry.url
            Thumbnails.load(url, side: side, modified: entry.modified) { [weak self] image in
                guard self?.url == url else { return }
                self?.icon.image = image
            }
        }
        updateHighlight()
    }

    override var isSelected: Bool {
        didSet { updateHighlight() }
    }

    private func updateHighlight() {
        let emphasized = view.window?.isKeyWindow ?? true
        iconBackground.layer?.backgroundColor = isSelected ? NSColor.labelColor.withAlphaComponent(0.12).cgColor : nil
        name.layer?.backgroundColor = isSelected && !name.isEditable
            ? (emphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).cgColor : nil
        name.textColor = isSelected && !name.isEditable && emphasized ? .alternateSelectedControlTextColor : .labelColor
    }

    func beginEditing(_ commit: @escaping (String) -> Void) {
        guard !name.isEditable else { return }
        onRename = commit
        name.isHidden = false
        name.isEditable = true
        name.isBezeled = false
        name.drawsBackground = true
        name.backgroundColor = .textBackgroundColor
        updateHighlight()
        view.window?.makeFirstResponder(name)
        // Select the name without its extension, as Finder does.
        if let editor = name.currentEditor() {
            let base = (name.stringValue as NSString).deletingPathExtension
            editor.selectedRange = NSRange(location: 0, length: (base as NSString).length)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard name.isEditable else { return }
        name.isEditable = false
        name.drawsBackground = false
        let commit = onRename
        onRename = nil
        updateHighlight()
        commit?(name.stringValue)
        collectionView?.window?.makeFirstResponder(collectionView)
    }
}

// MARK: List

struct FolderListView: NSViewRepresentable {
    let model: FolderBrowserModel

    func makeCoordinator() -> FolderListCoordinator { FolderListCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let table = FolderTableView()
        table.coordinator = coordinator
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.rowHeight = 20
        table.backgroundColor = .clear
        table.headerView = NSTableHeaderView()
        for column in FolderListCoordinator.columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.sort.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 50
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.sort.rawValue, ascending: !column.sort.descendsByDefault)
            table.addTableColumn(tableColumn)
        }
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(FolderListCoordinator.doubleClicked)
        table.registerForDraggedTypes([fileURLType])
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        table.draggingDestinationFeedbackStyle = .regular
        coordinator.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        coordinator.sync()
        DispatchQueue.main.async { table.window?.makeFirstResponder(table) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.sync()
    }
}

@MainActor
final class FolderListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    struct Column {
        let sort: FolderSort
        let title: String
        let width: CGFloat
    }

    static let columns = [
        Column(sort: .name, title: "Name", width: 190),
        Column(sort: .dateModified, title: "Date Modified", width: 120),
        Column(sort: .dateAdded, title: "Date Added", width: 120),
        Column(sort: .size, title: "Size", width: 64),
        Column(sort: .kind, title: "Kind", width: 90),
    ]

    let model: FolderBrowserModel
    weak var table: NSTableView?
    private var shown: [FolderEntry] = []
    private var appliedSelection = -1
    private var applying = false

    private static let dateFormat = Date.FormatStyle(date: .numeric, time: .shortened)

    init(model: FolderBrowserModel) {
        self.model = model
    }

    func sync() {
        guard let table else { return }
        applying = true
        defer { applying = false }
        let descriptor = NSSortDescriptor(key: model.options.sort.rawValue, ascending: model.options.ascending)
        if table.sortDescriptors.first != descriptor { table.sortDescriptors = [descriptor] }
        for column in table.tableColumns {
            let active = column.identifier.rawValue == model.options.sort.rawValue
            table.setIndicatorImage(active ? NSImage(named: model.options.ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator") : nil,
                                    in: column)
            if active { table.highlightedTableColumn = column }
        }
        if shown != model.visible {
            shown = model.visible
            table.reloadData()
            appliedSelection = -1
        }
        let rows = IndexSet(shown.indices.filter { model.selection.contains(shown[$0].url) })
        if appliedSelection != model.selectionRevision || table.selectedRowIndexes != rows {
            appliedSelection = model.selectionRevision
            table.selectRowIndexes(rows, byExtendingSelection: false)
            if let first = rows.first { table.scrollRowToVisible(first) }
        }
        if let renaming = model.renaming, let row = shown.firstIndex(where: { $0.url == renaming }),
           table.currentEditor() == nil {
            table.editColumn(0, row: row, with: nil, select: true)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, shown.indices.contains(row) else { return nil }
        let entry = shown[row]
        let id = tableColumn.identifier
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
        cell.textField?.stringValue = text(for: entry, column: FolderSort(rawValue: id.rawValue) ?? .name)
        if id.rawValue == FolderSort.name.rawValue {
            cell.imageView?.image = IconProvider.icon(forPath: entry.url.path)
            cell.textField?.isEditable = true
            cell.textField?.delegate = self
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingMiddle
        field.font = .systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        var leading = field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2)
        if id.rawValue == FolderSort.name.rawValue {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
            ])
            leading = field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5)
        } else {
            field.textColor = .secondaryLabelColor
        }
        NSLayoutConstraint.activate([
            leading,
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func text(for entry: FolderEntry, column: FolderSort) -> String {
        switch column {
        case .name: entry.name
        case .kind: entry.kind
        case .size: entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--"
        case .dateModified: entry.modified?.formatted(Self.dateFormat) ?? "--"
        case .dateAdded: entry.added?.formatted(Self.dateFormat) ?? "--"
        case .dateCreated: entry.created?.formatted(Self.dateFormat) ?? "--"
        case .dateLastOpened: entry.lastOpened?.formatted(Self.dateFormat) ?? "--"
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !applying, let key = tableView.sortDescriptors.first?.key, let sort = FolderSort(rawValue: key) else { return }
        model.updateOptions { $0.toggleSort(sort) }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applying, let table else { return }
        model.selectionChanged(Set(table.selectedRowIndexes.compactMap { shown.indices.contains($0) ? shown[$0].url : nil }))
    }

    func entry(at row: Int) -> FolderEntry? { shown.indices.contains(row) ? shown[row] : nil }

    @objc func doubleClicked() {
        guard let table, let entry = entry(at: table.clickedRow) else { return }
        model.open(entry.isFolder ? [entry.url] : model.selectedURLs)
    }

    // Renaming
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let table else { return }
        let row = table.row(for: field)
        guard let entry = entry(at: row) else { return }
        if field.stringValue == entry.name {
            model.renaming = nil
        } else {
            model.commitRename(entry.url, to: field.stringValue)
        }
    }

    // Dragging out
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        entry(at: row)?.url as NSURL?
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
                   operation: NSDragOperation) {
        if !operation.isEmpty { model.draggedOut() }
    }

    // Dropping in
    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let fromSelf = info.draggingSource as? NSTableView === tableView
        if dropOperation == .on, let target = entry(at: row), target.isFolder, !model.selection.contains(target.url) || !fromSelf {
            return model.dropOperation(info, fromSelf: fromSelf)
        }
        if fromSelf { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return model.dropOperation(info, fromSelf: false)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let fromSelf = info.draggingSource as? NSTableView === tableView
        let folder = row >= 0 ? entry(at: row).flatMap { $0.isFolder ? $0.url : nil } : nil
        return model.acceptDrop(info, into: folder, fromSelf: fromSelf)
    }
}

final class FolderTableView: NSTableView {
    weak var coordinator: FolderListCoordinator?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator else { return nil }
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        return coordinator.model.contextMenu(clicked: coordinator.entry(at: row)?.url)
    }
}

// MARK: Columns

struct FolderColumnsView: NSViewRepresentable {
    let model: FolderBrowserModel

    func makeCoordinator() -> FolderColumnsCoordinator { FolderColumnsCoordinator(model: model) }

    func makeNSView(context: Context) -> NSBrowser {
        let coordinator = context.coordinator
        let browser = FolderNSBrowser()
        browser.coordinator = coordinator
        browser.delegate = coordinator
        browser.allowsMultipleSelection = true
        browser.allowsEmptySelection = true
        browser.hasHorizontalScroller = true
        browser.separatesColumns = true
        // Column titles would draw over the toolbar; the toolbar already names the folder.
        browser.isTitled = false
        browser.rowHeight = 20
        browser.minColumnWidth = 170
        browser.columnResizingType = .userColumnResizing
        browser.target = coordinator
        browser.action = #selector(FolderColumnsCoordinator.clicked)
        browser.doubleAction = #selector(FolderColumnsCoordinator.doubleClicked)
        browser.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        browser.registerForDraggedTypes([fileURLType])
        coordinator.browser = browser
        coordinator.sync()
        DispatchQueue.main.async { browser.window?.makeFirstResponder(browser) }
        return browser
    }

    func updateNSView(_ browser: NSBrowser, context: Context) {
        context.coordinator.sync()
    }
}

@MainActor
final class FolderColumnsCoordinator: NSObject, NSBrowserDelegate {
    let model: FolderBrowserModel
    weak var browser: NSBrowser?
    private var children: [URL: [FolderEntry]] = [:]
    private var root: URL?
    private var shown: [FolderEntry] = []
    private var revision = -1
    private var appliedSelection = -1

    init(model: FolderBrowserModel) {
        self.model = model
    }

    func sync() {
        guard let browser else { return }
        if root != model.current {
            root = model.current
            shown = model.visible
            revision = model.contentRevision
            children = [:]
            browser.loadColumnZero()
        } else if revision != model.contentRevision || shown != model.visible {
            revision = model.contentRevision
            shown = model.visible
            children = [:]
            let path = browser.selectionIndexPaths
            browser.loadColumnZero()
            browser.selectionIndexPaths = path.filter { valid($0) }
        }
        if appliedSelection != model.selectionRevision {
            appliedSelection = model.selectionRevision
            let rows = IndexSet(model.visible.indices.filter { model.selection.contains(model.visible[$0].url) })
            if !rows.isEmpty { browser.selectRowIndexes(rows, inColumn: 0) }
        }
        if let renaming = model.renaming {
            model.renaming = nil
            if let name = StorageDialogs.askText("Rename", message: "Enter a new name for \"\(renaming.lastPathComponent)\".",
                                                 initial: renaming.lastPathComponent, action: "Rename") {
                model.commitRename(renaming, to: name)
            }
        }
    }

    private func valid(_ path: IndexPath) -> Bool {
        var folder = model.current
        for (depth, index) in path.enumerated() {
            let list = entries(in: folder, depth: depth)
            guard list.indices.contains(index) else { return false }
            folder = list[index].url
        }
        return true
    }

    /// Column zero is the browser's filtered folder; deeper columns are read when opened.
    private func entries(in folder: URL, depth: Int) -> [FolderEntry] {
        if depth == 0 || folder == model.current { return model.visible }
        if let cached = children[folder] { return cached }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .localizedNameKey, .contentModificationDateKey,
                                      .addedToDirectoryDateKey, .creationDateKey, .fileSizeKey, .localizedTypeDescriptionKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: model.options.showHidden ? [] : [.skipsHiddenFiles])) ?? []
        let list = FolderOrdering.sorted(urls.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = v?.isDirectory == true && v?.isPackage != true
            return FolderEntry(url: url, name: v?.localizedName ?? url.lastPathComponent, isFolder: isFolder,
                               size: v?.fileSize.map(Int64.init), kind: v?.localizedTypeDescription ?? "",
                               modified: v?.contentModificationDate, created: v?.creationDate, added: v?.addedToDirectoryDate)
        }, options: model.options)
        children[folder] = list
        return list
    }

    private func folder(of item: Any?) -> URL { (item as? URL) ?? model.current }

    private func entry(for item: Any?) -> FolderEntry? {
        guard let url = item as? URL else { return nil }
        return entries(in: url.deletingLastPathComponent(), depth: url.deletingLastPathComponent() == model.current ? 0 : 1)
            .first { $0.url == url }
    }

    func rootItem(for browser: NSBrowser) -> Any? { model.current }

    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        let url = folder(of: item)
        return entries(in: url, depth: url == model.current ? 0 : 1).count
    }

    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        let url = folder(of: item)
        return entries(in: url, depth: url == model.current ? 0 : 1)[index].url
    }

    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool { !(entry(for: item)?.isFolder ?? true) }

    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? { entry(for: item)?.name ?? "" }

    func browser(_ browser: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        guard let cell = cell as? NSBrowserCell, let url = browser.item(atRow: row, inColumn: column) as? URL else { return }
        let icon = IconProvider.icon(forPath: url.path).copy() as? NSImage
        icon?.size = NSSize(width: 16, height: 16)
        cell.image = icon
    }

    func browser(_ browser: NSBrowser, previewViewControllerForLeafItem item: Any) -> NSViewController? {
        let controller = NSViewController()
        let preview = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 220, height: 220), style: .compact)
        preview?.previewItem = (item as? URL) as NSURL?
        controller.view = preview ?? NSView()
        return controller
    }

    func selectedURLs() -> [URL] {
        guard let browser else { return [] }
        return browser.selectionIndexPaths.compactMap { browser.item(at: $0) as? URL }
    }

    @objc func clicked() {
        model.selectionChanged(Set(selectedURLs()))
    }

    @objc func doubleClicked() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        // A folder already opens in the next column; double-clicking it browses into it.
        model.open(urls)
    }

    // Dragging out
    func browser(_ browser: NSBrowser, canDragRowsWith rowIndexes: IndexSet, inColumn column: Int, with event: NSEvent) -> Bool { true }

    func browser(_ browser: NSBrowser, writeRowsWith rowIndexes: IndexSet, inColumn column: Int, to pasteboard: NSPasteboard) -> Bool {
        let urls = rowIndexes.compactMap { browser.item(atRow: $0, inColumn: column) as? URL }
        pasteboard.clearContents()
        return pasteboard.writeObjects(urls as [NSURL])
    }

    // Dropping in: onto a folder row, or into the folder a column lists.
    func browser(_ browser: NSBrowser, validateDrop info: any NSDraggingInfo,
                 proposedRow row: UnsafeMutablePointer<Int>, column: UnsafeMutablePointer<Int>,
                 dropOperation: UnsafeMutablePointer<NSBrowser.DropOperation>) -> NSDragOperation {
        let fromSelf = info.draggingSource as? NSBrowser === browser
        return model.dropOperation(info, fromSelf: fromSelf)
    }

    func browser(_ browser: NSBrowser, acceptDrop info: any NSDraggingInfo, atRow row: Int, column: Int,
                 dropOperation: NSBrowser.DropOperation) -> Bool {
        let fromSelf = info.draggingSource as? NSBrowser === browser
        var target: URL? = column > 0 ? browser.parentForItems(inColumn: column) as? URL : nil
        if dropOperation == .on, let url = browser.item(atRow: row, inColumn: column) as? URL, entry(for: url)?.isFolder == true {
            target = url
        }
        return model.acceptDrop(info, into: target, fromSelf: fromSelf)
    }

    func contextMenu(row: Int, column: Int) -> NSMenu {
        guard let browser, row >= 0, let url = browser.item(atRow: row, inColumn: column) as? URL else {
            return model.contextMenu(clicked: nil)
        }
        if !selectedURLs().contains(url) {
            browser.selectRow(row, inColumn: column)
            model.selectionChanged([url])
        }
        return model.contextMenu(clicked: url)
    }
}

final class FolderNSBrowser: NSBrowser {
    weak var coordinator: FolderColumnsCoordinator?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator else { return nil }
        var row = -1
        var column = -1
        _ = getRow(&row, column: &column, for: convert(event.locationInWindow, from: nil))
        return coordinator.contextMenu(row: row, column: max(column, 0))
    }
}

// MARK: Gallery preview

/// The gallery's large preview of the selected file.
struct FolderPreview: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> NSView {
        QLPreviewView(frame: .zero, style: .normal) ?? NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let preview = view as? QLPreviewView else { return }
        if (preview.previewItem as? NSURL) as URL? != url { preview.previewItem = url as NSURL? }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? QLPreviewView)?.close()
    }
}
