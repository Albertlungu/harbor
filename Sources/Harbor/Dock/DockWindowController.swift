import AppKit
import HarborCore
import Observation
import SwiftUI

/// What the dock's SwiftUI content needs to lay itself out inside the panel.
@MainActor
@Observable
final class DockViewState {
    let dockID: UUID
    let screenID: String
    /// The bar's rectangle in panel coordinates (top-left origin).
    var barRect: CGRect = .zero
    /// Which side of the panel the bar hugs; magnification and labels grow away from it.
    var hugEdge: ScreenEdge = .bottom
    var slots: [DockSlot] = []
    /// Pointer position along the dock axis in panel coordinates, while hovering the bar.
    var pointer: CGFloat?
    var hovering = false
    /// The panel's size, so magnified items can be kept inside it (and on screen).
    var panelSize: CGSize = .zero
    /// Slide applied to the whole dock while auto-hidden; the window itself stays put.
    var hideOffset: CGSize = .zero
    /// Fade applied while hidden as a floating dock or under another window.
    var contentOpacity: Double = 1
    /// True while a popover from this dock is open; keeps auto-hide from firing.
    var menuOpen = false
    /// The slot under the pointer, for gestures handled outside SwiftUI.
    var hoveredSlotID: String?
    /// Notch layout: folded into its pill, and where the pill sits in panel coordinates.
    var notchFolded = false
    var notchPillRect: CGRect = .zero

    init(dockID: UUID, screenID: String) {
        self.dockID = dockID
        self.screenID = screenID
    }

    var isHorizontal: Bool { hugEdge == .bottom || hugEdge == .top }
    /// Slid or faded out of sight; widgets that tick stop redrawing the panel while this holds.
    var contentHidden: Bool { hideOffset != .zero || contentOpacity == 0 }
}

/// Owns one dock panel on one screen and keeps it placed.
@MainActor
final class DockWindowController {
    let state: DockViewState
    let panel = DockPanel()
    private(set) var barFrame: CGRect = .zero
    private(set) var screen: ConnectedScreen
    private var dock: Dock

    /// Auto-hide state for this panel.
    private(set) var autoHidden = false
    private var leaveDate: Date?
    private var enterDate: Date?
    private(set) var fullscreenHidden = false
    private var hotkeyRevealUntil: Date?
    private var notchMoveTask: Task<Void, Never>?
    private var lastNotchPlacement: [AnyHashable] = []
    private var isEditing = false
    /// Faded out because another app's window overlaps the bar; returns after it has been clear a while.
    private(set) var windowHoverHidden = false
    private var windowClearSince: Date?
    /// Temporarily shown at the screen edge although fullscreen or window hover would hide it.
    private var edgeRevealed = false
    private var edgeEnter: Date?
    private var edgeLeave: Date?
    private var notchEnter: Date?
    private var notchLeave: Date?

    init(dock: Dock, screen: ConnectedScreen, model: AppModel) {
        self.dock = dock
        self.screen = screen
        state = DockViewState(dockID: dock.id, screenID: screen.id)
        let root = DockRootView(state: state).environment(model)
        panel.contentView = FirstClickHostingView(rootView: root)
        autoHidden = Self.hidesWhenIdle(dock)
        state.notchFolded = Self.foldsWhenIdle(dock)
    }

    private var isNotch: Bool { dock.layout == .notch }

    /// Auto-hide for dock layouts; notches use their idle mode instead.
    private static func hidesWhenIdle(_ dock: Dock) -> Bool {
        dock.layout == .notch ? dock.style.notch.idleMode == .hidden : dock.behavior.autoHide
    }

    private static func foldsWhenIdle(_ dock: Dock) -> Bool {
        dock.layout == .notch && dock.style.notch.idleMode == .pill
    }

    private var revealDelay: Double { isNotch ? dock.style.notch.expandAfter : dock.behavior.revealDelay }
    private var hideDelay: Double { isNotch ? dock.style.notch.foldAfter : dock.behavior.hideDelay }

    private var notchArea: CGRect {
        DockLayoutEngine.notchArea(position: ScreenResolver.position(for: dock, on: screen.id), screen: screen.geometry)
    }

    /// The screen-space region that currently responds to the pointer.
    /// How far magnified icons stick out from the bar; past this the panel is only room for labels.
    private var hoverReach: CGFloat = 8

    /// The bar plus the band its magnified icons grow into. Hover is held only here so the label room beside a
    /// side dock never swallows clicks meant for the windows next to it.
    private var hoverRect: CGRect {
        let bar = activeRect
        switch state.hugEdge {
        case .bottom: return CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: bar.height + hoverReach)
        case .top: return CGRect(x: bar.minX, y: bar.minY - hoverReach, width: bar.width, height: bar.height + hoverReach)
        case .left: return CGRect(x: bar.minX, y: bar.minY, width: bar.width + hoverReach, height: bar.height)
        case .right: return CGRect(x: bar.minX - hoverReach, y: bar.minY, width: bar.width + hoverReach, height: bar.height)
        }
    }

    private var activeRect: CGRect {
        guard isNotch, state.notchFolded else {
            // The collapse button sits just outside the bar's start, so it counts as part of the dock.
            guard dock.style.collapse.enabled, dock.layout == .dock, !dock.style.collapse.collapsed else { return barFrame }
            let reach = DockMetrics.collapseReach
            return state.isHorizontal
                ? CGRect(x: barFrame.minX - reach, y: barFrame.minY, width: barFrame.width + reach, height: barFrame.height)
                : CGRect(x: barFrame.minX, y: barFrame.minY, width: barFrame.width, height: barFrame.height + reach)
        }
        return DockLayoutEngine.notchPillFrame(for: barFrame, edge: state.hugEdge).insetBy(dx: -8, dy: -8)
    }

    var dockID: UUID { dock.id }
    var panelFrame: CGRect { panel.frame }

    func update(dock: Dock, screen: ConnectedScreen, slots: [DockSlot], settings: AppSettings, editing: Bool) {
        let behaviorChanged = Self.hidesWhenIdle(dock) != Self.hidesWhenIdle(self.dock)
        let foldChanged = Self.foldsWhenIdle(dock) != Self.foldsWhenIdle(self.dock)
        self.dock = dock
        self.screen = screen
        if behaviorChanged { autoHidden = Self.hidesWhenIdle(dock) }
        if foldChanged { state.notchFolded = Self.foldsWhenIdle(dock) }
        isEditing = editing
        if editing { autoHidden = false }
        state.slots = slots

        let iconSize = CGFloat(dock.style.iconSize)
        let spacing = CGFloat(dock.style.spacing.points)
        var lengths = slots.map { CGFloat($0.cells) * iconSize + ($0.cells > 1 ? spacing * CGFloat($0.cells - 1) : 0) }
        if dock.position.mode == .floating { lengths.append(DockMetrics.handleLength) }
        let position = ScreenResolver.position(for: dock, on: screen.id)
        // The panel is sized for the expanded bar even while collapsed, so collapsing and
        // expanding animate inside one window instead of snapping the window's frame.
        let expandedBar = DockLayoutEngine.barFrame(dock: dock, position: position, slotLengths: lengths, screen: screen.geometry)
        let collapsed = dock.style.collapse.enabled && dock.layout == .dock && dock.style.collapse.collapsed
        barFrame = collapsed ? Self.collapsedBar(expandedBar, dock: dock) : expandedBar

        let hug: ScreenEdge
        if position.mode == .pinned || dock.layout == .notch { hug = position.edge }
        else { hug = dock.style.orientation == .horizontal ? .bottom : .left }
        state.hugEdge = hug

        let magnify = dock.style.magnify && dock.layout == .dock
        let grow = magnify ? iconSize * CGFloat(dock.style.maxScale - 1) : 0
        let across = hug == .left || hug == .right
            ? max(grow + Tokens.Dock.labelHeadroom, Tokens.Dock.sideLabelRoom)
            : grow + Tokens.Dock.labelHeadroom
        hoverReach = grow + 8
        let along = grow * CGFloat(dock.style.falloff) + 12 + (dock.style.collapse.enabled && dock.layout == .dock ? DockMetrics.collapseReach : 0)
        var frame = expandedBar
        switch hug {
        case .bottom: frame = CGRect(x: frame.minX - along, y: frame.minY, width: frame.width + along * 2, height: frame.height + across)
        case .top: frame = CGRect(x: frame.minX - along, y: frame.minY - across, width: frame.width + along * 2, height: frame.height + across)
        case .left: frame = CGRect(x: frame.minX, y: frame.minY - along, width: frame.width + across, height: frame.height + along * 2)
        case .right: frame = CGRect(x: frame.minX - across, y: frame.minY - along, width: frame.width + across, height: frame.height + along * 2)
        }
        frame = frame.intersection(screen.geometry.frame.insetBy(dx: -1, dy: -1))
        if frame.isNull { frame = barFrame }

        state.panelSize = frame.size
        state.barRect = CGRect(x: barFrame.minX - frame.minX, y: frame.maxY - barFrame.maxY,
                               width: barFrame.width, height: barFrame.height)

        let pill = DockLayoutEngine.notchPillFrame(for: barFrame, edge: hug)
        state.notchPillRect = CGRect(x: pill.minX - frame.minX, y: frame.maxY - pill.maxY, width: pill.width, height: pill.height)

        applyWindowRules(position: position, settings: settings)
        panel.appearance = Self.contentAppearance(for: dock)
        if isNotch {
            if editing { state.notchFolded = false }
            moveNotch(to: frame, position: position)
        } else {
            place(frame: frame, animated: false)
        }
    }

    /// A notch that changes spot folds, moves while folded, then unfolds. Reduce Motion skips the dance.
    private func moveNotch(to frame: CGRect, position: Position) {
        let placement: [AnyHashable] = [position.edge, position.alignment, position.offsetAlongEdge, screen.id]
        defer { lastNotchPlacement = placement }
        let moved = !lastNotchPlacement.isEmpty && lastNotchPlacement != placement
        guard moved, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            place(frame: frame, animated: false)
            return
        }
        notchMoveTask?.cancel()
        state.notchFolded = true
        notchMoveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.base + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.place(frame: self.targetFrame, animated: false)
            self.state.notchFolded = false
            // Pill mode refolds on its own once the pointer is away.
            self.notchLeave = Date()
        }
    }

    /// The edge strip this dock keeps other windows out of, if it reserves any.
    func reservedStrip(settings: AppSettings) -> ReservedStrip? {
        let position = ScreenResolver.position(for: dock, on: screen.id)
        guard settings.reserveDockSpace, dock.behavior.reserveSpace, position.mode == .pinned, dock.layout == .dock,
              !dock.behavior.autoHide, !dock.behavior.hideOnWindowHover, !fullscreenHidden, !barFrame.isEmpty else { return nil }
        return DockLayoutEngine.reservedStrip(bar: barFrame, edge: position.edge, fullWidth: position.fullWidth,
                                              screen: screen.geometry)
    }

    static var popoverOnScreen: Bool {
        NSApp.windows.contains { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
    }

    /// A square the size of the bar's thickness, at the end the collapse button lives on.
    static func collapsedBar(_ bar: CGRect, dock: Dock) -> CGRect {
        let horizontal = bar.width >= bar.height
        let side = horizontal ? bar.height : bar.width
        let length = horizontal ? bar.width : bar.height
        let offset: CGFloat = switch dock.style.collapse.buttonPosition {
        case .auto, .start: 0
        case .center: (length - side) / 2
        case .end: length - side
        }
        // Start is the left end of a horizontal bar and the top end of a vertical one.
        return horizontal
            ? CGRect(x: bar.minX + offset, y: bar.minY, width: side, height: side)
            : CGRect(x: bar.minX, y: bar.maxY - side - offset, width: side, height: side)
    }

    /// Light or dark content to match the dock's own background, so labels and widgets stay
    /// legible on a light solid dock in dark mode and vice versa. Nil follows the system.
    static func contentAppearance(for dock: Dock) -> NSAppearance? {
        let style = dock.style
        if dock.layout == .notch {
            switch style.notch.background {
            case .black: return NSAppearance(named: .darkAqua)
            case .color: return NSAppearance(named: style.notch.color.isLight ? .aqua : .darkAqua)
            case .blur, .glass: return nil
            }
        }
        switch style.background {
        case .solid: return NSAppearance(named: style.solidColor.isLight ? .aqua : .darkAqua)
        case .blur where style.blurDarkness > 0.55: return NSAppearance(named: .darkAqua)
        case .glass where style.darkGlass: return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    private func applyWindowRules(position: Position, settings: AppSettings) {
        if position.desktopWidgetMode && dock.layout == .dock {
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        } else {
            panel.level = .statusBar
        }
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        switch dock.behavior.showOn {
        case .allSpaces: behavior.formUnion([.canJoinAllSpaces, .stationary])
        case .activeSpace: behavior.insert(.moveToActiveSpace)
        case .pinnedSpace: behavior.insert(.managed)
        }
        panel.collectionBehavior = behavior
        panel.sharingType = settings.hideFromScreenSharing ? .none : .readOnly
    }

    private var targetFrame: CGRect = .zero

    private func place(frame: CGRect, animated: Bool) {
        targetFrame = frame
        let shown = !suppressedByFullscreen
        var offset = CGSize.zero
        if autoHidden && shown && (dock.position.mode == .pinned || dock.layout == .notch) {
            let hiddenBar = isNotch
                ? DockLayoutEngine.notchHiddenFrame(for: barFrame, edge: state.hugEdge, area: notchArea)
                : DockLayoutEngine.hiddenFrame(for: barFrame, edge: state.hugEdge, screen: screen.geometry)
            // AppKit's y axis points up and SwiftUI's points down.
            offset = CGSize(width: hiddenBar.minX - barFrame.minX, height: barFrame.minY - hiddenBar.minY)
        }
        let floatingHidden = autoHidden && dock.position.mode == .floating && dock.layout == .dock
        let opacity: Double = (floatingHidden || (windowHoverHidden && !edgeRevealed)) ? 0 : 1

        // The window keeps its frame and only the content slides or fades, on the GPU.
        // Animating the window frame relaid the SwiftUI content every step and ran choppy.
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.alphaValue = 1
        let changes = { [state] in
            state.hideOffset = offset
            state.contentOpacity = opacity
        }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.smooth(duration: 0.26), changes)
        } else {
            changes()
        }
        if shown {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            panel.orderOut(nil)
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: Pointer tracking

    /// Called on every pointer move with the global pointer location.
    func pointerMoved(to point: CGPoint, now: Date = Date()) {
        // A hidden dock's resting rect is still on screen; ignoring it stops labels peeking out at the edge.
        let barHit = !(autoHidden && !isNotch) && activeRect.insetBy(dx: -2, dy: -2).contains(point)
        let panelHit = panel.frame.contains(point) && hoverRect.insetBy(dx: -2, dy: -2).contains(point)
        let inside = barHit || (state.hovering && panelHit && !autoHidden)

        if inside != state.hovering { state.hovering = inside }
        // Only touch the window when the value changes; setting it reaches the window server on every mouse move.
        let ignore = (windowHoverHidden && !edgeRevealed) || !(barHit || (state.hovering && panelHit))
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
        if inside {
            let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
            state.pointer = state.isHorizontal ? local.x : local.y
        } else if state.pointer != nil {
            state.pointer = nil
        }
        updateEdgeReveal(pointer: point, now: now)
        updateNotchFold(pointer: point, now: now)
        updateAutoHide(pointer: point, inside: inside, now: now)
    }

    /// Pill idle mode: unfold after the pointer rests on the pill, refold once it has left the open notch.
    private func updateNotchFold(pointer: CGPoint, now: Date) {
        guard isNotch, dock.style.notch.idleMode == .pill, !isEditing else { return }
        if state.notchFolded {
            notchLeave = nil
            if activeRect.contains(pointer) {
                if notchEnter == nil { notchEnter = now }
                if now.timeIntervalSince(notchEnter!) >= dock.style.notch.expandAfter {
                    state.notchFolded = false
                    notchEnter = nil
                }
            } else {
                notchEnter = nil
            }
        } else {
            notchEnter = nil
            if barFrame.insetBy(dx: -4, dy: -4).contains(pointer) || state.menuOpen {
                notchLeave = nil
            } else {
                if notchLeave == nil { notchLeave = now }
                if now.timeIntervalSince(notchLeave!) >= dock.style.notch.foldAfter { state.notchFolded = true }
            }
        }
    }

    private func updateAutoHide(pointer: CGPoint, inside: Bool, now: Date) {
        guard Self.hidesWhenIdle(dock) || dock.behavior.showAtEdgeWhileHidden || hotkeyRevealUntil != nil else { return }
        if let until = hotkeyRevealUntil {
            if now < until || inside { return }
            hotkeyRevealUntil = nil
        }
        guard Self.hidesWhenIdle(dock) else { return }
        if autoHidden {
            let reveal: Bool
            if dock.position.mode == .pinned || dock.layout == .notch {
                let distance = dock.behavior.revealTrigger == .atEdge || isNotch ? 2 : CGFloat(dock.behavior.revealDistance)
                let zone = isNotch
                    ? DockLayoutEngine.notchRevealZone(for: barFrame, edge: state.hugEdge, area: notchArea, distance: distance)
                    : DockLayoutEngine.revealZone(for: barFrame, edge: state.hugEdge, screen: screen.geometry, distance: distance)
                reveal = zone.contains(pointer)
            } else {
                reveal = barFrame.insetBy(dx: -CGFloat(dock.behavior.revealDistance),
                                          dy: -CGFloat(dock.behavior.revealDistance)).contains(pointer)
            }
            if reveal {
                if enterDate == nil { enterDate = now }
                if now.timeIntervalSince(enterDate!) >= revealDelay {
                    autoHidden = false
                    enterDate = nil
                    place(frame: targetFrame, animated: true)
                }
            } else {
                enterDate = nil
            }
        } else {
            // The strip between the bar and the screen edge counts as near, so a pointer parked
            // at the edge doesn't hide the dock and then immediately reveal it again.
            let pinned = dock.position.mode == .pinned || isNotch
            let edgeStrip = pinned
                ? DockLayoutEngine.revealZone(for: barFrame, edge: state.hugEdge, screen: screen.geometry,
                                              distance: CGFloat(dock.position.gap) + 10)
                : .null
            let near = inside || barFrame.insetBy(dx: -8, dy: -8).contains(pointer) || edgeStrip.contains(pointer)
            // A popover keeps the dock up only while one is really on screen; the flag alone could
            // stay set if the item that opened it was redrawn, leaving the dock up for good.
            if state.menuOpen && !Self.popoverOnScreen { state.menuOpen = false }
            if near || state.menuOpen {
                leaveDate = nil
            } else {
                if leaveDate == nil { leaveDate = now }
                if now.timeIntervalSince(leaveDate!) >= hideDelay {
                    autoHidden = true
                    leaveDate = nil
                    place(frame: targetFrame, animated: true)
                }
            }
        }
    }

    /// Brings an auto-hidden dock out for a few seconds, e.g. when a download lands in one of its folders.
    func peek(duration: Double) {
        guard autoHidden else { return }
        revealFromHotkey(duration: duration)
        peekTask?.cancel()
        // Hiding is otherwise decided on pointer moves, so a still pointer would leave the dock out indefinitely.
        peekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.endPeek()
        }
    }

    private var peekTask: Task<Void, Never>?

    private func endPeek() {
        guard hotkeyRevealUntil != nil, Self.hidesWhenIdle(dock), !state.menuOpen,
              !hoverRect.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) else { return }
        hotkeyRevealUntil = nil
        autoHidden = true
        place(frame: targetFrame, animated: true)
    }

    /// Shows an auto-hidden dock after a hotkey, keeping it up for `duration` seconds (0 = until pointer leaves).
    func revealFromHotkey(duration: Double) {
        autoHidden = false
        hotkeyRevealUntil = Date().addingTimeInterval(duration > 0 ? duration : 1)
        place(frame: targetFrame, animated: true)
    }

    private var suppressedByFullscreen: Bool { fullscreenHidden && !edgeRevealed }

    /// Whether the bar can be seen right now; an auto-hidden or faded bar keeps its resting `barFrame`.
    var showsBar: Bool {
        panel.isVisible && !barFrame.isEmpty && !suppressedByFullscreen && !autoHidden
            && !(windowHoverHidden && !edgeRevealed)
    }

    /// "Show at screen edge while hidden": a pointer resting at the edge zone brings the dock back until it leaves.
    private func updateEdgeReveal(pointer: CGPoint, now: Date) {
        guard dock.behavior.showAtEdgeWhileHidden, dock.position.mode == .pinned, !isNotch,
              fullscreenHidden || windowHoverHidden else {
            if edgeRevealed { edgeRevealed = false; place(frame: targetFrame, animated: true) }
            edgeEnter = nil
            edgeLeave = nil
            return
        }
        if edgeRevealed {
            if barFrame.insetBy(dx: -8, dy: -8).contains(pointer) || state.menuOpen {
                edgeLeave = nil
            } else {
                if edgeLeave == nil { edgeLeave = now }
                if now.timeIntervalSince(edgeLeave!) >= dock.behavior.hideDelay {
                    edgeRevealed = false
                    edgeLeave = nil
                    place(frame: targetFrame, animated: true)
                }
            }
        } else {
            let zone = DockLayoutEngine.revealZone(for: barFrame, edge: state.hugEdge, screen: screen.geometry, distance: 2)
            if zone.contains(pointer) {
                if edgeEnter == nil { edgeEnter = now }
                if now.timeIntervalSince(edgeEnter!) >= dock.behavior.revealDelay {
                    edgeRevealed = true
                    edgeEnter = nil
                    edgeLeave = nil
                    place(frame: targetFrame, animated: true)
                }
            } else {
                edgeEnter = nil
            }
        }
    }

    /// `overlapping` is whether another app's window currently intersects the bar.
    func updateWindowHover(overlapping: Bool, now: Date = Date()) {
        guard dock.behavior.hideOnWindowHover, !isEditing else {
            if windowHoverHidden { windowHoverHidden = false; windowClearSince = nil; place(frame: targetFrame, animated: true) }
            return
        }
        if overlapping {
            windowClearSince = nil
            if !windowHoverHidden {
                windowHoverHidden = true
                state.pointer = nil
                place(frame: targetFrame, animated: true)
            }
        } else if windowHoverHidden {
            if windowClearSince == nil { windowClearSince = now }
            if now.timeIntervalSince(windowClearSince!) >= 0.4 {
                windowHoverHidden = false
                windowClearSince = nil
                place(frame: targetFrame, animated: true)
            }
        }
    }

    func setFullscreenHidden(_ hidden: Bool) {
        guard hidden != fullscreenHidden else { return }
        fullscreenHidden = hidden
        place(frame: targetFrame, animated: false)
    }
}

enum DockMetrics {
    static let handleLength: CGFloat = 14
    /// Room outside the bar's start for the collapse button.
    static let collapseReach: CGFloat = 24
}
