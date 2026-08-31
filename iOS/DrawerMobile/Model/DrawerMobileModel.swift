import Combine
import DrawerCore
import Foundation
import WidgetKit

@MainActor
final class DrawerMobileModel: ObservableObject {
    enum ConnectionState: Equatable {
        case loading
        case disconnected
        case connected
        case needsPermission
    }

    struct UndoPayload {
        let label: String
        let originalData: Data
        let expectedCurrentData: Data
    }

    @Published private(set) var connectionState: ConnectionState = .loading
    @Published private(set) var carriedItems: [TodoItem] = []
    @Published private(set) var todayItems: [TodoItem] = []
    @Published private(set) var upcomingItems: [TodoItem] = []
    @Published private(set) var backlogItems: [TodoItem] = []
    @Published private(set) var upcomingLabel = ""
    @Published private(set) var sourceName = "Drawer.md"
    @Published var statusMessage: String?
    @Published private(set) var undoLabel: String?
    @Published private(set) var captureRequestToken = 0

    let focusTimer = FocusTimer()

    private var document: CoordinatedDrawerDocument?
    private var lastAppliedData: Data?
    private var lastAppliedDayKey: String?
    private var undoPayload: UndoPayload?
    private var undoExpiryTask: Task<Void, Never>?
    private var isSceneActive = true

    init() {
        focusTimer.onComplete = { _ in
            FocusNotificationScheduler.cancel()
            DrawerHaptics.shared.focusFinished()
        }
    }

    var connectedFileURL: URL? { document?.url }

    func bootstrap() {
        guard DrawerBookmarkStore.hasBookmark else {
            connectionState = .disconnected
            return
        }
        openStoredDocument()
    }

    func connect(to pickedURL: URL) {
        do {
            try DrawerBookmarkStore.save(pickedURL)
            openStoredDocument()
        } catch {
            connectionState = .needsPermission
            fail(error)
        }
    }

    func disconnect() {
        document?.stopObserving()
        document = nil
        lastAppliedData = nil
        lastAppliedDayKey = nil
        carriedItems = []
        todayItems = []
        upcomingItems = []
        backlogItems = []
        upcomingLabel = ""
        DrawerBookmarkStore.clear()
        if let snapshotURL = WidgetSnapshotStore.snapshotURL {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        connectionState = .disconnected
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        focusTimer.setDisplayActive(active)
        guard let document else { return }
        if active {
            startObserving(document)
            // Date-derived buckets can change while the app is backgrounded
            // even when Drawer.md itself has not changed.
            reload()
        } else {
            document.stopObserving()
        }
    }

    /// Re-evaluates all date-derived state after midnight, a timezone change,
    /// or a significant system-clock change. The data cache deliberately keys
    /// on both canonical bytes and the local day so unchanged Markdown cannot
    /// leave Today/Carried stale.
    func handleSignificantTimeChange() {
        reload()
    }

    func requestCapture() {
        captureRequestToken &+= 1
    }

    func reload() {
        guard let document else { return }
        do {
            let data = try document.read()
            let today = DrawerDate.todayKey()
            if data == lastAppliedData, today == lastAppliedDayKey { return }

            // Keep parity with the desktop store's small automatic cleanup.
            if let text = String(data: data, encoding: .utf8) {
                let swept = TodoArchiver.archiveCompleted(
                    in: text,
                    today: today
                )
                if swept != text, let sweptData = swept.data(using: .utf8) {
                    try document.write(sweptData)
                    apply(try document.read())
                    return
                }
            }
            apply(data)
        } catch {
            fail(error)
        }
    }

    @discardableResult
    func toggle(_ item: TodoItem) -> Bool {
        commit { data in
            try TodoWriteback.toggle(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                in: data
            )
        } != nil
    }

    @discardableResult
    func add(_ title: String, destination: DrawerTaskDestination) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let today = DrawerDate.todayKey()
        let tomorrow = DrawerDate.tomorrowKey()
        return commit { data in
            switch destination {
            case .today:
                return try TodoWriteback.append(title: title, today: today, in: data)
            case .tomorrow:
                return try TodoWriteback.insert(
                    line: "- [ ] " + title,
                    intoSectionKey: tomorrow,
                    displayHeading: tomorrow,
                    in: data
                )
            case .backlog:
                return try TodoWriteback.insert(
                    line: "- [ ] " + title,
                    intoSectionKey: TodoParser.backlogKey,
                    displayHeading: "Backlog",
                    in: data
                )
            }
        } != nil
    }

    @discardableResult
    func setInProgress(_ item: TodoItem, _ inProgress: Bool) -> Bool {
        commit { data in
            try TodoWriteback.setInProgress(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                inProgress: inProgress,
                in: data
            )
        } != nil
    }

    @discardableResult
    func setNote(_ item: TodoItem, _ note: String) -> Bool {
        commit { data in
            try TodoWriteback.setNote(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                note: note,
                in: data
            )
        } != nil
    }

    @discardableResult
    func rename(_ item: TodoItem, to newTitle: String) -> Bool {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        return commit { data in
            try TodoWriteback.rename(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                to: title,
                in: data
            )
        } != nil
    }

    @discardableResult
    func move(_ item: TodoItem, to destination: DrawerTaskDestination) -> Bool {
        let target: (key: String, heading: String)
        switch destination {
        case .today:
            let today = DrawerDate.todayKey()
            target = (today, today)
        case .tomorrow:
            let tomorrow = DrawerDate.tomorrowKey()
            target = (tomorrow, tomorrow)
        case .backlog:
            target = (TodoParser.backlogKey, "Backlog")
        }
        guard item.sectionDate != target.key else { return true }

        guard let result = commit({ data in
            try TodoWriteback.move(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                toSectionKey: target.key,
                displayHeading: target.heading,
                in: data
            )
        }) else { return false }

        armUndo(
            label: "Moved to \(destination.title)",
            original: result.before,
            expectedCurrent: result.after
        )
        return true
    }

    @discardableResult
    func delete(_ item: TodoItem) -> Bool {
        guard let result = commit({ data in
            try TodoWriteback.delete(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                in: data
            )
        }) else { return false }

        armUndo(
            label: "Deleted \(item.title)",
            original: result.before,
            expectedCurrent: result.after
        )
        return true
    }

    @discardableResult
    func undoLastMutation() -> Bool {
        guard let payload = undoPayload, let document else { return false }
        do {
            let current = try document.read()
            guard current == payload.expectedCurrentData else {
                clearUndo()
                statusMessage = "Couldn't undo because Drawer.md changed elsewhere."
                DrawerHaptics.shared.error()
                reload()
                return false
            }
            try document.write(payload.originalData)
            let canonical = try document.read()
            guard canonical == payload.originalData else {
                throw CocoaError(.fileWriteUnknown)
            }
            clearUndo()
            apply(canonical)
            return true
        } catch {
            clearUndo()
            fail(error)
            return false
        }
    }

    func startFocus(on item: TodoItem) {
        focusTimer.start(taskTitle: item.title, minutes: item.minutes)
        objectWillChange.send()
        FocusNotificationScheduler.schedule(
            taskTitle: item.title,
            seconds: TimeInterval(item.minutes * 60)
        )
    }

    func pauseFocus() {
        focusTimer.pause()
        FocusNotificationScheduler.cancel()
    }

    func resumeFocus() {
        focusTimer.resume()
        if focusTimer.phase == .running {
            FocusNotificationScheduler.schedule(
                taskTitle: focusTimer.taskTitle,
                seconds: focusTimer.remaining
            )
        }
    }

    func resetFocus() {
        focusTimer.reset()
        objectWillChange.send()
        FocusNotificationScheduler.cancel()
    }

    var remainingCount: Int {
        (carriedItems + todayItems).filter { !$0.isDone }.count
    }

    private struct CommitResult {
        let before: Data
        let after: Data
    }

    private func commit(_ transform: (Data) throws -> Data) -> CommitResult? {
        guard let document else { return nil }
        do {
            var base = try document.read()
            var output = try transform(base)
            let fresh = try document.read()
            if fresh != base {
                base = fresh
                output = try transform(base)
            }
            try document.write(output)
            let canonical = try document.read()
            apply(canonical)
            return CommitResult(before: base, after: canonical)
        } catch {
            fail(error)
            reload()
            return nil
        }
    }

    private func apply(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            statusMessage = "Drawer.md isn't UTF-8 text."
            return
        }
        let today = DrawerDate.todayKey()
        let display = TodoParser.display(
            sections: TodoParser.parse(text),
            today: today
        )
        carriedItems = display.carried
        todayItems = display.today
        upcomingItems = display.upcoming
        backlogItems = display.backlog
        if let date = display.upcomingDate {
            upcomingLabel = date == DrawerDate.tomorrowKey() ? "Tomorrow" : date
        } else {
            upcomingLabel = ""
        }
        statusMessage = nil
        lastAppliedData = data
        lastAppliedDayKey = today
        publishWidgetSnapshot(data, today: today)
    }

    private func publishWidgetSnapshot(_ data: Data, today: String) {
        do {
            try WidgetSnapshotStore.write(.make(from: data, todayKey: today))
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widget cache failure must never block canonical Markdown writes.
            // The next successful app refresh tries again.
        }
    }

    private func openStoredDocument() {
        do {
            document?.stopObserving()
            let newDocument = CoordinatedDrawerDocument(
                session: try DrawerBookmarkStore.openSession()
            )
            document = newDocument
            sourceName = newDocument.url.lastPathComponent
            connectionState = .connected
            lastAppliedData = nil
            lastAppliedDayKey = nil
            if isSceneActive { startObserving(newDocument) }
            reload()
        } catch {
            document = nil
            connectionState = DrawerBookmarkStore.hasBookmark ? .needsPermission : .disconnected
            fail(error)
        }
    }

    private func startObserving(_ document: CoordinatedDrawerDocument) {
        document.startObserving(
            onChange: { [weak self] in self?.reload() },
            onMove: { [weak self] newURL in
                guard let self else { return }
                do {
                    try DrawerBookmarkStore.save(newURL)
                    self.openStoredDocument()
                } catch {
                    self.fail(error)
                }
            }
        )
    }

    private func armUndo(label: String, original: Data, expectedCurrent: Data) {
        undoExpiryTask?.cancel()
        undoPayload = UndoPayload(
            label: label,
            originalData: original,
            expectedCurrentData: expectedCurrent
        )
        undoLabel = label
        undoExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.clearUndo() }
        }
    }

    private func clearUndo() {
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        undoPayload = nil
        undoLabel = nil
    }

    private func fail(_ error: Error) {
        statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        DrawerHaptics.shared.error()
    }
}
