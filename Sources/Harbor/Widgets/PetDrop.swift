import AppKit
import HarborCore
import Observation
import SwiftUI

/// Lets code outside the pet's view, such as the drop handler, trigger its animations.
@MainActor
@Observable
final class PetReactions {
    static let shared = PetReactions()
    private(set) var feeds: [UUID: Int] = [:]

    func fed(_ id: UUID) { feeds[id, default: 0] += 1 }
}

/// Files dropped on a pet are food. The file itself is never read, moved or deleted.
@MainActor
enum PetDrop {
    static func handle(_ providers: [NSItemProvider], item: DockItem, dock: Dock, model: AppModel) -> Bool {
        guard providers.contains(where: { $0.canLoadObject(ofClass: URL.self) }) else { return false }
        let fields = WidgetFields(model: model, itemID: item.id, dockID: dock.id)
        if fields.current.bool("needs", false) { PetStore.apply(fields) { PetLogic.fed($0) } }
        PetReactions.shared.fed(item.id)
        return true
    }
}
