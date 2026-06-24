import AppKit

/// One selectable check-off sound. `id` is what gets stored.
struct CheckOffSoundOption: Identifiable, Hashable {
    let id: String
    let label: String
}

/// The check-off sounds you can pick from. The id encodes the source: "chime"
/// is the synthesized one, "system:Glass" a macOS sound, "custom:foo.wav" a file
/// imported into the Sounds folder.
enum CheckOffSound {
    static let chimeID = "chime"

    /// Imported sounds, kept under Application Support and out of any iCloud vault.
    static var soundsDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Drawer", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Read the system sounds folder so the list stays right across OS versions.
    static func systemSoundNames() -> [String] {
        let names = (try? FileManager.default
            .contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return names.filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    static func customFileNames() -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: soundsDir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { !$0.hasDirectoryPath }
            .map { $0.lastPathComponent }
            .sorted()
    }

    static func options() -> [CheckOffSoundOption] {
        var opts = [CheckOffSoundOption(id: chimeID, label: "Chime")]
        opts += systemSoundNames().map { CheckOffSoundOption(id: "system:\($0)", label: $0) }
        opts += customFileNames().map { CheckOffSoundOption(id: "custom:\($0)", label: $0) }
        return opts
    }
}

/// Plays the selected check-off sound. The chime goes through `CompletionChime`;
/// system and custom sounds are `NSSound`s, cached so rapid check-offs do not
/// rebuild them.
@MainActor
final class CheckOffSoundPlayer {
    static let shared = CheckOffSoundPlayer()

    private var cache: [String: NSSound] = [:]

    func play(id: String, volume: Double) {
        let vol = Float(max(0, min(1, volume)))
        if id == CheckOffSound.chimeID {
            CompletionChime.shared.play(volume: vol)
            return
        }
        guard let sound = sound(for: id) else {
            CompletionChime.shared.play(volume: vol) // file gone: fall back to the chime
            return
        }
        sound.volume = vol
        sound.stop()
        sound.play()
    }

    private func sound(for id: String) -> NSSound? {
        if let cached = cache[id] { return cached }
        let made: NSSound?
        if id.hasPrefix("system:") {
            made = NSSound(named: String(id.dropFirst("system:".count)))
        } else if id.hasPrefix("custom:") {
            let url = CheckOffSound.soundsDir
                .appendingPathComponent(String(id.dropFirst("custom:".count)))
            made = NSSound(contentsOf: url, byReference: true)
        } else {
            made = nil
        }
        if let made { cache[id] = made }
        return made
    }
}
