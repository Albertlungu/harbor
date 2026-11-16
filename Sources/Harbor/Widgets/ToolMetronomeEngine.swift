import AVFoundation
import HarborCore
import Observation

/// Plays one metronome. Each beat is a single buffer exactly one beat long (click, then silence),
/// and buffers are queued back to back on the player node, so timing is decided by the audio
/// clock and not by the main thread.
@MainActor
@Observable
final class MetronomeEngine {
    private(set) var isRunning = false
    /// Position in the measure of the beat now sounding, and a counter that changes on every beat.
    private(set) var beat = 0
    private(set) var tick = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    @ObservationIgnored private var cache: [String: AVAudioPCMBuffer] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var nextScheduled = 0
    @ObservationIgnored private var bpm = MetronomeLogic.defaultBPM
    @ObservationIgnored private var beats = MetronomeLogic.defaultBeats
    @ObservationIgnored private var accent = true

    /// Enough queued beats to ride out a busy main thread without drifting audibly late on tempo changes.
    private let queueDepth = 3

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func configure(bpm: Int, beats: Int, accent: Bool, volume: Double) {
        self.bpm = bpm
        self.beats = beats
        self.accent = accent
        player.volume = Float(volume)
    }

    func start() {
        guard !isRunning else { return }
        do { try engine.start() } catch { return }
        isRunning = true
        generation += 1
        nextScheduled = 0
        beat = 0
        tick += 1
        for _ in 0..<queueDepth { scheduleNext() }
        player.play()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        player.stop()
        engine.stop()
    }

    func toggle() { isRunning ? stop() : start() }

    /// Begins beat one now. Used by tap tempo so the next click lands exactly where the last tap did;
    /// the audio engine stays up so there is no start-up delay between the tap and the click.
    func restart() {
        if isRunning {
            generation += 1
            player.stop()
            isRunning = false
        }
        start()
    }

    private func scheduleNext() {
        let index = nextScheduled % beats
        nextScheduled += 1
        let buffer = clickBuffer(accented: accent && index == 0)
        let token = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.beatFinished(token) }
        }
    }

    /// The buffer that just ended is followed immediately by the next one, so its end is the next beat's start.
    private func beatFinished(_ token: Int) {
        guard isRunning, token == generation else { return }
        beat = (beat + 1) % beats
        tick += 1
        scheduleNext()
    }

    private func clickBuffer(accented: Bool) -> AVAudioPCMBuffer {
        let key = "\(bpm)-\(accented)"
        if let cached = cache[key] { return cached }
        if cache.count > 8 { cache.removeAll() }
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(MetronomeLogic.beatInterval(bpm: bpm) * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        samples.update(repeating: 0, count: Int(frames))
        let frequency = accented ? 1600.0 : 1000.0
        let clickFrames = min(Int(rate * 0.03), Int(frames))
        for i in 0..<clickFrames {
            let t = Double(i) / rate
            // A fast exponential fade avoids a pop at the end of the click.
            let envelope = exp(-Double(i) / Double(clickFrames) * 6)
            samples[i] = Float(sin(2 * .pi * frequency * t) * envelope * 0.8)
        }
        cache[key] = buffer
        return buffer
    }
}

@MainActor
enum MetronomeEngines {
    private static var engines: [UUID: MetronomeEngine] = [:]

    static func engine(for id: UUID) -> MetronomeEngine {
        if let existing = engines[id] { return existing }
        let created = MetronomeEngine()
        engines[id] = created
        return created
    }
}
