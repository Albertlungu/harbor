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
    /// True while a popover from this dock is open; keeps auto-hide from firing.
    var menuOpen = false

    init(dockID: UUID, screenID: String) {
        self.dockID = dockID
        self.screenID = screenID
    }

    var isHorizontal: Bool { hugEdge == .bottom || hugEdge == .top }
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

    init(dock: Dock, screen: ConnectedScreen, model: AppModel) {
        self.dock = dock
        self.screen = screen
        state = DockViewState(dockID: dock.id, screenID: screen.id)
        let root = DockRootView(state: state).environment(model)
        panel.contentView = FirstClickHostingView(rootView: root)
        autoHidden = dock.behavior.autoHide
    }

    var dockID: UUID { dock.id }

    func update(dock: Dock, screen: ConnectedScreen, slots: [DockSlot], settings: AppSettings, editing: Bool) {
        let behaviorChanged = dock.behavior.autoHide != self.dock.behavior.autoHide
        self.dock = dock
        self.screen = screen
        if behaviorChanged { autoHidden = dock.behavior.autoHide }
        if editing { autoHidden = false }
        state.slots = slots

        let iconSize = CGFloat(dock.style.iconSize)
        let spacing = CGFloat(dock.style.spacing.points)
        var lengths = slots.map { CGFloat($0.cells) * iconSize + ($0.cells > 1 ? spacing * CGFloat($0.cells - 1) : 0) }
        if dock.style.collapse.enabled && dock.style.collapse.collapsed { lengths = [] }
        if dock.position.mode == .floating { lengths.append(DockMetrics.handleLength) }
        let position = ScreenResolver.position(for: dock, on: screen.id)
        barFrame = DockLayoutEngine.barFrame(dock: dock, position: position, slotLengths: lengths, screen: screen.geometry)

        let hug: ScreenEdge
        if position.mode == .pinned || dock.layout == .notch { hug = position.edge }
        else { hug = dock.style.orientation == .horizontal ? .bottom : .left }
        state.hugEdge = hug

        let magnify = dock.style.magnify && dock.layout == .dock
        let grow = magnify ? iconSize * CGFloat(dock.style.maxScale - 1) : 0
        let across = grow + Tokens.Dock.labelHeadroom
        let along = grow * CGFloat(dock.style.falloff) + 12
        var frame = barFrame
        switch hug {
        case .bottom: frame = CGRect(x: frame.minX - along, y: frame.minY, width: frame.width + along * 2, height: frame.height + across)
        case .top: frame = CGRect(x: frame.minX - along, y: frame.minY - across, width: frame.width + along * 2, height: frame.height + across)
        case .left: frame = CGRect(x: frame.minX, y: frame.minY - along, width: frame.width + across, height: frame.height + along * 2)
        case .right: frame = CGRect(x: frame.minX - across, y: frame.minY - along, width: frame.width + across, height: frame.height + along * 2)
        }
        frame = frame.intersection(screen.geometry.frame.insetBy(dx: -1, dy: -1))
        if frame.isNull { frame = barFrame }

        state.barRect = CGRect(x: barFrame.minX - frame.minX, y: frame.maxY - barFrame.maxY,
                               width: barFrame.width, height: barFrame.height)

        applyWindowRules(position: position, settings: settings)
        place(frame: frame, animated: false)
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
        let shown = !fullscreenHidden
        var final = frame
        if autoHidden && shown {
            if dock.position.mode == .pinned || dock.layout == .notch {
                let hiddenBar = DockLayoutEngine.hiddenFrame(for: barFrame, edge: state.hugEdge, screen: screen.geometry)
                final = frame.offsetBy(dx: hiddenBar.minX - barFrame.minX, dy: hiddenBar.minY - barFrame.minY)
            }
        }
        let alpha: CGFloat = (autoHidden && dock.position.mode == .floating && dock.layout == .dock) ? 0 : 1
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Tokens.Motion.reveal
                panel.animator().setFrame(final, display: true)
                panel.animator().alphaValue = alpha
            }
        } else {
            panel.setFrame(final, display: true)
            panel.alphaValue = alpha
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
        let barHit = barFrame.insetBy(dx: -2, dy: -2).contains(point)
        let panelHit = panel.frame.contains(point)
        let inside = barHit || (state.hovering && panelHit && !autoHidden)

        if inside != state.hovering { state.hovering = inside }
        panel.ignoresMouseEvents = !(barHit || (state.hovering && panelHit))
        if inside {
            let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
            state.pointer = state.isHorizontal ? local.x : local.y
        } else if state.pointer != nil {
            state.pointer = nil
        }
        updateAutoHide(pointer: point, inside: inside, now: now)
    }

    private func updateAutoHide(pointer: CGPoint, inside: Bool, now: Date) {
        guard dock.behavior.autoHide || dock.behavior.showAtEdgeWhileHidden || hotkeyRevealUntil != nil else { return }
        if let until = hotkeyRevealUntil {
            if now < until || inside { return }
            hotkeyRevealUntil = nil
        }
        guard dock.behavior.autoHide else { return }
        if autoHidden {
            let reveal: Bool
            if dock.position.mode == .pinned || dock.layout == .notch {
                let distance = dock.behavior.revealTrigger == .atEdge ? 2 : CGFloat(dock.behavior.revealDistance)
                reveal = DockLayoutEngine.revealZone(for: barFrame, edge: state.hugEdge, screen: screen.geometry,
                                                     distance: distance).contains(pointer)
            } else {
                reveal = barFrame.insetBy(dx: -CGFloat(dock.behavior.revealDistance),
                                          dy: -CGFloat(dock.behavior.revealDistance)).contains(pointer)
            }
            if reveal {
                if enterDate == nil { enterDate = now }
                if now.timeIntervalSince(enterDate!) >= dock.behavior.revealDelay {
                    autoHidden = false
                    enterDate = nil
                    place(frame: targetFrame, animated: true)
                }
            } else {
                enterDate = nil
            }
        } else {
            let near = panel.frame.contains(pointer) && (inside || barFrame.insetBy(dx: -8, dy: -8).contains(pointer))
            if near || state.menuOpen {
                leaveDate = nil
            } else {
                if leaveDate == nil { leaveDate = now }
                if now.timeIntervalSince(leaveDate!) >= dock.behavior.hideDelay {
                    autoHidden = true
                    leaveDate = nil
                    place(frame: targetFrame, animated: true)
                }
            }
        }
    }

    /// Shows an auto-hidden dock after a hotkey, keeping it up for `duration` seconds (0 = until pointer leaves).
    func revealFromHotkey(duration: Double) {
        autoHidden = false
        hotkeyRevealUntil = Date().addingTimeInterval(duration > 0 ? duration : 1)
        place(frame: targetFrame, animated: true)
    }

    func setFullscreenHidden(_ hidden: Bool) {
        guard hidden != fullscreenHidden else { return }
        fullscreenHidden = hidden
        place(frame: targetFrame, animated: false)
    }
}

enum DockMetrics {
    static let handleLength: CGFloat = 14
}
