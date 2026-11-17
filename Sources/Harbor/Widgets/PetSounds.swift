import AVFoundation
import HarborCore

/// Plays the roaming pet's soft sounds. Buffers are rendered once on first use, a gate keeps the
/// sounds sparse, and the audio engine only runs while something is playing.
@MainActor
final class PetSounds {
    static let shared = PetSounds()
    static let defaultVolume = 0.3

    /// Off until the owner turns it on, so the pet never makes noise unasked.
    var enabled = false
    /// 0 to 1, scaled again by each cue's own level.
    var volume = defaultVolume

    private static let idleTimeout: Duration = .seconds(5)
    private let format = AVAudioFormat(standardFormatWithSampleRate: PetSoundSynth.sampleRate, channels: 1)
    private var engine: AVAudioEngine?
    /// A few voices so a long purr is not cut off by a footstep.
    private let players = (0..<3).map { _ in AVAudioPlayerNode() }
    private var nextPlayer = 0
    private var buffers: [PetSoundCue: [AVAudioPCMBuffer]] = [:]
    private var takes: [PetSoundCue: Int] = [:]
    private var gate = PetSoundGate()
    private let clock = ContinuousClock()
    private let epoch = ContinuousClock.now
    private var idleTask: Task<Void, Never>?

    private init() {}

    /// Plays `cue` unless sounds are off or the gate holds it back; `intensity` (0 to 1) scales it further.
    func play(_ cue: PetSoundCue, intensity: Double = 1) {
        let level = max(0, min(volume, 1)) * max(0, min(intensity, 1))
        guard enabled, level > 0 else { return }
        let elapsed = clock.now - epoch
        let now = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        guard gate.admit(cue, at: now), let buffer = take(of: cue), startEngine() else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = Float(level)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        scheduleIdleStop()
    }

    private func take(of cue: PetSoundCue) -> AVAudioPCMBuffer? {
        let list = buffers[cue] ?? render(cue)
        buffers[cue] = list
        guard !list.isEmpty else { return nil }
        let index = takes[cue, default: 0]
        takes[cue] = (index + 1) % list.count
        return list[index % list.count]
    }

    private func render(_ cue: PetSoundCue) -> [AVAudioPCMBuffer] {
        guard let format else { return [] }
        return (0..<PetSoundSynth.variants(for: cue)).compactMap { variant in
            let samples = PetSoundSynth.samples(for: cue, variant: variant)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for (index, sample) in samples.enumerated() { channel[index] = sample }
            return buffer
        }
    }

    private func startEngine() -> Bool {
        guard let format else { return false }
        let running = engine ?? {
            let created = AVAudioEngine()
            for player in players {
                created.attach(player)
                created.connect(player, to: created.mainMixerNode, format: format)
            }
            return created
        }()
        engine = running
        if running.isRunning { return true }
        return (try? running.start()) != nil
    }

    private func scheduleIdleStop() {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard let self, !Task.isCancelled else { return }
            for player in self.players { player.stop() }
            self.engine?.stop()
        }
    }
}
