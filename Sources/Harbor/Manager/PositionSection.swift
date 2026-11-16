import HarborCore
import SwiftUI

struct PositionSection: View {
    @Environment(AppModel.self) private var model
    let dock: Dock

    var body: some View {
        let notch = dock.layout == .notch
        Form {
            if !notch {
                Section {
                    Picker("Placement", selection: modeBinding) {
                        Text("Pinned to an edge").tag(PositionMode.pinned)
                        Text("Floating").tag(PositionMode.floating)
                    }
                    .pickerStyle(.segmented)
                }
            }

            if dock.position.mode == .pinned || notch {
                Section(notch ? "Notch position" : "Screen position") {
                    SpotPicker(edge: dock.position.edge, alignment: dock.position.alignment,
                               taken: takenSpots,
                               disabledEdges: notch && !model.store.settings.deepHideNativeDock ? [.bottom] : []) { edge, alignment in
                        model.store.updateDock(dock.id) {
                            $0.position.edge = edge
                            $0.position.alignment = alignment
                            $0.perScreenPositions = [:]
                        }
                    }
                    .frame(height: 150)
                    if notch && !model.store.settings.deepHideNativeDock {
                        Text("Bottom spots need Settings › General › Hide the macOS Dock.")
                            .font(.caption).foregroundStyle(Tokens.textMuted)
                    }
                }
                if !notch {
                    Section {
                        Toggle("Span the whole edge", isOn: dock[binding: model, \.position.fullWidth])
                        PresetPicker(title: "Gap from edge", preset: dock[binding: model, \.position.gapPreset],
                                     custom: .custom, value: dock[binding: model, \.position.customGap], range: 0...64, unit: "pt")
                    }
                    Section("Fine tuning") {
                        if !dock.position.fullWidth {
                            ValueSlider(title: "Shift along edge", value: dock[binding: model, \.position.offsetAlongEdge],
                                        range: -400...400, unit: " pt")
                        }
                        ValueSlider(title: "Extra edge inset", value: dock[binding: model, \.position.edgePadding],
                                    range: 0...64, unit: " pt")
                        ValueSlider(title: "Inset from corners", value: dock[binding: model, \.position.endPadding],
                                    range: 0...200, unit: " pt")
                    }
                }
            } else {
                Section("Floating") {
                    Toggle("Always show the drag handle", isOn: dock[binding: model, \.position.alwaysShowDragHandle])
                    Toggle("Lock position", isOn: dock[binding: model, \.position.locked])
                    Button("Center on Screen") {
                        model.store.updateDock(dock.id) {
                            $0.position.floatingCenterX = 0.5
                            $0.position.floatingCenterY = 0.5
                            $0.perScreenPositions = [:]
                        }
                    }
                    Text("Drag the handle at the end of the dock to move it. It snaps to edges and the screen's center when magnetic snapping is on.")
                        .font(.caption).foregroundStyle(Tokens.textMuted)
                }
            }

            if !notch {
                Section {
                    Toggle("Sit on the desktop, behind windows", isOn: dock[binding: model, \.position.desktopWidgetMode])
                }
            }

            if !dock.perScreenPositions.isEmpty {
                Section("Screen-specific positions") {
                    Text("This dock has its own position on \(dock.perScreenPositions.count) screen(s), set by dragging it there.")
                    Button("Use the Same Position Everywhere") {
                        model.store.updateDock(dock.id) { $0.perScreenPositions = [:] }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var modeBinding: Binding<PositionMode> {
        Binding(get: { dock.position.mode }, set: { mode in
            model.store.updateDock(dock.id) {
                $0.position.mode = mode
                if mode == .pinned {
                    $0.position.edge = .bottom
                    $0.position.alignment = .center
                }
                $0.perScreenPositions = [:]
            }
        })
    }

    /// Spots other enabled pinned docks of the same layout already use, so two docks
    /// don't end up stacked on the same spot without the picker saying so.
    private var takenSpots: [SpotPicker.Spot] {
        model.store.docks
            .filter { $0.id != dock.id && $0.enabled && $0.layout == dock.layout
                && ($0.position.mode == .pinned || $0.layout == .notch) }
            .map { SpotPicker.Spot(edge: $0.position.edge, alignment: $0.position.alignment) }
    }
}

/// Twelve spots, three per screen edge, drawn on a small screen outline.
struct SpotPicker: View {
    struct Spot: Hashable {
        let edge: ScreenEdge
        let alignment: EdgeAlignment
    }

    let edge: ScreenEdge
    let alignment: EdgeAlignment
    var taken: [Spot] = []
    var disabledEdges: Set<ScreenEdge> = []
    let select: (ScreenEdge, EdgeAlignment) -> Void

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: 16, dy: 12)
            ZStack {
                RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                ForEach(ScreenEdge.allCases, id: \.self) { e in
                    ForEach(EdgeAlignment.allCases, id: \.self) { a in
                        spot(e, a, in: rect)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen position")
    }

    @ViewBuilder
    private func spot(_ e: ScreenEdge, _ a: EdgeAlignment, in rect: CGRect) -> some View {
        let selected = e == edge && a == alignment
        let isTaken = taken.contains(Spot(edge: e, alignment: a))
        let disabled = disabledEdges.contains(e)
        let horizontal = e == .bottom || e == .top
        Button { select(e, a) } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(selected ? Tokens.accent : Tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Tokens.accent : Tokens.border))
                .overlay(isTaken ? Circle().fill(Tokens.textMuted).frame(width: 5, height: 5) : nil)
                .frame(width: horizontal ? 36 : 10, height: horizontal ? 10 : 30)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .position(point(e, a, rect))
        .accessibilityLabel("\(e.rawValue.capitalized), \(label(a, horizontal: horizontal))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(isTaken ? "Used by another dock" : "\(e.rawValue.capitalized), \(label(a, horizontal: horizontal))")
    }

    private func label(_ a: EdgeAlignment, horizontal: Bool) -> String {
        switch a {
        case .start: horizontal ? "left" : "top"
        case .center: "center"
        case .end: horizontal ? "right" : "bottom"
        }
    }

    private func point(_ e: ScreenEdge, _ a: EdgeAlignment, _ r: CGRect) -> CGPoint {
        let t: CGFloat = a == .start ? 0.2 : a == .center ? 0.5 : 0.8
        switch e {
        case .bottom: return CGPoint(x: r.minX + r.width * t, y: r.maxY - 8)
        case .top: return CGPoint(x: r.minX + r.width * t, y: r.minY + 8)
        case .left: return CGPoint(x: r.minX + 8, y: r.minY + r.height * t)
        case .right: return CGPoint(x: r.maxX - 8, y: r.minY + r.height * t)
        }
    }
}
