import AVFoundation
import HarborCore

/// Plays the short sound that goes with an open effect. Buffers are synthesized once and the audio
/// engine only runs while something is playing, so an idle dock holds no audio resources.
@MainActor
enum OpenFeedback {
    private static let idleTimeout: Duration = .seconds(5)
    private static let format = AVAudioFormat(standardFormatWithSampleRate: OpenEffectSound.sampleRate, channels: 1)
    private static var engine: AVAudioEngine?
    private static let player = AVAudioPlayerNode()
    private static var buffers: [OpenEffect: AVAudioPCMBuffer] = [:]
    private static var idleTask: Task<Void, Never>?

    static func play(effect: OpenEffect, volume: Double) {
        let level = OpenEffectSound.volume(volume)
        guard level > 0, let buffer = buffer(for: effect), startEngine() else { return }
        player.volume = Float(level)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        scheduleIdleStop()
    }

    private static func buffer(for effect: OpenEffect) -> AVAudioPCMBuffer? {
        if let cached = buffers[effect] { return cached }
        let samples = OpenEffectSound.samples(for: effect)
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() { channel[index] = sample }
        buffers[effect] = buffer
        return buffer
    }

    private static func startEngine() -> Bool {
        guard let format else { return false }
        let running = engine ?? {
            let created = AVAudioEngine()
            created.attach(player)
            created.connect(player, to: created.mainMixerNode, format: format)
            return created
        }()
        engine = running
        if running.isRunning { return true }
        return (try? running.start()) != nil
    }

    private static func scheduleIdleStop() {
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: idleTimeout)
            guard !Task.isCancelled else { return }
            player.stop()
            engine?.stop()
        }
    }
}
