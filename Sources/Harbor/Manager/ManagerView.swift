import AppKit
import HarborCore
import SwiftUI

/// The dock list and the editor for the selected dock.
struct ManagerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            DockSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            if let id = model.selectedDockID, let dock = model.store.dock(id) {
                DockEditor(dock: dock)
            } else if model.store.docks.isEmpty {
                EmptyManager()
            } else {
                ContentUnavailableView("Pick a dock", systemImage: "sidebar.left",
                                       description: Text("Choose a dock on the left to change it."))
            }
        }
        .onAppear {
            if model.selectedDockID == nil { model.selectedDockID = model.store.docks.first?.id }
        }
        .sheet(item: $model.itemSheet) { ref in
            ItemOptionsSheet(ref: ref).environment(model)
        }
    }
}

private struct EmptyManager: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let line = Copy.noDocks(model.playful)
        ContentUnavailableView {
            Label(line.title, systemImage: "dock.rectangle")
        } description: {
            Text(line.detail)
        } actions: {
            Button(Copy.createDock(model.playful)) { model.newDock() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct DockSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: UUID?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedDockID) {
            ForEach(model.store.docks) { dock in
                SidebarRow(dock: dock, renaming: $renaming)
                    .tag(dock.id)
                    .contextMenu { rowMenu(dock) }
            }
            .onMove { model.store.moveDocks(from: $0, to: $1) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Tokens.Space.m) {
                Button { model.windows.showSettings() } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                Button { model.showingRestore = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("Restore a backup")
                Spacer()
                Button { model.newDock() } label: { Image(systemName: "plus") }
                    .help("New dock")
                    .accessibilityLabel("New dock")
            }
            .buttonStyle(.borderless)
            .padding(Tokens.Space.m)
        }
        .sheet(isPresented: $model.showingRestore) {
            RestoreSheet().environment(model)
        }
    }

    @ViewBuilder
    private func rowMenu(_ dock: Dock) -> some View {
        let store = model.store
        Button("Rename") { renaming = dock.id }
        Toggle("Enabled", isOn: Binding(get: { dock.enabled }, set: { store.setEnabled(dock.id, $0) }))
        Button("Duplicate") {
            if let copy = store.duplicate(dock.id) { model.selectedDockID = copy.id }
        }
        Divider()
        Button("Copy Settings") { store.copySettings(from: dock.id) }
        Button("Paste Settings") { store.pasteSettings(to: dock.id) }
            .disabled(!store.canPasteSettings)
        Divider()
        Button("Delete", role: .destructive) {
            store.delete(dock.id)
            if model.selectedDockID == dock.id { model.selectedDockID = store.docks.first?.id }
        }
    }
}

private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let dock: Dock
    @Binding var renaming: UUID?
    @State private var draft = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if renaming == dock.id {
                    TextField("Name", text: $draft)
                        .onSubmit {
                            model.store.rename(dock.id, to: draft)
                            renaming = nil
                        }
                        .onAppear { draft = dock.name }
                } else {
                    Text(dock.name).lineLimit(1)
                        .foregroundStyle(dock.enabled ? Tokens.text : Tokens.textMuted)
                }
                Text(subtitle).font(.caption).foregroundStyle(Tokens.textMuted).lineLimit(1)
            }
            Spacer()
            Button {
                model.store.setEnabled(dock.id, !dock.enabled)
            } label: {
                Image(systemName: dock.enabled ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
            .help(dock.enabled ? "Turn off" : "Turn on")
            .accessibilityLabel(dock.enabled ? "Turn off \(dock.name)" : "Turn on \(dock.name)")
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if !dock.enabled { return "Off" }
        if let source = model.store.runtimeHidden[dock.id] { return "Hidden by \(source.rawValue)" }
        let count = dock.items.count
        return "\(dock.placementSummary) · \(count) item\(count == 1 ? "" : "s")"
    }
}

/// Name field, section picker and the selected section's form.
struct DockEditor: View {
    @Environment(AppModel.self) private var model
    let dock: Dock
    @State private var name = ""

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Section", selection: $model.managerSection) {
                ForEach(ManagerSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Tokens.Space.l)
            .padding(.top, Tokens.Space.m)
            ManagerBanners(dock: dock)
            FillAvailable {
                switch model.managerSection {
                case .items: ItemsSection(dock: dock)
                case .style: StyleSection(dock: dock)
                case .position: PositionSection(dock: dock)
                case .screens: ScreensSection(dock: dock)
                case .behavior: BehaviorSection(dock: dock)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TextField("Dock name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { if !model.store.rename(dock.id, to: name) { name = dock.name } }
                    // Names save as you type; an empty field keeps the old name until something is typed.
                    .onChange(of: name) { _, new in model.store.rename(dock.id, to: new) }
                    .accessibilityLabel("Dock name")
            }
        }
        .onAppear { name = dock.name }
        .onChange(of: dock.id) { name = dock.name }
        .onChange(of: dock.name) { name = dock.name }
    }
}

/// Notices shown above the editor: permissions, runtime hiding, save failures.
struct ManagerBanners: View {
    @Environment(AppModel.self) private var model
    let dock: Dock

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            if !WindowControl.isTrusted {
                Banner(kind: .warning,
                       text: "Accessibility access is off, so clicking an app can't bring back a specific window.",
                       action: "Allow Access") { WindowControl.requestTrust() }
            }
            if let source = model.store.runtimeHidden[dock.id] {
                Banner(kind: .info, text: "This dock is hidden by \(source.rawValue).", action: "Show Dock") {
                    model.store.show(dock.id)
                }
            }
            if model.store.editing.contains(dock.id) {
                Banner(kind: .info, text: "Edit Mode: drag to reorder, drop files from Finder to pin them.",
                       action: "Done") { model.store.setEditing(dock.id, false) }
            }
            if let error = model.store.lastSaveError {
                Banner(kind: .error, text: Copy.saveFailed(error, model.playful), action: nil) {}
            }
            if model.store.recoveredFromDamage {
                Banner(kind: .warning, text: "Your settings file was damaged, so Harbor loaded the latest backup.",
                       action: "OK") { model.store.recoveredFromDamage = false }
            }
        }
        .padding(.horizontal, Tokens.Space.l)
        .padding(.top, Tokens.Space.s)
    }
}

struct Banner: View {
    enum Kind { case info, warning, error }
    let kind: Kind
    let text: String
    let action: String?
    let perform: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: symbol).foregroundStyle(color)
            // No fixedSize here: measured at a narrow width during layout, a pinned height
            // wrapped into a tall column and forced the whole window taller than the screen.
            Text(text).font(.callout).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            if let action { Button(action, action: perform) }
        }
        .padding(Tokens.Space.m)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    private var symbol: String {
        switch kind {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .info: Tokens.accent
        case .warning: Tokens.warning
        case .error: Tokens.danger
        }
    }
}

/// Gives its content exactly the space on offer and reports nothing back up. Lists and
/// grouped forms otherwise report their full, unscrolled height, which made the window
/// refuse to be shorter than every row and clipped the layout instead of scrolling.
struct FillAvailable<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            content.frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
