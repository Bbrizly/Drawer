import Foundation

enum DrawerBookmarkError: LocalizedError {
    case missingBookmark
    case missingPendingBookmark
    case accessDenied
    case invalidEncoding
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .missingBookmark:
            "No Drawer.md is connected."
        case .missingPendingBookmark:
            "The pending Drawer.md selection is no longer available. Choose the file again."
        case .accessDenied:
            "Drawer no longer has permission to access that file. Choose Drawer.md again."
        case .invalidEncoding:
            "That file isn't UTF-8 Markdown. Choose a UTF-8 Drawer.md file."
        case .appGroupUnavailable:
            "Drawer's shared app container is unavailable. Check the App Group entitlement."
        }
    }
}

enum DrawerBookmarkSaveOutcome: Equatable {
    case ready
    case staged
}

enum DrawerBookmarkStore {
    static var hasBookmark: Bool {
        guard DrawerShared.containerURL != nil else { return false }
        return DrawerShared.defaults.data(forKey: DrawerShared.bookmarkKey) != nil
    }

    static var hasPendingBookmark: Bool {
        guard DrawerShared.containerURL != nil else { return false }
        return DrawerShared.defaults.data(forKey: DrawerShared.pendingBookmarkKey) != nil
    }

    /// Persist a document-picker grant transactionally.
    ///
    /// A normal/local selection is promoted only after proving it is readable
    /// UTF-8 Markdown. If iCloud or another Files provider has granted the URL
    /// but the source needs download, provider recovery, authentication, or
    /// conflict resolution, keep the new bookmark in a separate pending slot.
    /// The previous canonical bookmark remains intact until the pending source
    /// produces a real successful read.
    static func save(_ pickedURL: URL) throws -> DrawerBookmarkSaveOutcome {
        guard DrawerShared.containerURL != nil else {
            throw DrawerBookmarkError.appGroupUnavailable
        }

        let data = try makeBookmarkData(for: pickedURL)
        let probe = DrawerFileSession(url: pickedURL)

        do {
            let contents = try probe.read()
            guard String(data: contents, encoding: .utf8) != nil else {
                throw DrawerBookmarkError.invalidEncoding
            }

            DrawerShared.defaults.set(data, forKey: DrawerShared.bookmarkKey)
            DrawerShared.defaults.removeObject(forKey: DrawerShared.pendingBookmarkKey)
            return .ready
        } catch let accessError as DrawerFileAccessError where accessError.preservesSelectedGrant {
            // A newer viable selection supersedes an older pending attempt.
            // Terminal validation failures never disturb the source (primary or
            // pending) that was already in use.
            DrawerShared.defaults.set(data, forKey: DrawerShared.pendingBookmarkKey)
            return .staged
        }
    }

    static func clear() {
        DrawerShared.defaults.removeObject(forKey: DrawerShared.bookmarkKey)
        DrawerShared.defaults.removeObject(forKey: DrawerShared.pendingBookmarkKey)
    }

    static func discardPending() {
        DrawerShared.defaults.removeObject(forKey: DrawerShared.pendingBookmarkKey)
    }

    /// Commit a staged source only after its session has completed a real UTF-8
    /// canonical read. This preserves Change Drawer.md's rollback guarantee even
    /// when a File Provider needed time or user action before making the source
    /// safe to read.
    static func promotePending() throws {
        guard DrawerShared.containerURL != nil else {
            throw DrawerBookmarkError.appGroupUnavailable
        }
        guard let data = DrawerShared.defaults.data(forKey: DrawerShared.pendingBookmarkKey) else {
            throw DrawerBookmarkError.missingPendingBookmark
        }

        DrawerShared.defaults.set(data, forKey: DrawerShared.bookmarkKey)
        DrawerShared.defaults.removeObject(forKey: DrawerShared.pendingBookmarkKey)
    }

    static func openSession() throws -> DrawerFileSession {
        guard DrawerShared.containerURL != nil else {
            throw DrawerBookmarkError.appGroupUnavailable
        }
        guard let data = DrawerShared.defaults.data(forKey: DrawerShared.bookmarkKey) else {
            throw DrawerBookmarkError.missingBookmark
        }

        return try openSession(from: data, refreshKey: DrawerShared.bookmarkKey)
    }

    static func openPendingSession() throws -> DrawerFileSession {
        guard DrawerShared.containerURL != nil else {
            throw DrawerBookmarkError.appGroupUnavailable
        }
        guard let data = DrawerShared.defaults.data(forKey: DrawerShared.pendingBookmarkKey) else {
            throw DrawerBookmarkError.missingPendingBookmark
        }

        return try openSession(from: data, refreshKey: DrawerShared.pendingBookmarkKey)
    }

    private static func openSession(from data: Data, refreshKey: String) throws -> DrawerFileSession {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI, .withoutImplicitStartAccessing],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )

        let session = DrawerFileSession(url: url)
        if stale {
            // This is the same logical selection, not a source replacement, so
            // refreshing bookmark bytes is safe even if the provider is still
            // making file contents available.
            if let refreshed = try? makeBookmarkData(for: url) {
                DrawerShared.defaults.set(refreshed, forKey: refreshKey)
            }
        }
        return session
    }

    private static func makeBookmarkData(for url: URL) throws -> Data {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }

        // A file picked from Files normally returns true above. Still attempt
        // bookmark creation when it doesn't: iOS' file security model can keep
        // a valid scoped URL even when the explicit start call reports false.
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [
                .nameKey,
                .contentModificationDateKey,
                .isUbiquitousItemKey,
            ],
            relativeTo: nil
        )
    }
}
