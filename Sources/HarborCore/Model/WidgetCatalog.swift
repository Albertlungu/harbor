import Foundation

public enum WidgetCategory: String, CaseIterable, Sendable {
    case all, apps, folders, clocks, tasks, system

    public var title: String {
        switch self {
        case .all: "All Widgets"
        case .apps: "Apps"
        case .folders: "Files & Folders"
        case .clocks: "Time"
        case .tasks: "Tools"
        case .system: "System"
        }
    }
}

/// Names, descriptions and categories for the widget library.
public enum WidgetCatalog {
    public static func name(for kind: WidgetKind) -> String {
        switch kind {
        case .clock: "Clock"
        case .link: "Link"
        case .finder: "Finder"
        case .ipAddress: "IP Address"
        case .spacer: "Spacer"
        case .divider: "Divider"
        case .label: "Label"
        case .folderStack: "Folder Stack"
        case .appStack: "App Stack"
        case .shelf: "Shelf"
        case .fileShelf: "File Shelf"
        case .liveDock: "Live Dock"
        case .runningApps: "Running Apps"
        case .spaceAwareness: "Space Apps"
        case .trash: "Trash"
        case .battery: "Battery"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .bluetoothBattery: "Bluetooth Battery"
        case .clicker: "Counter"
        case .timer: "Timer"
        case .metronome: "Metronome"
        case .pet: "Dock Pet"
        }
    }

    public static func summary(for kind: WidgetKind) -> String {
        switch kind {
        case .clock: "The time, and the date if you want it."
        case .link: "Open a web address in one click."
        case .finder: "A Finder button that opens where you choose."
        case .ipAddress: "Your public or local address, ready to copy."
        case .spacer: "Empty room between items."
        case .divider: "A thin line to separate groups."
        case .label: "A line of text to name a group."
        case .folderStack: "Several folders behind one icon."
        case .appStack: "A hand-picked group of apps and files."
        case .shelf: "A place to park copies of files."
        case .fileShelf: "Bookmarks to files without moving them."
        case .liveDock: "Everything in the macOS Dock, here too."
        case .runningApps: "Apps that are open but not pinned."
        case .spaceAwareness: "Apps with windows on this desktop."
        case .trash: "Drop files to delete them; browse and empty."
        case .battery: "Charge level and charging state."
        case .cpu: "How busy the processor is."
        case .memory: "How much memory is in use."
        case .gpu: "How busy the graphics chip is."
        case .bluetoothBattery: "Charge of your keyboard, mouse and headphones."
        case .clicker: "A tally counter that remembers."
        case .timer: "A countdown ring with an alert."
        case .metronome: "A steady beat with tap tempo."
        case .pet: "A small companion that lives in your dock."
        }
    }

    public static func category(for kind: WidgetKind) -> WidgetCategory {
        switch kind {
        case .liveDock, .runningApps, .spaceAwareness, .finder, .link, .appStack: .apps
        case .folderStack, .shelf, .fileShelf, .trash: .folders
        case .clock, .timer: .clocks
        case .clicker, .metronome, .pet, .label, .spacer, .divider: .tasks
        case .battery, .cpu, .memory, .gpu, .bluetoothBattery, .ipAddress: .system
        }
    }

    public static func symbol(for kind: WidgetKind) -> String {
        switch kind {
        case .clock: "clock"
        case .link: "link"
        case .finder: "face.smiling"
        case .ipAddress: "network"
        case .spacer: "arrow.left.and.right"
        case .divider: "line.diagonal"
        case .label: "textformat"
        case .folderStack: "folder"
        case .appStack: "square.stack.3d.up"
        case .shelf: "tray.full"
        case .fileShelf: "bookmark"
        case .liveDock: "dock.rectangle"
        case .runningApps: "app.badge"
        case .spaceAwareness: "rectangle.3.group"
        case .trash: "trash"
        case .battery: "battery.75percent"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "square.3.layers.3d"
        case .bluetoothBattery: "headphones"
        case .clicker: "plus.circle"
        case .timer: "timer"
        case .metronome: "metronome"
        case .pet: "pawprint"
        }
    }

    public static func kinds(in category: WidgetCategory, matching query: String = "") -> [WidgetKind] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return WidgetKind.allCases.filter { kind in
            (category == .all || Self.category(for: kind) == category)
                && (q.isEmpty
                    || name(for: kind).lowercased().contains(q)
                    || Self.category(for: kind).title.lowercased().contains(q))
        }
    }

    /// Widgets added by the "system monitor" preset.
    public static let monitorPreset: [WidgetKind] = [.cpu, .memory, .gpu, .battery, .ipAddress, .bluetoothBattery]
}
