import HarborCore
import SwiftUI

/// The "Appearance" group of the pet's settings: species, colour, markings and accessories, with a live preview.
struct PetAppearanceSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fields: WidgetFields

    private var appearance: PetAppearance { PetAppearance(fields.current) }

    private func update(_ change: (inout PetAppearance) -> Void) {
        var next = appearance
        change(&next)
        for (key, value) in next.settings { fields.set(key, value) }
    }

    private func binding<T>(_ path: WritableKeyPath<PetAppearance, T>) -> Binding<T> {
        Binding(get: { appearance[keyPath: path] }, set: { value in update { $0[keyPath: path] = value } })
    }

    var body: some View {
        let current = appearance
        Section("Appearance") {
            preview(current)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Tokens.Space.m)], spacing: Tokens.Space.m) {
                ForEach(PetSpecies.allCases, id: \.self) { species in
                    speciesButton(species, selected: species == current.species)
                }
            }
            LabeledContent("Color") {
                HStack(spacing: Tokens.Space.s) {
                    ForEach(current.species.swatches, id: \.id) { swatch in
                        swatchButton(swatch, selected: current.color == .swatch(swatch.id))
                    }
                    ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom color")
                }
            }
            Picker("Markings", selection: binding(\.pattern)) {
                ForEach(PetPattern.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Eyes", selection: binding(\.eyes)) {
                ForEach(PetEyeStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Accessory", selection: binding(\.accessory)) {
                ForEach(PetAccessory.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            HStack {
                Button(Copy.randomizePet(model.playful)) {
                    update { $0 = PetAppearance.random { Double.random(in: 0..<1) } }
                }
                if current != PetAppearance() {
                    Button("Reset") { update { $0 = PetAppearance() } }
                }
            }
        }
    }

    /// A front view and a walking view, so a change shows both the face and the gait.
    private func preview(_ current: PetAppearance) -> some View {
        let look = PetLook(current)
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: Tokens.Space.xxl) {
                PetFigure(unit: 72, pose: PetPose(face: PetExpression.calm.face), padBottom: false, look: look)
                    .frame(width: 72, height: 72)
                PetFigure(unit: 48, pose: walking(look.species, time: time), padBottom: false, look: look)
                    .frame(width: 48, height: 48)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Space.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of a \(current.species.title.lowercased())")
    }

    private func walking(_ species: PetSpecies, time: Double) -> PetPose {
        var pose = PetPose(face: PetExpression.happy.face)
        guard !reduceMotion else { return pose }
        let rate = PetGait.strideRate(speed: 40, unit: 48) * (species.gait == .hop ? 0.75 : 1)
        pose.turn = PetLocomotion.walkTurn
        PetLocomotion.apply(&pose, PetBodyState(moving: true, phase: time * rate * 2 * .pi, time: time),
                            species: species, unit: 48)
        return pose
    }

    private func speciesButton(_ species: PetSpecies, selected: Bool) -> some View {
        Button {
            update {
                $0.species = species
                $0.color = .swatch(species.swatches[0].id)
            }
        } label: {
            VStack(spacing: Tokens.Space.xxs) {
                PetFigure(unit: 36, pose: PetPose(), padBottom: false, look: PetLook(PetAppearance(species: species)))
                    .frame(width: 36, height: 40, alignment: .bottom)
                Text(species.title).font(.caption).foregroundStyle(selected ? Tokens.text : Tokens.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Space.s)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(selected ? Tokens.accent.opacity(0.14) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(selected ? Tokens.accent : Tokens.border, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(species.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatchButton(_ swatch: PetSwatch, selected: Bool) -> some View {
        Button {
            update { $0.color = .swatch(swatch.id) }
        } label: {
            Circle()
                .fill(Color(.sRGB, red: Double((swatch.hex >> 16) & 0xFF) / 255,
                            green: Double((swatch.hex >> 8) & 0xFF) / 255, blue: Double(swatch.hex & 0xFF) / 255))
                .overlay(Circle().stroke(Tokens.border, lineWidth: 1))
                .padding(3)
                .overlay(Circle().stroke(selected ? Tokens.accent : Color.clear, lineWidth: 2))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(swatch.name)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customColor: Binding<Color> {
        Binding(get: {
            let fur = appearance.fur
            return Color(.sRGB, red: fur.red, green: fur.green, blue: fur.blue)
        }, set: { color in
            let rgba = RGBA(color)
            update { $0.color = .custom(PetRGB(red: rgba.red, green: rgba.green, blue: rgba.blue)) }
        })
    }
}
