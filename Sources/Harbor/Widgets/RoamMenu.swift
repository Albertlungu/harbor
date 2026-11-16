import HarborCore
import SwiftUI

/// Roaming commands for one pet, shared by the dock's right-click menu, the roaming window and the menu bar.
struct PetMenuItems: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let dock: Dock

    var body: some View {
        let widget = model.store.dock(dock.id)?.items.first { $0.id == item.id }?.widget
        let coordinator = RoamCoordinator.shared
        if widget?.isRoaming == true {
            Button("Bring it home") {
                coordinator.start(model: model)
                coordinator.bringHome(item: item, dock: dock)
            }
            Menu("Roaming Mode") {
                ForEach(RoamMode.allCases, id: \.self) { mode in
                    Toggle(mode.title, isOn: Binding(get: { widget?.roamMode == mode }, set: { _ in
                        coordinator.setMode(item: item, dock: dock, mode)
                    }))
                }
            }
        } else {
            Menu("Let it roam") {
                ForEach(RoamMode.allCases, id: \.self) { mode in
                    Button(mode.title) {
                        coordinator.start(model: model)
                        coordinator.roam(item: item, dock: dock, mode: mode)
                    }
                }
            }
        }
    }
}

/// The pet's whole right-click menu: its needs and treats, then where it lives.
struct PetContextItems: View {
    let item: DockItem
    let dock: Dock

    var body: some View {
        ToolWidgetMenu(item: item, dock: dock)
        PetMenuItems(item: item, dock: dock)
    }
}

/// The "Pet" submenu of the menu bar menu.
struct PetSubmenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pets = model.store.docks.flatMap { dock in
            dock.items.filter { $0.widget?.kind == .pet }.map { (dock: dock, item: $0) }
        }
        if !pets.isEmpty {
            Menu("Pet") {
                ForEach(pets, id: \.item.id) { pet in
                    if pets.count == 1 {
                        PetMenuItems(item: pet.item, dock: pet.dock)
                    } else {
                        Menu(pet.item.widget?.string("name", "Pup") ?? "Pup") {
                            PetMenuItems(item: pet.item, dock: pet.dock)
                        }
                    }
                }
            }
        }
    }
}
