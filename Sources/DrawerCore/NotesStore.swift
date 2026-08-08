import Combine
import Foundation

/// One tab in the notes pad: a file, and the short label the tab shows.
public struct NoteTab: Identifiable, Equatable, Sendable {
    public var url: URL
    public var label: String
    public var id: URL { url }
}

/// The scratchpad. Holds one block of text, loads whatever was last written,
/// and saves itself as you type. There is no save button. Edits are debounced
/// so a fast typist triggers one write, not one per key.
///
/// Notes come in tabs, and a tab is a file. The first tab is the notes file
/// itself; the rest live in a `Drawer Notes` folder beside it, so the tab list
/// is just that folder listed. Nothing to keep in sync, nothing to corrupt.
/// Closing a tab moves its file into `Drawer Notes/Removed`, so no note is
/// ever destroyed by a click. Settings clears that folder when you mean it.
@MainActor
public final class NotesStore: ObservableObject {
    @Published public var text: String = "" {
        didSet {
            guard !suppressSave else { return }
            scheduleSave()
        }
    }

    /// Every open tab, first one first. Always holds at least the notes file.
    @Published public private(set) var tabs: [NoteTab] = []
    @Published public private(set) var activeIndex = 0

    /// The file the text currently belongs to.
    public private(set) var fileURL: URL
    /// The notes file proper. Always tab one, never closeable.
    public let primaryURL: URL

    private let readString: (URL) throws -> String
    private let writeString: (String, URL) throws -> Void
    private let debounce: TimeInterval
    private var saveTask: Task<Void, Never>?
    private var suppressSave = false

    public var tabsDirectory: URL {
        primaryURL.deletingLastPathComponent()
            .appendingPathComponent("Drawer Notes", isDirectory: true)
    }

    /// Where closed tabs go. Kept, not deleted; Settings > Storage empties it.
    public var removedDirectory: URL {
        tabsDirectory.appendingPathComponent("Removed", isDirectory: true)
    }

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
        self.primaryURL = fileURL
        self.debounce = max(0, debounce)
        self.readString = readString
        self.writeString = writeString
    }

    /// Reads the file into `text` without scheduling a save back.
    public func load() {
        suppressSave = true
        defer { suppressSave = false }
        text = (try? readString(fileURL)) ?? ""
        refreshTabs()
    }

    /// Writes the current text right now, cancelling any pending debounce.
    /// Call this on teardown so nothing typed in the last moment is lost.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        write(text)
    }

    // MARK: tabs

    public func select(_ index: Int) {
        guard tabs.indices.contains(index), index != activeIndex else { return }
        saveNow()
        open(index)
    }

    /// Adds a tab: a new empty file in the notes folder, opened straight away.
    public func addTab() {
        saveNow()
        let url = freshTabURL()
        try? writeString("", url)
        refreshTabs()
        if let index = tabs.firstIndex(where: { $0.url == url }) { open(index) }
    }

    /// Closes a tab. The file is moved aside, never deleted: a stray click on
    /// a minus should not be able to lose writing. Tab one cannot be closed.
    public func removeTab(at index: Int) {
        guard index > 0, tabs.indices.contains(index) else { return }
        // Always, even when the tab going away is not the open one: the
        // refresh below can re-read the open file, and anything still sitting
        // in the debounce would be read back over.
        saveNow()
        let closingOpenTab = tabs[index].url == fileURL
        let url = tabs[index].url
        let fm = FileManager.default
        try? fm.createDirectory(at: removedDirectory, withIntermediateDirectories: true)
        var target = removedDirectory.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = removedDirectory.appendingPathComponent(
                "\(url.deletingPathExtension().lastPathComponent) \(n).\(url.pathExtension)")
            n += 1
        }
        try? fm.moveItem(at: url, to: target)
        if closingOpenTab { fileURL = primaryURL }
        refreshTabs()
        if closingOpenTab { open(activeIndex) }
    }

    /// Rebuilds the tab list from disk. The notes file first, then whatever
    /// `.md` files sit in the notes folder, by name.
    public func refreshTabs() {
        let extras = (try? FileManager.default.contentsOfDirectory(
            at: tabsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        // Rebuilt from names, not from what the listing handed back: it
        // resolves symlinks in the path, so its URLs never compare equal to
        // the ones we make ourselves.
        let urls = [primaryURL] + extras
            .filter { $0.pathExtension.lowercased() == "md" }
            .map(\.lastPathComponent)
            .sorted()
            .map { tabsDirectory.appendingPathComponent($0) }
        // File names first, so nothing waits on IO. The real labels are the
        // notes' own first lines and they land a beat later; reading a folder
        // of files on the main thread at launch is how you freeze a launch.
        tabs = urls.map {
            NoteTab(url: $0, label: $0.deletingPathExtension().lastPathComponent)
        }
        if let index = tabs.firstIndex(where: { $0.url == fileURL }) {
            activeIndex = index
        } else {
            // The open file went away outside the app. Fall back to the notes
            // file and pull its text in, or the next keystroke writes the
            // vanished note over it.
            fileURL = primaryURL
            open(0)
        }
        refreshLabels()
    }

    /// Fills in each tab's first-line label off the main thread.
    private func refreshLabels() {
        let read = readString
        let urls = tabs.map(\.url)
        let open = fileURL
        let openText = text
        Task { [weak self] in
            let labels = await Task.detached(priority: .utility) {
                urls.map { url -> String in
                    let fallback = url.deletingPathExtension().lastPathComponent
                    if url == open { return Self.label(for: openText, fallback: fallback) }
                    return Self.label(for: (try? read(url)) ?? "", fallback: fallback)
                }
            }.value
            guard let self, self.tabs.map(\.url) == urls else { return }
            for (i, label) in labels.enumerated() { self.tabs[i].label = label }
        }
    }

    /// A tab's short name: the note's first real line, else the file name. A
    /// note titled by its own first line needs no rename UI.
    nonisolated public static func label(for text: String, fallback: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let trimmed = (first.map(String.init) ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#-* \t"))
        guard !trimmed.isEmpty else { return fallback }
        return trimmed.count > 18 ? String(trimmed.prefix(17)) + "\u{2026}" : trimmed
    }

    /// Points the store at a tab and pulls its text in. No save on the way
    /// out; callers that might have unsaved edits flush first.
    private func open(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        fileURL = tabs[index].url
        suppressSave = true
        text = (try? readString(fileURL)) ?? ""
        suppressSave = false
    }

    private func freshTabURL() -> URL {
        let taken = Set(tabs.map { $0.url.lastPathComponent })
        var n = 2
        while taken.contains("Note \(n).md") { n += 1 }
        return tabsDirectory.appendingPathComponent("Note \(n).md")
    }

    // MARK: saving

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
        // The tab wears the note's first line, so it follows what you type.
        if tabs.indices.contains(activeIndex) {
            let fallback = fileURL.deletingPathExtension().lastPathComponent
            tabs[activeIndex].label = Self.label(for: value, fallback: fallback)
        }
    }
}
