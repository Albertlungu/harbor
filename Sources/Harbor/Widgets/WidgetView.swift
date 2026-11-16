import AppKit
import HarborCore
import SwiftUI

/// Renders a widget on a dock by type.
struct WidgetView: View {
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    var body: some View {
        switch widget.kind {
        case .clock?:
            ClockWidget(widget: widget, size: size)
        case .spacer?:
            Color.clear.accessibilityHidden(true)
        case .divider?:
            DividerWidget(widget: widget, size: size, horizontal: state.isHorizontal)
        case .label?:
            LabelWidget(widget: widget, size: size, horizontal: state.isHorizontal)
        case .battery?, .cpu?, .memory?, .gpu?:
            MonitorWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .ipAddress?:
            IPWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .bluetoothBattery?:
            BluetoothWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .finder?:
            FinderWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .link?:
            LinkWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .folderStack?:
            FolderStackWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .appStack?:
            AppStackWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .shelf?:
            ShelfWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .fileShelf?:
            FileShelfWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .trash?:
            TrashWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .clicker?:
            ClickerWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .timer?:
            TimerWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .metronome?:
            MetronomeWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .pet?:
            PetWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .spaceAwareness?:
            SpaceIndicatorWidget(item: item, widget: widget, dock: dock, size: size, state: state)
        case .liveDock?, .runningApps?:
            // Expanded into app slots by SlotBuilder; never drawn as a widget.
            EmptyView()
        case nil:
            Image(systemName: "questionmark.square.dashed")
                .foregroundStyle(Tokens.textMuted)
                .help("This widget needs a newer version of Harbor.")
        }
    }
}

/// Files dropped onto widgets that accept them.
@MainActor
enum WidgetDrop {
    static func handle(_ providers: [NSItemProvider], item: DockItem, dock: Dock, model: AppModel) -> Bool {
        switch item.widget?.kind {
        case .folderStack?, .appStack?, .shelf?, .fileShelf?, .trash?:
            return StorageWidgetDrop.handle(providers, item: item, dock: dock, model: model)
        default:
            return false
        }
    }
}

/// Widget-specific entries in a widget's right-click menu.
struct WidgetContextItems: View {
    let item: DockItem
    let dock: Dock

    var body: some View {
        switch item.widget?.kind {
        case .battery?, .cpu?, .memory?, .gpu?, .ipAddress?, .bluetoothBattery?:
            SystemWidgetMenu(item: item, dock: dock)
        case .finder?, .link?, .folderStack?, .appStack?, .shelf?, .fileShelf?, .trash?:
            StorageWidgetMenu(item: item, dock: dock)
        case .clicker?, .timer?, .metronome?, .pet?, .spaceAwareness?:
            ToolWidgetMenu(item: item, dock: dock)
        default:
            EmptyView()
        }
    }
}
