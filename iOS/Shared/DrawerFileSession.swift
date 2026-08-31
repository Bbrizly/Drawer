import FileProvider
import Foundation

enum DrawerStorageKind: Equatable, Sendable {
    case iCloudDrive
    case files

    var displayName: String {
        switch self {
        case .iCloudDrive: "iCloud Drive"
        case .files: "On My iPhone / Files"
        }
    }
}

enum DrawerFileAccessError: LocalizedError {
    case waitingForICloud
    case iCloudConflict
    case providerUnavailable(DrawerStorageKind)
    case authenticationRequired(DrawerStorageKind)
    case itemMissing
    case permissionDenied
    case notRegularFile
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .waitingForICloud:
            "Drawer.md is syncing from iCloud. Drawer will retry automatically."
        case .iCloudConflict:
            "iCloud has an unresolved conflict for Drawer.md. Resolve it in Files or Obsidian before Drawer writes anything."
        case .providerUnavailable(let storage):
            "\(storage.displayName) isn't available right now. Drawer kept your connection and will retry."
        case .authenticationRequired(let storage):
            "\(storage.displayName) needs account access again. Open Files or the provider app, sign in if needed, then return to Drawer."
        case .itemMissing:
            "Drawer.md was moved or deleted. If it still exists, choose it again."
        case .permissionDenied:
            "Drawer no longer has permission to access Drawer.md. Choose the file again."
        case .notRegularFile:
            "Choose a Markdown file, not a folder or package."
        case .readFailed(let message):
            "Drawer couldn't read Drawer.md: \(message)"
        case .writeFailed(let message):
            "Drawer couldn't save Drawer.md: \(message)"
        }
    }

    var isTransient: Bool {
        switch self {
        case .waitingForICloud, .providerUnavailable:
            true
        default:
            false
        }
    }

    var widgetMessage: String {
        switch self {
        case .waitingForICloud:
            "Drawer.md is syncing from iCloud. Open Drawer to finish syncing, then retry."
        case .providerUnavailable:
            "Drawer.md's Files provider is unavailable. Open Drawer to retry."
        case .authenticationRequired:
            "Drawer.md's Files provider needs account access. Open Drawer to reconnect."
        case .iCloudConflict:
            "Drawer.md has an iCloud conflict. Resolve it in Files or Obsidian first."
        case .itemMissing, .permissionDenied:
            "Open Drawer to reconnect Drawer.md."
        case .notRegularFile, .readFailed, .writeFailed:
            "Update failed. Open Drawer and try again."
        }
    }
}

/// A short-lived, explicitly scoped handle to the user's canonical Drawer.md.
/// Every read/write is coordinated so Obsidian, iCloud and File Provider apps
/// get a chance to reconcile their own state around the operation.
///
/// The source may be an On My iPhone file, an iCloud Drive item, or a document
/// exposed by another Files provider. iCloud is special-cased because Apple can
/// leave a stale/evicted local placeholder. Drawer never reads that placeholder
/// as canonical truth and never writes until iCloud reports the local copy is
/// current.
final class DrawerFileSession {
    let url: URL
    let storageKind: DrawerStorageKind
    private let didStartAccess: Bool

    init(url: URL) {
        self.url = url
        self.didStartAccess = url.startAccessingSecurityScopedResource()
        self.storageKind = Self.storageKind(for: url)
    }

    deinit {
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func read() throws -> Data {
        try preflight(writing: false)

        var coordinationError: NSError?
        var readError: Error?
        var result: Data?

        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                result = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            throw Self.mapAccessError(coordinationError, storage: storageKind, writing: false)
        }
        if let readError {
            throw Self.mapAccessError(readError, storage: storageKind, writing: false)
        }
        guard let result else { throw DrawerFileAccessError.permissionDenied }
        return result
    }

    func write(_ data: Data) throws {
        try preflight(writing: true)

        var coordinationError: NSError?
        var writeError: Error?

        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw Self.mapAccessError(coordinationError, storage: storageKind, writing: true)
        }
        if let writeError {
            throw Self.mapAccessError(writeError, storage: storageKind, writing: true)
        }
    }

    /// Public to the test target through @testable so the storage invariant is
    /// regression-tested without requiring an actual iCloud account in CI.
    static func iCloudNeedsMaterialization(
        _ status: URLUbiquitousItemDownloadingStatus?
    ) -> Bool {
        status == .notDownloaded || status == .downloaded
    }

    private func preflight(writing: Bool) throws {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isReadableKey,
            .isWritableKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey,
            .ubiquitousItemHasUnresolvedConflictsKey,
        ]

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: keys)
        } catch {
            // Some providers are lazy about metadata even though coordinated
            // file access succeeds. Only stop here for errors we can identify
            // as meaningful access failures; otherwise let coordination decide.
            if let known = Self.knownAccessError(error, storage: storageKind) {
                throw known
            }
            return
        }

        if values.isRegularFile == false {
            throw DrawerFileAccessError.notRegularFile
        }

        if values.isUbiquitousItem == true {
            if values.ubiquitousItemHasUnresolvedConflicts == true {
                throw DrawerFileAccessError.iCloudConflict
            }

            if let downloadError = values.ubiquitousItemDownloadingError {
                throw Self.mapAccessError(downloadError, storage: .iCloudDrive, writing: writing)
            }

            if Self.iCloudNeedsMaterialization(values.ubiquitousItemDownloadingStatus) {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    throw Self.mapAccessError(error, storage: .iCloudDrive, writing: writing)
                }
                throw DrawerFileAccessError.waitingForICloud
            }
        }

        if values.isReadable == false {
            throw DrawerFileAccessError.permissionDenied
        }
        if writing, values.isWritable == false {
            throw DrawerFileAccessError.permissionDenied
        }
    }

    private static func storageKind(for url: URL) -> DrawerStorageKind {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        return values?.isUbiquitousItem == true ? .iCloudDrive : .files
    }

    private static func knownAccessError(
        _ error: Error,
        storage: DrawerStorageKind
    ) -> DrawerFileAccessError? {
        if let access = error as? DrawerFileAccessError { return access }
        let nsError = error as NSError

        if nsError.domain == NSFileProviderErrorDomain,
           let code = NSFileProviderError.Code(rawValue: nsError.code) {
            switch code {
            case .notAuthenticated:
                return .authenticationRequired(storage)
            case .serverUnreachable:
                return .providerUnavailable(storage)
            case .noSuchItem:
                return .itemMissing
            default:
                // Quota, collision, sync-anchor and other provider errors are
                // not necessarily transient connectivity failures. Let the
                // caller surface their real localized read/write failure rather
                // than entering an automatic retry loop that cannot fix them.
                return nil
            }
        }

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .permissionDenied
            case NSFileNoSuchFileError:
                return .itemMissing
            default:
                break
            }
        }

        return nil
    }

    private static func mapAccessError(
        _ error: Error,
        storage: DrawerStorageKind,
        writing: Bool
    ) -> DrawerFileAccessError {
        if let known = knownAccessError(error, storage: storage) {
            return known
        }

        let message = (error as NSError).localizedDescription
        return writing ? .writeFailed(message) : .readFailed(message)
    }
}
