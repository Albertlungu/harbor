import HarborCore
import SwiftUI

extension AppModel {
    /// A binding into one field of a stored dock.
    func bind<T>(_ id: UUID, _ keyPath: WritableKeyPath<Dock, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { self.store.dock(id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.store.updateDock(id) { $0[keyPath: keyPath] = value } }
        )
    }

    /// A binding into one field of the app-wide settings.
    func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.store.settings[keyPath: keyPath] },
            set: { value in self.store.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

extension Dock {
    @MainActor subscript<T>(binding model: AppModel, _ keyPath: WritableKeyPath<Dock, T>) -> Binding<T> {
        model.bind(id, keyPath, fallback: self[keyPath: keyPath])
    }
}

/// A segmented preset picker that reveals a slider when Custom is chosen.
struct PresetPicker<Preset: Hashable & CaseIterable & RawRepresentable>: View where Preset.RawValue == String, Preset.AllCases: RandomAccessCollection {
    let title: String
    @Binding var preset: Preset
    let custom: Preset?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var titles: [Preset: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Picker(title, selection: $preset) {
                ForEach(Array(Preset.allCases), id: \.self) { p in
                    Text(titles[p] ?? p.rawValue.capitalized).tag(p)
                }
            }
            .pickerStyle(.segmented)
            if let custom, preset == custom {
                HStack {
                    Slider(value: $value, in: range)
                    Text("\(value, specifier: range.upperBound <= 10 ? "%.1f" : "%.0f") \(unit)")
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.leading, 120)
            }
        }
    }
}

/// A slider row with its current value.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format = "%.0f"
    var unit = ""

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                Text("\(String(format: format, value))\(unit)").monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
    }
}

extension String {
    /// "cycleWindows" -> "Cycle windows".
    var spacedTitle: String {
        var out = ""
        for ch in self {
            if ch.isUppercase, !out.isEmpty { out += " " + ch.lowercased() } else { out.append(ch) }
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}
