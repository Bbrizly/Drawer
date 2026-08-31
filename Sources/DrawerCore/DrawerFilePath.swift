import Foundation

/// The drawer-file default and the resolution chain, in DrawerCore so the app
/// and the pure-Foundation MCP binary resolve the file identically. First hit
/// wins: `--file` argument, `DRAWER_FILE` env, the app's saved default (read via
/// CFPreferences, MCP-side), then `DrawerFilePath.default`.
public enum DrawerFilePath {
    #if os(iOS)
        /// iOS never implicitly reaches into a desktop-style home directory.
        /// The mobile app uses a user-selected, security-scoped Drawer.md; this
        /// container-local value only keeps the shared resolver well-defined
        /// for callers that explicitly use it on iOS.
        public static let `default`: String = (FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Drawer.md")
            .path
    #elseif APPSTORE
        /// Sandboxed macOS default: Drawer.md in the container's Documents
        /// folder, writable with no grant. Users can pick their vault file via
        /// the panel, which persists a security-scoped bookmark.
        public static let `default`: String = (FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents"))
            .appendingPathComponent("Drawer.md")
            .path
    #else
        /// The shared macOS default location: Drawer.md in the Obsidian iCloud
        /// vault. `AppPaths.defaultDrawerFile` points here so both desktop
        /// targets agree.
        public static let `default`: String = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents")
            .appendingPathComponent("My life/1 Projects/Drawer.md")
            .path
    #endif

    /// Resolves the drawer file by precedence. `storedDefault` is the app's
    /// saved `drawerFilePath` (nil/empty when unset); the MCP binary reads it
    /// with `storedAppDefault(bundleID:)`, the app passes its own AppStorage.
    public static func resolve(
        arguments: [String],
        environment: [String: String],
        storedDefault: String?
    ) -> String {
        if let i = arguments.firstIndex(of: "--file"), i + 1 < arguments.count,
           !arguments[i + 1].isEmpty {
            return arguments[i + 1]
        }
        if let env = environment["DRAWER_FILE"], !env.isEmpty {
            return env
        }
        if let stored = storedDefault, !stored.isEmpty {
            return stored
        }
        return `default`
    }

    /// Reads the app's saved `drawerFilePath` from its preferences domain,
    /// without linking the app. The MCP binary uses this for step 3 of the
    /// chain; nil when the user never set a custom path.
    public static func storedAppDefault(bundleID: String) -> String? {
        CFPreferencesCopyAppValue(
            "drawerFilePath" as CFString, bundleID as CFString
        ) as? String
    }
}
