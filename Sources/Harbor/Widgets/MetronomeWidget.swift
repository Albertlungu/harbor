import HarborCore
import SwiftUI

struct MetronomeWidget: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var pulsing = false

    private var bpm: Int { MetronomeLogic.bpm(widget.double("bpm", Double(MetronomeLogic.defaultBPM))) }
    private var beats: Int { MetronomeLogic.beats(widget.double("beats", Double(MetronomeLogic.defaultBeats))) }

    var body: some View {
        let engine = MetronomeEngines.engine(for: item.id)
        let unit = Tokens.Tool.unit(size)
        let radius = Tokens.Tool.chipRadius(unit)
        VStack(spacing: unit * 0.07) {
            Circle()
                .fill(engine.isRunning ? Tokens.accent : Tokens.textMuted.opacity(0.5))
                .frame(width: unit * 0.26, height: unit * 0.26)
                .scaleEffect(pulsing ? 1.3 : 1)
            Text("\(bpm)")
                .font(.system(size: unit * 0.26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Tokens.text)
            HStack(spacing: unit * 0.04) {
                ForEach(0..<beats, id: \.self) { index in
                    Circle()
                        .fill(engine.isRunning && engine.beat == index ? Tokens.accent : Tokens.border)
                        .frame(width: unit * 0.07, height: unit * 0.07)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Tokens.border, lineWidth: 1))
                .padding(unit * 0.04)
        )
        .contentShape(Rectangle())
        .onTapGesture { engine.toggle() }
        .onChange(of: engine.tick) { pulse() }
        .onChange(of: settingsKey, initial: true) { configure(engine) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Metronome")
        .accessibilityValue("\(bpm) beats per minute, \(beats) beats, \(engine.isRunning ? "playing" : "stopped")")
        .accessibilityHint(engine.isRunning ? "Stops the metronome" : "Starts the metronome")
        .accessibilityAddTraits(.isButton)
    }

    private var settingsKey: [Double] {
        [Double(bpm), Double(beats), widget.bool("accent", true) ? 1 : 0, MetronomeLogic.volume(widget.double("volume", 0.7))]
    }

    private func configure(_ engine: MetronomeEngine) {
        engine.configure(bpm: bpm, beats: beats, accent: widget.bool("accent", true),
                         volume: MetronomeLogic.volume(widget.double("volume", 0.7)))
    }

    private func pulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.06)) { pulsing = true } completion: {
            withAnimation(.easeIn(duration: 0.18)) { pulsing = false }
        }
    }
}
