import AppKit
import HarborCore
import SwiftUI

struct ScreensSection: View {
    @Environment(AppModel.self) private var model
    let dock: Dock
    @State private var renaming: String?
    @State private var draft = ""

    var body: some View {
        let connected = Set(DockController.connectedScreens().map(\.id))
        Form {
            Section {
                Toggle("Show on every screen", isOn: dock[binding: model, \.screens.showOnAllScreens])
                Text(dock.screens.showOnAllScreens
                     ? "One copy per screen. Editing any copy edits them all."
                     : "Pick screens below. With none picked, the dock uses the main screen. With several, it shows on the first one that's connected.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
            }

            Section("Screens") {
                ForEach(model.store.config.knownScreens) { screen in
                    HStack {
                        Toggle(isOn: assignment(screen.id)) {
                            VStack(alignment: .leading) {
                                if renaming == screen.id {
                                    TextField("Name", text: $draft).onSubmit {
                                        model.store.renameScreen(screen.id, to: draft)
                                        renaming = nil
                                    }
                                } else {
                                    Text(screen.displayName)
                                }
                                Text(connected.contains(screen.id) ? "Connected" : "Not connected · last seen \(screen.lastSeen.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundStyle(connected.contains(screen.id) ? Tokens.success : Tokens.textMuted)
                            }
                        }
                        .disabled(dock.screens.showOnAllScreens)
                        if let index = dock.screens.assignedScreenIDs.firstIndex(of: screen.id), !dock.screens.showOnAllScreens {
                            Text("#\(index + 1)").font(.caption).foregroundStyle(Tokens.textMuted)
                                .help("Order of preference when several assigned screens are connected")
                        }
                    }
                    .contextMenu {
                        Button("Rename") {
                            draft = screen.displayName
                            renaming = screen.id
                        }
                        Button("Forget Screen", role: .destructive) { model.store.forgetScreen(screen.id) }
                            .disabled(connected.contains(screen.id))
                    }
                }
            }

            Section {
                Button("Export Screen Diagnostics…") { Diagnostics.exportScreens(model: model) }
            }
        }
        .formStyle(.grouped)
    }

    private func assignment(_ id: String) -> Binding<Bool> {
        Binding(
            get: { dock.screens.assignedScreenIDs.contains(id) },
            set: { on in
                model.store.updateDock(dock.id) {
                    if on { $0.screens.assignedScreenIDs.append(id) } else { $0.screens.assignedScreenIDs.removeAll { $0 == id } }
                }
            })
    }
}
