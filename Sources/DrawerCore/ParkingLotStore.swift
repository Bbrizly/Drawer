import Combine
import Foundation

/// The parking lot file: loaded on start, watched for outside edits, and
/// spliced back one idea at a time as you type. There is no save button.
/// Mirrors NotesStore's debounce and FileWatcher wiring.
@MainActor
public final class ParkingLotStore: ObservableObject {
    @Published public private(set) var document = ParkingLotDocument()

    public let fileURL: URL
    private var text = ""
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
        // Our own atomic write comes back through the watcher; skip the noop.
        guard read != text else { return }
        text = read
        document = ParkingLotParser.parse(text)
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

    /// Capture: appends to the Unsorted bay stamped with today's date.
    public func park(title: String, details: String) {
        apply(ParkingLotWriteback.append(
            title: title, details: details, parked: todayProvider(),
            color: nil, toBay: "Unsorted", in: text))
    }

    /// Writes right now, cancelling any pending debounce. Call on teardown.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        try? writeString(text, fileURL)
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
            // Best effort, same as NotesStore: the next edit tries again.
            try? self.writeString(snapshot, self.fileURL)
            self.saveTask = nil
        }
    }
}
