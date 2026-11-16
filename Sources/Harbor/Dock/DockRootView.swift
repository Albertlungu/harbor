import AppKit
import HarborCore
import SwiftUI

/// Positions the bar and every slot inside the panel, applying magnification.
struct DockRootView: View {
    @Environment(AppModel.self) private var model
    let state: DockViewState

    var body: some View {
        if let dock = model.store.dock(state.dockID) {
            DockBarLayout(dock: dock, state: state, editing: model.store.editing.contains(dock.id))
        }
    }
}

private struct SlotFrame {
    var slot: DockSlot
    var center: CGFloat
    var length: CGFloat
    var scale: CGFloat
}

struct DockBarLayout: View {
    @Environment(AppModel.self) private var model
    let dock: Dock
    let state: DockViewState
    let editing: Bool

    private var horizontal: Bool { state.isHorizontal }
    private var icon: CGFloat { CGFloat(dock.style.iconSize) }
    private var spacing: CGFloat { CGFloat(dock.style.spacing.points) }
    private var collapsed: Bool { dock.style.collapse.enabled && dock.style.collapse.collapsed }
    private var floating: Bool { dock.position.mode == .floating && dock.layout == .dock }

    var body: some View {
        let frames = slotFrames()
        let bg = backgroundRect(frames)
        ZStack(alignment: .topLeading) {
            DockBackground(style: dock.style, thickness: CGFloat(dock.style.thickness),
                           opaque: model.store.settings.opaqueBackgrounds, editing: editing)
                .frame(width: bg.width, height: bg.height)
                .offset(x: bg.minX, y: bg.minY)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleBarDrop(providers, location: nil)
                }

            if !dock.style.effects.isEmpty && dock.layout == .dock {
                EffectsView(effects: dock.style.effects, intensity: dock.style.effectIntensity)
                    .frame(width: bg.width, height: bg.height)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(dock.style.thickness * dock.style.cornerStyle.fraction)))
                    .offset(x: bg.minX, y: bg.minY)
                    .allowsHitTesting(false)
            }

            if collapsed || dock.style.collapse.enabled {
                CollapseButton(dock: dock, horizontal: horizontal)
                    .frame(width: horizontal ? 18 : state.barRect.width, height: horizontal ? state.barRect.height : 18)
                    .offset(collapseOffset(bg))
            }

            if !collapsed {
                ForEach(frames, id: \.slot.id) { frame in
                    slotView(frame)
                }
            }

            if floating {
                DragHandle(dock: dock, state: state, horizontal: horizontal)
                    .frame(width: horizontal ? DockMetrics.handleLength : state.barRect.width,
                           height: horizontal ? state.barRect.height : DockMetrics.handleLength)
                    .offset(handleOffset(bg))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: state.pointer)
    }

    // MARK: Layout math

    private func slotFrames() -> [SlotFrame] {
        let bar = state.barRect
        var cursor = (horizontal ? bar.minX : bar.minY) + CGFloat(dock.style.sidePadding)
        if dock.position.fullWidth && dock.position.mode == .pinned {
            let content = state.slots.reduce(CGFloat(0)) { $0 + baseLength($1) } + spacing * CGFloat(max(state.slots.count - 1, 0))
            let barLength = horizontal ? bar.width : bar.height
            let free = barLength - content - CGFloat(dock.style.sidePadding) * 2
            switch dock.position.alignment {
            case .start: break
            case .center: cursor += free / 2
            case .end: cursor += free
            }
        }
        var frames: [SlotFrame] = []
        for slot in state.slots {
            let length = baseLength(slot)
            frames.append(SlotFrame(slot: slot, center: cursor + length / 2, length: length, scale: 1))
            cursor += length + spacing
        }
        guard let pointer = state.pointer, dock.style.magnify, dock.layout == .dock, !editing else { return frames }

        // Grow magnifying slots, then shift so the slot under the pointer stays under it.
        var shiftBack: CGFloat = 0
        for i in frames.indices where frames[i].slot.magnifies {
            let scale = DockLayoutEngine.magnification(distance: abs(pointer - frames[i].center), iconSize: icon,
                                                       maxScale: CGFloat(dock.style.maxScale),
                                                       falloff: CGFloat(dock.style.falloff))
            frames[i].scale = scale
            let growth = frames[i].length * (scale - 1)
            let start = frames[i].center - frames[i].length / 2
            let leftShare = min(max((pointer - start) / frames[i].length, 0), 1)
            shiftBack += growth * leftShare
        }
        var position = (frames.first.map { $0.center - $0.length / 2 } ?? 0) - shiftBack
        for i in frames.indices {
            let grown = frames[i].length * frames[i].scale
            frames[i].center = position + grown / 2
            position += grown + spacing
        }
        return frames
    }

    private func baseLength(_ slot: DockSlot) -> CGFloat {
        let cells = CGFloat(slot.cells)
        return cells * icon + (cells > 1 ? spacing * (cells - 1) : 0)
    }

    private func backgroundRect(_ frames: [SlotFrame]) -> CGRect {
        var rect = state.barRect
        guard let first = frames.first, let last = frames.last, !collapsed else { return rect }
        let pad = CGFloat(dock.style.sidePadding)
        let start = first.center - first.length * first.scale / 2 - pad
        var end = last.center + last.length * last.scale / 2 + pad
        if floating { end += DockMetrics.handleLength }
        if horizontal {
            let minX = min(rect.minX, start), maxX = max(rect.maxX, end)
            rect.origin.x = minX
            rect.size.width = maxX - minX
        } else {
            let minY = min(rect.minY, start), maxY = max(rect.maxY, end)
            rect.origin.y = minY
            rect.size.height = maxY - minY
        }
        return rect
    }

    private func handleOffset(_ bg: CGRect) -> CGSize {
        horizontal
            ? CGSize(width: bg.maxX - DockMetrics.handleLength - 2, height: state.barRect.minY)
            : CGSize(width: state.barRect.minX, height: bg.maxY - DockMetrics.handleLength - 2)
    }

    private func collapseOffset(_ bg: CGRect) -> CGSize {
        horizontal ? CGSize(width: bg.minX - 20, height: state.barRect.minY)
                   : CGSize(width: state.barRect.minX, height: bg.minY - 20)
    }

    // MARK: Slot views

    @ViewBuilder
    private func slotView(_ frame: SlotFrame) -> some View {
        let bar = state.barRect
        let crossLength = icon * frame.scale
        let alongLength = frame.length * frame.scale
        let width = horizontal ? alongLength : crossLength
        let height = horizontal ? crossLength : alongLength
        let origin = slotOrigin(frame: frame, bar: bar, width: width, height: height)
        let hovered = isHovered(frame)

        DockSlotView(slot: frame.slot, dock: dock, size: CGSize(width: width, height: height),
                     iconSize: icon * frame.scale, hovered: hovered, editing: editing, state: state)
            .frame(width: width, height: height)
            .overlay(alignment: labelAlignment) {
                if shouldShowLabel(frame, hovered: hovered) {
                    LabelPill(text: label(for: frame.slot))
                        .fixedSize()
                        .offset(labelOffset(height: height, width: width))
                        .allowsHitTesting(false)
                }
            }
            .offset(x: origin.x, y: origin.y)
            .zIndex(Double(frame.scale))
    }

    private func slotOrigin(frame: SlotFrame, bar: CGRect, width: CGFloat, height: CGFloat) -> CGPoint {
        let inset = (CGFloat(dock.style.thickness) - icon) / 2
        if horizontal {
            let x = frame.center - width / 2
            let y = state.hugEdge == .top ? bar.minY + inset : bar.maxY - inset - height
            return CGPoint(x: x, y: y)
        } else {
            let y = frame.center - height / 2
            let x = state.hugEdge == .right ? bar.maxX - inset - width : bar.minX + inset
            return CGPoint(x: x, y: y)
        }
    }

    private func isHovered(_ frame: SlotFrame) -> Bool {
        guard let pointer = state.pointer else { return false }
        let half = frame.length * frame.scale / 2 + spacing / 2
        return abs(pointer - frame.center) <= half
    }

    private func shouldShowLabel(_ frame: SlotFrame, hovered: Bool) -> Bool {
        if case .app(_, _, _, true) = frame.slot { return false }
        if let item = frame.slot.item {
            if item.kind == .widget { return hovered && item.widget?.kind?.showsHoverLabel == true }
            if dock.style.alwaysShowNames || item.alwaysShowLabel { return true }
        }
        return hovered && !editing
    }

    private func label(for slot: DockSlot) -> String {
        switch slot {
        case .item(let item): item.displayName
        case .app(_, _, let name, _): name
        }
    }

    private var labelAlignment: Alignment {
        switch state.hugEdge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    private func labelOffset(height: CGFloat, width: CGFloat) -> CGSize {
        switch state.hugEdge {
        case .bottom: CGSize(width: 0, height: -24)
        case .top: CGSize(width: 0, height: 24)
        case .left: CGSize(width: 8, height: 0)
        case .right: CGSize(width: -8, height: 0)
        }
    }

    // MARK: Drops on empty bar space

    private func handleBarDrop(_ providers: [NSItemProvider], location: CGPoint?) -> Bool {
        guard editing else {
            model.flashHint("Right-click the dock and choose Edit Dock to add items.")
            return false
        }
        DropLoader.urls(from: providers) { urls in
            model.store.addItems(urls.map(DockItem.file(at:)), to: dock.id)
        }
        return true
    }
}

extension WidgetKind {
    /// Widgets that show their name on hover (the rest are self-describing).
    var showsHoverLabel: Bool {
        switch self {
        case .folderStack, .appStack, .shelf, .fileShelf, .trash, .finder, .link: true
        default: false
        }
    }
}

/// Loads file URLs from drag providers and calls back on the main actor.
enum DropLoader {
    static func urls(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let box = URLBox()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { box.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = box.urls
            MainActor.assumeIsolated { completion(urls) }
        }
    }

    private final class URLBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [URL] = []
        func append(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
        var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
    }
}
