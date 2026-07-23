import Foundation

/// Persists security-scoped bookmarks so the sandboxed App Store build keeps
/// access to user-picked files across relaunches. Keyed by the path-setting
/// name (drawerFilePath, notesFilePath, ...) so a moved or renamed file can
/// update its own preference after resolution. Inert in the direct build,
/// which runs unsandboxed.
@MainActor
enum SandboxBookmarks {
    static let defaultsKey = "sandboxBookmarks"
    /// The URLs currently holding a security scope, per setting, so a re-pick
    /// releases the old grant instead of leaking it. Scopes for paths in use
    /// are held for the app's lifetime; the process exit releases them.
    private static var active: [String: URL] = [:]

    /// Every path setting whose value can point outside the sandbox container.
    static let userPathKeys = [
        AppPaths.dataFolderPathKey,
        AppPaths.drawerFilePathKey,
        AppPaths.notesFilePathKey,
        AppPaths.workLogFilePathKey,
        AppPaths.workLogMarkdownFilePathKey,
        AppPaths.ideasDirectoryPathKey,
        AppPaths.plannerPrioritiesPathKey,
        AppPaths.parkingLotFilePathKey,
    ]

    /// Called right after an NSOpenPanel pick. The panel's grant covers this
    /// process; the bookmark makes it survive relaunch.
    static func save(url: URL, forSetting key: String) {
        guard appStoreBuild else { return }
        guard let data = try? url.bookmarkData(options: .withSecurityScope) else { return }
        var all = stored()
        all[key] = data
        UserDefaults.standard.set(all, forKey: defaultsKey)
        active[key]?.stopAccessingSecurityScopedResource()
        active[key] = url.startAccessingSecurityScopedResource() ? url : nil
    }

    /// Resolve every saved bookmark and open its scope for the app's lifetime.
    /// Must run before the first file read. A custom path with no resolvable
    /// bookmark (a preferences file carried over from a direct-download
    /// install, or a revoked grant) is reset to the default so the app starts
    /// working instead of failing on an inaccessible path forever.
    static func restoreAll() {
        guard appStoreBuild else { return }
        let defaults = UserDefaults.standard
        var all = stored()
        var dirty = false
        for key in userPathKeys {
            guard let path = defaults.string(forKey: key), !path.isEmpty else { continue }
            guard let data = all[key] else {
                defaults.removeObject(forKey: key)  // no grant for this path
                continue
            }
            var stale = false
            guard let url = try? URL(
                    resolvingBookmarkData: data, options: .withSecurityScope,
                    relativeTo: nil, bookmarkDataIsStale: &stale),
                url.startAccessingSecurityScopedResource()
            else {
                defaults.removeObject(forKey: key)
                all.removeValue(forKey: key)
                dirty = true
                continue
            }
            active[key] = url
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
                all[key] = fresh
                dirty = true
            }
            // The bookmark follows a moved/renamed file; the path setting must too.
            if url.path != path { defaults.set(url.path, forKey: key) }
        }
        if dirty { defaults.set(all, forKey: defaultsKey) }
    }

    private static func stored() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }
}
