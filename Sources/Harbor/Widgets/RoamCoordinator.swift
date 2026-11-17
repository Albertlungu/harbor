import AppKit
import HarborCore
import SwiftUI

struct PetKey: Hashable {
    let dock: UUID
    let item: UUID
}

/// Transparent and click-through except over the pet itself.
final class RoamPanel: NSPanel {
    init(side: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .statusBar
        // Matches the docks, so the pet stays put while Spaces slide past, fullscreen ones included.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
    }

    // Taking key status would pull typing focus away from whatever the person is working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Near the menu bar AppKit would otherwise nudge the window down, which would lift the pet off its ledge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// One live copy of a pet on the desktop.
@MainActor
private final class RoamPet {
    let key: PetKey
    let panel: RoamPanel
    let driver: RoamDriver
    var state: RoamState
    var screen: ConnectedScreen
    var home: RoamHome
    var mode: RoamMode = .patrol
    var surfaces: [RoamSurface] = []
    var walls: [RoamWall] = []
    var ceilings: [RoamSurface] = []
    var nav: RoamNav?
    var bars: [CGRect] = []
    var walkOnWindows = true
    var hidden = true
    var ticker: RoamTicker?
    var beat: Task<Void, Never>?
    var lastStep = ContinuousClock.now
    var holdUntil = Date.distantPast
    /// A menu is open on it or it is pressed: it stays exactly where it is until let go.
    var frozen = false
    /// The angle it is drawn at, eased toward the brain's, and the corner it is swinging around.
    var shownAngle = 0.0
    var turn: RoamTurn?
    /// The brain's middle when the swing began, so the pet keeps moving along the new surface meanwhile.
    var turnBase = CGPoint.zero
    var shownMiddle: CGPoint?
    var wasAttached = false
    var lastPresent = ContinuousClock.now

    init(key: PetKey, unit: CGFloat, screen: ConnectedScreen, home: RoamHome) {
        self.key = key
        driver = RoamDriver(unit: unit)
        panel = RoamPanel(side: driver.side)
        state = RoamState(x: home.point.x, y: home.point.y)
        self.screen = screen
        self.home = home
    }

    var unit: Double { Double(driver.unit) }
    var feet: CGPoint { CGPoint(x: state.x, y: state.y) }

    /// The middle of the body: above the feet, out from the wall it holds, or below its ceiling.
    var middle: CGPoint { RoamBrain.middle(state, half: unit / 2) }

    /// Still turning a corner or easing its angle, so it needs frames even when the brain is still.
    var settling: Bool {
        turn != nil || abs(RoamPose.delta(from: shownAngle, to: RoamPose.angle(state))) > 0.05
    }
}

/// A roaming pet as other layers see it, such as desktop weather.
struct RoamBody {
    let key: PetKey
    /// Bottom center of the body when upright; on a wall or ceiling, the point touching it.
    let feet: CGPoint
    let velocity: CGVector
    let unit: CGFloat
}

/// Owns every roaming pet: windows, the loops that move them, and the rules for when they hide.
@MainActor
final class RoamCoordinator {
    static let shared = RoamCoordinator()

    private var model: AppModel?
    private var pets: [PetKey: RoamPet] = [:]
    private var cells: [PetKey: CGPoint] = [:]
    private var windows: [RoamWindow] = []
    private var fullscreen: [CGRect] = []
    /// Screens that only just looked fullscreen, and since when.
    private var fullscreenSeen: (screens: [CGRect], since: Date)?
    private var locked = false
    private var monitors: [Any] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var snapshotTask: Task<Void, Never>?
    private var gate: CheckedContinuation<Void, Never>?
    private var forceSnapshot = false
    private var carrying: PetKey?
    /// Recent pointer positions while carrying, to throw the pet with the pointer's speed.
    private var carryTrail: [(time: TimeInterval, point: CGPoint)] = []
    private var elements: [CGRect] = []
    private var attention: CGPoint?
    /// Told about every jump, grab, slide, climb and landing, for sound effects.
    var eventSink: ((PetKey, RoamEvent) -> Void)?
    private let elementWatcher = RoamElementWatcher()
    private let attentionWatcher = RoamAttention()
    private var scanningElements = false
    private var watchingAttention = false
    private var lastGazeTick = Date.distantPast
    private var menusOpen = 0

    /// Quiet mode (Settings › Personality) keeps a roaming pet hanging out in one place.
    private var quiet: Bool { model?.store.settings.petQuiet ?? false }

    // MARK: Lifecycle

    /// Idempotent; called by any pet widget that appears, which is also what revives pets after a launch.
    func start(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        watch(nc, NSApplication.didChangeScreenParametersNotification) { $0.screensChanged() }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            watch(ws, name) { $0.requestSnapshot() }
        }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.setLocked(true) }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.setLocked(false) }
        // A right-click menu on a pet holds it still until the menu closes.
        watch(nc, NSMenu.didBeginTrackingNotification) { $0.menuTracking(true) }
        watch(nc, NSMenu.didEndTrackingNotification) { $0.menuTracking(false) }
        elementWatcher.onUpdate = { [weak self] rects in self?.updateElements(rects) }
        attentionWatcher.onChange = { [weak self] point, _ in self?.updateAttention(point) }
        eventSink = { _, event in Self.playSound(for: event) }
        observeStore()
        reconcile()
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name,
                       _ action: @escaping @MainActor (RoamCoordinator) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, token))
    }

    private func observeStore() {
        guard let model else { return }
        withObservationTracking {
            _ = model.store.config
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reconcile()
                self?.observeStore()
            }
        }
    }

    private func setLocked(_ value: Bool) {
        locked = value
        requestSnapshot()
        updateVisibility()
    }

    private func screensChanged() {
        for pet in pets.values { pet.screen = screen(id: pet.screen.id) ?? pet.screen }
        requestSnapshot()
    }

    // MARK: Reconcile

    func reconcile() {
        guard let model else { return }
        var wanted: Set<PetKey> = []
        for dock in model.store.docks {
            for item in dock.items {
                guard let widget = item.widget, widget.kind == .pet, widget.isRoaming else { continue }
                let key = PetKey(dock: dock.id, item: item.id)
                wanted.insert(key)
                if let pet = pets[key] {
                    refresh(pet, widget: widget, dock: dock)
                } else {
                    create(key, widget: widget, dock: dock)
                }
            }
        }
        for key in pets.keys where !wanted.contains(key) { remove(key) }
        if pets.isEmpty { removeMonitors() } else if monitors.isEmpty { installMonitors() }
        let sounds = PetSounds.shared
        sounds.enabled = model.store.settings.petSounds && !quiet
        sounds.volume = model.store.settings.petSoundVolume
        updateVisibility()
        kick()
    }

    /// Scanning other apps' controls costs Accessibility round trips, so it runs only while a visible pet
    /// can stand on them; attention feeds only Extra Curious pets.
    private func updateSenses() {
        let shown = pets.values.filter { !$0.hidden }
        let wantElements = shown.contains { $0.walkOnWindows }
        // Accessibility may be granted after the watcher first gave up, so keep offering it the chance.
        if wantElements, scanningElements { elementWatcher.start() }
        let wantAttention = shown.contains { $0.mode == .curious }
        if wantElements != scanningElements {
            scanningElements = wantElements
            if wantElements { elementWatcher.start() } else { elementWatcher.stop(); updateElements([]) }
        }
        if wantAttention != watchingAttention {
            watchingAttention = wantAttention
            if wantAttention { attentionWatcher.start() } else { attentionWatcher.stop(); updateAttention(nil) }
        }
    }

    private static func playSound(for event: RoamEvent) {
        let sounds = PetSounds.shared
        switch event {
        case .landed(let impact): sounds.play(.land, intensity: min(1, impact / 900))
        case .jumped: sounds.play(.hop)
        case .grabbedWall: sounds.play(.grab)
        case .slid: sounds.play(.slide)
        case .climbed: sounds.play(.climb)
        case .startled: sounds.play(.startle)
        case .woke: sounds.play(.sigh)
        case .turned: break
        }
    }

    private func create(_ key: PetKey, widget: WidgetConfig, dock: Dock) {
        guard let model else { return }
        let home = widget.roamHome ?? defaultHome(for: dock)
        let screenForPet = screen(id: home.screenID) ?? Self.screens().first
        guard let screenForPet else { return }
        let pet = RoamPet(key: key, unit: CGFloat(widget.roamSize), screen: screenForPet, home: home)
        pet.state.activity = .falling
        pet.state.preferMenuBar = isNearMenuBar(home.point, screen: screenForPet)
        let driver = pet.driver
        driver.onTouch = { [weak self] in self?.touched(key) }
        driver.onCarry = { [weak self] in self?.beginCarry(key) }
        let host = FirstClickHostingView(rootView: RoamPetRoot(key: key, driver: driver, screenID: screenForPet.id)
            .environment(model))
        host.sizingOptions = []
        pet.panel.contentView = host
        pet.ticker = RoamTicker(view: host) { [weak self, weak pet] in
            if let self, let pet { self.step(pet) }
        }
        pets[key] = pet
        refresh(pet, widget: widget, dock: dock)
    }

    private func refresh(_ pet: RoamPet, widget: WidgetConfig, dock: Dock) {
        pet.mode = RoamBrain.effectiveMode(widget.roamMode, quiet: quiet)
        pet.walkOnWindows = widget.walksOnWindows
        // The window server leaves non-shareable windows out of the Space-switch animation as well as out of
        // recordings, so hiding is opt-in.
        let sharing: NSWindow.SharingType = widget.hidesFromRecordings ? .none : .readOnly
        if pet.panel.sharingType != sharing { pet.panel.sharingType = sharing }
        if let home = widget.roamHome { pet.home = home }
        let unit = CGFloat(widget.roamSize)
        if pet.driver.unit != unit { pet.driver.unit = unit }
        // Energy from Settings › Personality sets the pace; a happy pet with needs on also perks up.
        let energy = model?.store.settings.petEnergy ?? .normal
        pet.driver.lively = energy == .lively
            || (energy == .normal && widget.bool("needs", false)
                && PetStore.current(widget, now: .now).happiness >= PetLogic.happyAtLeast)
        if widget.staysOnOwnScreen, let model, carrying != pet.key {
            let own = model.dockController.controllers(for: dock.id).map(\.screen.id)
            if !own.isEmpty, !own.contains(pet.screen.id) { respawn(pet, dock: dock) }
        }
        rebuildSurfaces(pet)
        present(pet)
    }

    private func remove(_ key: PetKey) {
        guard let pet = pets.removeValue(forKey: key) else { return }
        stopLoop(pet)
        pet.ticker?.invalidate()
        pet.panel.orderOut(nil)
        pet.panel.contentView = nil
        if carrying == key { carrying = nil }
    }

    // MARK: Screens and surfaces

    private static func screens() -> [ConnectedScreen] { DockController.connectedScreens() }

    private func screen(id: String) -> ConnectedScreen? { Self.screens().first { $0.id == id } }

    private func screen(containing point: CGPoint) -> ConnectedScreen? {
        Self.screens().first { $0.geometry.frame.contains(point) }
    }

    private func menuBarHeight(_ screen: ConnectedScreen) -> Double {
        max(0, screen.geometry.frame.maxY - screen.geometry.visibleFrame.maxY)
    }

    private func menuBarY(_ screen: ConnectedScreen) -> Double? {
        let height = menuBarHeight(screen)
        return height > 0 ? screen.geometry.frame.maxY - height : nil
    }

    private func isNearMenuBar(_ point: CGPoint, screen: ConnectedScreen) -> Bool {
        guard let y = menuBarY(screen) else { return false }
        return abs(point.y - y) < 2
    }

    /// Only bars that can be seen: an auto-hidden dock keeps its resting frame, and standing on it
    /// would leave the pet floating where the bar would be.
    private func visibleBars(on screen: ConnectedScreen) -> [CGRect] {
        guard let model else { return [] }
        return model.dockController.windows.values
            .filter { $0.screen.id == screen.id && $0.showsBar }
            .map(\.barFrame)
    }

    private func rebuildSurfaces(_ pet: RoamPet) {
        let frame = pet.screen.geometry.frame
        let onScreen = windows.filter { $0.frame.intersects(frame) }
        pet.bars = visibleBars(on: pet.screen)
        let surfaces = RoamSurfaces.build(screen: frame, menuBarHeight: menuBarHeight(pet.screen), windows: onScreen,
                                          docks: pet.bars, walkOnWindows: pet.walkOnWindows,
                                          elements: elements.filter { $0.intersects(frame) })
        let walls = RoamSurfaces.walls(screen: frame, menuBarHeight: menuBarHeight(pet.screen), windows: onScreen,
                                       walkOnWindows: pet.walkOnWindows)
        let ceilings = RoamSurfaces.ceilings(screen: frame, menuBarHeight: menuBarHeight(pet.screen), windows: onScreen,
                                             walkOnWindows: pet.walkOnWindows, unit: pet.unit)
        // Building routes flies every possible leap, so it only happens when something actually moved.
        if surfaces != pet.surfaces || walls != pet.walls || ceilings != pet.ceilings || pet.nav?.half != pet.unit / 2 {
            pet.surfaces = surfaces
            pet.walls = walls
            pet.ceilings = ceilings
            pet.nav = RoamNav(ledges: surfaces, walls: walls, ceilings: ceilings, half: pet.unit / 2,
                              screenMinX: frame.minX, screenMaxX: frame.maxX)
        }
    }

    private func environment(_ pet: RoamPet) -> RoamEnvironment {
        let frame = pet.screen.geometry.frame
        return RoamEnvironment(surfaces: pet.surfaces, walls: pet.walls, ceilings: pet.ceilings, nav: pet.nav,
                               mode: pet.mode, home: pet.home.point, pointer: NSEvent.mouseLocation,
                               lively: pet.driver.lively, screenMinX: frame.minX, screenMaxX: frame.maxX,
                               screenMinY: frame.minY, screenMaxY: frame.maxY,
                               attention: attention.flatMap { frame.contains($0) ? $0 : nil },
                               elements: elements.filter { $0.intersects(frame) }, unit: pet.unit)
    }

    private func defaultHome(for dock: Dock) -> RoamHome {
        let target = spawnPoint(for: dock, key: nil)
        return RoamHome(point: target.point, screenID: target.screen.id)
    }

    /// Standing on top of the dock's bar, above the pet's own cell when that is known.
    private func spawnPoint(for dock: Dock, key: PetKey?) -> (point: CGPoint, screen: ConnectedScreen) {
        let mouse = NSEvent.mouseLocation
        let controllers = model?.dockController.controllers(for: dock.id) ?? []
        let controller = controllers.first { $0.panelFrame.contains(mouse) } ?? controllers.first
        if let controller, !controller.barFrame.isEmpty {
            let bar = controller.barFrame
            let x = key.flatMap { cells[$0] }.map { min(max($0.x, bar.minX), bar.maxX) } ?? bar.midX
            return (CGPoint(x: x, y: bar.maxY), controller.screen)
        }
        let fallback = Self.screens().first!
        return (CGPoint(x: fallback.geometry.frame.midX, y: fallback.geometry.frame.minY), fallback)
    }

    private func respawn(_ pet: RoamPet, dock: Dock) {
        let target = spawnPoint(for: dock, key: pet.key)
        pet.screen = target.screen
        pet.state.x = target.point.x
        pet.state.y = target.point.y
        pet.state.activity = .falling
        pet.state.vx = 0
        pet.state.vy = 0
        pet.state.wall = nil
        pet.state.ceiling = nil
        pet.state.route = []
        pet.home = RoamHome(point: target.point, screenID: target.screen.id)
    }

    // MARK: Commands

    /// The dock cell reports where it is so a pet that leaves starts out standing above it.
    func noteCell(_ key: PetKey, center: CGPoint) { cells[key] = center }

    func roam(item: DockItem, dock: Dock, mode: RoamMode?) {
        guard let model else { return }
        let key = PetKey(dock: dock.id, item: item.id)
        guard pets[key] == nil else {
            if let mode { setMode(item: item, dock: dock, mode) }
            return
        }
        let target = spawnPoint(for: dock, key: key)
        let fields = WidgetFields(model: model, itemID: item.id, dockID: dock.id)
        var changes: [String: JSONValue?] = [
            "roaming": .bool(true),
            "roamHome": RoamHome(point: target.point, screenID: target.screen.id).json,
        ]
        if let mode { changes["roamMode"] = .string(mode.rawValue) }
        fields.setStates(changes)
        reconcile()
    }

    func bringHome(item: DockItem, dock: Dock) {
        guard let model else { return }
        WidgetFields(model: model, itemID: item.id, dockID: dock.id).setStates(["roaming": .bool(false)])
        reconcile()
    }

    func setMode(item: DockItem, dock: Dock, _ mode: RoamMode) {
        guard let model else { return }
        WidgetFields(model: model, itemID: item.id, dockID: dock.id).setStates(["roamMode": .string(mode.rawValue)])
        reconcile()
    }

    func isRoaming(_ key: PetKey) -> Bool { pets[key] != nil }

    /// Notable controls in other apps' windows, in AppKit coordinates; their tops become ledges.
    func updateElements(_ rects: [CGRect]) {
        guard rects != elements else { return }
        elements = rects
        for pet in pets.values { rebuildSurfaces(pet) }
    }

    /// Every roaming pet that is out and visible, for layers that react to it.
    var petBodies: [RoamBody] {
        pets.values.filter { !$0.hidden }.map { pet in
            let s = pet.state
            let feet = s.wall != nil && s.activity.isOnWall ? CGPoint(x: s.wall!.x, y: s.y) : pet.feet
            let moving = s.activity == .falling || s.activity == .floating
            return RoamBody(key: pet.key, feet: feet, velocity: moving ? CGVector(dx: s.vx, dy: s.vy) : .zero,
                            unit: pet.driver.unit)
        }
    }

    /// Bumps a pet, in points per second. A soft push leaves a standing or clinging pet where it is; a hard
    /// one knocks it loose, and a pet in the air takes all of it.
    func nudge(_ key: PetKey, impulse: CGVector) {
        guard let pet = pets[key], !pet.hidden, !pet.frozen, carrying != key else { return }
        emit(RoamBrain.nudge(&pet.state, impulse: impulse, env: environment(pet)), for: pet)
        schedule(pet)
    }

    /// Where the person's attention is, such as the text cursor; Extra Curious pets head for it.
    func updateAttention(_ point: CGPoint?) { attention = point }

    /// Called from the dock cell's drag: once the pointer leaves the bar, the pet comes along.
    func dockDragMoved(item: DockItem, dock: Dock) {
        guard let model, carrying == nil else { return }
        let key = PetKey(dock: dock.id, item: item.id)
        guard pets[key] == nil else { return }
        let pointer = NSEvent.mouseLocation
        let controllers = model.dockController.controllers(for: dock.id)
        guard !controllers.contains(where: { $0.barFrame.insetBy(dx: -4, dy: -4).contains(pointer) }),
              let screen = screen(containing: pointer) else { return }
        WidgetFields(model: model, itemID: item.id, dockID: dock.id).setStates([
            "roaming": .bool(true),
            "roamHome": RoamHome(point: pointer, screenID: screen.id).json,
        ])
        reconcile()
        beginCarry(key)
    }

    // MARK: Carrying

    private func beginCarry(_ key: PetKey) {
        guard carrying == nil, let pet = pets[key] else { return }
        carrying = key
        pet.state.activity = .carried
        pet.state.wall = nil
        pet.state.ceiling = nil
        pet.state.tumbling = false
        pet.state.spin = 0
        pet.frozen = false
        pet.turn = nil
        pet.state.route = []
        pet.driver.carried = true
        carryTrail = []
        stopLoop(pet)
        pet.panel.ignoresMouseEvents = false
        pet.panel.orderFrontRegardless()
        moveCarried(pet)
    }

    private func moveCarried(_ pet: RoamPet) {
        let pointer = NSEvent.mouseLocation
        if let screen = screen(containing: pointer), screen.id != pet.screen.id, allows(screen, for: pet) {
            pet.screen = screen
            rebuildSurfaces(pet)
        }
        pet.state.x = pointer.x
        pet.state.y = pointer.y - pet.unit * 0.7
        let now = ProcessInfo.processInfo.systemUptime
        carryTrail.append((now, pointer))
        carryTrail.removeAll { now - $0.time > 0.08 }
        present(pet)
    }

    /// The pointer's velocity over its last 80 ms; zero if it paused before letting go.
    private func throwVelocity() -> CGVector {
        let now = ProcessInfo.processInfo.systemUptime
        guard let first = carryTrail.first, let last = carryTrail.last, now - last.time < 0.05,
              last.time - first.time > 0.01 else { return .zero }
        let span = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / span, dy: (last.point.y - first.point.y) / span)
    }

    private func allows(_ screen: ConnectedScreen, for pet: RoamPet) -> Bool {
        guard let model, let dock = model.store.dock(pet.key.dock),
              let widget = dock.items.first(where: { $0.id == pet.key.item })?.widget, widget.staysOnOwnScreen
        else { return true }
        return model.dockController.controllers(for: dock.id).contains { $0.screen.id == screen.id }
    }

    private func endCarry() {
        guard let key = carrying, let pet = pets[key], let model else { return }
        carrying = nil
        pet.driver.carried = false
        let pointer = NSEvent.mouseLocation
        if model.dockController.windows.values.contains(where: { $0.barFrame.insetBy(dx: -6, dy: -6).contains(pointer) }),
           let dock = model.store.dock(key.dock), let item = dock.items.first(where: { $0.id == key.item }) {
            bringHome(item: item, dock: dock)
            return
        }
        let velocity = throwVelocity()
        carryTrail = []
        pet.state.vx = 0
        pet.state.vy = 0
        if let menuY = menuBarY(pet.screen), pet.state.y > menuY - pet.unit,
           hypot(velocity.dx, velocity.dy) < RoamBrain.throwThreshold {
            pet.state.y = menuY
            pet.state.activity = .resting
            pet.state.timeLeft = 1
            pet.state.preferMenuBar = true
        } else {
            pet.state.y = min(RoamSurfaces.escapingTitleZone(x: pet.state.x, y: pet.state.y,
                                                             zone: RoamSurfaces.titleZone(windows)),
                              menuBarY(pet.screen) ?? .infinity)
            pet.state.preferMenuBar = false
            emit(RoamBrain.release(&pet.state, velocity: velocity, env: environment(pet)), for: pet)
        }
        pet.home = RoamHome(point: pet.feet, screenID: pet.screen.id)
        WidgetFields(model: model, itemID: key.item, dockID: key.dock).setStates(["roamHome": pet.home.json])
        pet.driver.moving = true
        schedule(pet)
        kick()
    }

    /// Holds whichever pet the pointer is over while a menu is open on it.
    private func menuTracking(_ open: Bool) {
        menusOpen = max(0, menusOpen + (open ? 1 : -1))
        if open {
            for pet in pets.values where pet.driver.hovering { freeze(pet, true) }
        } else if menusOpen == 0 {
            for pet in pets.values where pet.frozen { freeze(pet, false) }
        }
    }

    private func freeze(_ pet: RoamPet, _ value: Bool) {
        guard pet.frozen != value, carrying != pet.key else { return }
        pet.frozen = value
        if value {
            stopLoop(pet)
        } else {
            pet.lastStep = .now
            pet.lastPresent = .now
            schedule(pet)
        }
    }

    private func touched(_ key: PetKey) {
        guard let pet = pets[key], pet.state.activity != .carried else { return }
        pet.holdUntil = Date.now.addingTimeInterval(3)
        PetSounds.shared.play(.chirp)
        if pet.state.activity == .walking || pet.state.activity == .napping {
            pet.state.activity = .resting
            pet.state.timeLeft = 3
        } else if pet.state.activity == .climbing {
            pet.state.activity = .clinging
            pet.state.timeLeft = 3
        }
        present(pet)
    }

    // MARK: Pointer

    private func installMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.pointerEvent(event) }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in handler(event); return event }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }

    private func pointerEvent(_ event: NSEvent) {
        // Pressing on a pet holds it in place until the button comes up or the press becomes a carry.
        if event.type == .leftMouseDown {
            for pet in pets.values where event.window === pet.panel { freeze(pet, true) }
            return
        }
        if event.type == .leftMouseUp, menusOpen == 0 {
            for pet in pets.values where pet.frozen { freeze(pet, false) }
        }
        if let key = carrying, let pet = pets[key] {
            if event.type == .leftMouseUp {
                endCarry()
            } else {
                moveCarried(pet)
            }
            return
        }
        let pointer = NSEvent.mouseLocation
        let gazeDue = Date.now.timeIntervalSince(lastGazeTick) >= 1.0 / 30
        for pet in pets.values where !pet.hidden {
            updateHover(pet, pointer: pointer)
            let near = hypot(pointer.x - pet.middle.x, pointer.y - pet.middle.y) <= PetLogic.trackingRange
            if gazeDue, near, !pet.state.activity.isMoving { pet.driver.pointerTick += 1 }
        }
        if gazeDue { lastGazeTick = .now }
    }

    private func updateHover(_ pet: RoamPet, pointer: CGPoint) {
        let inside = RoamBrain.hits(point: pointer, middle: pet.shownMiddle ?? pet.middle, unit: pet.unit,
                                    sideways: pet.state.activity.isOnWall && pet.state.wall != nil)
        if pet.panel.ignoresMouseEvents == inside { pet.panel.ignoresMouseEvents = !inside }
        if pet.driver.hovering != inside { pet.driver.hovering = inside }
    }

    // MARK: Visibility

    private func updateVisibility() {
        for pet in pets.values {
            let frame = pet.screen.geometry.frame.insetBy(dx: 1, dy: 1)
            let hide = locked || fullscreen.contains { $0.intersects(frame) }
            guard hide != pet.hidden else { continue }
            pet.hidden = hide
            if hide {
                stopLoop(pet)
                pet.panel.orderOut(nil)
            } else {
                present(pet)
                pet.panel.orderFrontRegardless()
                schedule(pet)
            }
        }
        updateSenses()
    }

    // MARK: Motion

    /// A moving pet steps on every refresh of its display; a still one on a slow beat that only
    /// watches for a reason to move.
    private func schedule(_ pet: RoamPet) {
        guard !pet.hidden, !pet.frozen, carrying != pet.key else { return stopLoop(pet) }
        if RoamBrain.needsFrames(pet.state) || pet.settling {
            pet.beat?.cancel()
            pet.beat = nil
            if pet.ticker?.running != true {
                pet.lastStep = .now
                pet.ticker?.running = true
            }
        } else if pet.beat == nil {
            pet.ticker?.running = false
            pet.beat = Task { [weak self, weak pet] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(RoamBrain.idleInterval(pet?.state.activity ?? .resting)))
                    guard !Task.isCancelled, let pet else { return }
                    self?.step(pet)
                }
            }
        }
    }

    private func stopLoop(_ pet: RoamPet) {
        pet.ticker?.running = false
        pet.beat?.cancel()
        pet.beat = nil
    }

    private func step(_ pet: RoamPet) {
        guard !pet.hidden, !pet.frozen, pet.state.activity != .carried else { return }
        defer { schedule(pet) }
        let now = ContinuousClock.now
        let dt = min((now - pet.lastStep) / .seconds(1), 0.25)
        pet.lastStep = now
        let before = pet.state.activity
        // Being petted pauses it, but nothing stops a fall or a slide halfway.
        if Date.now < pet.holdUntil, pet.state.activity != .falling, pet.state.activity != .sliding {
            present(pet)
            return
        }
        // Docks hide and reveal between window snapshots; the pet should not stand on one that slid away.
        if visibleBars(on: pet.screen) != pet.bars { rebuildSurfaces(pet) }
        let events = RoamBrain.step(&pet.state, dt: dt, env: environment(pet), roll: { Double.random(in: 0..<1) })
        if pet.state.activity == .detaching, before != .detaching {
            // The crouch before it springs off, drawn as a landing squash.
            pet.driver.landImpact = 0.8
            pet.driver.landAt = .now
            pet.driver.landTick += 1
        }
        emit(events, for: pet)
        present(pet)
        if RoamBrain.snapshotInterval(before) != RoamBrain.snapshotInterval(pet.state.activity) { kick() }
    }

    private func emit(_ events: [RoamEvent], for pet: RoamPet) {
        for event in events {
            switch event {
            case .landed(let impact):
                pet.driver.landImpact = min(1, impact / 900)
                pet.driver.landAt = .now
                pet.driver.landTick += 1
            case .startled, .woke:
                pet.driver.startleTick += 1
            case .turned, .jumped, .grabbedWall, .slid, .climbed:
                break
            }
            eventSink?(pet.key, event)
        }
    }

    /// Where and at what angle to draw the pet. A change of surface swings it around the corner over a
    /// moment instead of snapping; other changes of angle, such as a grab or the end of a tumble, ease in.
    private func pose(_ pet: RoamPet) -> CGPoint {
        let now = ContinuousClock.now
        let dt = min((now - pet.lastPresent) / .seconds(1), 0.1)
        pet.lastPresent = now
        let middle = pet.middle
        let target = RoamPose.angle(pet.state)
        let attached = RoamPose.isAttached(pet.state.activity)
        if attached, pet.wasAttached, let shown = pet.shownMiddle, pet.turn == nil,
           abs(RoamPose.delta(from: pet.shownAngle, to: target)) >= 45 {
            pet.turn = RoamTurn(from: shown, to: middle, fromAngle: pet.shownAngle, toAngle: target)
            pet.turnBase = middle
        }
        pet.wasAttached = attached
        var drawn = middle
        if var turn = pet.turn, attached {
            turn.elapsed += dt
            let sample = turn.sample
            drawn = CGPoint(x: sample.middle.x + middle.x - pet.turnBase.x, y: sample.middle.y + middle.y - pet.turnBase.y)
            pet.shownAngle = sample.angle
            pet.turn = turn.isDone ? nil : turn
            if turn.isDone { pet.shownAngle = target }
        } else {
            pet.turn = nil
            pet.shownAngle = RoamPose.settle(pet.shownAngle, toward: target, dt: dt)
        }
        if pet.state.activity == .floating {
            // A slow bob, as if treading water.
            let time = Date.now.timeIntervalSinceReferenceDate
            drawn.y += sin(time * 2 * .pi * 0.7) * pet.unit * 0.08
        }
        pet.shownMiddle = drawn
        return drawn
    }

    private func present(_ pet: RoamPet) {
        let side = pet.driver.side
        let middle = pose(pet)
        // Snapping to whole points made slow walks stutter on Retina screens; snap to pixels instead.
        let scale = pet.panel.backingScaleFactor
        let origin = NSPoint(x: ((middle.x - side / 2) * scale).rounded() / scale,
                             y: ((middle.y - side / 2) * scale).rounded() / scale)
        if pet.panel.frame.size != CGSize(width: side, height: side) {
            pet.panel.setContentSize(CGSize(width: side, height: side))
        }
        if pet.panel.frame.origin != origin { pet.panel.setFrameOrigin(origin) }
        if pet.panel.alphaValue != pet.state.alpha { pet.panel.alphaValue = pet.state.alpha }
        let driver = pet.driver
        let activity = pet.state.activity
        if driver.facing != pet.state.facing { driver.facing = pet.state.facing }
        // Swimming through the air paddles the legs like a slow walk.
        let moving = activity == .walking || activity == .carried || activity == .climbing || activity == .floating
        if driver.moving != moving { driver.moving = moving }
        let speed = activity == .walking || activity == .climbing ? pet.state.speed : activity == .floating ? 40 : 0
        if driver.walkSpeed != speed { driver.walkSpeed = speed }
        if driver.climbing != activity.isOnWall { driver.climbing = activity.isOnWall }
        if driver.angle != pet.shownAngle { driver.angle = pet.shownAngle }
        if driver.sliding != (activity == .sliding) { driver.sliding = activity == .sliding }
        if driver.falling != (activity == .falling) { driver.falling = activity == .falling }
        if driver.sitting != (activity == .sitting) { driver.sitting = activity == .sitting }
        if driver.napping != (activity == .napping) { driver.napping = activity == .napping }
        if !pet.hidden, carrying != pet.key, !pet.frozen { updateHover(pet, pointer: NSEvent.mouseLocation) }
    }

    // MARK: Window snapshots

    private func requestSnapshot() {
        forceSnapshot = true
        startSnapshotLoopIfNeeded()
        kick()
    }

    private func startSnapshotLoopIfNeeded() {
        guard snapshotTask == nil else { return }
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.snapshotInterval()
                if interval == nil, !self.forceSnapshot {
                    await self.waitForWork()
                    continue
                }
                self.forceSnapshot = false
                await self.takeSnapshot()
                try? await Task.sleep(for: .seconds(interval ?? 0.5))
            }
        }
    }

    private func snapshotInterval() -> Double? {
        var intervals = pets.values.filter { !$0.hidden }.compactMap { RoamBrain.snapshotInterval($0.state.activity) }
        if fullscreenSeen != nil { intervals.append(0.3) }
        // A pet hidden for a fullscreen app has to keep looking, or it stays gone until some other app activates.
        if !locked, pets.values.contains(where: \.hidden) { intervals.append(1) }
        return intervals.min()
    }

    /// Mid-swipe between Spaces the window list briefly shows screen-sized windows, so only a fullscreen
    /// window that is still there a moment later hides the pet. Leaving fullscreen shows it at once.
    private func settleFullscreen(_ seen: [CGRect]) {
        fullscreen = fullscreen.filter(seen.contains)
        let added = seen.filter { !fullscreen.contains($0) }
        guard !added.isEmpty else {
            fullscreenSeen = nil
            return
        }
        if let pending = fullscreenSeen, pending.screens == added {
            guard Date.now.timeIntervalSince(pending.since) >= 0.6 else { return }
            fullscreen += added
            fullscreenSeen = nil
        } else {
            fullscreenSeen = (added, .now)
        }
    }

    private func takeSnapshot() async {
        let front = NSWorkspace.shared.frontmostApplication
        let own = ProcessInfo.processInfo.processIdentifier
        let frontPID = front?.processIdentifier == own ? nil : front?.processIdentifier
        let frames = NSScreen.screens.map(\.frame)
        let regular = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .map(\.processIdentifier))
        let result = await Task.detached(priority: .utility) {
            RoamSnapshot.take(frontPID: frontPID, ownPID: own, regularPIDs: regular, screens: frames)
        }.value
        windows = result.windows
        settleFullscreen(result.fullscreen)
        for pet in pets.values { rebuildSurfaces(pet) }
        updateVisibility()
    }

    private func waitForWork() async {
        await withCheckedContinuation { gate = $0 }
    }

    private func kick() {
        if !pets.isEmpty { startSnapshotLoopIfNeeded() }
        gate?.resume()
        gate = nil
    }
}

/// The roaming window's content: the same pet view the dock uses, fed live from the store.
struct RoamPetRoot: View {
    @Environment(AppModel.self) private var model
    let key: PetKey
    let driver: RoamDriver
    let screenID: String

    var body: some View {
        if let dock = model.store.dock(key.dock), let item = dock.items.first(where: { $0.id == key.item }),
           let widget = item.widget {
            PetWidget(item: item, widget: widget, dock: dock, size: CGSize(width: driver.side, height: driver.side),
                      state: DockViewState(dockID: dock.id, screenID: screenID), roam: driver)
                // The whole pet turns so its feet press against its wall or ceiling; the coordinator eases it.
                .rotationEffect(.degrees(driver.angle))
        }
    }
}
