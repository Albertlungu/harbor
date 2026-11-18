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
                Picker("Quality", selection: model.setting(\.weather.quality)) {
                    ForEach(WeatherQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                note("Smooth moves at 30 frames a second, Balanced at 20 and Light at 15 with half as much falling, which is easiest on the battery.")
                Button(Self.clearTitle(weather.season(at: .now))) { WeatherController.shared.clear() }
            }
            .disabled(!weather.enabled)
        }
    }

    private func playNote(_ season: Season) -> String {
        switch season {
        case .winter: "Drag a drift to roll a snowball, then let go to throw it. Stack three, biggest first, for a snowman. Click snow to kick it; hold still on it to make an angel."
        case .autumn: "Drag along a pile to rake the leaves into a heap, or lift up out of it to grab a handful and toss it. Click a pile to kick it; a quick flick scatters it."
        case .spring: "Grab a handful of petals and throw them, click puddles to splash, and pick a flower to replant it somewhere else. Flowers come up where rain has puddled."
        case .summer: "Click bubbles to pop them, push them along, or drag one to blow it bigger. Seeds drift away from the pointer; in the evening, click fireflies to catch them for a moment."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(Tokens.textMuted)
    }
}

/// The "Desktop Weather" submenu of the menu bar menu.
extension SeasonsSettings {
    /// Names what will be swept away, so it can't be mistaken for clearing files off the desktop.
    static func clearTitle(_ season: Season) -> String {
        switch season {
        case .winter: "Clear All Snow"
        case .autumn: "Clear All Leaves"
        case .spring: "Clear Petals and Puddles"
        case .summer: "Clear Seeds and Bubbles"
        }
    }
}

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
            Button(SeasonsSettings.clearTitle(weather.season(at: .now))) { WeatherController.shared.clear() }
                .disabled(!weather.enabled)
        }
    }
}
