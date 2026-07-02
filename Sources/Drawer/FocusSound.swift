import AVFoundation
import Combine

/// Synthesizes a continuous focus sound, sample by sample, in real stereo.
/// Lives on the audio render thread. Control params (`kind`, `targetAmp`) are
/// plain vars written from the main thread; the races are benign for audio
/// control values and avoid locking the real-time thread. Filter state is
/// touched only by `render`.
///
/// Quality choices: independent left/right noise (wide, not a mono point), a
/// refined 7-pole pink filter, a gentle low-pass to take the digital edge off,
/// and a smoothed amplitude so volume changes and start/stop never click.
final class NoiseGenerator: @unchecked Sendable {
    enum Kind: Int {
        case white, pink, brown, green, ocean
        init(name: String) {
            switch name {
            case "white": self = .white
            case "brown": self = .brown
            case "green": self = .green
            case "ocean": self = .ocean
            default: self = .pink
            }
        }
    }

    var kind: Kind = .pink
    /// Where the smoothed amplitude is heading. 0 = silent.
    var targetAmp: Float = 0

    private let sampleRate: Double
    private var curAmp: Float = 0
    private var lfoPhase = 0.0

    /// Per-channel DSP state, duplicated for independent stereo.
    private struct Channel {
        var rng: UInt32
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
        var brown = 0.0
        var lp = 0.0
        var svfLow = 0.0, svfBand = 0.0
    }
    private var left: Channel
    private var right: Channel

    /// Green-noise band-pass coefficients. They depend only on the sample rate,
    /// so they are computed once here, not recomputed (with a `sin`) per sample.
    private let svfF: Double
    private let svfQ = 0.55

    init(sampleRate: Double = 44_100, seedL: UInt32 = 0x1234_5678, seedR: UInt32 = 0x9E37_79B9) {
        self.sampleRate = sampleRate
        self.svfF = 2 * sin(Double.pi * 500 / sampleRate)
        left = Channel(rng: seedL)
        right = Channel(rng: seedR)
    }

    /// Start the fade-in from silence (call right before the engine starts).
    func resetEnvelope() { curAmp = 0 }

    /// xorshift32: fast, lock-free white noise in [-1, 1].
    private func white(_ c: inout Channel) -> Double {
        c.rng ^= c.rng << 13
        c.rng ^= c.rng >> 17
        c.rng ^= c.rng << 5
        return Double(c.rng) / Double(UInt32.max) * 2 - 1
    }

    private func sample(_ c: inout Channel, lfo: Double) -> Double {
        let w = white(&c)
        let v: Double
        switch kind {
        case .white:
            v = w * 0.55
        case .pink:
            // Paul Kellet's refined 7-pole pink filter: accurate -3 dB/octave.
            c.b0 = 0.99886 * c.b0 + w * 0.0555179
            c.b1 = 0.99332 * c.b1 + w * 0.0750759
            c.b2 = 0.96900 * c.b2 + w * 0.1538520
            c.b3 = 0.86650 * c.b3 + w * 0.3104856
            c.b4 = 0.55000 * c.b4 + w * 0.5329522
            c.b5 = -0.7616 * c.b5 - w * 0.0168980
            let pink = c.b0 + c.b1 + c.b2 + c.b3 + c.b4 + c.b5 + c.b6 + w * 0.5362
            c.b6 = w * 0.115926
            v = pink * 0.11
        case .brown:
            // Leaky integral of white: deep -6 dB/octave rumble.
            c.brown = (c.brown + 0.02 * w) / 1.02
            v = c.brown * 3.5
        case .green:
            // White through a resonant band-pass near 500 Hz: the mid-focused
            // "natural ambience" color. Coefficients precomputed in init.
            c.svfLow += svfF * c.svfBand
            let high = w - c.svfLow - svfQ * c.svfBand
            c.svfBand += svfF * high
            v = c.svfBand * 1.1
        case .ocean:
            // Brown noise swelled by a slow LFO: surf rolling in and back out.
            c.brown = (c.brown + 0.02 * w) / 1.02
            let swell = 0.5 + 0.5 * sin(lfo) // 0...1
            v = c.brown * 3.5 * (0.2 + 0.8 * swell * swell)
        }
        // Gentle one-pole low-pass softens hiss on the brighter colors. Brown
        // and ocean are already dark, so leave them untouched.
        c.lp += 0.45 * (v - c.lp)
        let out = (kind == .brown || kind == .ocean) ? v : (0.5 * v + 0.5 * c.lp)
        return max(-1, min(1, out))
    }

    func render(into buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        let lfoInc = 2 * Double.pi * 0.09 / sampleRate // ~11 s wave period
        let channels = buffers.count
        for frame in 0..<frames {
            // Smooth toward the target so volume moves and fades never click
            // (time constant ~50 ms at 44.1 kHz).
            curAmp += (targetAmp - curAmp) * 0.0005
            let l = Float(sample(&left, lfo: lfoPhase)) * curAmp
            let r = Float(sample(&right, lfo: lfoPhase)) * curAmp
            lfoPhase += lfoInc
            if lfoPhase > 2 * .pi { lfoPhase -= 2 * .pi }
            if channels >= 2 {
                write(buffers[0], frame, l)
                write(buffers[1], frame, r)
            } else if channels == 1 {
                write(buffers[0], frame, (l + r) * 0.5)
            }
        }
    }

    private func write(_ buffer: AudioBuffer, _ frame: Int, _ value: Float) {
        let ptr = UnsafeMutableBufferPointer<Float>(buffer)
        if frame < ptr.count { ptr[frame] = value }
    }
}

/// Plays a continuous focus sound through one AVAudioEngine source node.
/// Survives the panel hiding (the engine is independent of the SwiftUI view),
/// so the sound keeps going while you work. Start and stop fade to avoid clicks.
@MainActor
final class FocusSoundPlayer: ObservableObject {
    /// The selectable sounds, shared by the header control and Settings.
    static let options: [(id: String, label: String, symbol: String)] = [
        ("white", "White", "aqi.high"),
        ("pink", "Pink", "waveform"),
        ("brown", "Brown", "waveform.path"),
        ("green", "Green", "leaf"),
        ("ocean", "Ocean", "water.waves"),
    ]

    @Published private(set) var isPlaying = false

    private let engine = AVAudioEngine()
    private let generator = NoiseGenerator()
    private var source: AVAudioSourceNode?
    private var stopWork: DispatchWorkItem?
    private var defaultsObserver: NSObjectProtocol?

    /// Slider value 0...1 mapped to a gain ceiling that never clips.
    private var mappedVolume: Float {
        let v = UserDefaults.standard.object(forKey: "focusSoundVolume") as? Double ?? 0.5
        return Float(max(0, min(1, v))) * 0.32
    }

    init() {
        generator.kind = NoiseGenerator.Kind(
            name: UserDefaults.standard.string(forKey: "focusSoundKind") ?? "pink"
        )
        // Settings lives in another window and edits the sound type and volume
        // via @AppStorage, so pull the latest into the live generator on any
        // defaults change. Cheap: it reads two values.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncFromDefaults() }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private func syncFromDefaults() {
        generator.kind = NoiseGenerator.Kind(
            name: UserDefaults.standard.string(forKey: "focusSoundKind") ?? "pink"
        )
        if isPlaying { generator.targetAmp = mappedVolume }
    }

    func toggle() { isPlaying ? stop() : play() }

    func play() {
        stopWork?.cancel() // a pending fade-out from a quick prior stop
        stopWork = nil
        isPlaying = true
        generator.targetAmp = mappedVolume
        if source != nil { return } // still alive from a recent stop: just ramp up

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
            return
        }
        let gen = generator
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            gen.render(into: abl, frames: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
        generator.resetEnvelope() // fade in from silence
        do {
            try engine.start()
        } catch {
            engine.detach(node)
            source = nil
            isPlaying = false
        }
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        generator.targetAmp = 0 // fade to silence, then tear down
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine.stop()
            if let source = self.source { self.engine.detach(source) }
            self.source = nil
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
