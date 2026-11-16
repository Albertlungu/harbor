import AppKit
import HarborCore
import SwiftUI

struct TrashItem: Identifiable, Sendable {
    let url: URL
    let entry: TrashEntry
    var id: URL { url }
}

enum TrashEmptyOutcome {
    case done
    case automationDenied
    case failed(String)
}

/// Reads and empties ~/.Trash.
enum TrashService {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    static let automationSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// Nil when the folder cannot be read, which is the case without Full Disk Access.
    static func hasItems() -> Bool? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
        return names.contains { !$0.hasPrefix(".") }
    }

    static func load() -> [TrashItem]? {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .fileSizeKey,
                                      .localizedTypeDescriptionKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        return urls.map { file in
            let values = try? file.resourceValues(forKeys: Set(keys))
            let entry = TrashEntry(name: file.lastPathComponent,
                                   added: values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast,
                                   size: Int64(values?.fileSize ?? 0),
                                   kind: values?.localizedTypeDescription ?? "Item")
            return TrashItem(url: file, entry: entry)
        }
    }

    @MainActor
    static func empty() -> TrashEmptyOutcome {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        guard let error else { return .done }
        // -1743 is "not authorized to send Apple events", the Automation permission.
        if (error["NSAppleScriptErrorNumber"] as? Int) == -1743 { return .automationDenied }
        return .failed(error["NSAppleScriptErrorMessage"] as? String ?? "Finder could not empty the Trash.")
    }

    @MainActor
    static func confirmEmpty() -> Bool {
        StorageDialogs.confirm("Empty the Trash?", message: "Everything in the Trash is deleted for good. This can't be undone.",
                               action: "Empty Trash")
    }

    /// Dialog version for places with no room for an inline message, like the context menu.
    @MainActor
    static func emptyWithDialogs() {
        guard confirmEmpty() else { return }
        switch empty() {
        case .done: Celebration.shared.play(dock: nil)
        case .automationDenied:
            let alert = NSAlert()
            alert.messageText = "Harbor can't control Finder"
            alert.informativeText = "Allow Harbor to control Finder in System Settings, under Privacy & Security, then Automation."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(automationSettings) }
        case .failed(let message):
            StorageDialogs.notice("Couldn't empty the Trash", message: message)
        }
    }
}

struct TrashWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var full = false
    @State private var open = false

    var body: some View {
        StorageGlyph(symbol: full ? "trash.fill" : "trash", size: size)
            .contentShape(Rectangle())
            .onTapGesture { open.toggle() }
            .task {
                // Polling is cheap and the folder has no change notification we can rely on without access.
                while !Task.isCancelled {
                    full = TrashService.hasItems() ?? false
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .storagePopover(isPresented: $open, state: state) {
                TrashPanel(onClose: { open = false }, onChange: { full = TrashService.hasItems() ?? false })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trash")
            .accessibilityValue(full ? "Has items" : "Empty")
            .accessibilityAddTraits(.isButton)
    }
}

private struct TrashPanel: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    let onChange: () -> Void

    @State private var items: [TrashItem] = []
    @State private var unreadable = false
    @State private var loaded = false
    @State private var query = ""
    @State private var sort: TrashSort = .date
    @State private var selection: URL?
    @State private var message: Message?

    private enum Message { case denied, failed(String) }

    private var visible: [TrashItem] {
        let byName = Dictionary(items.map { ($0.entry.name, $0) }, uniquingKeysWith: { a, _ in a })
        let sorted = StorageLogic.sortTrash(StorageLogic.filterTrash(items.map(\.entry), query: query), by: sort)
        return sorted.compactMap { byName[$0.name] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Text("Trash").font(.headline)
                Spacer()
                if !unreadable {
                    Picker("Sort by", selection: $sort) {
                        Text("Date").tag(TrashSort.date)
                        Text("Name").tag(TrashSort.name)
                        Text("Size").tag(TrashSort.size)
                        Text("Kind").tag(TrashSort.kind)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .labelsHidden()
                    .accessibilityLabel("Sort by")
                    Button("Empty Trash", role: .destructive, action: empty)
                        .disabled(items.isEmpty)
                }
            }
            messageView
            if unreadable {
                ContentUnavailableView {
                    Label("Can't read the Trash", systemImage: "lock")
                } description: {
                    Text("Harbor needs Full Disk Access to list what's in the Trash. You can still open it in Finder.")
                } actions: {
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(TrashService.url)
                        onClose()
                    }
                }
                .frame(minHeight: 180)
            } else if loaded && items.isEmpty {
                ContentUnavailableView(Copy.emptyTrash(model.playful), systemImage: "trash")
                    .frame(height: 160)
            } else {
                TextField("Search Trash", text: $query).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: Tokens.Space.xxs) {
                        ForEach(visible) { row($0) }
                    }
                }
                // Lazy stacks have no ideal height, so a popover would shrink the list to nothing.
                .frame(height: min(340, CGFloat(max(visible.count, 1)) * 46))
            }
        }
        .padding(Tokens.Storage.popoverPadding)
        .task { await reload() }
    }

    @ViewBuilder
    private var messageView: some View {
        switch message {
        case .denied:
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Harbor isn't allowed to control Finder, so it can't empty the Trash. Turn it on under Privacy & Security, then Automation.")
                    .font(.callout)
                Button("Open System Settings") { NSWorkspace.shared.open(TrashService.automationSettings) }
            }
            .padding(Tokens.Space.m)
            .background(RoundedRectangle(cornerRadius: Tokens.Storage.tileRadius, style: .continuous).fill(Tokens.warning.opacity(0.15)))
        case .failed(let text):
            Text(text).font(.callout).foregroundStyle(Tokens.danger)
        case nil:
            EmptyView()
        }
    }

    private func row(_ item: TrashItem) -> some View {
        HStack(spacing: Tokens.Space.l) {
            Image(nsImage: IconProvider.icon(forPath: item.url.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.entry.name).lineLimit(1).truncationMode(.middle)
                Text("\(item.entry.kind), \(ByteCountFormatter.string(fromByteCount: item.entry.size, countStyle: .file))")
                    .font(.caption).foregroundStyle(Tokens.textMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s)
        .contentShape(Rectangle())
        .hoverHighlight(selected: selection == item.url)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onTapGesture { selection = item.url }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { ItemActions.reveal(item.url) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.entry.name)
        .accessibilityValue(item.entry.kind)
        .accessibilityAddTraits(.isButton)
    }

    private func reload() async {
        let result = await Task.detached { TrashService.load() }.value
        loaded = true
        unreadable = result == nil
        items = result ?? []
    }

    private func empty() {
        guard TrashService.confirmEmpty() else { return }
        switch TrashService.empty() {
        case .done:
            message = nil
            Celebration.shared.play(dock: nil)
        case .automationDenied: message = .denied
        case .failed(let text): message = .failed(text)
        }
        Task {
            await reload()
            onChange()
        }
    }
}
