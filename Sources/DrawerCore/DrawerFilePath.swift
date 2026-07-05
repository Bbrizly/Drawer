import Foundation

/// The drawer-file default and the resolution chain, in DrawerCore so the app
/// and the pure-Foundation MCP binary resolve the file identically. First hit
/// wins: `--file` argument, `DRAWER_FILE` env, the app's saved default (read via
/// CFPreferences, MCP-side), then `DrawerFilePath.default`.
public enum DrawerFilePath {
    /// The shared default location: Drawer.md in the Obsidian iCloud vault.
    /// `AppPaths.defaultDrawerFile` points here so both targets agree.
    public static let `default`: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents")
        .appendingPathComponent("My life/1 Projects/Drawer.md")
        .path

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
