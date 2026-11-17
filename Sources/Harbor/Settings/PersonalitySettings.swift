import HarborCore
import SwiftUI

/// How much character Harbor has: one big choice up top, then each part on its own.
struct PersonalitySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                PersonalityChooser()
            }

            Section("Colour") {
                PaletteRow()
                PalettePreview()
                Toggle("Colour by category", isOn: model.setting(\.categoryColors))
                Toggle("Theme docks with the palette", isOn: model.setting(\.paletteGlass))
                note("Tints dock backgrounds, borders, running dots, labels and widget accents. Colours you set yourself, like a dock's glass tint, are kept.")
            }

            Section("Words") {
                Toggle("Playful wording", isOn: model.setting(\.playfulCopy))
                let sample = Copy.emptyDock(model.store.settings.playfulCopy)
                note("\(sample.title) \(sample.detail)")
            }

            Section("Moments") {
                Toggle("Celebrate the little wins", isOn: model.setting(\.celebrations))
                HStack {
                    Button("Try it") { Celebration.shared.play(window: NSApp.keyWindow) }
                        .disabled(!model.store.settings.celebrations)
                    note("Confetti for a finished timer, a first dock, an emptied Trash and a saved backup.")
                }
            }

            Section("Feel") {
                Toggle("Animate when opening", isOn: model.setting(\.openAnimation))
                OpenEffectPicker()
                Toggle("Play a sound", isOn: model.setting(\.openSound))
                if model.store.settings.openSound {
                    Slider(value: model.setting(\.openSoundVolume), in: 0...1) { Text("Volume") }
                }
                Text("The sound always matches the animation you choose.").font(.caption).foregroundStyle(Tokens.textMuted)
            }

            Section("Pet") {
                Picker("Energy", selection: model.setting(\.petEnergy)) {
                    ForEach(PetEnergy.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Quiet mode", isOn: model.setting(\.petQuiet))
                Toggle("Sound effects", isOn: model.setting(\.petSounds))
                if model.store.settings.petSounds {
                    Slider(value: model.setting(\.petSoundVolume), in: 0...1) { Text("Volume") }
                }
                note("Quiet mode also mutes the pet. Extra Curious, in the pet's roaming menu, lets it follow your typing.")
            }

            Section("Type") {
                Toggle("Rounded type", isOn: model.setting(\.roundedType))
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(Tokens.textMuted)
    }
}

private struct PersonalityChooser: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Tokens.Space.l) {
            ForEach(Personality.allCases, id: \.self) { personality in
                card(personality)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Personality")
    }

    private func card(_ personality: Personality) -> some View {
        let selected = model.store.settings.personality == personality
        return Button {
            model.store.updateSettings { personality.apply(to: &$0) }
        } label: {
            VStack(spacing: Tokens.Space.s) {
                Image(systemName: symbol(personality)).font(.system(size: 26, weight: .medium))
                Text(personality.title).font(.headline)
                Text(personality.summary)
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
            }
            .foregroundStyle(selected ? Tokens.accent : Tokens.text)
            .frame(maxWidth: .infinity)
            .padding(Tokens.Space.l)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.popover, style: .continuous)
                .fill(selected ? Tokens.accent.opacity(0.14) : Tokens.surface))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.popover, style: .continuous)
                .strokeBorder(selected ? Tokens.accent : Tokens.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(personality.title)
        .accessibilityHint(personality.summary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func symbol(_ p: Personality) -> String {
        switch p {
        case .calm: "leaf"
        case .balanced: "swatchpalette"
        case .playful: "sparkles"
        }
    }
}

private struct PaletteRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            ForEach(Palette.allCases, id: \.self) { palette in
                tile(palette)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Palette")
    }

    private func tile(_ palette: Palette) -> some View {
        let selected = model.store.settings.palette == palette
        let spec = palette.spec
        return Button {
            model.store.updateSettings { $0.palette = palette }
        } label: {
            VStack(spacing: Tokens.Space.s) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Appearance.accent(of: palette))
                    .frame(height: 22)
                HStack(spacing: 3) {
                    ForEach(Array(spec.categories.enumerated()), id: \.offset) { _, pair in
                        Circle().fill(Appearance.color(pair)).frame(width: 9, height: 9)
                    }
                }
                Text(palette.title).font(.caption).foregroundStyle(selected ? Tokens.accent : Tokens.text)
            }
            .padding(Tokens.Space.s)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .fill(selected ? Tokens.accent.opacity(0.14) : Tokens.surface))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .strokeBorder(selected ? Tokens.accent : Tokens.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(palette.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A miniature dock and button in the chosen palette, so the choice can be judged at a glance.
private struct PalettePreview: View {
    private let categories: [(WidgetCategory, String)] = [
        (.apps, "square.grid.2x2"), (.folders, "folder"), (.clocks, "timer"), (.tasks, "checklist"), (.system, "cpu"),
    ]

    var body: some View {
        let look = Appearance.shared
        HStack(spacing: Tokens.Space.l) {
            HStack(spacing: Tokens.Space.m) {
                ForEach(categories, id: \.0) { category, symbol in
                    let hue = look.hue(for: category)
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(hue)
                        .frame(width: 30, height: 30)
                        .background(hue.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(Tokens.Space.s)
            .background(Tokens.dockSolid, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
            Text("Accent")
                .font(.callout.weight(.semibold))
                .foregroundStyle(look.onAccent)
                .padding(.horizontal, Tokens.Space.l)
                .padding(.vertical, Tokens.Space.s)
                .background(look.accent, in: Capsule())
        }
        .accessibilityHidden(true)
    }
}
