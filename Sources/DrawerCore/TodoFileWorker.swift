import Foundation

/// One transaction's finished work: the bytes that are now on disk and the
/// parsed sections the UI shows. Built off the main actor and handed over whole,
/// so the main actor only assigns already-computed arrays.
struct TodoDisplaySnapshot: Sendable {
    var data: Data
    var today: [TodoItem]
    var carried: [TodoItem]
    var upcoming: [TodoItem]
    var upcomingDate: String?
    var backlog: [TodoItem]
    var archive: [TodoItem]
}

/// What a file transaction ended up meaning for the display.
enum TodoFileOutcome: Sendable {
    /// Our own write came back, or a sibling file in the watched directory
    /// moved. What is on screen is already right, so publish nothing.
    case unchanged
    case display(TodoDisplaySnapshot)
    case missingFile
    case unreadable
    case notUTF8
    /// A write that the user asked for did not land.
    case writeFailed
}

enum TodoFileError: Error {
    case notUTF8
}

/// Owns every read, write, sweep and parse of the drawer file. All of it used to
/// run inline on the main actor, which meant a reload blocked the frame for as
/// long as the disk and the parser took.
///
/// Each method here runs to completion with no suspension point inside it, so a
/// transaction is atomic: nothing can read the file between this one's compute
/// read and its CAS re-read. `TodoStore` chains the calls so they also stay in
/// the order they were asked for.
actor TodoFileWorker {
    private var fileURL: URL
    private let readData: (URL) throws -> Data
    private let writeData: (Data, URL) throws -> Void
    /// Bytes this app just wrote. The watcher fires on our own write; the next
    /// reload swallows exactly one match and clears it.
    private var lastWrittenData: Data?
    /// Bytes the current display was parsed from. The watcher covers the whole
    /// directory, so sibling saves fire reloads constantly; identical bytes mean
    /// there is nothing to re-parse or re-publish.
    private var lastAppliedData: Data?

    init(
        fileURL: URL,
        readData: @escaping (URL) throws -> Data,
        writeData: @escaping (Data, URL) throws -> Void
    ) {
        self.fileURL = fileURL
        self.readData = readData
        self.writeData = writeData
    }

    /// Points at a different file. Both suppression caches describe the old
    /// file's bytes, so they go with it.
    func setFileURL(_ url: URL) {
        fileURL = url
        lastWrittenData = nil
        lastAppliedData = nil
    }

    /// Day changed: identical bytes no longer mean an identical display, so
    /// neither cache can be trusted to skip the parse.
    func forgetSuppression() {
        lastWrittenData = nil
        lastAppliedData = nil
    }

    /// Read, sweep archived tasks if any are due, parse. Returns `.unchanged`
    /// when the bytes are ours or unchanged since the last publish.
    func reload(today: String) -> TodoFileOutcome {
        let data: Data
        do {
            data = try readData(fileURL)
        } catch {
            lastAppliedData = nil
            return isMissingFileError(error) ? .missingFile : .unreadable
        }
        // Self-write suppression: skip reload churn for our own write.
        if let last = lastWrittenData {
            lastWrittenData = nil
            if data == last { return .unchanged }
        }
        // Sibling-file suppression: the directory watcher fired but the drawer
        // file itself did not change, so what is displayed is already right.
        if data == lastAppliedData { return .unchanged }
        // Sweep done tasks older than the keep window into Archive > Done.
        // Idempotent and only writes when something actually moved, so the
        // follow-up watcher event is caught by the suppression check above.
        if let text = String(data: data, encoding: .utf8) {
            let swept = TodoArchiver.archiveCompleted(in: text, today: today)
            if swept != text, let sweptData = swept.data(using: .utf8) {
                do {
                    lastWrittenData = sweptData
                    try writeData(sweptData, fileURL)
                    return parse(sweptData, today: today)
                } catch {
                    lastWrittenData = nil
                    // Fall through and show the data we already read.
                }
            }
        }
        return parse(data, today: today)
    }

    /// Reads, runs a writeback transform, and writes with a one-shot content-CAS:
    /// if the file changed between our read and the write (a concurrent
    /// Obsidian/iCloud/MCP save), the transform is recomputed once against the
    /// fresh bytes so that edit is not clobbered. The writeback transforms locate
    /// their target by section + occurrence + exact rawLine, so replaying against
    /// fresh bytes hits the same logical task. `lastWrittenData` is set only after
    /// the write succeeds, so a thrown write never leaves a stale suppression
    /// value that swallows the next external reload.
    /// ponytail: one re-read, not a loop or a file lock. A single external editor
    /// is the only other writer in practice; upgrade to NSFileCoordinator if
    /// cross-process races ever matter.
    func commit(
        today: String,
        readingMissingAsEmpty: Bool,
        _ transform: (Data) throws -> Data
    ) throws -> TodoDisplaySnapshot {
        func currentData() throws -> Data {
            do { return try readData(fileURL) }
            catch where readingMissingAsEmpty && isMissingFileError(error) { return Data() }
        }
        do {
            var data = try currentData()
            var newData = try transform(data)
            let fresh = try currentData()
            if fresh != data {
                data = fresh
                newData = try transform(data)
            }
            try writeData(newData, fileURL)
            lastWrittenData = newData
            guard case let .display(snapshot) = parse(newData, today: today) else {
                throw TodoFileError.notUTF8
            }
            return snapshot
        } catch {
            lastWrittenData = nil
            throw error
        }
    }

    /// A transform that never surfaces its failure: on a stale line, a vanished
    /// file or a write error it drops the self-write guard and reloads the truth
    /// on disk. One operation, so nothing lands between the failure and the
    /// re-read.
    func mutate(today: String, _ transform: (Data) throws -> Data) -> TodoFileOutcome {
        do {
            return .display(try commit(today: today, readingMissingAsEmpty: false, transform))
        } catch {
            lastWrittenData = nil
            return reload(today: today)
        }
    }

    /// A transform the user asked for by name (add, insert). A failure is worth
    /// saying out loud rather than silently reloading.
    func write(
        today: String,
        readingMissingAsEmpty: Bool,
        _ transform: (Data) throws -> Data
    ) -> TodoFileOutcome {
        do {
            return .display(
                try commit(today: today, readingMissingAsEmpty: readingMissingAsEmpty, transform))
        } catch {
            return .writeFailed
        }
    }

    private func parse(_ data: Data, today: String) -> TodoFileOutcome {
        guard let text = String(data: data, encoding: .utf8) else {
            lastAppliedData = nil
            return .notUTF8
        }
        let display = TodoParser.display(sections: TodoParser.parse(text), today: today)
        lastAppliedData = data
        return .display(TodoDisplaySnapshot(
            data: data,
            today: display.today,
            carried: display.carried,
            upcoming: display.upcoming,
            upcomingDate: display.upcomingDate,
            backlog: display.backlog,
            archive: display.archive
        ))
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.fileReadNoSuchFile.rawValue
    }
}
