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
        case chatter, ding, thunk, rustle, shred, slide
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

    /// A receipt fed into the shredder: a short harsh burst with a downward
    /// sweep. Volume is passed at the call so hot-reload applies.
    func shred(volume: Double) { play(.shred, volume) }

    /// The stamp rack sliding out or back on its rail: a short mechanical sweep.
    func slide(volume: Double) { play(.slide, volume) }

    /// Velocity-scaled paper rustle while rummaging, rate-capped so a sweep is
    /// a texture rather than a burst of clicks (spec "The drawer scene").
    func rustle(_ intensity: CGFloat, tuning: BureauRustleTuning) {
        guard Double(intensity) >= tuning.velocityThreshold else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard (now - lastRustleAt) * 1000 >= tuning.rateCapMs else { return }
        lastRustleAt = now
        play(.rustle, min(tuning.maxVolume, tuning.gain * Double(intensity)))
    }

    /// Stop the engine when the Bureau is hidden. Once any sound has played the
    /// engine's render thread and the audio HAL stay live for the rest of the
    /// app run, a real idle power draw. `play` lazily restarts via `started`.
    func suspend() {
        guard started else { return }
        engine.stop()
        started = false
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
        case .chatter: return buffer(duration: 0.03) { t, rng in
            // A dot-matrix pin strike. Quantize time into 1 ms steps so the
            // tone grinds like a stepper motor instead of ringing smooth.
            let step = (t * 1000).rounded(.down) / 1000
            let pin = sin(2 * .pi * 1600 * step) * exp(-t * 250)
            let grit = rng() * exp(-t * 400) * 0.4
            // A faint motor hum sits under the strike.
            let hum = sin(2 * .pi * 55 * t) * 0.15 * exp(-t * 60)
            return (pin + grit) * 0.7 + hum
        }
        case .ding: return buffer(duration: 0.4) { t, _ in
            // A small terminal bell: a bright pair a fifth apart, rung once.
            (sin(2 * .pi * 1244.5 * t) + 0.5 * sin(2 * .pi * 1864.7 * t))
                * exp(-t * 9) * min(1, t * 400)
        }
        case .thunk: return buffer(duration: 0.24) { t, rng in
            // Stamp: a two-stage ka-CHUNK. Stage one is a hard mechanical click
            // that dies in about 15 ms.
            let click = t < 0.015 ? rng() * exp(-t * 400) * 0.6 : 0
            // A short gap, then stage two: a deep punchy thud that slides from
            // about 120 Hz down to 80 Hz and decays fast, no ring-out.
            let u = t - 0.03
            let thud = u > 0 ? sin(2 * .pi * (120 - 260 * u) * u) * exp(-u * 18) : 0
            return click + thud
        }
        case .rustle:
            var prev = 0.0
            return buffer(duration: 0.14) { t, rng in
                let n = rng()
                // High-pass feel without a filter: the difference of successive
                // noise samples drops the low rumble and leaves a dry edge.
                let hp = n - prev
                prev = n
                // A quiet crackle bed plus sparse spikes so it reads as dry
                // paper catching, not smooth hiss. hp spans -2...2, so the
                // gains keep the worst case at 2*0.10 + 2*0.40 = 1.0, and the
                // clamp guarantees no clipping.
                let spike = rng() > 0.985 ? hp * 0.40 : 0
                let env = sin(.pi * min(1, t / 0.14))
                return max(-0.95, min(0.95, (hp * 0.10 + spike) * env))
            }
        case .shred: return buffer(duration: 0.4) { t, rng in
            // Shredder teeth: a low grind that sweeps down slowly as the slip is
            // pulled under. Two incommensurate sines give an irregular amplitude
            // wobble, like the paper catching and slipping.
            let grind = sin(2 * .pi * (140 - 180 * t) * t)
            let wobble = 0.6 + 0.4 * sin(2 * .pi * 11 * t) * sin(2 * .pi * 7 * t)
            return (rng() * 0.6 + grind * 0.4) * wobble * exp(-t * 3)
        }
        case .slide: return buffer(duration: 0.12) { t, rng in
            // A drawer rail: filtered noise under a soft swell, with a faint low
            // tone so it reads as metal sliding rather than plain hiss.
            let env = sin(.pi * min(1, t / 0.12))
            let tone = sin(2 * .pi * 180 * t) * 0.2
            return (rng() * 0.5 + tone) * env
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
