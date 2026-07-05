import CryptoKit
import Foundation

/// One entry in the history index: when it was captured, the SHA-256 of the
/// exact file bytes, and the byte count. Blobs are keyed by hash, so identical
/// states share a blob and many index lines can reference one blob.
public struct SnapshotRecord: Codable, Equatable, Sendable {
    public var ts: Date
    public var hash: String
    public var bytes: Int

    public init(ts: Date, hash: String, bytes: Int) {
        self.ts = ts
        self.hash = hash
        self.bytes = bytes
    }
}

public enum SnapshotReadResult: Equatable, Sendable {
    case available(Data)
    case unavailable
}

public enum SnapshotAppendResult: Equatable, Sendable {
    case appended(SnapshotRecord)
    case duplicate
}

public struct PruneResult: Equatable, Sendable {
    public var kept: Int
    public var deletedBlobs: Int
}

/// Injectable filesystem operations so the store's logic is pure and testable.
public struct SnapshotStoreIO: Sendable {
    public var readIndex: @Sendable () throws -> Data
    public var replaceIndex: @Sendable (Data) throws -> Void
    public var appendIndexLine: @Sendable (Data) throws -> Void
    public var blobExists: @Sendable (String) throws -> Bool
    public var writeBlob: @Sendable (String, Data) throws -> Void
    public var readBlob: @Sendable (String) throws -> Data
    public var listBlobs: @Sendable () throws -> [String]
    public var deleteBlob: @Sendable (String) throws -> Void

    public init(
        readIndex: @escaping @Sendable () throws -> Data,
        replaceIndex: @escaping @Sendable (Data) throws -> Void,
        appendIndexLine: @escaping @Sendable (Data) throws -> Void,
        blobExists: @escaping @Sendable (String) throws -> Bool,
        writeBlob: @escaping @Sendable (String, Data) throws -> Void,
        readBlob: @escaping @Sendable (String) throws -> Data,
        listBlobs: @escaping @Sendable () throws -> [String],
        deleteBlob: @escaping @Sendable (String) throws -> Void
    ) {
        self.readIndex = readIndex
        self.replaceIndex = replaceIndex
        self.appendIndexLine = appendIndexLine
        self.blobExists = blobExists
        self.writeBlob = writeBlob
        self.readBlob = readBlob
        self.listBlobs = listBlobs
        self.deleteBlob = deleteBlob
    }
}

/// Append-only, content-addressed history of the drawer file. Snapshots dedupe
/// by hash; retention keeps the last N index lines and garbage-collects blobs
/// by reachability. View-only: it never writes back to Drawer.md.
public struct SnapshotStore: Sendable {
    private let io: SnapshotStoreIO
    private let hash: @Sendable (Data) -> String

    public init(io: SnapshotStoreIO, hash: @escaping @Sendable (Data) -> String = SnapshotStore.sha256Hex) {
        self.io = io
        self.hash = hash
    }

    public static let sha256Hex: @Sendable (Data) -> String = { data in
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Disk-backed store rooted at `directory` (index.jsonl + blobs/). Hashes are
    /// hex, so they are safe blob filenames. Blob/index writes are atomic.
    public init(directory: URL) {
        let indexURL = directory.appendingPathComponent("index.jsonl")
        let blobsDir = directory.appendingPathComponent("blobs", isDirectory: true)
        self.init(io: SnapshotStoreIO(
            readIndex: { (try? Data(contentsOf: indexURL)) ?? Data() },
            replaceIndex: { data in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: indexURL, options: .atomic)
            },
            appendIndexLine: { data in
                let fm = FileManager.default
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                if !fm.fileExists(atPath: indexURL.path) { fm.createFile(atPath: indexURL.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: indexURL)
                defer { try? handle.close() }
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            },
            blobExists: { FileManager.default.fileExists(atPath: blobsDir.appendingPathComponent($0).path) },
            writeBlob: { hash, data in
                try FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
                try data.write(to: blobsDir.appendingPathComponent(hash), options: .atomic)
            },
            readBlob: { try Data(contentsOf: blobsDir.appendingPathComponent($0)) },
            listBlobs: { (try? FileManager.default.contentsOfDirectory(atPath: blobsDir.path)) ?? [] },
            deleteBlob: { try FileManager.default.removeItem(at: blobsDir.appendingPathComponent($0)) }))
    }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    /// Snapshots in order. A corrupt line (a crash mid-append) is skipped, so a
    /// torn final line never poisons the whole timeline.
    public func readRange() -> [SnapshotRecord] {
        guard let data = try? io.readIndex(), let text = String(data: data, encoding: .utf8) else { return [] }
        let (_, dec) = Self.coder()
        return text.split(separator: "\n").compactMap {
            try? dec.decode(SnapshotRecord.self, from: Data($0.utf8))
        }
    }

    /// Captures `bytes` unless they match the latest snapshot's hash. Writes the
    /// blob FIRST, then the index line, so a crash between leaves at worst an
    /// orphan blob (GC reclaims it), never an index line without its blob.
    @discardableResult
    public func append(bytes: Data, ts: Date) throws -> SnapshotAppendResult {
        let digest = hash(bytes)
        if readRange().last?.hash == digest { return .duplicate }
        if try !io.blobExists(digest) { try io.writeBlob(digest, bytes) }
        let record = SnapshotRecord(ts: ts, hash: digest, bytes: bytes.count)
        let (enc, _) = Self.coder()
        var line = try enc.encode(record)
        line.append(contentsOf: Data("\n".utf8))
        try io.appendIndexLine(line)
        return .appended(record)
    }

    /// The exact bytes for a snapshot, or `.unavailable` if its blob is gone
    /// (manual tampering); the scrubber skips unavailable snapshots.
    public func reconstruct(_ record: SnapshotRecord) -> SnapshotReadResult {
        guard let data = try? io.readBlob(record.hash) else { return .unavailable }
        return .available(data)
    }

    /// Keeps the last `limit` index lines and deletes every blob no surviving
    /// line references. GC is by reachability over the SURVIVORS, never by which
    /// lines were removed — a blob shared by a surviving duplicate must stay, or
    /// every earlier snapshot sharing it corrupts silently.
    @discardableResult
    public func prune(keepLast limit: Int) throws -> PruneResult {
        let records = readRange()
        let survivors = limit <= 0 ? [] : Array(records.suffix(limit))
        let reachable = Set(survivors.map(\.hash))

        let (enc, _) = Self.coder()
        let body = try survivors
            .map { String(decoding: try enc.encode($0), as: UTF8.self) }
            .joined(separator: "\n")
        try io.replaceIndex(Data((body.isEmpty ? "" : body + "\n").utf8))

        var deleted = 0
        for blob in (try? io.listBlobs()) ?? [] where !reachable.contains(blob) {
            try io.deleteBlob(blob)
            deleted += 1
        }
        return PruneResult(kept: survivors.count, deletedBlobs: deleted)
    }
}

/// Pure debounce: capture only after the file has been quiet for `quietInterval`.
/// The app owns the real Timer and just asks "given now, is a capture due?", so
/// a burst of edits yields one snapshot and this is testable with an injected
/// clock instead of real time.
public struct QuietPeriodDebouncer: Sendable {
    public var quietInterval: TimeInterval
    private var pendingDeadline: Date?

    public init(quietInterval: TimeInterval) {
        self.quietInterval = quietInterval
    }

    /// A change was observed; push the quiet deadline out.
    public mutating func change(at now: Date) {
        pendingDeadline = now.addingTimeInterval(quietInterval)
    }

    /// True once (and only once) the quiet window has elapsed with no new change.
    public mutating func dueActions(at now: Date) -> Bool {
        guard let deadline = pendingDeadline, now >= deadline else { return false }
        pendingDeadline = nil
        return true
    }
}
