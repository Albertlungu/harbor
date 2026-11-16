import AppKit
import HarborCore
import SwiftUI

struct SpaceIndicatorWidget: View {
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var spaces: (current: Int, total: Int)?

    private static let maxDots = 7

    var body: some View {
        // Apps mode is expanded into app slots elsewhere.
        if widget.string("mode", "apps") == "indicator" {
            indicator
                .frame(width: size.width, height: size.height)
                .onAppear { refresh() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
                    refresh()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Desktop")
                .accessibilityValue(spaces.map { "\($0.current) of \($0.total)" } ?? "Unknown")
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var indicator: some View {
        let unit = Tokens.Tool.unit(size)
        if let spaces {
            if widget.string("style", "dots") == "number" || spaces.total > Self.maxDots {
                Text("\(spaces.current) / \(spaces.total)")
                    .font(.system(size: unit * 0.3, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Tokens.text)
                    .padding(.horizontal, unit * 0.08)
            } else {
                let dots = ForEach(1...max(spaces.total, 1), id: \.self) { index in
                    Circle()
                        .fill(index == spaces.current ? Tokens.text : Tokens.textMuted.opacity(0.35))
                        .frame(width: unit * 0.14, height: unit * 0.14)
                }
                if state.isHorizontal {
                    HStack(spacing: unit * 0.1) { dots }
                } else {
                    VStack(spacing: unit * 0.1) { dots }
                }
            }
        } else {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: unit * 0.3))
                .foregroundStyle(Tokens.textMuted)
        }
    }

    /// The preferences file can trail the switch, so it is read once now and again shortly after.
    private func refresh() {
        spaces = SpaceApps.spaceIndicator()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            spaces = SpaceApps.spaceIndicator()
        }
    }
}
