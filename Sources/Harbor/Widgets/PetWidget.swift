import AppKit
import HarborCore
import SwiftUI
import UniformTypeIdentifiers

/// Reads and writes a pet's needs. Needs only drift between the anchor and now, and the anchor
/// moves to "now" whenever the pet appears, so time spent hidden or asleep costs nothing.
@MainActor
enum PetStore {
    /// Longest gap one settle may charge; a sleeping Mac or locked screen leaves larger gaps that must not count.
    static let maxCharge: TimeInterval = 120

    static func stored(_ widget: WidgetConfig) -> PetNeeds {
        PetNeeds(happiness: widget.stateDouble("happiness") ?? 80,
                 hunger: widget.stateDouble("hunger") ?? 80,
                 energy: widget.stateDouble("energy") ?? 80)
    }

    static func write(_ fields: WidgetFields, _ needs: PetNeeds, anchor: Date?) {
        fields.setStates([
            "happiness": .number(needs.happiness),
            "hunger": .number(needs.hunger),
            "energy": .number(needs.energy),
            "anchor": anchor.map { .number($0.timeIntervalSince1970) },
        ])
    }

    /// Needs as of `now`, charging the time since the anchor.
    static func current(_ widget: WidgetConfig, now: Date) -> PetNeeds {
        guard let anchor = widget.stateDouble("anchor") else { return stored(widget) }
        let elapsed = min(now.timeIntervalSince1970 - anchor, maxCharge)
        return stored(widget).decayed(by: elapsed)
    }

    static func settle(_ fields: WidgetFields, now: Date = .now) {
        write(fields, current(fields.current, now: now), anchor: now)
    }

    static func apply(_ fields: WidgetFields, _ change: (PetNeeds) -> PetNeeds) {
        let now = Date.now
        write(fields, change(current(fields.current, now: now)), anchor: now)
    }

    static func resume(_ fields: WidgetFields) {
        write(fields, stored(fields.current), anchor: .now)
    }

    /// Bond fades in real time, hidden or not, so a long absence cools the pet without erasing it.
    static func bond(_ widget: WidgetConfig, now: Date = .now) -> Double {
        let stored = widget.stateDouble("bond") ?? 0
        let stamp = widget.stateDouble("bondAt") ?? now.timeIntervalSince1970
        return PetLogic.decayedBond(stored, elapsed: now.timeIntervalSince1970 - stamp)
    }

    static func raiseBond(_ fields: WidgetFields, petting: Bool, now: Date = .now) {
        let raised = PetLogic.bond(bond(fields.current, now: now), afterPetting: petting)
        fields.setStates(["bond": .number(raised), "bondAt": .number(now.timeIntervalSince1970)])
    }

    static func pause(_ fields: WidgetFields) {
        write(fields, current(fields.current, now: .now), anchor: nil)
    }
}

/// One-shot performances. Only one plays at a time, which keeps the pose a function of a single clock.
private enum PetAct {
    case pet, hop, startle, giggle, spin, wave, scratch, yawn, chaseTail, hum, peek, lookAround
    case gulp, sneeze, flop, gift

    var duration: Double {
        switch self {
        case .pet: 1.0
        case .hop: 1.2
        case .startle: 2.4
        case .giggle: 0.8
        case .spin: 1.2
        case .wave: 1.6
        case .scratch: 1.8
        case .yawn: 2.2
        case .chaseTail: 1.6
        case .hum: 2.4
        case .peek: 1.8
        case .lookAround: 2.2
        case .gulp: 0.8
        case .sneeze: 1.2
        case .flop: 2.6
        case .gift: 1.6
        }
    }

    /// A face the act imposes while it plays, or nil to keep the underlying mood.
    func expression(at p: Double) -> PetExpression? {
        switch self {
        case .pet, .wave, .hum, .yawn, .flop, .scratch: .happy
        case .hop: .surprised
        case .startle: p < 0.4 ? .surprised : .excited
        case .giggle, .spin, .chaseTail: .excited
        case .peek: .curious
        case .gulp: p < 0.25 ? .surprised : .happy
        case .sneeze: p < 0.55 ? .happy : .surprised
        case .gift: .proud
        case .lookAround: nil
        }
    }
}

/// Body motion for one instant of an act, in unit fractions and degrees.
private struct PetActFrame {
    var x = 0.0
    var y = 0.0
    var squash = 0.0
    var stretchX = 0.0
    var rotation = 0.0
    var headTilt = 0.0
    var flipperLeft = 0.0
    var flipperRight = 0.0
    var rightOffset = CGSize.zero
    var mouthOpen = 0.0
    var gaze: CGSize?
}

struct PetWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState
    /// Present when this copy lives in the roaming window rather than in a dock cell.
    var roam: RoamDriver? = nil

    @State private var appeared = false
    @State private var windowVisible = true
    @State private var windowBox = PetWindowBox()
    @State private var frame: CGRect = .zero

    @State private var expression: PetExpression = .calm
    @State private var blinking = false
    @State private var hovering = false
    @State private var lastInteraction = Date.now
    @State private var didYawn = false
    @State private var tapTracker = PetTapTracker()
    @State private var hoverStart: Date?
    @State private var particles: [PetParticle] = []
    @State private var nextParticle = 0

    @State private var act: PetAct?
    @State private var actStart = Date.now
    @State private var peekSide = 1.0
    @State private var lastIdle: PetIdle?
    @State private var pointerGaze: PetVector?
    @State private var actRunning = false
    @State private var settling = false
    @State private var turning = false
    @State private var strideClock = PetStrideClock()
    @State private var turnClock = PetTurnClock()

    private static let lagInterval: TimeInterval = 0.08

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dock.id) }
    private var tracksNeeds: Bool { widget.bool("needs", false) }
    private var visible: Bool { appeared && windowVisible }
    private var hour: Int { Calendar.current.component(.hour, from: .now) }
    private var species: PetSpecies { PetAppearance(widget).species }

    var body: some View {
        if roam == nil, widget.isRoaming {
            outline
        } else {
            character
        }
    }

    /// What a roaming pet leaves behind in its dock cell; clicking it calls the pet home.
    private var outline: some View {
        let unit = Tokens.Tool.unit(size)
        return Ellipse()
            .strokeBorder(Tokens.textMuted.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: unit * 0.7, height: unit * 0.8)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { RoamCoordinator.shared.bringHome(item: item, dock: dock) }
            .onAppear { RoamCoordinator.shared.start(model: model) }
            .help("Call \(widget.string("name", "Pup")) home")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(widget.string("name", "Pup")) is out roaming")
            .accessibilityHint("Calls it home")
            .accessibilityAddTraits(.isButton)
    }

    /// Whether anything on screen is changing, so a still roaming pet can stop producing frames.
    private var animating: Bool {
        guard let roam else { return true }
        return roam.moving || roam.falling || roam.carried || actRunning || settling || turning || !particles.isEmpty
    }

    private func timeline(unit: CGFloat, needs: PetNeeds) -> some View {
        let look = PetLook(PetAppearance(widget))
        return TimelineView(.animation(minimumInterval: roam == nil ? 1 / 60 : 1 / 30,
                                       paused: reduceMotion || !visible || !animating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let shown = shownExpression(at: context.date)
            ZStack {
                PetFigure(unit: unit, pose: pose(at: context.date, time: time, shown: shown, unit: unit),
                          padBottom: tracksNeeds && roam == nil, look: look)
                if shown == .asleep {
                    PetSnoreBubble(unit: unit, time: time).offset(x: unit * 0.07, y: unit * 0.1)
                    PetSleepLetters(unit: unit, time: time, animated: !reduceMotion)
                } else if shown == .hungry {
                    PetFishBubble(unit: unit).offset(x: unit * 0.34, y: unit * 0.2)
                }
                ForEach(particles) { particle in
                    PetParticleView(unit: unit, particle: particle, animated: !reduceMotion) {
                        particles.removeAll { $0.id == particle.id }
                    }
                }
                if tracksNeeds, roam == nil {
                    VStack {
                        Spacer()
                        Capsule()
                            .fill(Tokens.border)
                            .frame(width: unit * 0.5, height: max(unit * 0.04, 2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Tokens.accent)
                                    .frame(width: unit * 0.5 * min(needs.happiness, needs.hunger, needs.energy) / 100)
                            }
                    }
                    .padding(.bottom, unit * 0.02)
                }
            }
        }
    }

    private var interactive: some View {
        timeline(unit: roam?.unit ?? Tokens.Tool.unit(size), needs: PetStore.stored(widget))
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .background(PetWindowReader(box: windowBox))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            frame = $0
            noteCell()
        }
        .onHover { inside in if roam == nil { hover(inside) } }
        .onTapGesture { pet() }
        .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .global).onChanged { _ in dragMoved() })
        .modifier(PetRoamExtras(enabled: roam != nil, item: item, dock: dock))
    }

    private var observing: some View {
        interactive
        .onChange(of: roam?.hovering) { if let inside = roam?.hovering { hover(inside) } }
        .onChange(of: roam?.pointerTick) { updatePointer() }
        .onChange(of: roam?.startleTick) { startAct(.startle) }
        .onChange(of: roam?.napping) { refresh() }
        .onChange(of: roam?.moving) {
            // Keep frames coming while the head swings back to face the viewer after a walk.
            turning = true
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                turning = false
            }
        }
        .onChange(of: roam?.landTick) {
            settling = true
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                settling = false
            }
        }
    }

    private var character: some View {
        let needs = PetStore.stored(widget)
        return observing
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow, window === windowBox.window else { return }
            windowVisible = window.occlusionState.contains(.visible)
        }
        .onChange(of: PetReactions.shared.feeds[item.id]) { gulp() }
        .onAppear {
            appeared = true
            if roam == nil { RoamCoordinator.shared.start(model: model) }
            lastInteraction = .now
            if tracksNeeds { PetStore.resume(fields) }
        }
        .onDisappear {
            appeared = false
            pointerGaze = nil
            if tracksNeeds { PetStore.pause(fields) }
        }
        .task(id: visible) { await settleLoop() }
        .task(id: visible && !reduceMotion) { await pointerLoop() }
        .task(id: visible) { await mindLoop() }
        .task(id: visible) { await blinkLoop() }
        .task(id: visible && !reduceMotion) { await idleLoop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widget.string("name", "Pup"))
        .accessibilityValue(tracksNeeds
            ? "Happiness \(Int(needs.happiness)), hunger \(Int(needs.hunger)), energy \(Int(needs.energy))"
            : "")
        .accessibilityHint("Pets it")
        .accessibilityAddTraits(.isButton)
    }

    private func noteCell() {
        guard roam == nil, let window = windowBox.window, frame != .zero else { return }
        RoamCoordinator.shared.noteCell(PetKey(dock: dock.id, item: item.id),
                                        center: CGPoint(x: window.frame.minX + frame.midX, y: window.frame.maxY - frame.midY))
    }

    private func dragMoved() {
        if let roam {
            roam.onCarry?()
        } else if !model.store.editing.contains(dock.id) {
            RoamCoordinator.shared.dockDragMoved(item: item, dock: dock)
        }
    }

    // MARK: Pose

    private func actProgress(at date: Date) -> (act: PetAct, elapsed: Double, p: Double)? {
        guard let act else { return nil }
        let elapsed = date.timeIntervalSince(actStart)
        guard elapsed >= 0, elapsed < act.duration else { return nil }
        return (act, elapsed, elapsed / act.duration)
    }

    private func shownExpression(at date: Date) -> PetExpression {
        if expression == .asleep { return .asleep }
        guard let current = actProgress(at: date) else { return expression }
        return current.act.expression(at: current.p) ?? expression
    }

    private func envelope(_ p: Double) -> Double { max(0, min(1, p / 0.15, (1 - p) / 0.15)) }

    private func easeInOut(_ p: Double) -> Double { p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 }

    private func motion(of act: PetAct, elapsed e: Double, p: Double) -> PetActFrame {
        var f = PetActFrame()
        let env = envelope(p)
        switch act {
        case .pet:
            let hop = PetMotion.hop(elapsed: e)
            f.y = -0.08 * hop.lift
            f.squash = hop.squash
            f.flipperLeft = 25 * sin(p * .pi)
            f.flipperRight = 25 * sin(p * .pi)
        case .hop:
            let hop = PetMotion.hop(elapsed: e)
            f.y = -0.18 * hop.lift
            f.squash = hop.squash
        case .startle:
            let hop = PetMotion.hop(elapsed: e)
            f.y = -0.2 * hop.lift
            f.squash = hop.squash
            if e > 1.0 {
                let decay = max(0, 1 - (e - 1.0) / 1.4)
                f.rotation = sin((e - 1.0) * 2 * .pi * 5) * 8 * decay
                f.flipperLeft = 20 * decay
                f.flipperRight = 20 * decay
            }
        case .giggle:
            let beat = abs(sin(e * 2 * .pi * 4.5))
            f.rotation = sin(e * 2 * .pi * 9) * 7 * env
            f.y = -0.015 * beat
            f.flipperLeft = 30 * beat
            f.flipperRight = 30 * beat
        case .spin:
            f.rotation = 360 * easeInOut(p)
            f.y = -0.1 * abs(sin(p * 3 * .pi))
            f.flipperLeft = 30
            f.flipperRight = 30
        case .wave:
            f.flipperRight = 70 * env + 14 * sin(e * 14) * env
            f.headTilt = 5 * env
        case .scratch:
            f.flipperRight = 75 * env + 12 * sin(e * 32) * env
            f.rightOffset = CGSize(width: -0.06 * env + 0.012 * sin(e * 32) * env, height: -0.11 * env)
            f.headTilt = 8 * env
        case .yawn:
            let arc = sin(p * .pi)
            f.mouthOpen = arc
            f.squash = -0.08 * arc
            f.stretchX = -0.03 * arc
            f.flipperLeft = 40 * arc
            f.flipperRight = 40 * arc
        case .chaseTail:
            f.rotation = 720 * easeInOut(p)
            f.headTilt = 8 * env
        case .hum:
            f.rotation = sin(e * 2 * .pi * 0.9) * 4 * env
            f.y = -0.01 * sin(e * 2 * .pi * 1.8) * env
        case .peek:
            f.headTilt = 9 * peekSide * env
            f.x = 0.02 * peekSide * env
            f.gaze = pointerGaze.map { CGSize(width: $0.x, height: $0.y) } ?? CGSize(width: 0.9 * peekSide, height: -0.1)
        case .lookAround:
            f.gaze = CGSize(width: sin(p * 2 * .pi * 1.5) * 0.9 * env, height: -0.15 * env)
        case .gulp:
            if e < 0.15 {
                f.squash = 0.08 * sin(e / 0.15 * .pi / 2)
            } else {
                let q = (e - 0.15) / 0.65
                let pulse = 0.05 * sin(q * 4 * .pi)
                f.mouthOpen = q < 0.5 ? sin(q / 0.5 * .pi) : 0
                f.squash = -pulse
                f.stretchX = pulse
            }
        case .sneeze:
            if p < 0.45 {
                f.headTilt = -8 * (p / 0.45)
                f.squash = -0.04 * (p / 0.45)
            } else {
                let burst = sin(min((p - 0.45) / 0.2, 1) * .pi)
                f.headTilt = 8 * burst
                f.mouthOpen = burst
                f.squash = 0.1 * burst
                f.y = -0.04 * burst
            }
        case .flop:
            let rise = act.duration * 0.75
            f.rotation = e < rise ? 80 * PetMotion.spring(e, response: 0.35) : 80 * (1 - PetMotion.spring(e - rise, response: 0.35))
            f.y = 0.1 * min(1, e / 0.2) * (e < rise ? 1 : max(0, 1 - (e - rise) / 0.2))
            f.flipperLeft = e > 0.5 && e < rise ? 35 * abs(sin(e * 8)) : 0
            f.flipperRight = f.flipperLeft
        case .gift:
            let hop = PetMotion.hop(elapsed: e)
            f.y = -0.06 * hop.lift
            f.squash = hop.squash * 0.5
            f.flipperRight = 45 * env
        }
        return f
    }

    private func pose(at date: Date, time: Double, shown: PetExpression, unit: CGFloat) -> PetPose {
        var pose = PetPose()
        pose.face = shown.face
        pose.lid = blinking ? 1 : 0
        guard !reduceMotion else {
            pose.gaze = gazeVector(for: pose.face.gaze, override: nil)
            return pose
        }

        let breath = PetMotion.breath(at: shown == .asleep ? time * 0.75 : time)
        pose.scale = CGSize(width: 1 - 0.015 * breath, height: 1 + 0.03 * breath)
        pose.twinkle = (sin(time * 3) + 1) / 2
        pose.tail = shown == .asleep ? 0 : sin((time - Self.lagInterval) * 1.4) * 14

        var current = PetActFrame()
        var earlier = PetActFrame()
        if let now = actProgress(at: date) {
            current = motion(of: now.act, elapsed: now.elapsed, p: now.p)
        }
        if let before = actProgress(at: date.addingTimeInterval(-Self.lagInterval)) {
            earlier = motion(of: before.act, elapsed: before.elapsed, p: before.p)
        }
        pose.scale.width *= 1 + current.stretchX
        pose.scale.height *= 1 - current.squash
        pose.rotation = current.rotation
        pose.headTilt = current.headTilt
        pose.flipperLeft = current.flipperLeft
        pose.flipperRight = current.flipperRight
        pose.rightFlipperOffset = CGSize(width: current.rightOffset.width * unit, height: current.rightOffset.height * unit)
        pose.mouthOpen = current.mouthOpen
        // Appendages sample the body a beat earlier, so they trail it and settle just after it stops.
        pose.lag = CGSize(width: (earlier.x - current.x) * unit, height: (earlier.y - current.y) * unit)
        pose.offset = CGSize(width: current.x * unit, height: current.y * unit)

        if let roam {
            applyRoamMotion(&pose, roam: roam, date: date, time: time, unit: unit)
        }
        if hovering && shown != .asleep {
            pose.flipperLeft += sin(time * 12) * 10 + 10
            pose.flipperRight += sin(time * 12 + .pi) * 10 + 10
            if let start = hoverStart, date.timeIntervalSince(start) >= PetLogic.warmAfter {
                pose.scale.width *= 1.04
                pose.scale.height *= 1.04
                pose.headTilt += 6
            }
        }
        if pose.face.wiggles && current.rotation == 0 { pose.rotation = sin(time * 2 * .pi * 4) * 3 }
        pose.gaze = gazeVector(for: pose.face.gaze, override: current.gaze)
        return pose
    }

    /// Walking speed in points per second, which sets the stride cadence.
    private func walkSpeed(_ roam: RoamDriver) -> Double {
        // Stand-in until the driver reports its real speed; swap in `roam.walkSpeed` here.
        Double(roam.unit) * (roam.lively ? 1.65 : 1.2)
    }

    /// Locomotion layered over the shared pose: a directional walk, a squash on landing, limp limbs when held.
    private func applyRoamMotion(_ pose: inout PetPose, roam: RoamDriver, date: Date, time: Double, unit: CGFloat) {
        let walking = roam.moving && !roam.carried && !roam.falling
        let rate = walking ? PetGait.strideRate(speed: walkSpeed(roam), unit: Double(unit)) : 0
        let species = species
        let hopRate = species.gait == .hop ? 0.75 : 1
        let state = PetBodyState(moving: roam.moving, falling: roam.falling, carried: roam.carried,
                                 sitting: roam.sitting, napping: roam.napping, facing: roam.facing,
                                 phase: strideClock.advance(to: time, rate: rate * hopRate), time: time)
        pose.turn = turnClock.value(at: time, target: walking ? roam.facing * PetLocomotion.walkTurn : 0)
        PetLocomotion.apply(&pose, state, species: species, unit: unit)
        let landed = date.timeIntervalSince(roam.landAt) / 0.35
        if landed >= 0, landed < 1 {
            let squash = roam.landImpact * 0.28 * sin(landed * .pi)
            pose.scale.height *= 1 - squash
            pose.scale.width *= 1 + squash * 0.6
        }
    }

    private func gazeVector(for mode: PetGazeMode, override: CGSize?) -> CGSize {
        let followed = override ?? pointerGaze.map { CGSize(width: $0.x, height: $0.y) } ?? .zero
        switch mode {
        case .follow:
            let clamped = PetLogic.clampGaze(PetVector(x: followed.width, y: followed.height))
            return CGSize(width: clamped.x, height: clamped.y)
        case .down: return CGSize(width: 0.5, height: 0.9)
        case .away: return CGSize(width: followed.width >= 0 ? -0.9 : 0.9, height: 0.3)
        }
    }

    // MARK: Interaction

    private func startAct(_ next: PetAct) {
        guard !reduceMotion else { return }
        act = next
        actStart = .now
        actRunning = true
        quickBlink()
    }

    private func wake() {
        lastInteraction = .now
        didYawn = false
        refresh()
    }

    private func hover(_ inside: Bool) {
        hovering = inside
        hoverStart = inside ? .now : nil
        guard inside else { return }
        wake()
        if !reduceMotion, PetLogic.showsHoverHeart(bond: PetStore.bond(fields.current)) {
            emit(.heart, origin: CGSize(width: 0.12, height: -0.28), drift: CGSize(width: 0.05, height: -0.25))
        }
    }

    private func pet() {
        let wasAsleep = expression == .asleep
        let clock = ProcessInfo.processInfo.systemUptime
        let burst = tapTracker.tap(at: clock)
        let streak = tapTracker.streak(at: clock)
        hoverStart = hovering ? .now : nil
        wake()
        roam?.onTouch?()
        if tracksNeeds { PetStore.apply(fields) { $0.petted() } }
        PetStore.raiseBond(fields, petting: true)
        for _ in 0..<Int.random(in: 1...3) {
            emit(.heart, origin: CGSize(width: .random(in: -0.12...0.12), height: -0.25),
                 drift: CGSize(width: .random(in: -0.15...0.15), height: .random(in: -0.4 ... -0.25)))
        }
        guard !wasAsleep else { return }
        if burst {
            startAct(.spin)
        } else if streak >= 2 {
            startAct(.giggle)
        } else {
            startAct(.pet)
        }
    }

    private func gulp() {
        wake()
        PetStore.raiseBond(fields, petting: false)
        startAct(.gulp)
        guard !reduceMotion else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            for _ in 0..<6 {
                emit(.crumb, origin: CGSize(width: 0, height: 0.17),
                     drift: CGSize(width: .random(in: -0.3...0.3), height: .random(in: -0.1...0.2)))
            }
        }
    }

    private func emit(_ kind: PetParticle.Kind, origin: CGSize, drift: CGSize) {
        nextParticle += 1
        particles.append(PetParticle(id: nextParticle, kind: kind, origin: origin, drift: drift))
        if particles.count > 10 { particles.removeFirst() }
    }

    private func quickBlink() {
        Task {
            blinking = true
            try? await Task.sleep(for: .seconds(PetLogic.blinkDuration))
            blinking = false
        }
    }

    // MARK: Loops

    /// Settles drift on a slow beat while visible so a quit mid-session loses at most a minute.
    private func settleLoop() async {
        guard visible else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if tracksNeeds { PetStore.settle(fields) }
        }
    }

    /// Converts the pointer into the pet's frame of reference; only runs while the pet is on screen.
    private func pointerLoop() async {
        // A roaming pet is told when the pointer moves, so it never polls.
        guard visible, !reduceMotion, roam == nil else {
            pointerGaze = nil
            return
        }
        while !Task.isCancelled {
            updatePointer()
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private func updatePointer() {
        guard let window = windowBox.window, frame != .zero else { return }
        let mouse = NSEvent.mouseLocation
        // SwiftUI's global space is top-left origin within the window; screen space is bottom-left.
        let centerX = window.frame.minX + frame.midX
        let centerY = window.frame.maxY - frame.midY
        let next = PetLogic.gaze(dx: mouse.x - centerX, dy: centerY - mouse.y)
        guard next != pointerGaze else { return }
        withAnimation(.linear(duration: 1 / 30)) { pointerGaze = next }
    }

    /// Re-derives the mood a few times a second; it only compares a handful of numbers.
    private func mindLoop() async {
        guard visible else { return }
        while !Task.isCancelled {
            refresh()
            if actRunning, actProgress(at: .now) == nil { actRunning = false }
            try? await Task.sleep(for: .milliseconds(roam == nil ? 250 : 500))
        }
    }

    /// A roaming pet naps when its body says so, not when it has gone unpetted for a while.
    private func effectiveIdle(_ idle: TimeInterval) -> TimeInterval {
        guard let roam else { return idle }
        return roam.napping ? max(idle, PetLogic.napDelay(hour: hour)) : min(idle, PetLogic.boredAfter - 1)
    }

    private func refresh() {
        let now = Date.now
        let current = fields.current
        let idle = effectiveIdle(now.timeIntervalSince(lastInteraction))
        let needs = current.bool("needs", false) ? PetStore.stored(current) : PetNeeds()
        let context = PetContext(needs: needs, bond: PetStore.bond(current), idle: idle, hour: hour,
                                 hover: hoverStart.map { now.timeIntervalSince($0) } ?? 0,
                                 clickStreak: tapTracker.streak(at: ProcessInfo.processInfo.systemUptime))
        if PetLogic.shouldYawn(idle: idle, hour: hour), !didYawn {
            didYawn = true
            startAct(.yawn)
        }
        let next = PetLogic.expression(context)
        guard next != expression else { return }
        let wasAsleep = expression == .asleep
        expression = next
        if wasAsleep {
            // Waking is a startled jump followed by a happy wiggle.
            startAct(.startle)
        } else {
            quickBlink()
        }
    }

    private func blinkLoop() async {
        guard visible else { return }
        while !Task.isCancelled {
            let plan = PetLogic.blinkPlan(delayRoll: .random(in: 0...1), doubleRoll: .random(in: 0...1))
            try? await Task.sleep(for: .seconds(plan.delay))
            guard expression != .asleep else { continue }
            blinking = true
            try? await Task.sleep(for: .seconds(PetLogic.blinkDuration))
            blinking = false
            if plan.double {
                try? await Task.sleep(for: .milliseconds(120))
                blinking = true
                try? await Task.sleep(for: .seconds(PetLogic.blinkDuration))
                blinking = false
            }
        }
    }

    private func idleLoop() async {
        guard visible, !reduceMotion else { return }
        while !Task.isCancelled {
            // Energy from Settings › Personality: mellow pets do tricks half as often, lively ones
            // nearly twice as often, and quiet ones only react to you.
            let settings = model.store.settings
            if settings.petQuiet {
                try? await Task.sleep(for: .seconds(30))
                continue
            }
            let pace: Double = switch settings.petEnergy {
            case .mellow: 2.0
            case .normal: 1.0
            case .lively: 0.55
            }
            let wait = PetLogic.idleDelay(hour: hour, roll: .random(in: 0..<1)) * pace
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, expression != .asleep, !hovering, actProgress(at: .now) == nil,
                  roam?.moving != true, roam?.falling != true else { continue }
            if Double.random(in: 0..<1) < PetLogic.surpriseProbability(visibleFor: wait) {
                await perform(PetSurprise.pick(roll: .random(in: 0..<1)))
            } else {
                let bond = PetStore.bond(fields.current)
                let idle = PetLogic.pickIdle(previous: lastIdle, bond: bond, hour: hour, roll: .random(in: 0..<1))
                lastIdle = idle
                await perform(idle)
            }
        }
    }

    private func perform(_ idle: PetIdle) async {
        peekSide = Bool.random() ? 1 : -1
        switch idle {
        case .lookAround: startAct(.lookAround)
        case .wave: startAct(.wave)
        case .scratch: startAct(.scratch)
        case .yawn: startAct(.yawn)
        case .chaseTail: startAct(.chaseTail)
        case .peek: startAct(.peek)
        case .hum:
            startAct(.hum)
            for step in 0..<3 {
                try? await Task.sleep(for: .milliseconds(500))
                emit(.note, origin: CGSize(width: 0.3 + 0.03 * Double(step), height: -0.2),
                     drift: CGSize(width: .random(in: 0.0...0.1), height: -0.25))
            }
        }
    }

    private func perform(_ surprise: PetSurprise) async {
        switch surprise {
        case .sneeze:
            startAct(.sneeze)
            try? await Task.sleep(for: .milliseconds(600))
            for _ in 0..<3 {
                emit(.crumb, origin: CGSize(width: 0, height: 0.15),
                     drift: CGSize(width: .random(in: -0.25...0.25), height: .random(in: 0.0...0.15)))
            }
        case .flop:
            startAct(.flop)
        case .gift:
            startAct(.gift)
            for step in 0..<3 {
                try? await Task.sleep(for: .milliseconds(250))
                emit(.sparkle, origin: CGSize(width: Double(step - 1) * 0.12, height: -0.2),
                     drift: CGSize(width: .random(in: -0.08...0.08), height: -0.2))
            }
        }
    }
}

/// Context menu and file feeding for the roaming window; the dock cell gets both from the dock itself.
private struct PetRoamExtras: ViewModifier {
    @Environment(AppModel.self) private var model
    let enabled: Bool
    let item: DockItem
    let dock: Dock

    func body(content: Content) -> some View {
        if enabled {
            content
                .contextMenu { PetContextItems(item: item, dock: dock) }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    PetDrop.handle(providers, item: item, dock: dock, model: model)
                }
        } else {
            content
        }
    }
}
