import AppKit
import HarborCore
import SwiftUI
import UniformTypeIdentifiers

struct StyleSection: View {
    @Environment(AppModel.self) private var model
    let dock: Dock
    @State private var themeName = ""
    @State private var showingThemeSave = false

    var body: some View {
        let notch = dock.layout == .notch
        Form {
            Section("Layout") {
                Picker("Layout", selection: layoutBinding) {
                    Text("Dock").tag(DockLayout.dock)
                    Text("Notch").tag(DockLayout.notch)
                }
                .pickerStyle(.segmented)
                if notch {
                    Text("Notch docks attach to an edge and fold away when idle. Effects, border and magnification are off.")
                        .font(.caption).foregroundStyle(Tokens.textMuted)
                }
            }

            if notch {
                notchSection
            } else {
                Section("Bar") {
                    Picker("Orientation", selection: dock[binding: model, \.style.orientation]) {
                        Text("Horizontal").tag(Orientation.horizontal)
                        Text("Vertical").tag(Orientation.vertical)
                    }
                    .disabled(dock.position.mode == .pinned)
                    if dock.position.mode == .pinned {
                        Text("Pinned docks follow their edge.").font(.caption).foregroundStyle(Tokens.textMuted)
                    }
                    Toggle("Collapse bar", isOn: dock[binding: model, \.style.collapse.enabled])
                    if dock.style.collapse.enabled { collapseControls }
                }
            }

            Section("Size and Spacing") {
                PresetPicker(title: "Icon size", preset: dock[binding: model, \.style.iconSizePreset], custom: .custom,
                             value: dock[binding: model, \.style.customIconSize], range: 20...128, unit: "pt")
                PresetPicker(title: notch ? "Notch depth" : "Bar thickness", preset: dock[binding: model, \.style.thicknessPreset],
                             custom: .custom, value: dock[binding: model, \.style.customThickness], range: 24...200, unit: "pt")
                Picker("Space between icons", selection: dock[binding: model, \.style.spacing]) {
                    ForEach(SpacingPreset.allCases, id: \.self) { p in
                        Text(p == .normal ? "Default" : p.rawValue.capitalized).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Always show item names", isOn: dock[binding: model, \.style.alwaysShowNames])
                if !notch {
                    Picker("Corners", selection: dock[binding: model, \.style.cornerStyle]) {
                        Text("Default").tag(CornerStyle.standard)
                        Text("Soft").tag(CornerStyle.soft)
                        Text("Round").tag(CornerStyle.round)
                    }
                    .pickerStyle(.segmented)
                    ValueSlider(title: "Side padding", value: dock[binding: model, \.style.sidePadding], range: 0...40, unit: " pt")
                }
            }

            Section("Icons") {
                Toggle("Tint icons", isOn: dock[binding: model, \.style.tintIcons])
                if dock.style.tintIcons {
                    ColorPicker("Tint color", selection: dock[binding: model, \.style.tintColor].color, supportsOpacity: false)
                    ValueSlider(title: "Intensity", value: dock[binding: model, \.style.tintIntensity], range: 0.1...1,
                                format: "%.1f")
                    Text("Widgets keep their own colors.").font(.caption).foregroundStyle(Tokens.textMuted)
                }
            }

            if !notch {
                backgroundSection
                Section("Border") {
                    Toggle("Show border", isOn: dock[binding: model, \.style.showBorder])
                    if dock.style.showBorder {
                        ValueSlider(title: "Width", value: dock[binding: model, \.style.borderWidth], range: 0.5...6,
                                    format: "%.1f", unit: " pt")
                        ColorPicker("Color", selection: dock[binding: model, \.style.borderColor].color)
                    }
                }
                Section("Effects") {
                    ForEach(EffectKind.allCases, id: \.self) { effect in
                        Toggle(effect.rawValue.capitalized, isOn: Binding(
                            get: { dock.style.effects.contains(effect) },
                            set: { on in
                                model.store.updateDock(dock.id) {
                                    if on { $0.style.effects.insert(effect) } else { $0.style.effects.remove(effect) }
                                }
                            }))
                    }
                    if !dock.style.effects.isEmpty {
                        ValueSlider(title: "Intensity", value: dock[binding: model, \.style.effectIntensity], range: 0...1,
                                    format: "%.1f")
                    }
                }
                Section("Magnification") {
                    Toggle("Magnify icons on hover", isOn: dock[binding: model, \.style.magnify])
                    if dock.style.magnify {
                        ValueSlider(title: "Largest size", value: dock[binding: model, \.style.maxScale], range: 1...4,
                                    format: "%.1f", unit: "×")
                        ValueSlider(title: "Spread", value: dock[binding: model, \.style.falloff], range: 1...5,
                                    format: "%.1f", unit: " icons")
                    }
                }
            }

            Section("Themes") {
                themesSection
            }
        }
        .formStyle(.grouped)
        .alert("Save Theme", isPresented: $showingThemeSave) {
            TextField("Name", text: $themeName)
            Button("Save") {
                let name = themeName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.store.saveTheme(named: name, from: dock.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves this dock's look so you can apply it to other docks.")
        }
    }

    private var layoutBinding: Binding<DockLayout> {
        Binding(get: { dock.layout }, set: { layout in
            model.store.updateDock(dock.id) { d in
                d.layout = layout
                if layout == .notch {
                    // Notch docks are pinned and plain; these are not restored when switching back.
                    d.position.mode = .pinned
                    d.position.fullWidth = false
                    d.position.gapPreset = .flush
                    d.position.desktopWidgetMode = false
                    d.style.magnify = false
                    d.style.effects = []
                    d.style.showBorder = false
                    if d.position.edge == .bottom && !model.store.settings.deepHideNativeDock { d.position.edge = .top }
                }
            }
        })
    }

    @ViewBuilder
    private var collapseControls: some View {
        Picker("Button position", selection: dock[binding: model, \.style.collapse.buttonPosition]) {
            ForEach(CollapseButtonPosition.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        Picker("Button style", selection: dock[binding: model, \.style.collapse.buttonStyle]) {
            ForEach(CollapseButtonStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        if dock.style.collapse.buttonStyle == .symbol {
            TextField("Symbol name", text: dock[binding: model, \.style.collapse.symbolName])
        }
        if dock.style.collapse.buttonStyle == .text {
            TextField("Text (up to 5 characters)", text: Binding(
                get: { dock.style.collapse.text },
                set: { v in model.store.updateDock(dock.id) { $0.style.collapse.text = String(v.prefix(5)) } }))
        }
        ColorPicker("Button color", selection: Binding(
            get: { (dock.style.collapse.buttonColor ?? RGBA(0.4, 0.4, 0.45)).color },
            set: { c in model.store.updateDock(dock.id) { $0.style.collapse.buttonColor = RGBA(c) } }))
        Picker("Expand with", selection: dock[binding: model, \.style.collapse.expandUsing]) {
            Text("Click only").tag(ExpandTrigger.click)
            Text("Hover on button").tag(ExpandTrigger.handleHover)
            Text("Hover on dock").tag(ExpandTrigger.dockHover)
            Text("Automatic").tag(ExpandTrigger.automatic)
        }
        if dock.style.collapse.expandUsing != .click {
            ValueSlider(title: "Expand after", value: dock[binding: model, \.style.collapse.expandAfter], range: 0...2,
                        format: "%.1f", unit: " s")
            ValueSlider(title: "Collapse after", value: dock[binding: model, \.style.collapse.collapseAfter], range: 0...5,
                        format: "%.1f", unit: " s")
        }
    }

    private var backgroundSection: some View {
        Section("Background") {
            Picker("Material", selection: dock[binding: model, \.style.background]) {
                Text("Glass").tag(BackgroundKind.glass)
                Text("Blur").tag(BackgroundKind.blur)
                Text("Solid").tag(BackgroundKind.solid)
                Text("None").tag(BackgroundKind.none)
            }
            .pickerStyle(.segmented)
            switch dock.style.background {
            case .glass:
                Toggle("Dark glass", isOn: dock[binding: model, \.style.darkGlass])
                Toggle("Tint glass", isOn: Binding(
                    get: { dock.style.glassTint != nil },
                    set: { on in model.store.updateDock(dock.id) { $0.style.glassTint = on ? RGBA(0.23, 0.36, 0.8, 0.3) : nil } }))
                if dock.style.glassTint != nil {
                    ColorPicker("Tint", selection: Binding(
                        get: { (dock.style.glassTint ?? .accent).color },
                        set: { c in model.store.updateDock(dock.id) { $0.style.glassTint = RGBA(c) } }))
                }
            case .blur:
                ValueSlider(title: "Darkness", value: dock[binding: model, \.style.blurDarkness], range: 0...1, format: "%.1f")
                opacityPicker
            case .solid:
                ColorPicker("Color", selection: dock[binding: model, \.style.solidColor].color, supportsOpacity: false)
                opacityPicker
            case .none:
                Text("Only the icons are drawn.").font(.caption).foregroundStyle(Tokens.textMuted)
            }
            if model.store.settings.opaqueBackgrounds {
                Text("Settings › General › Always use opaque backgrounds is on, so this dock is drawn solid.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
            }
        }
    }

    private var opacityPicker: some View {
        Picker("Opacity", selection: dock[binding: model, \.style.opacity]) {
            ForEach(OpacityPreset.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var notchSection: some View {
        Section("Notch") {
            Picker("When idle", selection: dock[binding: model, \.style.notch.idleMode]) {
                Text("Stay open").tag(NotchIdleMode.show)
                Text("Fold to a pill").tag(NotchIdleMode.pill)
                Text("Hide").tag(NotchIdleMode.hidden)
            }
            if dock.style.notch.idleMode != .show {
                ValueSlider(title: "Open after", value: dock[binding: model, \.style.notch.expandAfter], range: 0...2,
                            format: "%.1f", unit: " s")
                ValueSlider(title: "Fold after", value: dock[binding: model, \.style.notch.foldAfter], range: 0...5,
                            format: "%.1f", unit: " s")
            }
            Picker("Background", selection: dock[binding: model, \.style.notch.background]) {
                Text("Black").tag(NotchBackground.black)
                Text("Color").tag(NotchBackground.color)
                Text("Blur").tag(NotchBackground.blur)
                Text("Glass").tag(NotchBackground.glass)
            }
            if dock.style.notch.background == .color {
                ColorPicker("Color", selection: dock[binding: model, \.style.notch.color].color, supportsOpacity: false)
            }
        }
    }

    @ViewBuilder
    private var themesSection: some View {
        let themes = model.store.config.themes
        if themes.isEmpty {
            Text("No saved themes yet.").foregroundStyle(Tokens.textMuted)
        }
        ForEach(themes) { theme in
            HStack {
                Text(theme.name)
                Spacer()
                Button("Apply") { model.store.applyTheme(theme.id, to: dock.id) }
                Menu {
                    Button("Update from This Dock") {
                        model.store.updateThemes { list in
                            if let i = list.firstIndex(where: { $0.id == theme.id }) { list[i].style = dock.style }
                        }
                    }
                    Button("Export…") { ThemeFiles.export(theme) }
                    Button("Delete", role: .destructive) { model.store.updateThemes { $0.removeAll { $0.id == theme.id } } }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        HStack {
            Button("Save Current Look…") {
                themeName = ""
                showingThemeSave = true
            }
            Button("Import…") {
                if let theme = ThemeFiles.importTheme() { model.store.updateThemes { $0.append(theme) } }
            }
        }
    }
}

@MainActor
enum ThemeFiles {
    static func export(_ theme: Theme) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(theme.name).harbortheme"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? JSONEncoder().encode(theme) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func importTheme() -> Theme? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "harbortheme") ?? .json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              var theme = try? JSONDecoder().decode(Theme.self, from: data) else { return nil }
        theme.id = UUID()
        return theme
    }
}
