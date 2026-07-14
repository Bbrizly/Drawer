import Foundation

/// The full contents of `bureau-receipts.json`: schema per `bureau-impl.md`
/// section 5. `lifetimeFiled` is the FILED tray's engraved counter (spec
/// Decision 4); it survives the tray clearing every Monday.
public struct ReceiptDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var lifetimeFiled: Int
    public var receipts: [ReceiptLink]

    public init(version: Int = 1, lifetimeFiled: Int = 0, receipts: [ReceiptLink] = []) {
        self.version = version
        self.lifetimeFiled = lifetimeFiled
        self.receipts = receipts
    }
}

/// Holds every receipt (queued, in the drawer, sticky, filed, expired) and
/// saves them to `bureau-receipts.json`. Modeled on `BoardStore`: IO is
/// injected so tests never touch disk, writes are atomic, and the directory
/// is a plain `URL` rather than reaching into `AppPaths` (see the type doc
/// on why).
///
/// `DrawerBureau` depends on `DrawerCore` only (`Package.swift`); `AppPaths`
/// lives in the `Drawer` executable target, which depends on `DrawerBureau`,
/// not the other way around. So the data directory is threaded in from the
/// call site (`AppPaths.drawerDataDirectory` today) instead of this target
/// importing `AppPaths` directly.
@MainActor
public final class ReceiptStore: ObservableObject {
    @Published public private(set) var document = ReceiptDocument()

    public let directory: URL
    public var receiptsFile: URL { directory.appendingPathComponent("bureau-receipts.json") }

    private let readData: (URL) throws -> Data
    private let writeData: (Data, URL) throws -> Void

    public convenience init(directory: URL) {
        self.init(
            directory: directory,
            readData: { try Data(contentsOf: $0) },
            writeData: { data, url in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            }
        )
        load()
    }

    init(
        directory: URL,
        readData: @escaping (URL) throws -> Data,
        writeData: @escaping (Data, URL) throws -> Void
    ) {
        self.directory = directory
        self.readData = readData
        self.writeData = writeData
    }

    /// Reads bureau-receipts.json into memory. A missing or unreadable file
    /// leaves an empty document (best-effort, like `BoardStore.load`).
    public func load() {
        guard let data = try? readData(receiptsFile),
              let doc = try? Self.decoder.decode(ReceiptDocument.self, from: data)
        else {
            document = ReceiptDocument()
            return
        }
        document = doc
    }

    /// Writes the current document now.
    // ponytail: every mutation below writes synchronously, no debounce. Fine
    // for queue/print/stamp-rate mutations; if R2's drag physics starts
    // writing a position every frame, add BoardStore's debounce-and-coalesce
    // pattern (`scheduleSave`/`saveNow`) here rather than throttling calls.
    public func save() {
        guard let data = try? Self.encoder.encode(document) else { return }
        try? writeData(data, receiptsFile)
    }

    // MARK: mutations

    public func add(_ link: ReceiptLink) {
        document.receipts.append(link)
        save()
    }

    public func update(_ link: ReceiptLink) {
        guard let i = document.receipts.firstIndex(where: { $0.id == link.id }) else { return }
        document.receipts[i] = link
        save()
    }

    /// Applies a batch of settled positions/rotations in one write, so a
    /// drawer coming to rest after a rummage saves its whole layout once instead
    /// of a write per receipt (R2 deliverable 6). Ids not present are ignored.
    public func updatePositions(_ changes: [UUID: (ReceiptPosition, Double)]) {
        guard !changes.isEmpty else { return }
        var touched = false
        for i in document.receipts.indices {
            guard let (position, rotation) = changes[document.receipts[i].id] else { continue }
            document.receipts[i].position = position
            document.receipts[i].rotation = rotation
            touched = true
        }
        if touched { save() }
    }

    public func remove(_ id: UUID) {
        guard document.receipts.contains(where: { $0.id == id }) else { return }
        document.receipts.removeAll { $0.id == id }
        save()
    }

    /// Marks a receipt filed and bumps the lifetime counter. The DONE stamp
    /// path (R4) calls this after `TodoStore.toggle` checks the task off.
    public func file(_ id: UUID) {
        guard let i = document.receipts.firstIndex(where: { $0.id == id }) else { return }
        document.receipts[i].state = .filed
        document.lifetimeFiled += 1
        save()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
