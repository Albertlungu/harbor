import AppKit
import HarborCore

/// Whoever owns the roaming pets shows them to the weather and takes its requests for small hops.
@MainActor
protocol WeatherPetSource: AnyObject {
    /// Every visible roaming pet: an id, its feet in global AppKit coordinates and its size.
    var weatherPets: [(id: String, feet: CGPoint, unit: Double)] { get }
    /// A small playful hop; `impulse.dx` says which way, `impulse.dy` how hard.
    func weatherNudge(_ id: String, impulse: CGVector)
}

/// Covers one screen, above normal windows so snow can sit on their top edges. Click-through except while
/// the pointer is over something to play with.
final class WeatherPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Just above normal windows: under floating palettes, menus, the menu bar and the docks.
        level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosts the Metal layer and forwards presses on piles, balls and bubbles to the controller.
final class WeatherView: NSView {
    var onMouse: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouse?(event) }
    override func mouseDragged(with event: NSEvent) { onMouse?(event) }
    override func mouseUp(with event: NSEvent) { onMouse?(event) }
}

/// The weather on one connected screen.
@MainActor
private final class WeatherScreen {
    var screen: ConnectedScreen
    let panel: WeatherPanel
    let view = WeatherView()
    let renderer: WeatherRenderer
    var world: WeatherWorld
    var hidden = true
    var sprites: [WeatherSprite] = []

    init?(screen: ConnectedScreen, settings: WeatherSettings, season: Season, evening: Bool) {
        guard let renderer = WeatherRenderer() else { return nil }
        self.screen = screen
        self.renderer = renderer
        let frame = screen.geometry.frame
        panel = WeatherPanel(frame: frame)
        world = WeatherWorld(width: frame.width, height: frame.height, season: season, intensity: settings.intensity,
                             accumulation: settings.accumulation, interactions: settings.interactions, evening: evening,
                             seed: UInt64.random(in: 1...UInt64.max))
        view.wantsLayer = true
        view.layer = renderer.layer
        view.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = view
        resize()
    }

    var origin: CGPoint { screen.geometry.frame.origin }

    func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - origin.x, y: point.y - origin.y) }

    func resize() {
        let frame = screen.geometry.frame
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        world.width = frame.width
        world.height = frame.height
        let scale = NSScreen.screens.first { $0.frame == frame }?.backingScaleFactor ?? 2
        renderer.resize(points: frame.size, scale: scale)
    }

    func render() {
        sprites.removeAll(keepingCapacity: true)
        world.pileSprites(into: &sprites)
        world.liveSprites(into: &sprites)
        renderer.draw(sprites, viewport: screen.geometry.frame.size)
    }
}

/// Runs Settings › Seasons: one overlay per screen, one clock for all of them, and the window readings that
/// tell the weather where the ledges are.
@MainActor
final class WeatherController {
    static let shared = WeatherController()

    /// Set by whoever owns the roaming pets.
    weak var petSource: WeatherPetSource?

    private var model: AppModel?
    private var screens: [String: WeatherScreen] = [:]
    private var timer: Timer?
    private var fast = false
    private var lastTick = ContinuousClock.now
    private var locked = false
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var fullscreen: [CGRect] = []
    private var snapshotting = false
    private var lastSnapshot = ContinuousClock.now - .seconds(10)
    private var quietSnapshot = false
    private var monitors: [Any] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var pointer = CGPoint.zero
    private var pointerVelocity = CGVector.zero
    private var pointerTime = ContinuousClock.now
    private var holding: String?
    private var petFeet: [String: CGPoint] = [:]
    private var lastSeasonCheck = Date.distantPast

    private let environment = ProcessInfo.processInfo.environment
    /// HARBOR_WEATHER_SPEED runs simulated time faster, a development aid for watching piles build.
    private lazy var speed = environment["HARBOR_WEATHER_SPEED"].flatMap(Double.init).map { min(max($0, 0.1), 60) } ?? 1

    private var settings: WeatherSettings { model?.store.settings.weather ?? WeatherSettings() }

    // MARK: Lifecycle

    func start(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        watch(nc, NSApplication.didChangeScreenParametersNotification) { $0.reconcile() }
        watch(nc, Notification.Name.NSProcessInfoPowerStateDidChange) {
            $0.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            $0.updateVisibility()
        }
        watch(ws, NSWorkspace.activeSpaceDidChangeNotification) {
            // A Space switch takes the windows out of sight; their snow should not fall off them.
            $0.quietSnapshot = true
            $0.snapshot()
        }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification] {
            watch(ws, name) { $0.snapshot() }
        }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true; $0.updateVisibility() }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false; $0.updateVisibility() }
        observeSettings()
        reconcile()
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name,
                       _ action: @escaping @MainActor (WeatherController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, token))
    }

    private func observeSettings() {
        guard let model else { return }
        withObservationTracking {
            _ = model.store.settings.weather
            _ = model.store.settings.hideFromScreenSharing
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reconcile()
                self?.observeSettings()
            }
        }
    }

    /// Drops every pile, ball and particle, as the menu's "Clear" does.
    func clear() {
        for screen in screens.values {
            let season = screen.world.season
            screen.world = WeatherWorld(width: screen.world.width, height: screen.world.height, season: season,
                                        intensity: settings.intensity, accumulation: settings.accumulation,
                                        interactions: settings.interactions, evening: screen.world.evening,
                                        seed: UInt64.random(in: 1...UInt64.max))
        }
        snapshot()
    }

    // MARK: Screens

    private func currentSeason() -> (season: Season, evening: Bool) {
        let now = Date.now
        let hour = environment["HARBOR_WEATHER_HOUR"].flatMap(Int.init) ?? Calendar.current.component(.hour, from: now)
        return (settings.season(at: now), Season.isEvening(hour: hour))
    }

    private func reconcile() {
        let settings = settings
        guard settings.enabled, model != nil else {
            for key in screens.keys { remove(key) }
            stopClock()
            removeMonitors()
            return
        }
        let connected = DockController.connectedScreens()
        let now = currentSeason()
        for screen in connected {
            if let existing = screens[screen.id] {
                existing.screen = screen
                existing.resize()
            } else if let created = WeatherScreen(screen: screen, settings: settings, season: now.season,
                                                  evening: now.evening) {
                created.view.onMouse = { [weak self, weak created] event in
                    guard let created else { return }
                    self?.mouse(event, on: created)
                }
                screens[screen.id] = created
            }
        }
        for key in screens.keys where !connected.contains(where: { $0.id == key }) { remove(key) }
        let sharing: NSWindow.SharingType = model?.store.settings.hideFromScreenSharing == true ? .none : .readOnly
        for screen in screens.values {
            screen.world.season = now.season
            screen.world.evening = now.evening
            screen.world.intensity = settings.intensity
            screen.world.accumulation = settings.accumulation
            screen.world.interactions = settings.interactions
            if screen.panel.sharingType != sharing { screen.panel.sharingType = sharing }
        }
        if monitors.isEmpty { installMonitors() }
        updateVisibility()
        snapshot()
    }

    private func remove(_ key: String) {
        guard let screen = screens.removeValue(forKey: key) else { return }
        screen.panel.orderOut(nil)
        screen.panel.contentView = nil
    }

    private func updateVisibility() {
        for screen in screens.values {
            let frame = screen.screen.geometry.frame.insetBy(dx: 1, dy: 1)
            let hide = locked || lowPower || fullscreen.contains { $0.intersects(frame) }
            guard hide != screen.hidden else { continue }
            screen.hidden = hide
            if hide {
                screen.panel.orderOut(nil)
            } else {
                screen.panel.orderFrontRegardless()
            }
        }
        if screens.values.contains(where: { !$0.hidden }) { setClock(fast: true) } else { stopClock() }
    }

    // MARK: Clock

    private func setClock(fast wanted: Bool) {
        guard timer == nil || fast != wanted else { return }
        timer?.invalidate()
        fast = wanted
        lastTick = .now
        let interval = wanted ? 1.0 / 30 : 1.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = wanted ? 0.004 : 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopClock() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = ContinuousClock.now
        let elapsed = min((now - lastTick) / .seconds(1), 1.5) * speed
        lastTick = now
        if Date.now.timeIntervalSince(lastSeasonCheck) > 60 {
            lastSeasonCheck = .now
            let current = currentSeason()
            for screen in screens.values {
                screen.world.season = current.season
                screen.world.evening = current.evening
            }
        }
        let pets = petBodies(dt: elapsed / speed)
        var still = true
        for screen in screens.values where !screen.hidden {
            let local = localPets(pets, on: screen)
            var left = elapsed
            while left > 0 {
                let dt = min(left, 1.0 / 30)
                left -= dt
                handle(screen.world.step(dt: dt, pets: local), on: screen)
            }
            screen.render()
            if !screen.world.isStill || holding == screen.screen.id || !local.isEmpty { still = false }
        }
        let interval = still ? 1.0 : 0.25
        if (now - lastSnapshot) / .seconds(1) >= interval { snapshot() }
        setClock(fast: !still)
    }

    // MARK: Pets

    private struct PetBody {
        var id: String
        var feet: CGPoint
        var velocity: CGVector
        var unit: Double
    }

    private func petBodies(dt: Double) -> [PetBody] {
        guard let petSource else { return [] }
        var bodies: [PetBody] = []
        var seen: [String: CGPoint] = [:]
        for pet in petSource.weatherPets {
            let before = petFeet[pet.id] ?? pet.feet
            let velocity = dt > 0 ? CGVector(dx: (pet.feet.x - before.x) / dt, dy: (pet.feet.y - before.y) / dt) : .zero
            bodies.append(PetBody(id: pet.id, feet: pet.feet, velocity: velocity, unit: pet.unit))
            seen[pet.id] = pet.feet
        }
        petFeet = seen
        return bodies
    }

    private func localPets(_ pets: [PetBody], on screen: WeatherScreen) -> [WeatherPet] {
        let frame = screen.screen.geometry.frame
        return pets.filter { frame.contains($0.feet) }.map {
            let p = screen.local($0.feet)
            return WeatherPet(id: $0.id, x: p.x, y: p.y, vx: $0.velocity.dx, vy: $0.velocity.dy, unit: $0.unit)
        }
    }

    private func handle(_ events: [WeatherEvent], on screen: WeatherScreen) {
        for event in events {
            switch event {
            case .nudge(let pet, let dx, let dy):
                petSource?.weatherNudge(pet, impulse: CGVector(dx: dx, dy: dy))
            case .popped:
                play("Pop")
            case .splat:
                play("Blow")
            case .snowman:
                play("Glass")
            }
        }
    }

    private func play(_ name: String) {
        guard settings.sounds, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.3
        sound.play()
    }

    // MARK: Window readings

    private func snapshot() {
        lastSnapshot = .now
        guard !snapshotting, let model, !screens.isEmpty else { return }
        snapshotting = true
        let front = NSWorkspace.shared.frontmostApplication
        let own = ProcessInfo.processInfo.processIdentifier
        let frontPID = front?.processIdentifier == own ? nil : front?.processIdentifier
        let frames = NSScreen.screens.map(\.frame)
        let bars = model.dockController.windows.values.map { (screen: $0.screen.id, bar: $0.barFrame) }
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                RoamSnapshot.take(frontPID: frontPID, ownPID: own, screens: frames)
            }.value
            self?.apply(result, bars: bars)
        }
    }

    private func apply(_ result: RoamSnapshot.Result, bars: [(screen: String, bar: CGRect)]) {
        snapshotting = false
        let quietly = quietSnapshot
        quietSnapshot = false
        fullscreen = result.fullscreen
        // The focused window gets no title-bar exclusion here: snow may sit on any window's top edge.
        let windows = result.windows.map { RoamWindow(frame: $0.frame) }
        for screen in screens.values {
            let frame = screen.screen.geometry.frame
            let menuBar = max(0, frame.maxY - screen.screen.geometry.visibleFrame.maxY)
            let docks = bars.filter { $0.screen == screen.screen.id && !$0.bar.isEmpty }.map(\.bar)
            let surfaces = RoamSurfaces.build(screen: frame, menuBarHeight: menuBar,
                                              windows: windows.filter { $0.frame.intersects(frame) }, docks: docks,
                                              walkOnWindows: true)
            let origin = frame.origin
            let local = surfaces.map {
                RoamSurface(kind: $0.kind, y: $0.y - origin.y, minX: $0.minX - origin.x, maxX: $0.maxX - origin.x)
            }
            screen.world.setSurfaces(local, quietly: quietly)
        }
        updateVisibility()
    }

    // MARK: Pointer

    private func installMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in handler(event); return event }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        let now = ContinuousClock.now
        let dt = (now - pointerTime) / .seconds(1)
        if dt > 0.004 {
            let raw = CGVector(dx: (location.x - pointer.x) / dt, dy: (location.y - pointer.y) / dt)
            // Smoothed so a throw follows the flick rather than its last jittery sample.
            let keep = dt > 0.1 ? 0.0 : 0.5
            pointerVelocity = CGVector(dx: pointerVelocity.dx * keep + raw.dx * (1 - keep),
                                       dy: pointerVelocity.dy * keep + raw.dy * (1 - keep))
            pointer = location
            pointerTime = now
        }
        for screen in screens.values where !screen.hidden {
            guard screen.screen.geometry.frame.contains(location) else {
                screen.world.pointerLeft()
                if holding != screen.screen.id, !screen.panel.ignoresMouseEvents { screen.panel.ignoresMouseEvents = true }
                continue
            }
            let p = screen.local(location)
            screen.world.pointerMoved(x: p.x, y: p.y, vx: pointerVelocity.dx, vy: pointerVelocity.dy)
            if holding == nil {
                let hit = screen.world.hitTest(x: p.x, y: p.y)
                if screen.panel.ignoresMouseEvents == hit { screen.panel.ignoresMouseEvents = !hit }
            }
            if !fast, hypot(pointerVelocity.dx, pointerVelocity.dy) > 300 { setClock(fast: true) }
        }
    }

    private func mouse(_ event: NSEvent, on screen: WeatherScreen) {
        let p = screen.local(NSEvent.mouseLocation)
        switch event.type {
        case .leftMouseDown:
            if screen.world.pointerDown(x: p.x, y: p.y), screen.world.isHolding { holding = screen.screen.id }
            setClock(fast: true)
        case .leftMouseDragged:
            pointerMoved()
            screen.world.pointerDragged(x: p.x, y: p.y)
        case .leftMouseUp:
            screen.world.pointerUp(vx: pointerVelocity.dx, vy: pointerVelocity.dy)
            holding = nil
            let hit = screen.world.hitTest(x: p.x, y: p.y)
            screen.panel.ignoresMouseEvents = !hit
        default:
            break
        }
    }
}
