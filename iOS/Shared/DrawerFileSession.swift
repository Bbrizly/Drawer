import Foundation

/// A short-lived, explicitly scoped handle to the user's canonical Drawer.md.
/// Every read/write is coordinated so Obsidian, iCloud and File Provider apps
/// get a chance to reconcile their own state around the operation.
final class DrawerFileSession {
    let url: URL
    private let didStartAccess: Bool

    init(url: URL) {
        self.url = url
        self.didStartAccess = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func read() throws -> Data {
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

        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let result else { throw DrawerBookmarkError.accessDenied }
        return result
    }

    func write(_ data: Data) throws {
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

        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
