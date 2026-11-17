import HarborCore
import SwiftUI

/// Settings › Seasons: the desktop weather.
struct SeasonsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let weather = model.store.settings.weather
        Form {
            Section {
                Toggle("Desktop weather", isOn: model.setting(\.weather.enabled))
                note("Snow, leaves, petals or fireflies on the desktop, settling on top of windows and docks. Hidden while an app is full screen.")
            }

            Section("Season") {
                Picker("Season", selection: model.setting(\.weather.season)) {
                    ForEach(SeasonChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if weather.season == .auto {
                    Toggle("Southern hemisphere", isOn: model.setting(\.weather.southernHemisphere))
                    note("Right now it's \(weather.season(at: .now).title.lowercased()).")
                }
                HStack {
                    Text("Intensity")
                    Slider(value: model.setting(\.weather.intensity), in: 0.05...1)
                }
            }
            .disabled(!weather.enabled)

            Section("Play") {
                Toggle("Let it pile up", isOn: model.setting(\.weather.accumulation))
                Toggle("Play with the pointer", isOn: model.setting(\.weather.interactions))
                note(playNote(weather.season(at: .now)))
                Toggle("Sounds", isOn: model.setting(\.weather.sounds))
                Button("Clear the Desktop") { WeatherController.shared.clear() }
            }
            .disabled(!weather.enabled)
        }
    }

    private func playNote(_ season: Season) -> String {
        switch season {
        case .winter: "Drag a drift to roll a snowball, then let go to throw it. Stack three, biggest first, for a snowman."
        case .autumn: "Drag along a pile to rake the leaves into a heap. A quick flick of the pointer scatters them."
        case .spring: "Drag through fallen petals to sweep them. Flowers come up where rain has puddled."
        case .summer: "Click bubbles to pop them. Seeds drift away from the pointer; fireflies come out in the evening."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(Tokens.textMuted)
    }
}

/// The "Desktop Weather" submenu of the menu bar menu.
struct WeatherSubmenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let weather = model.store.settings.weather
        Menu("Desktop Weather") {
            Toggle("Show Weather", isOn: model.setting(\.weather.enabled))
            Divider()
            ForEach(SeasonChoice.allCases, id: \.self) { choice in
                Toggle(choice.title, isOn: Binding(get: { weather.season == choice }, set: { _ in
                    model.store.updateSettings { $0.weather.season = choice }
                }))
            }
            Divider()
            Toggle("Let It Pile Up", isOn: model.setting(\.weather.accumulation))
            Button("Clear the Desktop") { WeatherController.shared.clear() }
                .disabled(!weather.enabled)
        }
    }
}
