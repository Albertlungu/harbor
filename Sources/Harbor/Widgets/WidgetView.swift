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
        case let kind?:
            Image(systemName: WidgetCatalog.symbol(for: kind))
                .font(.system(size: min(size.width, size.height) * 0.45))
                .foregroundStyle(Tokens.text)
                .frame(width: size.width, height: size.height)
                .help("\(WidgetCatalog.name(for: kind)) isn't finished yet.")
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
        false
    }
}

/// Widget-specific entries in a widget's right-click menu.
struct WidgetContextItems: View {
    let item: DockItem
    let dock: Dock

    var body: some View {
        EmptyView()
    }
}
