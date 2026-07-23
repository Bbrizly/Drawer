import DrawerCore
import Foundation

/// Every file Drawer reads or writes. Custom paths live in UserDefaults; an
/// empty stored value means "use the default below."
enum AppPaths {
    static let drawerFilePathKey = "drawerFilePath"
    static let notesFilePathKey = "notesFilePath"
    static let workLogFilePathKey = "workLogFilePath"
    static let workLogMarkdownFilePathKey = "workLogMarkdownFilePath"
    static let ideasDirectoryPathKey = "ideasDirectoryPath"
    static let plannerPrioritiesPathKey = "plannerPrioritiesPath"
    static let parkingLotFilePathKey = "parkingLotFilePath"
    static let dataFolderPathKey = "dataFolderPath"

    /// The folder the App Store build asks for on first run. A sandboxed app
    /// writes into a hidden container unless the user picks somewhere, and
    /// App Review rejects user files kept there (guideline 2.4.5). Empty
    /// until the pick; always empty in the direct build, which is not
    /// sandboxed and defaults into the vault.
    static var dataFolder: String {
        guard appStoreBuild else { return "" }
        return UserDefaults.standard.string(forKey: dataFolderPathKey) ?? ""
    }

    /// A user file inside that picked folder, or nil when there is no pick.
    static func inDataFolder(_ name: String, isDirectory: Bool = false) -> String? {
        let folder = dataFolder
        guard !folder.isEmpty else { return nil }
        return URL(fileURLWithPath: folder)
            .appendingPathComponent(name, isDirectory: isDirectory).path
    }

    // The fallback lives in DrawerCore so the MCP binary resolves it identically.
    static var defaultDrawerFile: String {
        inDataFolder("Drawer.md") ?? DrawerFilePath.default
    }

    static var drawerDataDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Drawer", isDirectory: true)
    }

    static var defaultNotesFile: String {
        inDataFolder("Notes.md")
            ?? drawerDataDirectory.appendingPathComponent("notes.md").path
    }

    static var defaultWorkLogFile: String {
        drawerDataDirectory.appendingPathComponent("work-sessions.jsonl").path
    }

    // The direct build defaults into the Obsidian iCloud vault; the App Store
    // build cannot reach outside its container without a user pick, so its
    // defaults stay inside (or, for the priorities file, empty = off).
    static var defaultWorkLogMarkdownFile: String {
        appStoreBuild
            ? (inDataFolder("Work Log.md")
                ?? drawerDataDirectory.appendingPathComponent("Work Log.md").path)
            : FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents")
                .appendingPathComponent("My life/1 Projects/Work Log.md")
                .path
    }

    static var defaultIdeasDirectory: String {
        inDataFolder("Ideas", isDirectory: true)
            ?? drawerDataDirectory.appendingPathComponent("Ideas", isDirectory: true).path
    }

    // Attribution sidecars (spec 02), all local-only under Application Support.
    static var defaultPrioritiesFile: String {
        appStoreBuild
            ? ""  // empty = the planner runs without a priorities file
            : FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents")
                .appendingPathComponent("My life/0 Focus.md")
                .path
    }

    /// The planner priorities file, or nil when the user cleared it (empty =
    /// skip). Absent key = the default focus file (none in the App Store build).
    static var plannerPrioritiesFile: String? {
        if let stored = UserDefaults.standard.string(forKey: plannerPrioritiesPathKey) {
            return stored.isEmpty ? nil : stored
        }
        return defaultPrioritiesFile.isEmpty ? nil : defaultPrioritiesFile
    }

    static var rawActivityFile: URL { drawerDataDirectory.appendingPathComponent("raw-activity.jsonl") }
    static var attributionQueueFile: URL { drawerDataDirectory.appendingPathComponent("attribution-queue.jsonl") }
    static var attributionRulesFile: URL { drawerDataDirectory.appendingPathComponent("attribution-rules.json") }
    static var daySummariesFile: URL { drawerDataDirectory.appendingPathComponent("day-summaries.jsonl") }
    static var daySchedulesFile: URL { drawerDataDirectory.appendingPathComponent("day-schedules.jsonl") }
    static var historyDirectory: URL { drawerDataDirectory.appendingPathComponent("history", isDirectory: true) }

    static func storedPath(forKey key: String, default defaultPath: String) -> String {
        guard let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty else {
            return defaultPath
        }
        return stored
    }

    static var drawerFile: String {
        storedPath(forKey: drawerFilePathKey, default: defaultDrawerFile)
    }

    static var notesFile: URL {
        URL(fileURLWithPath: storedPath(forKey: notesFilePathKey, default: defaultNotesFile))
    }

    static var workLogFile: URL {
        URL(fileURLWithPath: storedPath(forKey: workLogFilePathKey, default: defaultWorkLogFile))
    }

    static var workLogMarkdownFile: URL {
        URL(fileURLWithPath: storedPath(
            forKey: workLogMarkdownFilePathKey, default: defaultWorkLogMarkdownFile))
    }

    static var ideasDirectory: URL {
        URL(fileURLWithPath: storedPath(
            forKey: ideasDirectoryPathKey, default: defaultIdeasDirectory))
    }

    /// Parking lot.md sits next to the resolved drawer file, so it rides the
    /// same resolution chain and the same vault. That assumes nothing about
    /// how you file things: wherever your task file lives, the lot lands
    /// beside it.
    static var defaultParkingLotFile: String {
        URL(fileURLWithPath: drawerFile).deletingLastPathComponent()
            .appendingPathComponent("Parking lot.md").path
    }

    /// Override it when you keep loose ideas somewhere else. The file does not
    /// have to exist yet; the store creates it (and any missing folder) on the
    /// first park.
    static var parkingLotFile: URL {
        let picked = storedPath(
            forKey: parkingLotFilePathKey, default: defaultParkingLotFile)
        // Aiming the lot at the task file would let the lot writer splice its
        // own format over your tasks. Fall back rather than eat the file.
        guard picked != drawerFile else { return URL(fileURLWithPath: defaultParkingLotFile) }
        return URL(fileURLWithPath: picked)
    }

    /// The App Store default is off: the direct build's default target is the
    /// user's vault, which the sandbox can't write without a pick.
    static var defaultExportWorkLogMarkdown: Bool { !appStoreBuild }

    static var exportsWorkLogMarkdown: Bool {
        UserDefaults.standard.object(forKey: "exportWorkLogMarkdown") as? Bool
            ?? defaultExportWorkLogMarkdown
    }

    @MainActor
    static func exportWorkLog(_ workClock: WorkClock) {
        guard exportsWorkLogMarkdown else { return }
        // Merge the AI day-summary sidecar (spec 02) under each day heading.
        let daySummaries = DaySummaryStore(fileURL: daySummariesFile).byDay()
        workClock.exportMarkdown(to: workLogMarkdownFile, daySummaries: daySummaries)
    }
}
