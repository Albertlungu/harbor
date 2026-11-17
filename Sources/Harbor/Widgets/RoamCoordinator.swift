import AppKit
import HarborCore
import SwiftUI

struct PetKey: Hashable {
    let dock: UUID
    let item: UUID
}

/// Transparent and click-through except over the pet itself, and invisible to screen sharing.
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
        sharingType = .none
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
    var bars: [CGRect] = []
    var walkOnWindows = true
    var hidden = true
    var ticker: RoamTicker?
    var beat: Task<Void, Never>?
    var lastStep = ContinuousClock.now
    var holdUntil = Date.distantPast

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
    private var lastGazeTick = Date.distantPast

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
        updateVisibility()
        kick()
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
        pet.bars = visibleBars(on: pet.screen)
        pet.surfaces = RoamSurfaces.build(screen: frame, menuBarHeight: menuBarHeight(pet.screen),
                                          windows: windows.filter { $0.frame.intersects(frame) }, docks: pet.bars,
                                          walkOnWindows: pet.walkOnWindows)
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
        pet.state.fallSpeed = 0
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
        pet.driver.carried = true
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
        present(pet)
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
        pet.state.fallSpeed = 0
        pet.state.facing = 1
        if let menuY = menuBarY(pet.screen), pet.state.y > menuY - pet.unit {
            pet.state.y = menuY
            pet.state.activity = .resting
            pet.state.timeLeft = 1
            pet.state.preferMenuBar = true
        } else {
            pet.state.y = RoamSurfaces.escapingTitleZone(x: pet.state.x, y: pet.state.y,
                                                         zone: RoamSurfaces.titleZone(windows))
            pet.state.activity = .falling
            pet.state.preferMenuBar = false
        }
        pet.home = RoamHome(point: pet.feet, screenID: pet.screen.id)
        WidgetFields(model: model, itemID: key.item, dockID: key.dock).setStates(["roamHome": pet.home.json])
        pet.driver.moving = true
        schedule(pet)
        kick()
    }

    private func touched(_ key: PetKey) {
        guard let pet = pets[key], pet.state.activity != .carried else { return }
        pet.holdUntil = Date.now.addingTimeInterval(3)
        if pet.state.activity == .walking || pet.state.activity == .napping {
            pet.state.activity = .resting
            pet.state.timeLeft = 3
        }
        present(pet)
    }

    // MARK: Pointer

    private func installMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.pointerEvent(event) }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
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
            let near = hypot(pointer.x - pet.state.x, pointer.y - pet.state.y) <= PetLogic.trackingRange
            if gazeDue, near, !pet.state.activity.isMoving { pet.driver.pointerTick += 1 }
        }
        if gazeDue { lastGazeTick = .now }
    }

    private func updateHover(_ pet: RoamPet, pointer: CGPoint) {
        let inside = RoamBrain.hits(point: pointer, feet: pet.feet, unit: pet.unit)
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
    }

    // MARK: Motion

    /// A moving pet steps on every refresh of its display; a still one on a slow beat that only
    /// watches for a reason to move.
    private func schedule(_ pet: RoamPet) {
        guard !pet.hidden, carrying != pet.key else { return stopLoop(pet) }
        if pet.state.activity.isMoving {
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
        guard !pet.hidden, pet.state.activity != .carried else { return }
        defer { schedule(pet) }
        let now = ContinuousClock.now
        let dt = min((now - pet.lastStep) / .seconds(1), 0.25)
        pet.lastStep = now
        let before = pet.state.activity
        if Date.now < pet.holdUntil, pet.state.activity != .falling { present(pet); return }
        // Docks hide and reveal between window snapshots; the pet should not stand on one that slid away.
        if visibleBars(on: pet.screen) != pet.bars { rebuildSurfaces(pet) }
        let env = RoamEnvironment(surfaces: pet.surfaces, mode: pet.mode, home: pet.home.point,
                                  pointer: NSEvent.mouseLocation, lively: pet.driver.lively,
                                  screenMinX: pet.screen.geometry.frame.minX, screenMaxX: pet.screen.geometry.frame.maxX)
        let events = RoamBrain.step(&pet.state, dt: dt, env: env, roll: { Double.random(in: 0..<1) })
        for event in events {
            switch event {
            case .landed(let impact):
                pet.driver.landImpact = min(1, impact / 900)
                pet.driver.landAt = .now
                pet.driver.landTick += 1
            case .startled, .woke:
                pet.driver.startleTick += 1
            case .turned:
                break
            }
        }
        present(pet)
        if RoamBrain.snapshotInterval(before) != RoamBrain.snapshotInterval(pet.state.activity) { kick() }
    }

    private func present(_ pet: RoamPet) {
        let side = pet.driver.side
        let margin = (side - pet.driver.unit) / 2
        // Snapping to whole points made slow walks stutter on Retina screens; snap to pixels instead.
        let scale = pet.panel.backingScaleFactor
        let origin = NSPoint(x: ((pet.state.x - side / 2) * scale).rounded() / scale,
                             y: ((pet.state.y - margin) * scale).rounded() / scale)
        if pet.panel.frame.size != CGSize(width: side, height: side) {
            pet.panel.setContentSize(CGSize(width: side, height: side))
        }
        if pet.panel.frame.origin != origin { pet.panel.setFrameOrigin(origin) }
        if pet.panel.alphaValue != pet.state.alpha { pet.panel.alphaValue = pet.state.alpha }
        let driver = pet.driver
        let activity = pet.state.activity
        if driver.facing != pet.state.facing { driver.facing = pet.state.facing }
        if driver.moving != (activity == .walking || activity == .carried) {
            driver.moving = activity == .walking || activity == .carried
        }
        if driver.falling != (activity == .falling) { driver.falling = activity == .falling }
        if driver.sitting != (activity == .sitting) { driver.sitting = activity == .sitting }
        if driver.napping != (activity == .napping) { driver.napping = activity == .napping }
        if !pet.hidden, carrying != pet.key { updateHover(pet, pointer: NSEvent.mouseLocation) }
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
        }
    }
}
