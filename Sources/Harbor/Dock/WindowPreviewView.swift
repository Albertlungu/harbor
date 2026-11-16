import AppKit
import HarborCore
import Observation
import SwiftUI

/// What the preview panel shows; the controller refills it for each hovered app.
@MainActor
@Observable
final class WindowPreviewModel {
    var windows: [PreviewWindow] = []
    var images: [CGWindowID: CGImage] = [:]
    var appName = ""
    var icon = NSImage()
    var settings = PreviewSettings()
    var layout = PreviewLayout.empty
    var hasScreenAccess = false
    var canClose = false
    /// The window picked by scrolling over the app's dock icon.
    var selectedID: CGWindowID?

    @ObservationIgnored var onRaise: (PreviewWindow) -> Void = { _ in }
    @ObservationIgnored var onClose: (PreviewWindow) -> Void = { _ in }
    @ObservationIgnored var onHover: (Bool) -> Void = { _ in }
}

/// Grid or list metrics for a set of windows, so the panel can be sized before it is drawn.
struct PreviewLayout {
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 12
    static let compactRow: CGFloat = 30
    static let compactWidth: CGFloat = 280
    static let empty = PreviewLayout(columns: 1, rows: 1, compact: true, cardWidth: 0, cardHeight: 0, size: .zero)

    var columns: Int
    var rows: Int
    var compact: Bool
    var cardWidth: CGFloat
    var cardHeight: CGFloat
    var size: CGSize

    /// Compact is used when asked for, when the permission needed for thumbnails is missing,
    /// or once the window count reaches the auto-switch threshold.
    static func isCompact(count: Int, settings: PreviewSettings, hasScreenAccess: Bool) -> Bool {
        !hasScreenAccess || (settings.compactAt > 0 && count >= settings.compactAt)
    }

    static func make(count: Int, settings: PreviewSettings, compact: Bool) -> PreviewLayout {
        let count = max(count, 1)
        let maxRows = max(settings.maxRows, 1), maxColumns = max(settings.maxColumns, 1)
        if compact {
            let rows = min(count, maxRows * maxColumns)
            let height = CGFloat(rows) * compactRow + CGFloat(rows - 1) * 2 + padding * 2
            return PreviewLayout(columns: 1, rows: rows, compact: true, cardWidth: compactWidth, cardHeight: compactRow,
                                 size: CGSize(width: compactWidth + padding * 2, height: height))
        }
        let width = CGFloat(min(max(settings.cardWidth, 100), 600))
        let labelled = settings.showAppName || settings.showWindowTitle
        let cardHeight = width * 10 / 16 + (labelled ? 26 : 0) + 12
        let columns = min(count, maxColumns)
        let rows = min((count + columns - 1) / columns, maxRows)
        let size = CGSize(width: CGFloat(columns) * width + CGFloat(columns - 1) * spacing + padding * 2,
                          height: CGFloat(rows) * cardHeight + CGFloat(rows - 1) * spacing + padding * 2)
        return PreviewLayout(columns: columns, rows: rows, compact: false, cardWidth: width, cardHeight: cardHeight, size: size)
    }
}

struct WindowPreviewView: View {
    let model: WindowPreviewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let layout = model.layout
        ScrollView(.vertical, showsIndicators: false) {
            if layout.compact {
                VStack(spacing: 2) {
                    ForEach(model.windows) { window in CompactRow(model: model, window: window) }
                }
                .padding(PreviewLayout.padding)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.cardWidth), spacing: PreviewLayout.spacing),
                                         count: layout.columns),
                          spacing: PreviewLayout.spacing) {
                    ForEach(model.windows) { window in PreviewCard(model: model, window: window) }
                }
                .padding(PreviewLayout.padding)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .background { backdrop }
        .onHover { model.onHover($0) }
    }

    @ViewBuilder
    private var backdrop: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.popover, style: .continuous)
        if reduceTransparency {
            shape.fill(Tokens.dockSolid)
        } else {
            shape.fill(.clear).glassEffect(.regular, in: shape)
        }
    }
}

private struct PreviewCard: View {
    let model: WindowPreviewModel
    let window: PreviewWindow
    @State private var hovered = false

    var body: some View {
        let settings = model.settings
        let width = model.layout.cardWidth
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            ZStack(alignment: .topLeading) {
                thumbnail
                    .frame(width: width - 12, height: (width - 12) * 10 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card - 3, style: .continuous))
                if model.canClose {
                    CloseButton(label: window.title) { model.onClose(window) }
                        .padding(Tokens.Space.xs)
                        .opacity(hovered ? 1 : 0)
                }
            }
            if settings.showAppName || settings.showWindowTitle {
                VStack(alignment: .leading, spacing: 0) {
                    if settings.showAppName {
                        Text(model.appName).font(.system(size: 11, weight: .semibold)).foregroundStyle(Tokens.text)
                    }
                    // A title that just repeats the app name adds nothing.
                    if settings.showWindowTitle && !(settings.showAppName && displayTitle == model.appName) {
                        Text(displayTitle).font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            }
        }
        .padding(6)
        .frame(width: width)
        .background(hovered || model.selectedID == window.id ? Tokens.surface.opacity(0.8) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .overlay {
            if model.selectedID == window.id {
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .strokeBorder(Tokens.accent, lineWidth: 2)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.selectedID)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { model.onRaise(window) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayTitle)
        .accessibilityAddTraits(.isButton)
    }

    private var displayTitle: String { window.title.isEmpty ? model.appName : window.title }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = model.images[window.id] {
            Image(decorative: image, scale: 1)
                .resizable()
                // Fit, not fill: a cropped thumbnail hides the part of the window you'd recognize.
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(window.minimized || window.hidden ? 0.6 : 1)
        } else {
            ZStack {
                Tokens.surface
                Image(nsImage: model.icon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .opacity(0.8)
            }
        }
    }
}

private struct CompactRow: View {
    let model: WindowPreviewModel
    let window: PreviewWindow
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(nsImage: model.icon).resizable().frame(width: 18, height: 18)
            Text(window.title.isEmpty ? model.appName : window.title)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            if window.minimized || window.hidden {
                Image(systemName: window.minimized ? "arrow.down.right.and.arrow.up.left" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.textMuted)
            }
            if model.canClose {
                CloseButton(label: window.title) { model.onClose(window) }.opacity(hovered ? 1 : 0)
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(height: PreviewLayout.compactRow)
        .background(hovered || model.selectedID == window.id ? Tokens.accent.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.pill, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { model.onRaise(window) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(window.title.isEmpty ? model.appName : window.title)
        .accessibilityAddTraits(.isButton)
    }
}

private struct CloseButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Tokens.onLabel)
                .frame(width: 18, height: 18)
                .background(Tokens.labelBackground.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close \(label)")
    }
}
