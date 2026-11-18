import AppKit
import HarborCore

/// Whoever owns the roaming pets shows them to the weather and takes its requests for small hops.
@MainActor
protocol WeatherPetSource: AnyObject {
    /// Every visible roaming pet: an id, its feet in global AppKit coordinates and its size.
    var weatherPets: [(id: String, feet: CGPoint, unit: Double)] { get }
    /// A small playful hop; `impulse.dx` says which way, `impulse.dy` how hard.
    func weatherNudge(_ id: String, impulse: CGVector)
    /// How keen a pet is to play right now: 0 while quiet, asleep, held or in the air.
    func weatherPlayfulness(_ id: String) -> Double
    /// A walk along the ledge the pet stands on, to `x` in global AppKit coordinates.
    func weatherWalk(_ id: String, toX x: Double)
    /// How the pet looks for the next `seconds` while it plays; `ball` is a held snowball's radius.
    func weatherPose(_ id: String, pose: WeatherPetPose, seconds: Double, ball: Double)
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

/// A thread with its own run loop, where the display links fire and the weather is stepped and drawn, so a
/// busy main thread can't make the weather stutter and the weather can't hold up the main thread.
private final class WeatherThread: Thread, @unchecked Sendable {
    private var loop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        name = "Harbor weather"
        qualityOfService = .userInteractive
    }

    func launch() {
        start()
        ready.wait()
    }

    override func main() {
        loop = CFRunLoopGetCurrent()
        // A port keeps the run loop waiting while no display link is attached.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
    }

    func perform(_ block: @escaping @Sendable () -> Void) {
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }
}

/// What one screen's frame tells the main thread.
private struct WeatherReport: Sendable {
    var events: [WeatherEvent]
    var still: Bool
    var playing: Bool
}

/// The part of one screen's weather that the weather thread steps and draws. `lock` guards the world and
/// whatever the main thread hands over; the rest belongs to the weather thread.
private final class WeatherStage: NSObject, @unchecked Sendable {
    let renderer = WeatherRenderer()
    /// Set on the main thread before the link is attached, then used only on the weather thread.
    var link: CADisplayLink?
    private let report: @Sendable (WeatherReport) -> Void
    private let speed: Double

    private let lock = NSLock()
    private var world: WeatherWorld
    private var pets: [WeatherPet] = []
    private var hidden = true

    // Weather thread only.
    private var lastFrame: CFTimeInterval = 0
    private var sprites: [WeatherSprite] = []

    init(world: WeatherWorld, speed: Double, report: @escaping @Sendable (WeatherReport) -> Void) {
        self.world = world
        self.speed = speed
        self.report = report
    }

    func with<T>(_ body: (inout WeatherWorld) -> T) -> T { lock.withLock { body(&world) } }

    func setPets(_ next: [WeatherPet]) { lock.withLock { pets = next } }

    func setHidden(_ next: Bool) { lock.withLock { hidden = next } }

    /// Weather thread: how often the display link fires, or not at all while still or hidden.
    func pace(_ rate: Double?) {
        guard let link else { return }
        if let rate {
            let r = Float(rate)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: r, maximum: r, preferred: r)
        }
        let hidden = lock.withLock { self.hidden }
        link.isPaused = rate == nil || hidden
        // Shown again later, the world picks up where it was rather than jumping ahead.
        if hidden { lastFrame = 0 }
    }

    @objc func tick(_ link: CADisplayLink) { frame(at: link.targetTimestamp) }

    /// Weather thread: steps the world to `now` and draws it. Display-link frames step by the time between
    /// vsyncs rather than by when the callback happened to run, so motion stays even.
    func frame(at now: CFTimeInterval) {
        let elapsed = lastFrame == 0 ? 1.0 / 30 : min(max(now - lastFrame, 0), 1.5)
        lastFrame = now
        sprites.removeAll(keepingCapacity: true)
        var events: [WeatherEvent] = []
        var still = true, playing = false
        let shown: Bool = lock.withLock {
            guard !hidden else { return false }
            // A still world can catch up a whole beat at once, but anything in the air has to be seen moving:
            // snow tipped off a closed window would otherwise fall and land between two frames.
            var left = (world.isStill ? elapsed : min(elapsed, 0.1)) * speed
            while left > 0 {
                let dt = min(left, 1.0 / 30)
                left -= dt
                events += world.step(dt: dt, pets: pets)
            }
            world.pileSprites(into: &sprites)
            world.liveSprites(into: &sprites)
            still = world.isStill && pets.isEmpty
            playing = world.isPlaying
            return true
        }
        guard shown else {
            lastFrame = 0
            return
        }
        renderer.draw(sprites)
        report(WeatherReport(events: events, still: still, playing: playing))
    }
}

/// The weather on one connected screen.
@MainActor
private final class WeatherScreen {
    var screen: ConnectedScreen
    let panel: WeatherPanel
    let view = WeatherView()
    let stage: WeatherStage
    var hidden = true
    var still = true
    var playing = false

    init?(screen: ConnectedScreen, settings: WeatherSettings, season: Season, evening: Bool, speed: Double,
          report: @escaping @Sendable (WeatherReport) -> Void) {
        guard WeatherRenderer.device != nil else { return nil }
        self.screen = screen
        let frame = screen.geometry.frame
        panel = WeatherPanel(frame: frame)
        let world = WeatherWorld(width: frame.width, height: frame.height, season: season,
                                 intensity: settings.intensity, accumulation: settings.accumulation,
                                 interactions: settings.interactions, evening: evening,
                                 seed: UInt64.random(in: 1...UInt64.max))
        stage = WeatherStage(world: world, speed: speed, report: report)
        view.layer = stage.renderer.layer
        view.wantsLayer = true
        view.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = view
        resize()
        stage.link = view.displayLink(target: stage, selector: #selector(WeatherStage.tick(_:)))
    }

    var origin: CGPoint { screen.geometry.frame.origin }

    func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - origin.x, y: point.y - origin.y) }

    func resize() {
        let frame = screen.geometry.frame
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        stage.with {
            $0.width = frame.width
            $0.height = frame.height
        }
        let scale = NSScreen.screens.first { $0.frame == frame }?.backingScaleFactor ?? 2
        stage.renderer.resize(points: frame.size, scale: scale)
    }
}

/// Runs Settings › Seasons: one overlay per screen, each paced by its display on the weather thread, and the
/// window readings that tell the weather where the ledges are.
@MainActor
final class WeatherController {
    static let shared = WeatherController()

    /// Set by whoever owns the roaming pets.
    weak var petSource: WeatherPetSource?

    private var model: AppModel?
    private var screens: [String: WeatherScreen] = [:]
    /// Started with the first overlay, so a Harbor with the weather off never runs it.
    private lazy var thread: WeatherThread = {
        let thread = WeatherThread()
        thread.launch()
        return thread
    }()
    private var pace: Pace?
    /// The slow beat that stands in for the display links while nothing moves.
    private var beat: Timer?
    /// When the pointer last moved fast enough to blow the weather about.
    private var lastGust = ContinuousClock.now - .seconds(10)
    /// When a left-button drag was last seen anywhere, which is how windows usually get moved.
    private var lastDrag = ContinuousClock.now - .seconds(10)
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
    private var lastPets = ContinuousClock.now
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
        if environment["HARBOR_WEATHER_SCRIPT"] != nil { runScript() }
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
        for screen in screens.values { reset(screen) }
        snapshot()
    }

    private func reset(_ screen: WeatherScreen) {
        let settings = settings
        screen.stage.with {
            $0 = WeatherWorld(width: $0.width, height: $0.height, season: $0.season, intensity: settings.intensity,
                              accumulation: settings.accumulation, interactions: settings.interactions,
                              evening: $0.evening, seed: UInt64.random(in: 1...UInt64.max))
        }
        // Drawn now rather than on the next beat, which can be a second away while the weather is still.
        let stage = screen.stage
        thread.perform { stage.frame(at: CACurrentMediaTime()) }
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
                                                  evening: now.evening, speed: speed, report: report(screen.id)) {
                created.view.onMouse = { [weak self, weak created] event in
                    guard let created else { return }
                    self?.mouse(event, on: created)
                }
                screens[screen.id] = created
                let stage = created.stage
                thread.perform {
                    stage.link?.add(to: .current, forMode: .default)
                    stage.pace(nil)
                }
            }
        }
        for key in screens.keys where !connected.contains(where: { $0.id == key }) { remove(key) }
        let sharing: NSWindow.SharingType = model?.store.settings.hideFromScreenSharing == true ? .none : .readOnly
        for screen in screens.values {
            screen.stage.with {
                $0.season = now.season
                $0.evening = now.evening
                $0.intensity = settings.intensity
                $0.accumulation = settings.accumulation
                $0.interactions = settings.interactions
            }
            if screen.panel.sharingType != sharing { screen.panel.sharingType = sharing }
        }
        if monitors.isEmpty { installMonitors() }
        updateVisibility()
        snapshot()
    }

    private func remove(_ key: String) {
        guard let screen = screens.removeValue(forKey: key) else { return }
        screen.stage.setHidden(true)
        let stage = screen.stage
        thread.perform {
            stage.link?.invalidate()
            stage.link = nil
        }
        screen.panel.orderOut(nil)
        screen.panel.contentView = nil
    }

    private func updateVisibility() {
        var appeared = false
        for screen in screens.values {
            let frame = screen.screen.geometry.frame.insetBy(dx: 1, dy: 1)
            let hide = locked || lowPower || fullscreen.contains { $0.intersects(frame) }
            guard hide != screen.hidden else { continue }
            screen.hidden = hide
            screen.stage.setHidden(hide)
            if hide {
                let stage = screen.stage
                thread.perform { stage.pace(nil) }
                screen.panel.orderOut(nil)
                // A fullscreen app starts clean: nothing waits to pile back in when the desktop returns.
                if fullscreen.contains(where: { $0.intersects(frame) }) { reset(screen) }
            } else {
                screen.panel.orderFrontRegardless()
                appeared = true
            }
        }
        if screens.values.contains(where: { !$0.hidden }) {
            // A screen just shown needs its link running even if the pace hasn't changed.
            if appeared { pace = nil }
            if pace == nil { setClock(.drift) }
        } else {
            stopClock()
        }
    }

    // MARK: Clock

    /// Frames a second: brisk while a ball or bubble is in hand or in flight, steady for weather that drifts,
    /// and a slow beat when nothing moves at all. Every frame makes the window server recomposite the screen,
    /// so the brisk rate is kept to direct play; the rates divide common refresh rates so frames land evenly.
    private enum Pace: Double {
        case play = 60, drift = 30, still = 1
    }

    private func setClock(_ wanted: Pace) {
        guard pace != wanted else { return }
        pace = wanted
        let rate: Double? = wanted == .still ? nil : wanted.rawValue
        for stage in screens.values.map(\.stage) { thread.perform { stage.pace(rate) } }
        beat?.invalidate()
        beat = nil
        guard wanted == .still else { return }
        let beat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.still() }
        }
        beat.tolerance = 0.2
        RunLoop.main.add(beat, forMode: .common)
        self.beat = beat
    }

    private func stopClock() {
        pace = nil
        beat?.invalidate()
        beat = nil
        for stage in screens.values.map(\.stage) { thread.perform { stage.pace(nil) } }
    }

    /// One frame on every shown screen while the display links rest.
    private func still() {
        for screen in screens.values where !screen.hidden {
            let stage = screen.stage
            thread.perform { stage.frame(at: CACurrentMediaTime()) }
        }
    }

    /// Hands a screen's frame reports to the main thread.
    private func report(_ id: String) -> @Sendable (WeatherReport) -> Void {
        { report in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { WeatherController.shared.frameDone(report, on: id) }
            }
        }
    }

    /// After each screen's frame: plays its events, hands the pets over and settles the pace and readings.
    private func frameDone(_ report: WeatherReport, on id: String) {
        guard let screen = screens[id] else { return }
        handle(report.events, on: screen)
        screen.still = report.still
        screen.playing = report.playing
        let now = ContinuousClock.now
        if Date.now.timeIntervalSince(lastSeasonCheck) > 60 {
            lastSeasonCheck = .now
            let current = currentSeason()
            for screen in screens.values {
                screen.stage.with {
                    $0.season = current.season
                    $0.evening = current.evening
                }
            }
        }
        // Several screens report each frame; the pets only need handing over once. A screen with pets on it
        // reports itself busy, which keeps the pace up while they walk.
        let sincePets = (now - lastPets) / .seconds(1)
        if sincePets > 0.01 {
            lastPets = now
            let pets = petBodies(dt: sincePets)
            for screen in screens.values { screen.stage.setPets(localPets(pets, on: screen)) }
        }
        let shown = screens.values.filter { !$0.hidden }
        let still = (now - lastDrag) / .seconds(1) > 0.5 && (now - lastGust) / .seconds(1) > 1
            && shown.allSatisfy(\.still)
        let playing = holding != nil || shown.contains(where: \.playing)
        // Reading the window list costs a few milliseconds, so it is quick only while something is being
        // dragged; app switches, Space changes and wake ask for a reading straight away.
        // While dragging the reading keeps up with the window so its pile drops as it leaves; otherwise twice a
        // second is enough for closes and moves made without the pointer, and a mouse-up reads straight away.
        let interval = (now - lastDrag) / .seconds(1) < 0.5 ? 0.05 : 0.5
        // A dock sliding away must drop its ledge at once, not at the next slow reading.
        if (now - lastSnapshot) / .seconds(1) >= interval || visibleBars().map(\.bar) != lastBars { snapshot() }
        if !shown.isEmpty { setClock(still ? .still : playing ? .play : .drift) }
    }

    // MARK: Pets

    private struct PetBody {
        var id: String
        var feet: CGPoint
        var velocity: CGVector
        var unit: Double
        var playful: Double
    }

    private func petBodies(dt: Double) -> [PetBody] {
        guard let petSource else { return [] }
        var bodies: [PetBody] = []
        var seen: [String: CGPoint] = [:]
        for pet in petSource.weatherPets {
            let before = petFeet[pet.id] ?? pet.feet
            let velocity = dt > 0 ? CGVector(dx: (pet.feet.x - before.x) / dt, dy: (pet.feet.y - before.y) / dt) : .zero
            bodies.append(PetBody(id: pet.id, feet: pet.feet, velocity: velocity, unit: pet.unit,
                                  playful: settings.interactions ? petSource.weatherPlayfulness(pet.id) : 0))
            seen[pet.id] = pet.feet
        }
        petFeet = seen
        return bodies
    }

    private func localPets(_ pets: [PetBody], on screen: WeatherScreen) -> [WeatherPet] {
        let frame = screen.screen.geometry.frame
        return pets.filter { frame.contains($0.feet) }.map {
            let p = screen.local($0.feet)
            return WeatherPet(id: $0.id, x: p.x, y: p.y, vx: $0.velocity.dx, vy: $0.velocity.dy, unit: $0.unit,
                              playful: $0.playful)
        }
    }

    private func handle(_ events: [WeatherEvent], on screen: WeatherScreen) {
        for event in events {
            switch event {
            case .nudge(let pet, let dx, let dy):
                petSource?.weatherNudge(pet, impulse: CGVector(dx: dx, dy: dy))
            case .walk(let pet, let x):
                petSource?.weatherWalk(pet, toX: x + screen.origin.x)
            case .pose(let pet, let pose, let seconds, let ball):
                petSource?.weatherPose(pet, pose: pose, seconds: seconds, ball: ball)
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

    private var lastBars: [CGRect] = []

    /// Only bars on screen right now; an auto-hidden or faded dock keeps its resting frame but has no top to land on.
    private func visibleBars() -> [(screen: String, bar: CGRect)] {
        guard let model else { return [] }
        return model.dockController.windows.values.filter(\.showsBar)
            .map { (screen: $0.screen.id, bar: $0.barFrame) }
            // Sorted so comparing against the last reading doesn't depend on dictionary order.
            .sorted { ($0.bar.minX, $0.bar.minY) < ($1.bar.minX, $1.bar.minY) }
    }

    private func snapshot() {
        lastSnapshot = .now
        guard !snapshotting, let model, !screens.isEmpty else { return }
        snapshotting = true
        let front = NSWorkspace.shared.frontmostApplication
        let own = ProcessInfo.processInfo.processIdentifier
        let frontPID = front?.processIdentifier == own ? nil : front?.processIdentifier
        let frames = NSScreen.screens.map(\.frame)
        let bars = visibleBars()
        lastBars = bars.map(\.bar)
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                // Asking every app for its activation policy takes tens of milliseconds, too long for the main
                // thread. Harbor runs without a Dock icon, so its own pid is added for snow to settle on its windows.
                let regular = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                    .map(\.processIdentifier)).union([own])
                // No pid is excluded: snow settles on Harbor's own Settings and Manager windows too. The
                // overlays, docks and pets are on other window levels, which the reading skips anyway.
                return RoamSnapshot.take(frontPID: frontPID, ownPID: -1, regularPIDs: regular, screens: frames)
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
        let frames = windows.map(\.frame)
        for screen in screens.values {
            let frame = screen.screen.geometry.frame
            let menuBar = max(0, frame.maxY - screen.screen.geometry.visibleFrame.maxY)
            let docks = bars.filter { $0.screen == screen.screen.id && !$0.bar.isEmpty }.map(\.bar)
            let built = RoamSurfaces.build(screen: frame, menuBarHeight: menuBar,
                                           windows: windows.filter { $0.frame.intersects(frame) }, docks: docks,
                                           walkOnWindows: true)
            let surfaces = WeatherWorld.roundingCorners(built, windows: frames)
            let origin = frame.origin
            let local = surfaces.map {
                RoamSurface(kind: $0.kind, y: $0.y - origin.y, minX: $0.minX - origin.x, maxX: $0.maxX - origin.x)
            }
            let falling = screen.stage.with {
                $0.setSurfaces(local, quietly: quietly)
                return !$0.isStill
            }
            // Snow tipped off a window that closed or moved falls at once, not on the next slow beat.
            if falling, !screen.hidden, pace == .still { setClock(.drift) }
        }
        updateVisibility()
    }

    // MARK: Development

    /// HARBOR_WEATHER_SCRIPT plays a scene for checking the weather by eye: a test window gets a deep drift,
    /// is hit by a snowball, moved, buried again and closed; then autumn, spring and summer each get their
    /// piles filled so a roaming pet nearby has something to play in. Its value picks the screen by index.
    private func runScript() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 220), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Weather test"
        window.isReleasedWhenClosed = false
        let screens = NSScreen.screens
        let index = min(max(Int(environment["HARBOR_WEATHER_SCRIPT"] ?? "") ?? 0, 0), max(screens.count - 1, 0))
        let main = screens.isEmpty ? .zero : screens[index].visibleFrame
        window.setFrameOrigin(CGPoint(x: main.midX - 210, y: main.midY - 160))
        let season = { (choice: SeasonChoice) in self.model?.store.updateSettings { $0.weather.season = choice } }
        let fill = { (depth: Double) in for screen in self.screens.values { screen.stage.with { $0.fill(depth: depth) } } }
        let steps: [(at: Double, name: String, run: @MainActor () -> Void)] = [
            (1, "window", { window.orderFrontRegardless(); self.snapshot() }),
            (3, "bury", { fill(7) }),
            (6, "throw", {
                let f = window.frame
                for screen in self.screens.values where screen.screen.geometry.frame.intersects(f) {
                    let p = screen.local(CGPoint(x: f.minX + 60, y: f.maxY + 120))
                    screen.stage.with { $0.throwSnowball(x: p.x, y: p.y, r: 10, vx: 520, vy: -300) }
                }
            }),
            (10, "move", { window.setFrameOrigin(CGPoint(x: window.frame.minX + 240, y: window.frame.minY)); self.snapshot() }),
            (14, "rebury", { fill(7) }),
            (17, "close", { window.close(); self.snapshot() }),
            (24, "autumn", { season(.autumn) }),
            (25, "leaves", { fill(9) }),
            (55, "spring", { season(.spring) }),
            (56, "petals", { fill(5) }),
            (80, "summer", { season(.summer) }),
            (81, "bubbles", { fill(0) }),
            (105, "done", {}),
        ]
        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.at) {
                MainActor.assumeIsolated {
                    FileHandle.standardError.write(Data("WEATHER-SCRIPT \(step.name) \(Date.now.timeIntervalSince1970)\n".utf8))
                    step.run()
                }
            }
        }
    }

    // MARK: Pointer

    private func installMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseUp, let self {
                    // A click on a close button or the end of a drag usually changes a window; read now and again
                    // once a closing window's fade-out has left the list.
                    self.snapshot()
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(250))
                        self?.snapshot()
                    }
                    return
                }
                if event.type == .leftMouseDragged, let self {
                    self.lastDrag = .now
                    if self.pace == .still { self.setClock(.drift) }
                }
                self?.pointerMoved()
            }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: handler)
        if let up { monitors.append(up) }
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
                screen.stage.with { $0.pointerLeft() }
                if holding != screen.screen.id, !screen.panel.ignoresMouseEvents { screen.panel.ignoresMouseEvents = true }
                continue
            }
            let p = screen.local(location)
            let velocity = pointerVelocity
            let hit = screen.stage.with {
                $0.pointerMoved(x: p.x, y: p.y, vx: velocity.dx, vy: velocity.dy)
                return $0.hitTest(x: p.x, y: p.y)
            }
            if holding == nil {
                if screen.panel.ignoresMouseEvents == hit { screen.panel.ignoresMouseEvents = !hit }
            }
            if hypot(pointerVelocity.dx, pointerVelocity.dy) > 300 {
                lastGust = now
                if pace == .still { setClock(.drift) }
            }
        }
    }

    private func mouse(_ event: NSEvent, on screen: WeatherScreen) {
        let p = screen.local(NSEvent.mouseLocation)
        switch event.type {
        case .leftMouseDown:
            if screen.stage.with({ $0.pointerDown(x: p.x, y: p.y) && $0.isHolding }) { holding = screen.screen.id }
            setClock(.play)
        case .leftMouseDragged:
            pointerMoved()
            screen.stage.with { $0.pointerDragged(x: p.x, y: p.y) }
        case .leftMouseUp:
            // Held still before letting go: a drop, not a throw.
            let paused = (ContinuousClock.now - pointerTime) / .seconds(1) > 0.1
            if paused { pointerVelocity = .zero }
            let velocity = pointerVelocity
            let hit = screen.stage.with {
                $0.pointerUp(vx: velocity.dx, vy: velocity.dy)
                return $0.hitTest(x: p.x, y: p.y)
            }
            holding = nil
            screen.panel.ignoresMouseEvents = !hit
        default:
            break
        }
    }
}
