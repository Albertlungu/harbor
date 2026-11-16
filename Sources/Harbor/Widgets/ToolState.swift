import AppKit
import HarborCore
import SwiftUI

extension WidgetConfig {
    func stateDouble(_ key: String) -> Double? { state[key]?.doubleValue }
}

extension WidgetFields {
    /// Writes several state keys in one store update so observers see a consistent snapshot.
    func setStates(_ values: [String: JSONValue?]) {
        model.store.updateItem(itemID, in: dockID) { item in
            for (key, value) in values { item.widget?.state[key] = value }
        }
    }
}

/// Actions shared by a widget's click handler and its right-click menu.
@MainActor
enum ToolActions {
    static func timerMinutes(_ widget: WidgetConfig) -> Int {
        TimerLogic.minutes(widget.double("minutes", Double(TimerLogic.defaultMinutes)))
    }

    static func startTimer(_ fields: WidgetFields) {
        let seconds = Double(timerMinutes(fields.current) * 60)
        fields.setStates([
            "endDate": .number(Date().addingTimeInterval(seconds).timeIntervalSince1970),
            "total": .number(seconds),
        ])
    }

    static func stopTimer(_ fields: WidgetFields) {
        fields.setStates(["endDate": nil, "total": nil])
    }

    static func timerIsActive(_ widget: WidgetConfig) -> Bool { widget.stateDouble("endDate") != nil }

    static func bumpClicker(_ fields: WidgetFields, increase: Bool) {
        let widget = fields.current
        let step = ClickerLogic.step(widget.double("step", 1))
        let count = Int(widget.stateDouble("count") ?? 0)
        fields.setStates(["count": .number(Double(ClickerLogic.next(count: count, step: step, increase: increase)))])
    }

    static func confirmResetClicker(_ fields: WidgetFields) {
        let alert = NSAlert()
        alert.messageText = "Reset the count to zero?"
        alert.informativeText = "The current count will be lost."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            fields.setStates(["count": .number(0)])
        }
    }
}
