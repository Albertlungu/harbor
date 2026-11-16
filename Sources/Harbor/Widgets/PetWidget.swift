import AppKit
import HarborCore
import SwiftUI

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

    static func pause(_ fields: WidgetFields) {
        write(fields, current(fields.current, now: .now), anchor: nil)
    }
}

struct PetWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var appeared = false
    @State private var windowVisible = true
    @State private var windowBox = PetWindowBox()
    @State private var frame: CGRect = .zero

    @State private var blinking = false
    @State private var hovering = false
    @State private var asleep = false
    @State private var lastInteraction = Date.now
    @State private var tapTracker = PetTapTracker()
    @State private var hearts: [Int] = []
    @State private var nextHeart = 0

    @State private var pointerGaze: PetVector?
    @State private var lookGaze: PetVector = .zero
    @State private var wanderX: CGFloat = 0

    @State private var hoverStart: Date?
    @State private var clickStart: Date?
    @State private var danceStart: Date?
    @State private var stretchStart: Date?
    @State private var gulpStart: Date?

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dock.id) }
    private var tracksNeeds: Bool { widget.bool("needs", false) }
    private var visible: Bool { appeared && windowVisible }

    var body: some View {
        let unit = Tokens.Tool.unit(size)
        let needs = PetStore.stored(widget)
        let mood: PetMood = tracksNeeds ? PetLogic.mood(for: needs) : .content
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || !visible)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                PetFigure(unit: unit, pose: pose(at: context.date, time: time, mood: mood, unit: unit),
                          padBottom: tracksNeeds)
                if asleep {
                    PetSleepLetters(unit: unit, time: time, animated: !reduceMotion)
                } else if mood == .hungry {
                    PetFishBubble(unit: unit).offset(x: unit * 0.22, y: -unit * 0.4)
                }
                ForEach(hearts, id: \.self) { id in
                    PetHeart(unit: unit, reduceMotion: reduceMotion) { hearts.removeAll { $0 == id } }
                }
                if tracksNeeds {
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
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .background(PetWindowReader(box: windowBox))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onHover { inside in hover(inside) }
        .onTapGesture { pet() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow, window === windowBox.window else { return }
            windowVisible = window.occlusionState.contains(.visible)
        }
        .onChange(of: PetReactions.shared.feeds[item.id]) { gulp() }
        .onAppear {
            appeared = true
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
        .task(id: visible) { await sleepLoop() }
        .task(id: visible) { await idleLoop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widget.string("name", "Pup"))
        .accessibilityValue(tracksNeeds
            ? "Happiness \(Int(needs.happiness)), hunger \(Int(needs.hunger)), energy \(Int(needs.energy))"
            : "")
        .accessibilityHint("Pets it")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Pose

    private func progress(_ start: Date?, _ duration: Double, at date: Date) -> Double? {
        guard let start else { return nil }
        let elapsed = date.timeIntervalSince(start)
        return elapsed >= 0 && elapsed < duration ? elapsed / duration : nil
    }

    private func pose(at date: Date, time: Double, mood: PetMood, unit: CGFloat) -> PetPose {
        var pose = PetPose()
        pose.mood = mood
        pose.lid = asleep || blinking ? 1 : (mood == .sleepy ? 0.45 : 0)
        guard !reduceMotion else { return pose }

        var lift = sin(time * (asleep ? 1.1 : 1.8)) * 0.02
        pose.twinkle = (sin(time * 3) + 1) / 2
        pose.tail = asleep ? 0 : sin(time * 1.4) * 14

        if let p = progress(hoverStart, 0.5, at: date) { lift -= 0.07 * sin(p * .pi) }
        if hovering && !asleep {
            pose.flipperLeft = sin(time * 12) * 18
            pose.flipperRight = sin(time * 12 + .pi) * 18
        }
        if let p = progress(clickStart, 0.7, at: date) { lift -= 0.14 * (1 - p) * abs(sin(p * 2 * .pi)) }
        if let p = progress(danceStart, 1.1, at: date) {
            let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            pose.rotation = 360 * eased
            lift -= 0.1 * abs(sin(p * 3 * .pi))
            pose.flipperLeft = 30
            pose.flipperRight = 30
        }
        if let p = progress(stretchStart, 0.9, at: date) {
            let arc = sin(p * .pi)
            pose.scale = CGSize(width: 1 - 0.04 * arc, height: 1 + 0.12 * arc)
            pose.flipperLeft = 40 * arc
            pose.flipperRight = 40 * arc
        }
        if let p = progress(gulpStart, 0.6, at: date) {
            pose.mouthOpen = p < 0.5 ? sin(p / 0.5 * .pi) : 0
            let pulse = 1 + 0.05 * sin(p * 4 * .pi)
            pose.scale = CGSize(width: pulse, height: 2 - pulse)
        }
        pose.offset = CGSize(width: wanderX, height: lift * unit)

        var gaze = pointerGaze ?? lookGaze
        if mood == .hungry && !hovering { gaze = PetVector(x: gaze.x * 0.5, y: 0.85) }
        gaze = PetLogic.clampGaze(gaze)
        pose.gaze = CGSize(width: gaze.x, height: gaze.y)
        return pose
    }

    // MARK: Interaction

    private func wake() {
        lastInteraction = .now
        guard asleep else { return }
        asleep = false
        if !reduceMotion { stretchStart = .now }
    }

    private func hover(_ inside: Bool) {
        hovering = inside
        guard inside else { return }
        wake()
        if !reduceMotion { hoverStart = .now }
    }

    private func pet() {
        wake()
        if tracksNeeds { PetStore.apply(fields) { $0.petted() } }
        nextHeart += 1
        hearts.append(nextHeart)
        if hearts.count > 4 { hearts.removeFirst() }
        guard !reduceMotion else { return }
        if tapTracker.tap(at: ProcessInfo.processInfo.systemUptime) {
            danceStart = .now
        } else {
            clickStart = .now
        }
    }

    private func gulp() {
        wake()
        if !reduceMotion { gulpStart = .now }
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
        guard visible, !reduceMotion else {
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

    private func sleepLoop() async {
        guard visible else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !asleep, !hovering else { continue }
            let hour = Calendar.current.component(.hour, from: .now)
            if PetLogic.shouldSleep(idle: Date.now.timeIntervalSince(lastInteraction), hour: hour) { asleep = true }
        }
    }

    private func idleLoop() async {
        guard visible else { return }
        var untilLook = Double.random(in: 5...9)
        var untilWander = Double.random(in: 18...35)
        while !Task.isCancelled {
            let wait = Double.random(in: 2...5)
            try? await Task.sleep(for: .seconds(wait))
            if !asleep {
                blinking = true
                try? await Task.sleep(for: .milliseconds(140))
                blinking = false
            }
            guard !reduceMotion, !asleep else { continue }
            untilLook -= wait
            untilWander -= wait
            if untilLook <= 0 {
                untilLook = Double.random(in: 5...9)
                withAnimation(.easeInOut(duration: 0.3)) {
                    lookGaze = PetVector(x: .random(in: -1...1), y: .random(in: -0.6...0.6))
                }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 0.3)) { lookGaze = .zero }
            }
            if untilWander <= 0, !hovering {
                untilWander = Double.random(in: 18...35)
                // Stay inside the cell: the body only leaves a small margin on each side.
                let reach = max((size.width - Tokens.Tool.unit(size) * 0.78) / 2 - 2, 0)
                let target = CGFloat.random(in: -reach...reach)
                withAnimation(.easeInOut(duration: 1.4)) { wanderX = target }
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeInOut(duration: 1.4)) { wanderX = 0 }
            }
        }
    }
}
