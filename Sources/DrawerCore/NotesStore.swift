import Combine
import Foundation

/// A single always-there scratchpad. Holds one block of text, loads whatever
/// was last written, and saves itself as you type. There is no save button.
/// Edits are debounced so a fast typist triggers one write, not one per key.
@MainActor
public final class NotesStore: ObservableObject {
    @Published public var text: String = "" {
        didSet {
            guard !suppressSave else { return }
            scheduleSave()
        }
    }

    public let fileURL: URL
    private let readString: (URL) throws -> String
    private let writeString: (String, URL) throws -> Void
    private let debounce: TimeInterval
    private var saveTask: Task<Void, Never>?
    private var suppressSave = false

    public convenience init(fileURL: URL, debounce: TimeInterval = 0.4) {
        self.init(
            fileURL: fileURL,
            debounce: debounce,
            readString: { try String(contentsOf: $0, encoding: .utf8) },
            writeString: { value, url in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try value.write(to: url, atomically: true, encoding: .utf8)
            }
        )
    }

    init(
        fileURL: URL,
        debounce: TimeInterval,
        readString: @escaping (URL) throws -> String,
        writeString: @escaping (String, URL) throws -> Void
    ) {
        self.fileURL = fileURL
        self.debounce = max(0, debounce)
        self.readString = readString
        self.writeString = writeString
    }

    /// Reads the file into `text` without scheduling a save back.
    public func load() {
        suppressSave = true
        defer { suppressSave = false }
        text = (try? readString(fileURL)) ?? ""
    }

    /// Writes the current text right now, cancelling any pending debounce.
    /// Call this on teardown so nothing typed in the last moment is lost.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        write(text)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        let delay = debounce
        saveTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            self.write(snapshot)
        }
    }

    private func write(_ value: String) {
        // Best-effort scratchpad. A failed write is not worth interrupting
        // typing for, and the next keystroke will try again.
        try? writeString(value, fileURL)
    }
}
