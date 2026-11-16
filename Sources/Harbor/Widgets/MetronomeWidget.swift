import HarborCore
import SwiftUI

struct MetronomeWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var taps = MetronomeInput.TapSequence()
    @State private var ringTrigger = 0
    @State private var overlayBPM = MetronomeLogic.defaultBPM
    @State private var overlayVisible = false
    @State private var overlayTask: Task<Void, Never>?
    @Environment(\.dockEdge) private var dockEdge
    @State private var hintVisible = false
    @State private var hintTask: Task<Void, Never>?
    // Swing is derived from the time of the last beat, so the bob is at an extreme exactly on each click.
    @State private var lastTickTime = Date()
    @State private var tickInterval = MetronomeLogic.beatInterval(bpm: MetronomeLogic.defaultBPM)

    private static let hintText = "Click to start. Tap in rhythm to set tempo. Scroll to adjust."
    private static let overlayLinger: Duration = .seconds(1)
    private static let hintLinger: Duration = .seconds(3)

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dock.id) }
    private var bpm: Int { MetronomeLogic.bpm(widget.double("bpm", Double(MetronomeLogic.defaultBPM))) }
    private var beats: Int { MetronomeLogic.beats(widget.double("beats", Double(MetronomeLogic.defaultBeats))) }

    var body: some View {
        let engine = MetronomeEngines.engine(for: item.id)
        let unit = Tokens.Tool.unit(size)
        let radius = Tokens.Tool.chipRadius(unit)
        VStack(spacing: unit * 0.05) {
            pendulum(engine: engine, unit: unit)
            Text("\(bpm)")
                .font(.system(size: unit * 0.22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Tokens.text)
            HStack(spacing: unit * 0.04) {
                ForEach(0..<beats, id: \.self) { index in
                    Circle()
                        .fill(engine.isRunning && engine.beat == index ? Tokens.accent : Tokens.border)
                        .frame(width: unit * 0.07, height: unit * 0.07)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Tokens.border, lineWidth: 1))
                .padding(unit * 0.04)
        )
        .overlay { tapRing(unit: unit) }
        .overlay { bigNumber(unit: unit, radius: radius) }
        .background(
            ScrollCatcher { steps, shift in scroll(steps: steps, shift: shift, engine: engine) }
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onTapGesture { tap(engine) }
        .onHover { inside in if inside { revealHintOnce() } }
        .overlay(alignment: hintAlignment) { hint(unit: unit) }
        .onChange(of: engine.tick) { tickInterval = MetronomeLogic.beatInterval(bpm: bpm); lastTickTime = Date() }
        .onChange(of: settingsKey, initial: true) { configure(engine) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Metronome")
        .accessibilityValue("\(bpm) beats per minute, \(beats) beats, \(engine.isRunning ? "playing" : "stopped")")
        .accessibilityHint(engine.isRunning ? "Stops the metronome" : "Starts the metronome")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Drawing

    private func pendulum(engine: MetronomeEngine, unit: CGFloat) -> some View {
        let rod = unit * 0.3
        let bob = unit * 0.13
        let running = engine.isRunning
        let accented = running && engine.beat == 0 && widget.bool("accent", true)
        return TimelineView(.animation(paused: !running)) { context in
            let progress = running ? min(max(context.date.timeIntervalSince(lastTickTime) / tickInterval, 0), 1) : 0
            // Alternating sides per beat; cos eases the turn-around like a real pendulum.
            let side: Double = engine.tick.isMultiple(of: 2) ? 1 : -1
            let angle = running && !reduceMotion ? side * 24 * cos(.pi * progress) : 0
            // With Reduce Motion the bob stays put and only its opacity pulses on the beat.
            let opacity = running && reduceMotion ? 1 - 0.6 * progress : 1
            VStack(spacing: 0) {
                Circle()
                    .fill(accented ? Tokens.accent : (running ? Tokens.text : Tokens.textMuted.opacity(0.5)))
                    .frame(width: bob, height: bob)
                    .scaleEffect(accented ? 1.3 : 1)
                    .opacity(opacity)
                Capsule()
                    .fill(Tokens.textMuted.opacity(0.6))
                    .frame(width: max(unit * 0.03, 1.5), height: rod)
            }
            .frame(height: rod + bob, alignment: .top)
            .rotationEffect(.degrees(angle), anchor: .bottom)
        }
        .frame(height: rod + bob * 1.3)
    }

    private func tapRing(unit: CGFloat) -> some View {
        let start = reduceMotion ? 1.0 : 0.7
        let end = reduceMotion ? 1.0 : 1.2
        return Circle()
            .strokeBorder(Tokens.accent, lineWidth: Tokens.Tool.ringWidth(unit) * 0.6)
            .frame(width: unit * 0.8, height: unit * 0.8)
            .keyframeAnimator(initialValue: RingValue(scale: start, opacity: 0), trigger: ringTrigger) { content, value in
                content.scaleEffect(value.scale).opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(start, duration: 0.001)
                    CubicKeyframe(end, duration: 0.35)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.9, duration: 0.001)
                    LinearKeyframe(0, duration: 0.35)
                }
            }
            .allowsHitTesting(false)
    }

    private func bigNumber(unit: CGFloat, radius: CGFloat) -> some View {
        Text("\(overlayBPM)")
            .font(.system(size: unit * 0.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(Tokens.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Tokens.surface).padding(unit * 0.04))
            .opacity(overlayVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: overlayVisible)
            .allowsHitTesting(false)
    }

    private var hintAlignment: Alignment {
        switch dockEdge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    private var hintOffset: CGSize {
        switch dockEdge {
        case .bottom: CGSize(width: 0, height: -size.height * 0.75)
        case .top: CGSize(width: 0, height: size.height * 0.75)
        case .left: CGSize(width: size.width * 0.75, height: 0)
        case .right: CGSize(width: -size.width * 0.75, height: 0)
        }
    }

    private func hint(unit: CGFloat) -> some View {
        Text(Self.hintText)
            .font(.system(size: max(unit * 0.17, 10)))
            .foregroundStyle(Tokens.text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Tokens.surface).overlay(Capsule().strokeBorder(Tokens.border, lineWidth: 1)))
            // Sits on the dock's inward side, where hover labels go, so it is never off screen.
            .offset(hintOffset)
            .opacity(hintVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: hintVisible)
            .allowsHitTesting(false)
    }

    // MARK: Input

    private func tap(_ engine: MetronomeEngine) {
        let result = taps.tap(at: ProcessInfo.processInfo.systemUptime)
        ringTrigger += 1
        guard let tempo = result.bpm else {
            engine.toggle()
            return
        }
        // From the second tap the click is tap tempo, not a toggle: set the tempo and restart so beat one
        // lands on this tap. Restarting also covers the case where the first tap had stopped a running beat.
        fields.set("bpm", .number(Double(tempo)))
        configure(engine, bpm: tempo)
        engine.restart()
        showOverlay(tempo)
    }

    private func scroll(steps: Int, shift: Bool, engine: MetronomeEngine) {
        let current = MetronomeLogic.bpm(fields.current.double("bpm", Double(MetronomeLogic.defaultBPM)))
        let next = MetronomeInput.adjusted(bpm: current, steps: steps, shift: shift)
        if next != current {
            fields.set("bpm", .number(Double(next)))
            // The engine reads its tempo when it queues the next beat, so a running metronome changes
            // on the first beat not already queued instead of cutting the current one short.
            configure(engine, bpm: next)
        }
        showOverlay(next)
    }

    private func showOverlay(_ value: Int) {
        overlayBPM = value
        overlayVisible = true
        overlayTask?.cancel()
        overlayTask = Task {
            try? await Task.sleep(for: Self.overlayLinger)
            guard !Task.isCancelled else { return }
            overlayVisible = false
        }
    }

    private func revealHintOnce() {
        guard fields.current.state["hintShown"]?.boolValue != true else { return }
        fields.setState("hintShown", .bool(true))
        hintVisible = true
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: Self.hintLinger)
            guard !Task.isCancelled else { return }
            hintVisible = false
        }
    }

    // MARK: Engine

    private var settingsKey: [Double] {
        [Double(bpm), Double(beats), widget.bool("accent", true) ? 1 : 0, MetronomeLogic.volume(widget.double("volume", 0.7))]
    }

    private func configure(_ engine: MetronomeEngine, bpm override: Int? = nil) {
        let current = fields.current
        engine.configure(bpm: override ?? bpm,
                         beats: MetronomeLogic.beats(current.double("beats", Double(MetronomeLogic.defaultBeats))),
                         accent: current.bool("accent", true),
                         volume: MetronomeLogic.volume(current.double("volume", 0.7)))
    }
}

private struct RingValue {
    var scale: Double
    var opacity: Double
}
