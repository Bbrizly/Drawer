import AVFoundation

/// The sound a finished task makes. A two-note chime over a short low thump,
/// rendered once into a stereo buffer at launch and replayed through a player
/// node. The tail decays to silence so it rings out instead of clicking.
@MainActor
final class CompletionChime {
    static let shared = CompletionChime()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer?
    private var started = false

    init() {
        buffer = CompletionChime.render()
        if let buffer {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        }
    }

    /// Play from the top. `volume` is a 0...1 gain.
    func play(volume: Float = 1) {
        guard let buffer else { return }
        if !started {
            do { try engine.start() } catch { return }
            started = true
        }
        player.volume = max(0, min(1, volume))
        if !player.isPlaying { player.play() }
        // Restart cleanly if a prior chime is still ringing.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    private static func render() -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let duration = 0.8
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frames

        let left = channels[0]
        let right = channels[1]

        // A perfect fifth, the second note landing late so it reads as a rise.
        let note1 = 659.25 // E5
        let note2 = 987.77 // B5
        let body = 164.81  // E3 thump

        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate

            // One struck note: fundamental plus a soft octave, quick attack, decay.
            func voice(_ f: Double, start: Double, decay: Double, scale: Double) -> Double {
                let lt = t - start
                if lt < 0 { return 0 }
                let env = min(1, lt / 0.004) * exp(-lt * decay)
                return (sin(2 * .pi * f * scale * lt)
                        + 0.3 * sin(2 * .pi * f * scale * 2 * lt)) * env
            }

            // `scale` detunes the right channel a touch for width.
            func build(_ scale: Double) -> Double {
                let v1 = voice(note1, start: 0.0, decay: 6.5, scale: scale)
                let v2 = voice(note2, start: 0.09, decay: 5.5, scale: scale)
                let thump = sin(2 * .pi * body * t) * exp(-t * 13) * 0.6
                return (0.5 * v1 + 0.55 * v2 + thump) * 0.5
            }

            var l = build(1.0)
            var r = build(1.004)

            // Fade the last moments so the tail reaches exactly zero.
            let fade = 0.05
            if t > duration - fade {
                let g = max(0, (duration - t) / fade)
                l *= g
                r *= g
            }

            left[i] = Float(l)
            right[i] = Float(r)
        }
        return buffer
    }
}
