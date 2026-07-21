import Combine
import Foundation

/// The parking lot file: loaded on start, watched for outside edits, and
/// spliced back one idea at a time as you type. There is no save button.
/// Mirrors NotesStore's debounce and FileWatcher wiring.
@MainActor
public final class ParkingLotStore: ObservableObject {
    @Published public private(set) var document = ParkingLotDocument()
    /// Bumped whenever an outside edit replaces the document. Views holding a
    /// position into it (an open card, a bay being renamed) cannot trust that
    /// position afterwards, so they watch this and let go.
    @Published public private(set) var reloads = 0

    public let fileURL: URL
    private var text = ""
    /// What the file held the last time we read or wrote it. A save compares
    /// against this to spot an outside edit that landed mid-flight.
    private var diskText = ""
    private let watcher: FileWatcher
    private let debounce: TimeInterval
    private var saveTask: Task<Void, Never>?
    private let readString: (URL) throws -> String
    private let writeString: (String, URL) throws -> Void
    private let todayProvider: () -> String

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
            },
            todayProvider: TodoStore.localToday
        )
    }

    init(
        fileURL: URL,
        debounce: TimeInterval,
        readString: @escaping (URL) throws -> String,
        writeString: @escaping (String, URL) throws -> Void,
        todayProvider: @escaping () -> String
    ) {
        self.fileURL = fileURL
        self.debounce = max(0, debounce)
        self.readString = readString
        self.writeString = writeString
        self.todayProvider = todayProvider
        self.watcher = FileWatcher(
            directory: fileURL.deletingLastPathComponent(), pollFile: fileURL)
    }

    public func start() {
        watcher.onChange = { [weak self] in self?.load() }
        watcher.start()
        load()
    }

    public func load() {
        // A pending save means in-app edits are newer than the disk; let the
        // debounced write land instead of clobbering it with a stale read.
        guard saveTask == nil else { return }
        let read = (try? readString(fileURL)) ?? ""
        diskText = read
        // Our own atomic write comes back through the watcher; skip the noop.
        guard read != text else { return }
        text = read
        document = ParkingLotParser.parse(text)
        reloads += 1
    }

    public var ideaCount: Int { document.bays.reduce(0) { $0 + $1.ideas.count } }

    public func update(
        bayIndex: Int, ideaIndex: Int, title: String, details: String, color: String?
    ) {
        guard let idea = idea(bayIndex, ideaIndex) else { return }
        apply(ParkingLotWriteback.replace(
            idea, in: text, title: title, details: details, color: color))
    }

    public func delete(bayIndex: Int, ideaIndex: Int) {
        guard let idea = idea(bayIndex, ideaIndex) else { return }
        apply(ParkingLotWriteback.delete(idea, in: text))
    }

    /// The only in-app way to move an idea between bays: drop its lines from
    /// the old bay and append them to the new one, metadata intact.
    public func move(bayIndex: Int, ideaIndex: Int, toBay bay: String) {
        guard let idea = idea(bayIndex, ideaIndex) else { return }
        var next = ParkingLotWriteback.delete(idea, in: text)
        next = ParkingLotWriteback.append(
            title: idea.title, details: idea.details,
            parked: idea.parked, color: idea.color, toBay: bay, in: next)
        apply(next)
    }

    /// Renames a bay. A blank name is ignored, since a heading with no name
    /// would swallow every idea under it on the next parse. A name another bay
    /// already holds is ignored too: bays are looked up by name when an idea
    /// moves, so two that match would quietly swallow each other's cars.
    public func renameBay(index: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard document.bays.indices.contains(index), !trimmed.isEmpty,
              trimmed != document.bays[index].name,
              !document.bays.contains(where: { $0.name == trimmed }) else { return }
        apply(ParkingLotWriteback.renameBay(at: index, to: trimmed, in: text))
    }

    /// Capture: appends to a bay stamped with today's date. Unsorted by
    /// default, which is where the capture bar parks.
    public func park(title: String, details: String, toBay bay: String = "Unsorted") {
        apply(ParkingLotWriteback.append(
            title: title, details: details, parked: todayProvider(),
            color: nil, toBay: bay, in: text))
    }

    /// Writes right now, cancelling any pending debounce. Call on teardown.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        write(text)
    }

    /// The only path to disk. An outside edit that landed while our change was
    /// in flight would be wiped by this write: we hold the whole file, they
    /// changed a copy we never read. Their file beats our one card, so take
    /// theirs and drop ours.
    private func write(_ snapshot: String) {
        let onDisk = (try? readString(fileURL)) ?? ""
        guard onDisk == diskText else {
            load()
            return
        }
        // Best effort, same as NotesStore: the next edit tries again.
        try? writeString(snapshot, fileURL)
        diskText = snapshot
    }

    private func idea(_ bay: Int, _ idea: Int) -> ParkedIdea? {
        guard document.bays.indices.contains(bay),
              document.bays[bay].ideas.indices.contains(idea) else { return nil }
        return document.bays[bay].ideas[idea]
    }

    private func apply(_ newText: String) {
        text = newText
        document = ParkingLotParser.parse(text)
        scheduleSave()
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
            self.saveTask = nil
            self.write(snapshot)
        }
    }
}
