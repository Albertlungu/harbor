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

    var body: some View {
        let unit = Tokens.Tool.unit(size)
        // Paused while idle so a stopped timer costs no redraws.
        TimelineView(.animation(minimumInterval: 0.25, paused: end == nil)) { context in
            let remaining = end.map { TimerLogic.remaining(end: $0, now: context.date) } ?? total
            let progress = end.map { TimerLogic.progress(end: $0, now: context.date, total: total) } ?? 1
            let finished = end != nil && remaining == 0
            ZStack {
                Circle().stroke(Tokens.Tool.ringTrack, lineWidth: Tokens.Tool.ringWidth(unit))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(finished ? Tokens.success : Tokens.accent,
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
            .accessibilityValue(finished ? "Finished" : (end == nil ? "Ready, \(TimerLogic.clock(remaining))" : "\(TimerLogic.clock(remaining)) left"))
            .accessibilityHint(end == nil ? "Starts the timer" : "Stops and resets the timer")
            .accessibilityAddTraits(.isButton)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if end == nil { ToolActions.startTimer(fields) } else { ToolActions.stopTimer(fields) }
        }
        // Keyed on the end date so a restart or a stop cancels any pending chime.
        .task(id: end) { await chimeWhenDone() }
    }

    private func chimeWhenDone() async {
        guard let end else { return }
        let wait = end.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        let sound = NSSound(named: NSSound.Name(widget.string("sound", "Glass")))
        while !Task.isCancelled {
            sound?.stop()
            sound?.play()
            guard widget.bool("repeat", false) else { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
