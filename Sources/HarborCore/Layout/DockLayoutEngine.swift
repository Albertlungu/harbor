import CoreGraphics
import Foundation

extension Array {
    /// Moves the elements at `source` so they sit before `destination`, matching List reordering.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { self[$0] }
        let before = source.filter { $0 < destination }.count
        for i in source.sorted(by: >) { remove(at: i) }
        insert(contentsOf: moving, at: Swift.min(destination - before, count))
    }
}

/// The screen geometry a dock is placed on, in AppKit global coordinates (origin bottom-left).
public struct ScreenGeometry: Equatable, Sendable {
    public var frame: CGRect
    /// The frame minus the menu bar and the native Dock.
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    /// The area pinned docks use: the whole screen except the menu bar.
    public var pinnedArea: CGRect {
        var area = frame
        area.size.height = visibleFrame.maxY - frame.minY
        return area
    }
}

/// Pure geometry for placing a dock's bar on a screen.
public enum DockLayoutEngine {
    public static let snapThreshold: CGFloat = 12

    /// Length of the bar along its axis for the given item lengths.
    public static func contentLength(style: DockStyle, slotLengths: [CGFloat]) -> CGFloat {
        let spacing = CGFloat(style.spacing.points)
        let items = slotLengths.reduce(0, +) + spacing * CGFloat(max(slotLengths.count - 1, 0))
        let padded = items + CGFloat(style.sidePadding) * 2
        return max(padded, CGFloat(style.thickness))
    }

    /// The bar's rectangle on `screen`.
    public static func barFrame(dock: Dock, position: Position, slotLengths: [CGFloat], screen: ScreenGeometry) -> CGRect {
        let thickness = CGFloat(dock.style.thickness)
        let orientation = dock.effectiveOrientation
        var length = contentLength(style: dock.style, slotLengths: slotLengths)

        if position.mode == .floating && dock.layout == .dock {
            let size = orientation == .horizontal
                ? CGSize(width: length, height: thickness)
                : CGSize(width: thickness, height: length)
            let vf = screen.visibleFrame
            let center = CGPoint(x: vf.minX + vf.width * position.floatingCenterX,
                                 y: vf.minY + vf.height * position.floatingCenterY)
            let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height)
            return clamp(rect, into: vf)
        }

        let area = dock.layout == .notch ? notchArea(position: position, screen: screen) : screen.pinnedArea
        let gap = CGFloat(dock.layout == .notch ? 0 : position.gap) + CGFloat(position.edgePadding)
        let endPad = CGFloat(position.endPadding)
        let edgeLength = orientation == .horizontal ? area.width : area.height
        let fullWidth = position.fullWidth && dock.layout == .dock
        if fullWidth { length = edgeLength - endPad * 2 }
        length = min(length, edgeLength - endPad * 2)

        // Distance from the start corner (left, or top on side edges) along the edge.
        var along: CGFloat
        switch position.alignment {
        case .start: along = endPad
        case .center: along = (edgeLength - length) / 2
        case .end: along = edgeLength - endPad - length
        }
        if !fullWidth {
            let offset = CGFloat(position.offsetAlongEdge)
            along += position.alignment == .end ? -offset : offset
            along = min(max(along, 0), edgeLength - length)
        }

        switch position.edge {
        case .bottom:
            return CGRect(x: area.minX + along, y: area.minY + gap, width: length, height: thickness)
        case .top:
            return CGRect(x: area.minX + along, y: area.maxY - gap - thickness, width: length, height: thickness)
        case .left:
            return CGRect(x: area.minX + gap, y: area.maxY - along - length, width: thickness, height: length)
        case .right:
            return CGRect(x: area.maxX - gap - thickness, y: area.maxY - along - length, width: thickness, height: length)
        }
    }

    /// Where an auto-hidden pinned bar sits: just past its edge, fully off screen.
    public static func hiddenFrame(for bar: CGRect, edge: ScreenEdge, screen: ScreenGeometry) -> CGRect {
        let area = screen.pinnedArea
        var r = bar
        switch edge {
        case .bottom: r.origin.y = area.minY - bar.height - 2
        case .top: r.origin.y = area.maxY + 2
        case .left: r.origin.x = area.minX - bar.width - 2
        case .right: r.origin.x = area.maxX + 2
        }
        return r
    }

    /// The strip along the edge that reveals a hidden pinned dock when the pointer enters it.
    public static func revealZone(for bar: CGRect, edge: ScreenEdge, screen: ScreenGeometry, distance: CGFloat) -> CGRect {
        let area = screen.pinnedArea
        let d = max(distance, 1)
        switch edge {
        case .bottom: return CGRect(x: bar.minX, y: area.minY, width: bar.width, height: d)
        case .top: return CGRect(x: bar.minX, y: area.maxY - d, width: bar.width, height: d)
        case .left: return CGRect(x: area.minX, y: bar.minY, width: d, height: bar.height)
        case .right: return CGRect(x: area.maxX - d, y: bar.minY, width: d, height: bar.height)
        }
    }

    // MARK: Notch

    public static let notchPillLength: CGFloat = 120
    public static let notchPillDepth: CGFloat = 8

    /// The area a notch bar attaches to. The top-center notch sits over the menu bar, flush to the screen top.
    public static func notchArea(position: Position, screen: ScreenGeometry) -> CGRect {
        position.edge == .top && position.alignment == .center ? screen.frame : screen.pinnedArea
    }

    /// The folded pill: centered on the bar along the edge, flush against the edge side.
    public static func notchPillFrame(for bar: CGRect, edge: ScreenEdge) -> CGRect {
        let long = min(notchPillLength, edge == .top || edge == .bottom ? bar.width : bar.height)
        switch edge {
        case .top: return CGRect(x: bar.midX - long / 2, y: bar.maxY - notchPillDepth, width: long, height: notchPillDepth)
        case .bottom: return CGRect(x: bar.midX - long / 2, y: bar.minY, width: long, height: notchPillDepth)
        case .left: return CGRect(x: bar.minX, y: bar.midY - long / 2, width: notchPillDepth, height: long)
        case .right: return CGRect(x: bar.maxX - notchPillDepth, y: bar.midY - long / 2, width: notchPillDepth, height: long)
        }
    }

    /// Where a notch in "hidden" idle mode rests: fully past its edge.
    public static func notchHiddenFrame(for bar: CGRect, edge: ScreenEdge, area: CGRect) -> CGRect {
        var r = bar
        switch edge {
        case .bottom: r.origin.y = area.minY - bar.height - 2
        case .top: r.origin.y = area.maxY + 2
        case .left: r.origin.x = area.minX - bar.width - 2
        case .right: r.origin.x = area.maxX + 2
        }
        return r
    }

    /// The edge strip that reveals a hidden notch, limited to the bar's span.
    public static func notchRevealZone(for bar: CGRect, edge: ScreenEdge, area: CGRect, distance: CGFloat) -> CGRect {
        let d = max(distance, 1)
        switch edge {
        case .bottom: return CGRect(x: bar.minX, y: area.minY, width: bar.width, height: d)
        case .top: return CGRect(x: bar.minX, y: area.maxY - d, width: bar.width, height: d)
        case .left: return CGRect(x: area.minX, y: bar.minY, width: d, height: bar.height)
        case .right: return CGRect(x: area.maxX - d, y: bar.minY, width: d, height: bar.height)
        }
    }

    /// Which corners of a notch are rounded: only the ones facing into the screen.
    public struct NotchCorners: Equatable, Sendable {
        public var topLeft = false, topRight = false, bottomLeft = false, bottomRight = false
    }

    public static func notchCorners(edge: ScreenEdge) -> NotchCorners {
        switch edge {
        case .top: NotchCorners(bottomLeft: true, bottomRight: true)
        case .bottom: NotchCorners(topLeft: true, topRight: true)
        case .left: NotchCorners(topRight: true, bottomRight: true)
        case .right: NotchCorners(topLeft: true, bottomLeft: true)
        }
    }

    /// Converts a dragged floating bar's frame back into stored center fractions,
    /// snapping to the screen's center lines and edges when close.
    public static func floatingCenter(for rect: CGRect, screen: ScreenGeometry, snap: Bool) -> (x: Double, y: Double) {
        let vf = screen.visibleFrame
        var r = clamp(rect, into: vf)
        if snap {
            let t = snapThreshold
            if abs(r.midX - vf.midX) < t { r.origin.x = vf.midX - r.width / 2 }
            if abs(r.midY - vf.midY) < t { r.origin.y = vf.midY - r.height / 2 }
            if abs(r.minX - vf.minX) < t { r.origin.x = vf.minX }
            if abs(r.maxX - vf.maxX) < t { r.origin.x = vf.maxX - r.width }
            if abs(r.minY - vf.minY) < t { r.origin.y = vf.minY }
            if abs(r.maxY - vf.maxY) < t { r.origin.y = vf.maxY - r.height }
        }
        let x = vf.width > 0 ? (r.midX - vf.minX) / vf.width : 0.5
        let y = vf.height > 0 ? (r.midY - vf.minY) / vf.height : 0.5
        return (Double(x), Double(y))
    }

    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var r = rect
        if r.width > bounds.width { r.origin.x = bounds.midX - r.width / 2 }
        else { r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width) }
        if r.height > bounds.height { r.origin.y = bounds.midY - r.height / 2 }
        else { r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height) }
        return r
    }

    /// Magnification scale for an icon whose center is `distance` points from the pointer.
    public static func magnification(distance: CGFloat, iconSize: CGFloat, maxScale: CGFloat, falloff: CGFloat) -> CGFloat {
        let radius = max(iconSize * falloff, 1)
        guard distance < radius else { return 1 }
        let t = distance / radius
        // Cosine bell: full scale under the pointer, smooth to 1 at the radius.
        let bell = (cos(t * .pi) + 1) / 2
        return 1 + (maxScale - 1) * bell
    }
}
