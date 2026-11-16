import AppKit
import HarborCore
import SwiftUI

/// Right-click entries for the system widgets.
struct SystemWidgetMenu: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dock: Dock

    var body: some View {
        switch item.widget?.kind {
        case .ipAddress?:
            Button("Refresh Now") { Task { await IPAddressModel.shared.refresh() } }
            Button("Copy Public") {
                Task {
                    if let address = await IPAddressModel.shared.currentPublic() { copy(address) } else { model.flashHint("Offline") }
                }
            }
            Button("Copy Local") {
                if let address = IPAddressModel.shared.currentLocal() { copy(address) } else { model.flashHint("No network") }
            }
        case .bluetoothBattery?:
            Button("Refresh Now") { Task { await BluetoothModel.shared.refresh() } }
        default:
            Button("Refresh Now") { SystemSampler.shared.refresh() }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.flashHint("Copied")
    }
}

/// Settings for the system widgets, used inside the widget settings form.
struct SystemWidgetSettings: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dockID) }
    private var current: WidgetConfig { fields.current }

    var body: some View {
        switch item.widget?.kind {
        case .ipAddress?: ip
        case .bluetoothBattery?: bluetooth
        case .battery?: monitor(showTextColor: false)
        default: monitor(showTextColor: true)
        }
    }

    // MARK: Monitor

    @ViewBuilder
    private func monitor(showTextColor: Bool) -> some View {
        Picker("Color", selection: fields.string("colorMode", "auto")) {
            Text("Automatic").tag("auto")
            Text("Fixed").tag("fixed")
        }
        if current.string("colorMode", "auto") == "fixed" {
            ColorPicker("Fixed color", selection: fields.color("fixedColor", Tokens.accent))
        }
        if showTextColor {
            Picker("Text color", selection: fields.string("textMode", "auto")) {
                Text("Automatic").tag("auto")
                Text("White").tag("white")
                Text("Black").tag("black")
                Text("Custom").tag("custom")
            }
            if current.string("textMode", "auto") == "custom" {
                ColorPicker("Custom text color", selection: fields.color("textColor", Tokens.text))
            }
        }
        Toggle("Show label", isOn: fields.bool("showLabel", true))
        ValueSlider(title: "Number size", value: fields.double("numberSize", 1), range: 0.6...1.4, format: "%.1f", unit: "x")
        Picker("Refresh rate", selection: fields.string("refresh", "normal")) {
            Text("Fast (1 s)").tag("fast")
            Text("Normal (2 s)").tag("normal")
            Text("Relaxed (5 s)").tag("relaxed")
            Text("Power Saver (10 s)").tag("powerSaver")
        }
    }

    // MARK: IP

    @ViewBuilder
    private var ip: some View {
        Picker("Show", selection: fields.string("mode", "public")) {
            Text("Public address").tag("public")
            Text("Local address").tag("local")
            Text("Both").tag("both")
        }
    }

    // MARK: Bluetooth

    @ViewBuilder
    private var bluetooth: some View {
        Stepper("Maximum devices: \(Int(current.double("maxDevices", 4)))", value: fields.double("maxDevices", 4), in: 1...12, step: 1)
        Toggle("Include offline devices (dimmed)", isOn: fields.bool("includeOffline", false))
        Toggle("Include devices with no battery", isOn: fields.bool("includeNoBattery", false))
        Toggle("Split AirPods into left, right and case", isOn: fields.bool("splitAirPods", false))
        ValueSlider(title: "Low battery below", value: fields.double("lowBattery", 20), range: 5...50, unit: "%")
        Stepper("Refresh every \(Int(current.double("minutes", 1))) min", value: fields.double("minutes", 1), in: 1...15, step: 1)
        Picker("Clicking it", selection: fields.string("click", "open")) {
            Text("Opens Bluetooth settings").tag("open")
            Text("Refreshes now").tag("refresh")
            Text("Does nothing").tag("none")
        }
    }
}
