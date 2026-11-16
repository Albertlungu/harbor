import HarborCore
import SwiftUI

/// A row of small tiles for choosing the open effect. Hovering a tile plays its animation and
/// clicking plays its sound, so each can be judged before it is chosen.
struct OpenEffectPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            ForEach(OpenEffect.allCases, id: \.self) { effect in
                OpenEffectTile(effect: effect, selected: model.store.settings.openEffect == effect) {
                    model.store.updateSettings { $0.openEffect = effect }
                    OpenFeedback.play(effect: effect, volume: model.store.settings.openSoundVolume)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open effect")
    }
}

private struct OpenEffectTile: View {
    let effect: OpenEffect
    let selected: Bool
    let choose: () -> Void
    @State private var trigger = 0

    var body: some View {
        Button(action: choose) {
            VStack(spacing: Tokens.Space.xs) {
                Image(systemName: effect.symbolName)
                    .font(.system(size: 20))
                    .frame(height: 26)
                    .modifier(OpenEffectModifier(trigger: trigger, effect: effect, edge: .bottom))
                Text(effect.title).font(.caption)
            }
            .foregroundStyle(selected ? Tokens.accent : Tokens.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Space.m)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .fill(selected ? Tokens.accent.opacity(0.14) : Tokens.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .strokeBorder(selected ? Tokens.accent : Tokens.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { trigger += 1 } }
        .help(effect.summary)
        .accessibilityLabel(effect.title)
        .accessibilityHint(effect.summary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
