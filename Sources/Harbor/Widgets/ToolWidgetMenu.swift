import HarborCore
import SwiftUI

/// Right-click entries for the tool widgets.
struct ToolWidgetMenu: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dock: Dock

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dock.id) }

    var body: some View {
        let widget = fields.current
        switch widget.kind {
        case .clicker?:
            if widget.bool("allowDecrease", false) {
                Button("Decrease") { ToolActions.bumpClicker(fields, increase: false) }
            }
            Button("Reset to Zero…") { ToolActions.confirmResetClicker(fields) }
        case .timer?:
            Button(ToolActions.timerIsActive(widget) ? "Restart" : "Start") { ToolActions.startTimer(fields) }
        case .metronome?:
            let engine = MetronomeEngines.engine(for: item.id)
            Button(engine.isRunning ? "Stop" : "Start") { engine.toggle() }
        case .pet?:
            if widget.bool("needs", false) {
                let needs = PetStore.current(widget, now: .now)
                Button("Feed") { PetStore.apply(fields) { $0.fed() } }
                Button("Play") { PetStore.apply(fields) { $0.played() } }
                Text("Happiness \(Int(needs.happiness))  Hunger \(Int(needs.hunger))  Energy \(Int(needs.energy))")
            }
        default:
            EmptyView()
        }
    }
}
