import Foundation

enum DrawerBookmarkError: LocalizedError {
    case missingBookmark
    case accessDenied
    case invalidEncoding
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .missingBookmark:
            "No Drawer.md is connected."
        case .accessDenied:
            "Drawer no longer has permission to access that file. Choose Drawer.md again."
        case .invalidEncoding:
            "That file isn't UTF-8 Markdown. Choose a UTF-8 Drawer.md file."
        case .appGroupUnavailable:
            "Drawer's shared app container is unavailable. Check the App Group entitlement."
        }
    }
}

enum DrawerBookmarkStore {
    static var hasBookmark: Bool {
        guard DrawerShared.containerURL != nil else { return false }
        return DrawerShared.defaults.data(forKey: DrawerShared.bookmarkKey) != nil
    }

    /// Persist the document picker grant only after proving the selected URL is
    /// readable UTF-8 text. A bad replacement therefore cannot overwrite the
    /// last known-good bookmark before Drawer knows it can actually use it.
    static func save(_ pickedURL: URL) throws {
        guard DrawerShared.containerURL != nil else {
            throw DrawerBookmarkError.appGroupUnavailable
        }

        let started = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if started { pickedURL.stopAccessingSecurityScopedResource() }
        }

        // A file picked from Files normally returns true above. Still attempt
        // bookmark creation when it doesn't: iOS' file security model can keep
        // a valid scoped URL even when the explicit start call reports false.
        let data = try pickedURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [.nameKey, .contentModificationDateKey],
            relativeTo: nil
        )

        let probe = DrawerFileSession(url: pickedURL)
        let contents = try probe.read()
        guard String(data: contents, encoding: .utf8) != nil else {
            throw DrawerBookmarkError.invalidEncoding
        }

        // Commit the bookmark last. Until this point an existing connection is
        // untouched, which makes Change Drawer.md transactional from the user's
        // perspective.
        DrawerShared.defaults.set(data, forKey: DrawerShared.bookmarkKey)
    }

    static func clear() {
        DrawerShared.defaults.removeObject(forKey: DrawerShared.bookmarkKey)
    }

    static func openSession() throws -> DrawerFileSession {
        guard DrawerShared.containerURL != nil else {
            throw DrawerBookmarkError.appGroupUnavailable
        }
        guard let data = DrawerShared.defaults.data(forKey: DrawerShared.bookmarkKey) else {
            throw DrawerBookmarkError.missingBookmark
        }

        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI, .withoutImplicitStartAccessing],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )

        let session = DrawerFileSession(url: url)
        if stale {
            // Refresh only after access is established. Failure to refresh the
            // bookmark should not throw away a session that can still read the
            // user's file right now.
            try? save(url)
        }
        return session
    }
}
