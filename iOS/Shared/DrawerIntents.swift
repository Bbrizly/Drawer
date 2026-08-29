import AppIntents
import DrawerCore
import Foundation
import WidgetKit

enum DrawerIntentDestination: String, AppEnum {
    case today
    case tomorrow
    case backlog

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drawer Destination")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today"),
        .tomorrow: DisplayRepresentation(title: "Tomorrow"),
        .backlog: DisplayRepresentation(title: "Backlog"),
    ]

    var destination: DrawerTaskDestination {
        switch self {
        case .today: .today
        case .tomorrow: .tomorrow
        case .backlog: .backlog
        }
    }
}

struct DrawerTaskEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drawer Task")
    static let defaultQuery = DrawerTaskQuery()

    let id: String
    let title: String
    let rawLine: String
    let sectionDate: String
    let occurrence: Int
    let isDone: Bool
    let isInProgress: Bool
    let minutes: Int
    let bucket: WidgetTask.Bucket

    init(_ task: WidgetTask) {
        id = task.id
        title = task.title
        rawLine = task.rawLine
        sectionDate = task.sectionDate
        occurrence = task.occurrence
        isDone = task.isDone
        isInProgress = task.isInProgress
        minutes = task.minutes
        bucket = task.bucket
    }

    var displayRepresentation: DisplayRepresentation {
        if bucket == .carried {
            return DisplayRepresentation(title: "\(title)", subtitle: "Carried over")
        }
        return DisplayRepresentation(title: "\(title)")
    }

    var widgetTask: WidgetTask {
        WidgetTask(
            id: id,
            title: title,
            rawLine: rawLine,
            sectionDate: sectionDate,
            occurrence: occurrence,
            isDone: isDone,
            isInProgress: isInProgress,
            minutes: minutes,
            bucket: bucket
        )
    }
}

struct DrawerTaskQuery: EntityQuery {
    func entities(for identifiers: [DrawerTaskEntity.ID]) async throws -> [DrawerTaskEntity] {
        let wanted = Set(identifiers)
        return WidgetSnapshotStore.read().allTasks
            .filter { wanted.contains($0.id) }
            .map(DrawerTaskEntity.init)
    }

    func suggestedEntities() async throws -> [DrawerTaskEntity] {
        WidgetSnapshotStore.read().actionableTasks.map(DrawerTaskEntity.init)
    }
}

struct ToggleDrawerTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Drawer Task"
    static let description = IntentDescription("Checks or reopens a task in the connected Drawer markdown file.")
    static let openAppWhenRun = false

    @Parameter(title: "Task ID") var taskID: String = ""
    @Parameter(title: "Markdown Line") var rawLine: String = ""
    @Parameter(title: "Section") var sectionDate: String = ""
    @Parameter(title: "Occurrence") var occurrence: Int = 0
    @Parameter(title: "Title") var taskTitle: String = ""
    @Parameter(title: "Done") var isDone: Bool = false
    @Parameter(title: "In Progress") var isInProgress: Bool = false
    @Parameter(title: "Minutes") var minutes: Int = 25
    @Parameter(title: "Bucket") var bucketRawValue: String = WidgetTask.Bucket.today.rawValue

    init() {}

    init(task: WidgetTask) {
        taskID = task.id
        rawLine = task.rawLine
        sectionDate = task.sectionDate
        occurrence = task.occurrence
        taskTitle = task.title
        isDone = task.isDone
        isInProgress = task.isInProgress
        minutes = task.minutes
        bucketRawValue = task.bucket.rawValue
    }

    func perform() async throws -> some IntentResult {
        let task = WidgetTask(
            id: taskID,
            title: taskTitle,
            rawLine: rawLine,
            sectionDate: sectionDate,
            occurrence: occurrence,
            isDone: isDone,
            isInProgress: isInProgress,
            minutes: minutes,
            bucket: WidgetTask.Bucket(rawValue: bucketRawValue) ?? .today
        )
        _ = try DrawerMutationEngine.toggle(task)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct AddDrawerTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Drawer Task"
    static let description = IntentDescription("Adds a task directly to the connected Drawer markdown file.")
    static let openAppWhenRun = false

    @Parameter(title: "Task") var taskTitle: String = ""
    @Parameter(title: "Destination") var destination: DrawerIntentDestination = .today

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(.$taskTitle) to \(.$destination)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try DrawerMutationEngine.add(
            title: taskTitle,
            destination: destination.destination
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Added to \(destination.rawValue).")
    }
}

struct CompleteDrawerTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Drawer Task"
    static let description = IntentDescription("Marks an unfinished Drawer task complete.")
    static let openAppWhenRun = false

    @Parameter(title: "Task") var task: DrawerTaskEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let task else {
            return .result(dialog: "Choose a Drawer task first.")
        }
        _ = try DrawerMutationEngine.complete(task.widgetTask)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Completed \(task.title).")
    }
}

#if !WIDGET_EXTENSION
struct DrawerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddDrawerTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Capture a task in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CompleteDrawerTaskIntent(),
            phrases: [
                "Complete a task in \(.applicationName)",
                "Finish a task in \(.applicationName)",
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
    }
}
#endif
