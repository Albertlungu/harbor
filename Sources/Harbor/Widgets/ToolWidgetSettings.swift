import HarborCore
import SwiftUI

/// Form rows for the tool widgets, placed inside the caller's Form.
struct ToolWidgetSettings: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dockID: UUID

    private var fields: WidgetFields { WidgetFields(model: model, itemID: item.id, dockID: dockID) }

    var body: some View {
        switch item.widget?.kind {
        case .clicker?: clicker
        case .timer?: TimerSettings(fields: fields)
        case .metronome?: MetronomeSettings(fields: fields)
        case .pet?: pet
        case .spaceAwareness?:
            if fields.current.string("mode", "apps") == "indicator" {
                Picker("Style", selection: fields.string("style", "dots")) {
                    Text("Dots").tag("dots")
                    Text("Number").tag("number")
                }
                .pickerStyle(.segmented)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var clicker: some View {
        Stepper("Step per click: \(ClickerLogic.step(fields.current.double("step", 1)))",
                value: fields.double("step", 1), in: 1...100, step: 1)
        Toggle("Allow decrease", isOn: fields.bool("allowDecrease", false))
        TextField("Caption", text: fields.string("caption", ""))
        ToolColorRow(title: "Chip color", key: "chipColor", fields: fields)
        ToolColorRow(title: "Number color", key: "numberColor", fields: fields)
    }

    @ViewBuilder
    private var pet: some View {
        TextField("Name", text: fields.string("name", "Pup"))
        Picker("Size", selection: fields.double("cells", 1)) {
            Text("Regular").tag(1.0)
            Text("Medium").tag(2.0)
            Text("Large").tag(3.0)
        }
        .pickerStyle(.segmented)
        Toggle("Track happiness, hunger and energy", isOn: fields.bool("needs", false))
        PetAppearanceSettings(fields: fields)
        PetRoamSettings(fields: fields)
    }
}

private struct PetRoamSettings: View {
    let fields: WidgetFields

    var body: some View {
        let widget = fields.current
        Section("Roaming") {
            Picker("Default mode", selection: Binding(
                get: { widget.roamMode },
                set: { fields.setState("roamMode", .string($0.rawValue)) })) {
                ForEach(RoamMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Stepper("Size: \(Int(widget.roamSize)) pt", value: Binding(
                get: { widget.roamSize },
                set: { fields.setState("roamSize", .number($0)) }), in: 24...48, step: 2)
            Toggle("Walk on window tops", isOn: fields.bool("roamWindows", true))
            Picker("Allowed screens", selection: fields.string("roamScreens", "all")) {
                Text("All screens").tag("all")
                Text("The dock's own screen").tag("own")
            }
        }
    }
}

private struct ToolColorRow: View {
    let title: String
    let key: String
    let fields: WidgetFields

    var body: some View {
        HStack {
            ColorPicker(title, selection: fields.color(key, Tokens.text))
            if fields.current.settings[key] != nil {
                Button("Default") { fields.set(key, nil) }
            }
        }
    }
}

private struct TimerSettings: View {
    let fields: WidgetFields
    @State private var custom: Bool

    private static let presets = [5, 10, 15, 25, 60]

    init(fields: WidgetFields) {
        self.fields = fields
        _custom = State(initialValue: !Self.presets.contains(ToolActions.timerMinutes(fields.current)))
    }

    private var minutes: Int { ToolActions.timerMinutes(fields.current) }

    var body: some View {
        Picker("Duration", selection: Binding(
            get: { custom ? -1 : minutes },
            set: { value in
                custom = value == -1
                if value != -1 { fields.set("minutes", .number(Double(value))) }
            })) {
            ForEach(Self.presets, id: \.self) { Text("\($0) min").tag($0) }
            Text("Custom").tag(-1)
        }
        if custom {
            Stepper("Minutes: \(minutes)", value: fields.double("minutes", 5), in: 1...180, step: 1)
        }
        TextField("Caption", text: fields.string("caption", ""))
        Picker("Sound", selection: fields.string("sound", "Glass")) {
            ForEach(["Glass", "Ping", "Hero", "Submarine", "Funk"], id: \.self) { Text($0).tag($0) }
        }
        Toggle("Keep chiming until stopped", isOn: fields.bool("repeat", false))
    }
}

private struct MetronomeSettings: View {
    let fields: WidgetFields
    @State private var tapper = MetronomeLogic.TapTempo()

    var body: some View {
        let widget = fields.current
        Stepper("Tempo: \(MetronomeLogic.bpm(widget.double("bpm", 100))) BPM",
                value: fields.double("bpm", 100), in: 30...300, step: 1)
        Button("Tap Tempo") {
            if let bpm = tapper.tap(at: ProcessInfo.processInfo.systemUptime) {
                fields.set("bpm", .number(Double(bpm)))
            }
        }
        Stepper("Beats per measure: \(MetronomeLogic.beats(widget.double("beats", 4)))",
                value: fields.double("beats", 4), in: 1...12, step: 1)
        Toggle("Accent first beat", isOn: fields.bool("accent", true))
        ValueSlider(title: "Volume", value: fields.double("volume", 0.7), range: 0...1, format: "%.2f")
    }
}
