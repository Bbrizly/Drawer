import AVFoundation

/// Every Bureau noise, synthesized at init into short PCM buffers and replayed
/// through one engine (the `CompletionChime` recipe, one player per sound so a
/// fast chatter never cuts off a ringing ding). All self-made, no assets
/// (spec "The drawer scene": sounds CC0/self-made). Volumes come from tuning
/// at each call so hot-reload applies immediately.
@MainActor
final class BureauSounds {
    private let engine = AVAudioEngine()
    private var players: [Sound: AVAudioPlayerNode] = [:]
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var started = false
    private var lastRustleAt: TimeInterval = 0

    enum Sound: CaseIterable {
        case chatter, ding, thunk, rustle
    }

    init() {
        for sound in Sound.allCases {
            guard let buffer = Self.render(sound) else { continue }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            players[sound] = player
            buffers[sound] = buffer
        }
    }

    /// One dot-matrix tick per print step (spec "The printer").
    func chatter(volume: Double) { play(.chatter, volume) }

    /// The terminal ding when a receipt finishes printing.
    func ding(volume: Double) { play(.ding, volume) }

    /// The stamp landing (spec "The stamp").
    func thunk(volume: Double) { play(.thunk, volume) }

    /// Velocity-scaled paper rustle while rummaging, rate-capped so a sweep is
    /// a texture rather than a burst of clicks (spec "The drawer scene").
    func rustle(_ intensity: CGFloat, tuning: BureauRustleTuning) {
        guard Double(intensity) >= tuning.velocityThreshold else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard (now - lastRustleAt) * 1000 >= tuning.rateCapMs else { return }
        lastRustleAt = now
        play(.rustle, min(tuning.maxVolume, tuning.gain * Double(intensity)))
    }

    private func play(_ sound: Sound, _ volume: Double) {
        guard volume > 0, let player = players[sound], let buffer = buffers[sound] else { return }
        if !started {
            do { try engine.start() } catch { return }
            started = true
        }
        player.volume = Float(max(0, min(1, volume)))
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    // MARK: synthesis

    private static func render(_ sound: Sound) -> AVAudioPCMBuffer? {
        switch sound {
        case .chatter: return buffer(duration: 0.02) { t, rng in
            // A pin strike: a hard noise tick with an instant decay.
            rng() * exp(-t * 300)
        }
        case .ding: return buffer(duration: 0.4) { t, _ in
            // A small terminal bell: a bright pair a fifth apart, rung once.
            (sin(2 * .pi * 1244.5 * t) + 0.5 * sin(2 * .pi * 1864.7 * t))
                * exp(-t * 9) * min(1, t * 400)
        }
        case .thunk: return buffer(duration: 0.22) { t, rng in
            // Weight: a low body dropping in pitch plus a leather-ish slap.
            let body = sin(2 * .pi * (82 - 60 * t) * t) * exp(-t * 22)
            let slap = rng() * exp(-t * 120) * 0.4
            return body + slap
        }
        case .rustle: return buffer(duration: 0.12) { t, rng in
            // Paper: soft noise swelling in and out, no tonal center.
            rng() * 0.35 * sin(.pi * min(1, t / 0.12))
        }
        }
    }

    /// Renders `sample(t, noise)` into a stereo buffer; `noise` is a fresh
    /// random value in -1...1 per call for the noise-based sounds.
    private static func buffer(
        duration: Double,
        sample: (Double, () -> Double) -> Double
    ) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frames
        var seed: UInt64 = 0x9E3779B97F4A7C15
        let noise: () -> Double = {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(Int64(bitPattern: seed)) / Double(Int64.max)
        }
        for i in 0..<Int(frames) {
            let value = Float(sample(Double(i) / sampleRate, noise))
            channels[0][i] = value
            channels[1][i] = value
        }
        return buffer
    }
}
