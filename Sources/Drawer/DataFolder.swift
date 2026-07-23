import AppKit
import Foundation

/// Asks, on first run of the sandboxed App Store build, where the user's own
/// files should live. Without a pick the sandbox puts them in a hidden
/// container, which App Review rejects for user data (guideline 2.4.5(i)).
/// The pick is remembered as a security-scoped bookmark, so the grant
/// survives a relaunch. Inert in the direct build, which is not sandboxed.
@MainActor
enum DataFolder {
    static var isSet: Bool { !AppPaths.dataFolder.isEmpty }

    /// Shows the folder panel and remembers the pick. False when cancelled;
    /// the app then keeps working out of the container and asks again next
    /// launch, rather than refusing to start.
    @discardableResult
    static func choose() -> Bool {
        // The menu bar app is not frontmost at launch, so the panel would open
        // behind whatever is.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.title = "Choose your Drawer folder"
        panel.message = "Pick a folder for your task file and notes, somewhere you can "
            + "open in Finder. Documents works, or your notes vault."
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        // Read the old locations before the setting moves them.
        let previous = [
            AppPaths.drawerFile, AppPaths.parkingLotFile.path,
            AppPaths.notesFile.path, AppPaths.ideasDirectory.path,
        ]
        SandboxBookmarks.save(url: url, forSetting: AppPaths.dataFolderPathKey)
        UserDefaults.standard.set(url.path, forKey: AppPaths.dataFolderPathKey)
        let moved = [
            AppPaths.drawerFile, AppPaths.parkingLotFile.path,
            AppPaths.notesFile.path, AppPaths.ideasDirectory.path,
        ]
        for (from, to) in zip(previous, moved) { move(from, to) }
        return true
    }

    /// Carries a file already written into the container over to the picked
    /// folder, so nothing typed before the pick disappears. A failed move
    /// falls back to a copy: the settings now point at the new folder, so
    /// leaving the only copy behind in the container would read as lost work.
    private static func move(_ from: String, _ to: String) {
        let fm = FileManager.default
        guard from != to, fm.fileExists(atPath: from), !fm.fileExists(atPath: to) else { return }
        try? fm.createDirectory(
            at: URL(fileURLWithPath: to).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        do {
            try fm.moveItem(atPath: from, toPath: to)
        } catch {
            try? fm.copyItem(atPath: from, toPath: to)
        }
    }
}
