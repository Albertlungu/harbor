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

    @State private var blinking = false
    @State private var wiggleStart: Date?
    @State private var hearts: [Int] = []
    @State private var nextHeart = 0

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dock.id) }
    private var tracksNeeds: Bool { widget.bool("needs", false) }

    var body: some View {
        let unit = Tokens.Tool.unit(size)
        let needs = PetStore.stored(widget)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bob = reduceMotion ? 0 : sin(t * 1.8) * unit * 0.02
            ZStack {
                seal(unit: unit, wiggle: wiggle(at: context.date))
                    .offset(y: bob)
                ForEach(hearts, id: \.self) { id in
                    FloatingHeart(unit: unit, reduceMotion: reduceMotion) { hearts.removeAll { $0 == id } }
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
        .onTapGesture { pet() }
        .onAppear { if tracksNeeds { PetStore.resume(fields) } }
        .onDisappear { if tracksNeeds { PetStore.pause(fields) } }
        .task { await settleLoop() }
        .task { await idleLoop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widget.string("name", "Pup"))
        .accessibilityValue(tracksNeeds
            ? "Happiness \(Int(needs.happiness)), hunger \(Int(needs.hunger)), energy \(Int(needs.energy))"
            : "")
        .accessibilityHint("Pets it")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Drawing

    private func seal(unit: CGFloat, wiggle: Double) -> some View {
        let bodyWidth = unit * 0.78
        let bodyHeight = unit * 0.62
        return ZStack {
            // Flippers sit behind the body so only their tips show.
            Ellipse().fill(Tokens.dockSolid)
                .overlay(Ellipse().stroke(Tokens.textMuted.opacity(0.5), lineWidth: 1))
                .frame(width: unit * 0.2, height: unit * 0.12)
                .rotationEffect(.degrees(-25))
                .offset(x: -bodyWidth * 0.5, y: bodyHeight * 0.18)
            Ellipse().fill(Tokens.dockSolid)
                .overlay(Ellipse().stroke(Tokens.textMuted.opacity(0.5), lineWidth: 1))
                .frame(width: unit * 0.2, height: unit * 0.12)
                .rotationEffect(.degrees(25))
                .offset(x: bodyWidth * 0.5, y: bodyHeight * 0.18)
            RoundedRectangle(cornerRadius: bodyHeight * 0.5, style: .continuous)
                .fill(Tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: bodyHeight * 0.5, style: .continuous)
                    .strokeBorder(Tokens.textMuted.opacity(0.5), lineWidth: 1))
                .frame(width: bodyWidth, height: bodyHeight)
            // Soft cheeks are the single accent.
            Circle().fill(Tokens.accent.opacity(0.28))
                .frame(width: unit * 0.1, height: unit * 0.1)
                .offset(x: -unit * 0.2, y: unit * 0.06)
            Circle().fill(Tokens.accent.opacity(0.28))
                .frame(width: unit * 0.1, height: unit * 0.1)
                .offset(x: unit * 0.2, y: unit * 0.06)
            eye.offset(x: -unit * 0.13, y: -unit * 0.02)
            eye.offset(x: unit * 0.13, y: -unit * 0.02)
            Ellipse().fill(Tokens.text)
                .frame(width: unit * 0.07, height: unit * 0.045)
                .offset(y: unit * 0.06)
        }
        .rotationEffect(.degrees(wiggle))
        .padding(.bottom, tracksNeeds ? unit * 0.06 : 0)
    }

    private var eye: some View {
        let unit = Tokens.Tool.unit(size)
        return Ellipse().fill(Tokens.text)
            .frame(width: unit * 0.07, height: blinking ? unit * 0.012 : unit * 0.07)
    }

    private func wiggle(at date: Date) -> Double {
        guard !reduceMotion, let start = wiggleStart else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        guard elapsed < 0.9 else { return 0 }
        return sin(elapsed * 22) * 7 * (1 - elapsed / 0.9)
    }

    // MARK: Behavior

    private func pet() {
        if tracksNeeds { PetStore.apply(fields) { $0.petted() } }
        nextHeart += 1
        hearts.append(nextHeart)
        if hearts.count > 4 { hearts.removeFirst() }
        if !reduceMotion { wiggleStart = .now }
    }

    /// Settles drift on a slow beat while visible so a quit mid-session loses at most a minute.
    private func settleLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if tracksNeeds { PetStore.settle(fields) }
        }
    }

    private func idleLoop() async {
        var untilWiggle = Double.random(in: 8...16)
        while !Task.isCancelled {
            let wait = Double.random(in: 2...5)
            try? await Task.sleep(for: .seconds(wait))
            blinking = true
            try? await Task.sleep(for: .milliseconds(140))
            blinking = false
            untilWiggle -= wait
            if untilWiggle <= 0 {
                if !reduceMotion { wiggleStart = .now }
                untilWiggle = Double.random(in: 8...16)
            }
        }
    }
}

private struct FloatingHeart: View {
    let unit: CGFloat
    let reduceMotion: Bool
    let done: () -> Void

    @State private var risen = false
    @State private var xOffset = CGFloat.random(in: -0.15...0.15)

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: unit * 0.16))
            .foregroundStyle(Tokens.accent)
            .offset(x: xOffset * unit, y: risen && !reduceMotion ? -unit * 0.4 : -unit * 0.1)
            .opacity(risen ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) { risen = true } completion: { done() }
            }
            .accessibilityHidden(true)
    }
}
