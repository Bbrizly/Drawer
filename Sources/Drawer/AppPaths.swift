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

    // The default lives in DrawerCore so the MCP binary resolves it identically.
    static let defaultDrawerFile = DrawerFilePath.default

    static var drawerDataDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Drawer", isDirectory: true)
    }

    static var defaultNotesFile: String {
        drawerDataDirectory.appendingPathComponent("notes.md").path
    }

    static var defaultWorkLogFile: String {
        drawerDataDirectory.appendingPathComponent("work-sessions.jsonl").path
    }

    static var defaultWorkLogMarkdownFile: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents")
            .appendingPathComponent("My life/1 Projects/Work Log.md")
            .path
    }

    static var defaultIdeasDirectory: String {
        drawerDataDirectory.appendingPathComponent("Ideas", isDirectory: true).path
    }

    // Attribution sidecars (spec 02), all local-only under Application Support.
    static var defaultPrioritiesFile: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents")
            .appendingPathComponent("My life/0 Focus.md")
            .path
    }

    /// The planner priorities file, or nil when the user cleared it (empty =
    /// skip). Absent key = the default focus file.
    static var plannerPrioritiesFile: String? {
        if let stored = UserDefaults.standard.string(forKey: plannerPrioritiesPathKey) {
            return stored.isEmpty ? nil : stored
        }
        return defaultPrioritiesFile
    }

    static var rawActivityFile: URL { drawerDataDirectory.appendingPathComponent("raw-activity.jsonl") }
    static var attributionQueueFile: URL { drawerDataDirectory.appendingPathComponent("attribution-queue.jsonl") }
    static var attributionRulesFile: URL { drawerDataDirectory.appendingPathComponent("attribution-rules.json") }
    static var daySummariesFile: URL { drawerDataDirectory.appendingPathComponent("day-summaries.jsonl") }

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

    static var exportsWorkLogMarkdown: Bool {
        UserDefaults.standard.object(forKey: "exportWorkLogMarkdown") as? Bool ?? true
    }

    @MainActor
    static func exportWorkLog(_ workClock: WorkClock) {
        guard exportsWorkLogMarkdown else { return }
        // Merge the AI day-summary sidecar (spec 02) under each day heading.
        let daySummaries = DaySummaryStore(fileURL: daySummariesFile).byDay()
        workClock.exportMarkdown(to: workLogMarkdownFile, daySummaries: daySummaries)
    }
}
