import AppKit
import HarborCore
import SwiftUI

struct TimerWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    private var end: Date? { widget.stateDouble("endDate").map { Date(timeIntervalSince1970: $0) } }
    private var total: TimeInterval { widget.stateDouble("total") ?? Double(ToolActions.timerMinutes(widget) * 60) }
    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dock.id) }

    @State private var overlayMinutes = 0
    @State private var overlayVisible = false
    @State private var overlayTask: Task<Void, Never>?

    var body: some View {
        let unit = Tokens.Tool.unit(size)
        let look = Appearance.shared
        let accent = look.dockAccent(for: .timer)
        // Still while idle, once it has run out and while the dock is hidden, so it costs no redraws then.
        TimelineView(CountdownSchedule(end: end, active: !state.contentHidden)) { context in
            let remaining = end.map { TimerLogic.remaining(end: $0, now: context.date) } ?? total
            let progress = end.map { TimerLogic.progress(end: $0, now: context.date, total: total) } ?? 1
            let finished = end != nil && remaining == 0
            ZStack {
                Circle().stroke(look.themesDocks ? accent.opacity(0.25) : Tokens.Tool.ringTrack, lineWidth: Tokens.Tool.ringWidth(unit))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(finished ? Tokens.success : accent,
                            style: StrokeStyle(lineWidth: Tokens.Tool.ringWidth(unit), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(TimerLogic.clock(remaining))
                        .font(.system(size: unit * 0.24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Tokens.text)
                    let caption = widget.string("caption", "")
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: max(unit * 0.13, 7)))
                            .lineLimit(1)
                            .foregroundStyle(Tokens.textMuted)
                    }
                }
                .padding(.horizontal, unit * 0.14)
            }
            .padding(Tokens.Tool.ringWidth(unit) / 2 + unit * 0.04)
            .frame(width: size.width, height: size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timer")
            .accessibilityValue(finished ? Copy.timerDone(model.playful) : (end == nil ? "Ready, \(TimerLogic.clock(remaining))" : "\(TimerLogic.clock(remaining)) left"))
            .accessibilityHint(end == nil ? "Starts the timer" : "Stops and resets the timer")
            .accessibilityAddTraits(.isButton)
        }
        .overlay { bigDuration(unit: unit) }
        .background(
            ScrollCatcher { steps, shift in scroll(steps: steps, shift: shift) }
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if end == nil { ToolActions.startTimer(fields) } else { ToolActions.stopTimer(fields) }
        }
        // Keyed on the end date so a restart or a stop cancels any pending chime.
        .task(id: end) { await chimeWhenDone() }
    }

    private func bigDuration(unit: CGFloat) -> some View {
        Text("\(overlayMinutes)m")
            .font(.system(size: unit * 0.4, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(Tokens.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Circle().fill(Tokens.surface).padding(unit * 0.04))
            .opacity(overlayVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: overlayVisible)
            .allowsHitTesting(false)
    }

    private func scroll(steps: Int, shift: Bool) {
        let current = fields.current
        let before = ToolActions.timerMinutes(current)
        let next = TimerScroll.adjusted(minutes: before, steps: steps, shift: shift)
        if next != before {
            fields.set("minutes", .number(Double(next)))
            // A finished timer has nothing left to shift; only the setting changes.
            if let end = current.stateDouble("endDate").map({ Date(timeIntervalSince1970: $0) }),
               TimerLogic.remaining(end: end, now: Date()) > 0 {
                let total = current.stateDouble("total") ?? Double(before * 60)
                let moved = TimerScroll.shifted(end: end, total: total, now: Date(), byMinutes: next - before)
                fields.setStates(["endDate": .number(moved.end.timeIntervalSince1970), "total": .number(moved.total)])
            }
        }
        overlayMinutes = next
        overlayVisible = true
        overlayTask?.cancel()
        overlayTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            overlayVisible = false
        }
    }

    /// Quarter-second ticks up to the end date, which is the last entry, so the finished face is drawn once.
    private struct CountdownSchedule: TimelineSchedule {
        let end: Date?
        let active: Bool

        func entries(from start: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
            guard active, let end, end > start else { return AnySequence([start]) }
            return AnySequence(sequence(first: start) { $0 < end ? min($0 + 0.25, end) : nil })
        }
    }

    private func chimeWhenDone() async {
        guard let end else { return }
        let wait = end.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        if wait > 0 && !Task.isCancelled { Celebration.shared.play(dock: dock.id) }
        let sound = NSSound(named: NSSound.Name(widget.string("sound", "Glass")))
        while !Task.isCancelled {
            sound?.stop()
            sound?.play()
            guard widget.bool("repeat", false) else { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
