import HarborCore
import SwiftUI

/// Per-instance settings for a widget, shown in the item sheet and the setup panel.
struct WidgetSettingsForm: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID

    var body: some View {
        Form {
            switch item.widget?.kind {
            case .clock?: clock
            case .spacer?: spacer
            case .divider?: divider
            case .label?: label
            case .liveDock?, .runningApps?: appList
            case .spaceAwareness?:
                appList
                ToolWidgetSettings(item: item, dockID: dockID)
            case .battery?, .cpu?, .memory?, .gpu?, .ipAddress?, .bluetoothBattery?:
                SystemWidgetSettings(item: item, dockID: dockID)
            case .finder?, .link?, .folderStack?, .appStack?, .shelf?, .fileShelf?, .trash?:
                StorageWidgetSettings(item: item, dockID: dockID)
            case .clicker?, .timer?, .metronome?, .pet?:
                ToolWidgetSettings(item: item, dockID: dockID)
            default:
                Text("This widget has no settings yet.").foregroundStyle(Tokens.textMuted)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Forms

    @ViewBuilder
    private var clock: some View {
        Picker("Hours", selection: string("hours", "system")) {
            Text("System").tag("system")
            Text("12-hour").tag("12")
            Text("24-hour").tag("24")
        }
        Toggle("Show seconds", isOn: bool("showSeconds", false))
        Toggle("Show the date", isOn: bool("showDate", false))
        if current.bool("showDate", false) {
            Picker("Date style", selection: string("dateStyle", "short")) {
                Text("Short").tag("short")
                Text("Long").tag("long")
                Text("Custom").tag("custom")
            }
            if current.string("dateStyle", "short") == "custom" {
                TextField("Pattern", text: string("dateFormat", "EEE d"), prompt: Text("EEE d MMM"))
            }
        }
        Picker("Time zone", selection: string("timeZone", "")) {
            Text("This Mac's").tag("")
            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
        }
        Toggle("Show the time zone", isOn: bool("showZone", false))
        Picker("Font", selection: string("font", "system")) {
            Text("System").tag("system")
            Text("Monospaced").tag("mono")
            Text("Rounded").tag("rounded")
        }
        .pickerStyle(.segmented)
        Toggle("Bold", isOn: bool("bold", true))
        color("Text color", "textColor")
        color("Background", "background")
        Picker("Clicking it", selection: string("click", "none")) {
            Text("Does nothing").tag("none")
            Text("Opens Date & Time settings").tag("dateTime")
        }
    }

    @ViewBuilder
    private var spacer: some View {
        Picker("Width", selection: double("cells", 0.25)) {
            Text("Quarter icon").tag(0.25)
            Text("Half icon").tag(0.5)
            Text("One icon").tag(1.0)
            Text("Two icons").tag(2.0)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var divider: some View {
        color("Line color", "color")
    }

    @ViewBuilder
    private var label: some View {
        TextField("Title", text: string("title", "Label"))
        TextField("Second line", text: string("subtitle", ""))
        ValueSlider(title: "Length", value: double("length", 96), range: 24...1200, unit: " pt")
        Picker("Text size", selection: string("textSize", "medium")) {
            Text("Small").tag("small")
            Text("Medium").tag("medium")
            Text("Large").tag("large")
        }
        .pickerStyle(.segmented)
        Picker("Alignment", selection: string("alignment", "center")) {
            Text("Left").tag("left")
            Text("Center").tag("center")
            Text("Right").tag("right")
        }
        .pickerStyle(.segmented)
        Toggle("Run text vertically on side docks", isOn: bool("vertical", true))
        color("Text color", "color")
    }

    @ViewBuilder
    private var appList: some View {
        if item.widget?.kind == .runningApps {
            Toggle("Include apps with no open windows", isOn: bool("showWindowless", true))
        }
        if item.widget?.kind == .spaceAwareness {
            Picker("Show", selection: string("mode", "apps")) {
                Text("Apps on this desktop").tag("apps")
                Text("Which desktop I'm on").tag("indicator")
            }
        }
        let hidden = current.strings("hiddenApps")
        Section("Hidden apps") {
            if hidden.isEmpty {
                Text("Right-click an app on the dock and choose Hide from This Widget.").foregroundStyle(Tokens.textMuted)
            }
            ForEach(hidden, id: \.self) { path in
                HStack {
                    Text(FileManager.default.displayName(atPath: path))
                    Spacer()
                    Button("Show") { set("hiddenApps", .array(hidden.filter { $0 != path }.map(JSONValue.string))) }
                }
            }
            if !hidden.isEmpty {
                Button("Show All") { set("hiddenApps", .array([])) }
            }
        }
    }

    // MARK: Bindings into widget settings

    private var current: WidgetConfig {
        model.store.dock(dockID)?.items.first { $0.id == item.id }?.widget ?? item.widget ?? WidgetConfig(kind: .spacer)
    }

    private func set(_ key: String, _ value: JSONValue?) {
        model.store.updateItem(item.id, in: dockID) { $0.widget?.settings[key] = value }
    }

    private func string(_ key: String, _ fallback: String) -> Binding<String> {
        Binding(get: { current.string(key, fallback) }, set: { set(key, .string($0)) })
    }

    private func bool(_ key: String, _ fallback: Bool) -> Binding<Bool> {
        Binding(get: { current.bool(key, fallback) }, set: { set(key, .bool($0)) })
    }

    private func double(_ key: String, _ fallback: Double) -> Binding<Double> {
        Binding(get: { current.double(key, fallback) }, set: { set(key, .number($0)) })
    }

    @ViewBuilder
    private func color(_ title: String, _ key: String) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { colorSetting(current, key) ?? Tokens.text },
                set: { set(key, colorValue($0)) }))
            if current.settings[key] != nil {
                Button("Default") { set(key, nil) }
            }
        }
    }
}
