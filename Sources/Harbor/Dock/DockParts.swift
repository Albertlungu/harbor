import AppKit
import HarborCore
import SwiftUI

struct DockBackground: View {
    let style: DockStyle
    let thickness: CGFloat
    let opaque: Bool
    let editing: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: thickness * CGFloat(style.cornerStyle.fraction), style: .continuous)
        ZStack {
            fill(shape)
            if style.showBorder {
                shape.strokeBorder(style.borderColor.color, lineWidth: CGFloat(style.borderWidth))
            }
            if editing {
                shape.strokeBorder(Tokens.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .shadow(color: .black.opacity(style.background == .none ? 0 : 0.18), radius: 12, y: 4)
    }

    @ViewBuilder
    private func fill(_ shape: RoundedRectangle) -> some View {
        if opaque || reduceTransparency, style.background != .none {
            shape.fill(style.background == .solid ? style.solidColor.color.opacity(1) : Tokens.dockSolid)
        } else {
            switch style.background {
            case .glass:
                let glass: Glass = style.glassTint.map { Glass.regular.tint($0.color) }
                    ?? (Appearance.shared.paletteGlass ? Glass.regular.tint(Tokens.accent.opacity(Tokens.paletteWash)) : .regular)
                shape.fill(.clear)
                    .glassEffect(glass, in: shape)
                    .overlay(style.darkGlass ? shape.fill(Color.black.opacity(0.35)) : nil)
            case .blur:
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.black.opacity(style.blurDarkness * 0.6)))
                    .opacity(style.opacity.value)
            case .solid:
                shape.fill(style.solidColor.color.opacity(style.opacity.value))
            case .none:
                shape.fill(Color.black.opacity(0.001))
            }
        }
    }
}

/// The notch bar: a shape attached to its edge, rounded only on the inward corners.
struct NotchBar: View {
    let style: DockStyle
    let edge: ScreenEdge
    let folded: Bool
    let open: CGRect
    let pill: CGRect
    let editing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let rect = folded ? pill : open
        let radius = folded ? min(4, pill.height / 2) : CGFloat(style.thickness * style.cornerStyle.fraction)
        let c = DockLayoutEngine.notchCorners(edge: edge)
        let shape = UnevenRoundedRectangle(topLeadingRadius: c.topLeft ? radius : 0,
                                           bottomLeadingRadius: c.bottomLeft ? radius : 0,
                                           bottomTrailingRadius: c.bottomRight ? radius : 0,
                                           topTrailingRadius: c.topRight ? radius : 0,
                                           style: .continuous)
        fill(shape)
            .overlay { if editing { shape.strokeBorder(Tokens.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])) } }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .animation(reduceMotion ? nil : .easeInOut(duration: Tokens.Motion.base), value: folded)
    }

    @ViewBuilder
    private func fill(_ shape: UnevenRoundedRectangle) -> some View {
        let kind = reduceTransparency && (style.notch.background == .blur || style.notch.background == .glass)
            ? NotchBar.Kind.black : NotchBar.Kind(style.notch.background)
        switch kind {
        case .black: shape.fill(Color.black)
        case .color: shape.fill(style.notch.color.color)
        case .blur:
            shape.fill(.ultraThinMaterial).overlay(shape.fill(Color.black.opacity(style.blurDarkness * 0.8)))
        case .glass:
            if folded {
                shape.fill(Color.black)
            } else {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            }
        }
    }

    private enum Kind {
        case black, color, blur, glass
        init(_ b: HarborCore.NotchBackground) {
            switch b {
            case .black: self = .black
            case .color: self = .color
            case .blur: self = .blur
            case .glass: self = .glass
            }
        }
    }
}

struct LabelPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(Tokens.onLabel)
            .padding(.horizontal, Tokens.Space.m)
            .padding(.vertical, Tokens.Space.xs)
            .background(Tokens.labelBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: Tokens.Radius.pill))
    }
}

struct CollapseButton: View {
    @Environment(AppModel.self) private var model
    let dock: Dock
    let horizontal: Bool
    let collapsed: Bool
    let thickness: CGFloat

    var body: some View {
        let collapse = dock.style.collapse
        let shape = RoundedRectangle(cornerRadius: collapsed ? thickness * CGFloat(dock.style.cornerStyle.fraction) : 7,
                                     style: .continuous)
        Button {
            model.store.updateDock(dock.id) { $0.style.collapse.collapsed.toggle() }
        } label: {
            Group {
                switch collapse.buttonStyle {
                case .arrow:
                    Image(systemName: horizontal ? "chevron.right" : "chevron.down")
                        .rotationEffect(.degrees(collapsed ? 0 : 180))
                case .symbol:
                    Image(systemName: collapse.symbolName)
                case .text:
                    Text(String(collapse.text.prefix(5))).font(.system(size: 11, weight: .bold, design: .rounded))
                case .none:
                    Color.clear
                }
            }
            .font(.system(size: collapsed ? thickness * 0.3 : 10, weight: .semibold))
            .foregroundStyle(collapse.buttonColor?.color ?? Tokens.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if collapsed {
                    DockBackground(style: dock.style, thickness: thickness,
                                   opaque: model.store.settings.opaqueBackgrounds, editing: false)
                } else {
                    shape.fill(Tokens.surface.opacity(0.7))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapse.collapsed ? "Expand \(dock.name)" : "Collapse \(dock.name)")
        .onHover { inside in
            guard inside, collapse.collapsed, collapse.expandUsing != .click else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(collapse.expandAfter))
                model.store.updateDock(dock.id) { $0.style.collapse.collapsed = false }
            }
        }
    }
}

/// Grip for moving a floating dock. Shown on hover unless set to always show.
struct DragHandle: View {
    @Environment(AppModel.self) private var model
    let dock: Dock
    let state: DockViewState
    let horizontal: Bool
    @State private var start: (mouse: CGPoint, bar: CGRect)?

    var body: some View {
        let visible = !dock.position.locked && (state.hovering || dock.position.alwaysShowDragHandle)
        Image(systemName: horizontal ? "line.3.horizontal" : "line.3.horizontal")
            .rotationEffect(horizontal ? .degrees(90) : .zero)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Tokens.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(visible ? 1 : 0)
            .gesture(DragGesture(minimumDistance: 1).onChanged { _ in drag() }.onEnded { _ in start = nil })
            .accessibilityLabel("Move \(dock.name)")
            .help(dock.position.locked ? "Position is locked" : "Drag to move")
    }

    private func drag() {
        guard !dock.position.locked,
              let controller = model.dockController.controllers(for: dock.id).first(where: { $0.state.screenID == state.screenID })
        else { return }
        let mouse = NSEvent.mouseLocation
        if start == nil { start = (mouse, controller.barFrame) }
        guard let start else { return }
        let rect = start.bar.offsetBy(dx: mouse.x - start.mouse.x, dy: mouse.y - start.mouse.y)
        let center = DockLayoutEngine.floatingCenter(for: rect, screen: controller.screen.geometry,
                                                     snap: model.store.settings.magneticSnapping)
        let screenID = state.screenID
        model.store.updateDock(dock.id) { dock in
            if dock.screens.showOnAllScreens || dock.perScreenPositions[screenID] != nil {
                var p = dock.perScreenPositions[screenID] ?? dock.position
                p.floatingCenterX = center.x
                p.floatingCenterY = center.y
                dock.perScreenPositions[screenID] = p
            } else {
                dock.position.floatingCenterX = center.x
                dock.position.floatingCenterY = center.y
            }
        }
    }
}
