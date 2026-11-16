import HarborCore
import SwiftUI

/// Bindings into one widget's stored settings and state, for settings forms and widget views.
@MainActor
struct WidgetFields {
    let model: AppModel
    let itemID: UUID
    let dockID: UUID

    var current: WidgetConfig {
        model.store.dock(dockID)?.items.first { $0.id == itemID }?.widget ?? WidgetConfig(kind: .spacer)
    }

    func set(_ key: String, _ value: JSONValue?) {
        model.store.updateItem(itemID, in: dockID) { $0.widget?.settings[key] = value }
    }

    func setState(_ key: String, _ value: JSONValue?) {
        model.store.updateItem(itemID, in: dockID) { $0.widget?.state[key] = value }
    }

    func string(_ key: String, _ fallback: String) -> Binding<String> {
        Binding(get: { current.string(key, fallback) }, set: { set(key, .string($0)) })
    }

    func bool(_ key: String, _ fallback: Bool) -> Binding<Bool> {
        Binding(get: { current.bool(key, fallback) }, set: { set(key, .bool($0)) })
    }

    func double(_ key: String, _ fallback: Double) -> Binding<Double> {
        Binding(get: { current.double(key, fallback) }, set: { set(key, .number($0)) })
    }

    func color(_ key: String, _ fallback: Color) -> Binding<Color> {
        Binding(get: { colorSetting(current, key) ?? fallback }, set: { set(key, colorValue($0)) })
    }
}
