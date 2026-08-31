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
        case waitingForProvider
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
    private var pendingDocument: CoordinatedDrawerDocument?
    private var lastAppliedData: Data?
    private var lastAppliedDayKey: String?
    private var undoPayload: UndoPayload?
    private var undoExpiryTask: Task<Void, Never>?
    private var providerRetryTask: Task<Void, Never>?
    private var pendingRetryTask: Task<Void, Never>?
    private var pendingStatusMessage: String?
    private var hasTransientAccessFailure = false
    private var isSceneActive = true
    private var focusSessionID: UUID?
    private var focusCreatedAt: Date?

    init() {
        focusTimer.onComplete = { [weak self] _ in
            FocusNotificationScheduler.cancel()
            DrawerHaptics.shared.focusFinished()
            self?.persistFocusState()
        }
        restoreFocusState()
    }

    var connectedFileURL: URL? { document?.url }

    func bootstrap() {
        if DrawerBookmarkStore.hasPendingBookmark {
            // A staged cloud/provider selection may have been interrupted by a
            // process kill. Reopen the previous canonical source first when one
            // exists, then continue materializing the staged replacement.
            if DrawerBookmarkStore.hasBookmark {
                openStoredDocument()
            }
            beginPendingSelection()
            return
        }

        guard DrawerBookmarkStore.hasBookmark else {
            WidgetInteractionFeedbackStore.clear()
            connectionState = .disconnected
            return
        }
        openStoredDocument()
    }

    func connect(to pickedURL: URL) {
        do {
            switch try DrawerBookmarkStore.save(pickedURL) {
            case .ready:
                openStoredDocument()
            case .waitingForProvider:
                beginPendingSelection()
            }
        } catch {
            // Change Drawer.md stays transactional even when another staged
            // source already exists. A bad replacement never destroys the
            // active source or the viable staged source that preceded it.
            if document != nil {
                connectionState = .connected
            } else if pendingDocument != nil || DrawerBookmarkStore.hasPendingBookmark {
                connectionState = .waitingForProvider
            } else {
                connectionState = DrawerBookmarkStore.hasBookmark ? .needsPermission : .disconnected
            }
            fail(error)
        }
    }

    func disconnect() {
        document?.stopObserving()
        document = nil
        clearUndo()
        cancelProviderRetry()
        clearPendingRuntime()
        hasTransientAccessFailure = false
        lastAppliedData = nil
        lastAppliedDayKey = nil
        carriedItems = []
        todayItems = []
        upcomingItems = []
        backlogItems = []
        upcomingLabel = ""
        statusMessage = nil
        DrawerBookmarkStore.clear()
        WidgetInteractionFeedbackStore.clear()
        if let snapshotURL = WidgetSnapshotStore.snapshotURL {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        WidgetCenter.shared.reloadAllTimelines()
        connectionState = .disconnected
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        focusTimer.setDisplayActive(active)
        if !active {
            persistFocusState()
            cancelProviderRetry()
            cancelPendingRetry()
        }

        if let document {
            if active {
                startObserving(document)
                reload()
            } else {
                document.stopObserving()
            }
        }

        if active, pendingDocument != nil {
            attemptPendingSelection()
        }
    }

    func handleSignificantTimeChange() {
        focusTimer.setDisplayActive(isSceneActive)
        persistFocusState()
        reload()
    }

    func requestCapture() {
        captureRequestToken &+= 1
    }

    func reload() {
        guard let document else { return }
        do {
            let today = DrawerDate.todayKey()
            var base = try document.read()
            if base == lastAppliedData, today == lastAppliedDayKey {
                if hasTransientAccessFailure {
                    hasTransientAccessFailure = false
                }
                cancelProviderRetry()
                statusMessage = pendingStatusMessage
                return
            }

            // Automatic recurrence/archive normalization is a canonical write,
            // so it follows the same one-retry content-CAS rule as a user
            // mutation. If Obsidian/iCloud changed Drawer.md after the first
            // read, recompute against those fresh bytes before writing.
            var normalized = try normalizedData(base, today: today)
            if normalized != base {
                let fresh = try document.read()
                if fresh != base {
                    base = fresh
                    normalized = try normalizedData(base, today: today)
                }

                if normalized != base {
                    try document.write(normalized)
                    apply(try document.read())
                } else {
                    apply(base)
                }
                return
            }

            apply(base)
        } catch {
            fail(error)
        }
    }

    @discardableResult
    func toggle(_ item: TodoItem) -> Bool {
        // A completed recurring occurrence already has a successor. Reopening
        // it would create two active members of one series, so history stays
        // immutable until a dedicated series-history editor exists.
        if item.isDone, recurrence(for: item) != nil {
            statusMessage = "Completed repeating occurrences stay in history. Edit the active copy instead."
            DrawerHaptics.shared.error()
            return false
        }

        return commit { data in
            if try TodoRecurrenceWriteback.recurrence(for: item, in: data) != nil {
                return try TodoRecurrenceWriteback.completeAndAdvance(
                    item: item,
                    today: DrawerDate.todayKey(),
                    in: data
                )
            }
            return try TodoWriteback.toggle(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                in: data
            )
        } != nil
    }

    func recurrence(for item: TodoItem) -> TodoRecurrence? {
        guard let document else { return nil }
        do {
            return try TodoRecurrenceWriteback.recurrence(for: item, in: document.read())
        } catch {
            return nil
        }
    }

    @discardableResult
    func setRecurrence(_ item: TodoItem, rule: TodoRecurrenceRule?) -> Bool {
        commit { data in
            try TodoRecurrenceWriteback.setRecurrence(
                for: item,
                rule: rule,
                today: DrawerDate.todayKey(),
                in: data
            )
        } != nil
    }

    @discardableResult
    func skipRecurring(_ item: TodoItem) -> Bool {
        guard recurrence(for: item) != nil, !item.isDone else { return false }
        return commit { data in
            try TodoRecurrenceWriteback.skipAndAdvance(
                item: item,
                today: DrawerDate.todayKey(),
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
            try TodoMetadataWriteback.setNote(
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

        armUndo(label: "Moved to \(destination.title)", original: result.before, expectedCurrent: result.after)
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

        armUndo(label: "Deleted \(item.title)", original: result.before, expectedCurrent: result.after)
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
            guard canonical == payload.originalData else { throw CocoaError(.fileWriteUnknown) }
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
        focusSessionID = UUID()
        focusCreatedAt = Date()
        focusTimer.start(taskTitle: item.title, minutes: item.minutes)
        objectWillChange.send()
        persistFocusState()
        FocusNotificationScheduler.schedule(
            taskTitle: item.title,
            seconds: TimeInterval(item.minutes * 60)
        )
    }

    func pauseFocus() {
        focusTimer.pause()
        persistFocusState()
        FocusNotificationScheduler.cancel()
    }

    func resumeFocus() {
        focusTimer.resume()
        persistFocusState()
        if focusTimer.phase == .running {
            FocusNotificationScheduler.schedule(
                taskTitle: focusTimer.taskTitle,
                seconds: focusTimer.remaining
            )
        }
    }

    func resetFocus() {
        focusTimer.reset()
        focusSessionID = nil
        focusCreatedAt = nil
        DrawerFocusStore.clear()
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
            guard String(data: base, encoding: .utf8) != nil else {
                throw DrawerBookmarkError.invalidEncoding
            }
            var output = try transform(base)
            let fresh = try document.read()
            if fresh != base {
                guard String(data: fresh, encoding: .utf8) != nil else {
                    throw DrawerBookmarkError.invalidEncoding
                }
                base = fresh
                output = try transform(base)
            }
            try document.write(output)
            let canonical = try document.read()
            apply(canonical)
            return CommitResult(before: base, after: canonical)
        } catch {
            fail(error)
            if (error as? DrawerFileAccessError)?.isTransient != true {
                reload()
            }
            return nil
        }
    }

    private func normalizedData(_ data: Data, today: String) throws -> Data {
        guard String(data: data, encoding: .utf8) != nil else {
            throw DrawerBookmarkError.invalidEncoding
        }

        var normalized = try TodoRecurrenceWriteback.reconcile(in: data, today: today)
        guard let normalizedText = String(data: normalized, encoding: .utf8) else {
            // A deterministic transform must never turn valid canonical input
            // into invalid text; treat it as a hard failure if it does.
            throw DrawerBookmarkError.invalidEncoding
        }
        let swept = TodoArchiver.archiveCompleted(in: normalizedText, today: today)
        if swept != normalizedText, let sweptData = swept.data(using: .utf8) {
            normalized = sweptData
        }
        return normalized
    }

    private func apply(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            statusMessage = "Drawer.md isn't UTF-8 text."
            return
        }
        let today = DrawerDate.todayKey()
        let display = TodoParser.display(sections: TodoParser.parse(text), today: today)
        carriedItems = display.carried
        todayItems = display.today
        upcomingItems = display.upcoming
        backlogItems = display.backlog
        if let date = display.upcomingDate {
            upcomingLabel = date == DrawerDate.tomorrowKey() ? "Tomorrow" : date
        } else {
            upcomingLabel = ""
        }
        hasTransientAccessFailure = false
        cancelProviderRetry()
        statusMessage = pendingStatusMessage
        lastAppliedData = data
        lastAppliedDayKey = today
        publishWidgetSnapshot(data, today: today)
    }

    private func publishWidgetSnapshot(_ data: Data, today: String) {
        do {
            try WidgetSnapshotStore.write(.make(from: data, todayKey: today))
            WidgetInteractionFeedbackStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            statusMessage = "Drawer.md is safe, but widgets couldn't refresh. Check the App Group setup."
            DrawerActionFeedbackCenter.notice(
                "Saved to Drawer.md, but widgets couldn't refresh.",
                systemImage: "rectangle.stack.badge.exclamationmark"
            )
        }
    }

    private func openStoredDocument() {
        do {
            let newDocument = CoordinatedDrawerDocument(session: try DrawerBookmarkStore.openSession())
            document?.stopObserving()
            clearUndo()
            cancelProviderRetry()
            clearPendingRuntime()
            hasTransientAccessFailure = false
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

    private func beginPendingSelection() {
        do {
            let candidate = CoordinatedDrawerDocument(session: try DrawerBookmarkStore.openPendingSession())
            pendingDocument = candidate
            pendingStatusMessage = "Getting the new Drawer.md ready."
            sourceName = document?.url.lastPathComponent ?? candidate.url.lastPathComponent

            if document == nil {
                connectionState = .waitingForProvider
                carriedItems = []
                todayItems = []
                upcomingItems = []
                backlogItems = []
                upcomingLabel = ""
            } else {
                connectionState = .connected
            }

            attemptPendingSelection()
        } catch {
            handlePendingSelectionFailure(error)
        }
    }

    private func attemptPendingSelection() {
        guard let candidate = pendingDocument else { return }

        do {
            let data = try candidate.read()
            guard String(data: data, encoding: .utf8) != nil else {
                throw DrawerBookmarkError.invalidEncoding
            }

            // Promotion happens only after a real current canonical read. Until
            // this line the previous primary bookmark remains untouched.
            try DrawerBookmarkStore.promotePending()

            document?.stopObserving()
            clearUndo()
            cancelProviderRetry()
            cancelPendingRetry()
            pendingStatusMessage = nil
            hasTransientAccessFailure = false
            document = candidate
            pendingDocument = nil
            sourceName = candidate.url.lastPathComponent
            connectionState = .connected
            lastAppliedData = nil
            lastAppliedDayKey = nil
            statusMessage = nil
            if isSceneActive { startObserving(candidate) }
            reload()
        } catch let accessError as DrawerFileAccessError where accessError.isTransient {
            pendingStatusMessage = pendingMessage(for: accessError)
            statusMessage = pendingStatusMessage
            if document == nil {
                connectionState = .waitingForProvider
            } else {
                connectionState = .connected
            }
            schedulePendingRetry()
        } catch {
            handlePendingSelectionFailure(error)
        }
    }

    private func handlePendingSelectionFailure(_ error: Error) {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        DrawerBookmarkStore.discardPending()
        clearPendingRuntime()

        if document != nil {
            connectionState = .connected
            statusMessage = "Couldn't switch Drawer.md. \(detail) Your current file is still connected."
            DrawerHaptics.shared.error()
            return
        }

        if DrawerBookmarkStore.hasBookmark {
            openStoredDocument()
            if document != nil {
                statusMessage = "Couldn't switch Drawer.md. \(detail) Your previous file is still connected."
                DrawerHaptics.shared.error()
                return
            }
        }

        connectionState = DrawerBookmarkStore.hasBookmark ? .needsPermission : .disconnected
        fail(error)
    }

    private func pendingMessage(for error: DrawerFileAccessError) -> String {
        let base = error.errorDescription ?? "Drawer.md isn't available yet."
        guard document != nil else { return base }
        return "\(base) Your current Drawer.md stays active until the new file is ready."
    }

    private func startObserving(_ document: CoordinatedDrawerDocument) {
        document.startObserving(
            onChange: { [weak self] in self?.reload() },
            onMove: { [weak self] newURL in
                guard let self else { return }
                do {
                    switch try DrawerBookmarkStore.save(newURL) {
                    case .ready:
                        self.openStoredDocument()
                    case .waitingForProvider:
                        self.beginPendingSelection()
                    }
                } catch {
                    self.fail(error)
                }
            }
        )
    }

    private func restoreFocusState() {
        guard let saved = DrawerFocusStore.load() else { return }

        // A finished timer is useful briefly if the app was killed around the
        // completion boundary, but it must not resurrect stale UI days later.
        let age = Date().timeIntervalSince(saved.createdAt)
        guard age >= 0, age < 24 * 60 * 60 else {
            DrawerFocusStore.clear()
            FocusNotificationScheduler.cancel()
            return
        }

        focusSessionID = saved.id
        focusCreatedAt = saved.createdAt
        switch saved.phase {
        case .running:
            guard let endDate = saved.endDate else {
                DrawerFocusStore.clear()
                focusSessionID = nil
                focusCreatedAt = nil
                return
            }
            focusTimer.restoreRunning(taskTitle: saved.taskTitle, endDate: endDate)
            if focusTimer.phase == .running {
                FocusNotificationScheduler.schedule(
                    taskTitle: saved.taskTitle,
                    seconds: focusTimer.remaining
                )
            } else {
                persistFocusState()
                FocusNotificationScheduler.cancel()
            }
        case .paused:
            focusTimer.restorePaused(taskTitle: saved.taskTitle, remaining: saved.remaining)
            persistFocusState()
            FocusNotificationScheduler.cancel()
        case .finished:
            focusTimer.restoreFinished(taskTitle: saved.taskTitle)
            FocusNotificationScheduler.cancel()
        }
    }

    private func persistFocusState() {
        guard focusTimer.phase != .idle else {
            DrawerFocusStore.clear()
            return
        }
        let id = focusSessionID ?? UUID()
        let createdAt = focusCreatedAt ?? Date()
        focusSessionID = id
        focusCreatedAt = createdAt

        let phase: DrawerPersistedFocus.Phase
        switch focusTimer.phase {
        case .idle:
            DrawerFocusStore.clear()
            return
        case .running:
            phase = .running
        case .paused:
            phase = .paused
        case .finished:
            phase = .finished
        }

        DrawerFocusStore.save(
            DrawerPersistedFocus(
                id: id,
                taskTitle: focusTimer.taskTitle,
                phase: phase,
                endDate: focusTimer.expectedEndDate,
                remaining: focusTimer.remaining,
                createdAt: createdAt
            )
        )
    }

    private func armUndo(label: String, original: Data, expectedCurrent: Data) {
        undoExpiryTask?.cancel()
        undoPayload = UndoPayload(label: label, originalData: original, expectedCurrentData: expectedCurrent)
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

    private func scheduleProviderRetry() {
        guard isSceneActive, document != nil, providerRetryTask == nil else { return }

        providerRetryTask = Task { [weak self] in
            let delays: [Duration] = [
                .milliseconds(500),
                .seconds(1),
                .seconds(2),
                .seconds(3),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
            ]

            for delay in delays {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }

                guard let self,
                      self.isSceneActive,
                      self.document != nil,
                      self.hasTransientAccessFailure
                else { return }

                self.reload()
                if !self.hasTransientAccessFailure { return }
            }

            self?.providerRetryTask = nil
        }
    }

    private func schedulePendingRetry() {
        guard isSceneActive, pendingDocument != nil, pendingRetryTask == nil else { return }

        pendingRetryTask = Task { [weak self] in
            let delays: [Duration] = [
                .milliseconds(500),
                .seconds(1),
                .seconds(2),
                .seconds(3),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
                .seconds(5),
            ]

            for delay in delays {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }

                guard let self,
                      self.isSceneActive,
                      self.pendingDocument != nil
                else { return }

                self.attemptPendingSelection()
                if self.pendingDocument == nil { return }
            }

            self?.pendingRetryTask = nil
        }
    }

    private func cancelProviderRetry() {
        providerRetryTask?.cancel()
        providerRetryTask = nil
    }

    private func cancelPendingRetry() {
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
    }

    private func clearPendingRuntime() {
        cancelPendingRetry()
        pendingDocument = nil
        pendingStatusMessage = nil
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let changed = statusMessage != message
        statusMessage = message

        if let accessError = error as? DrawerFileAccessError {
            hasTransientAccessFailure = accessError.isTransient
            if accessError.isTransient {
                scheduleProviderRetry()
                return
            }
        } else {
            hasTransientAccessFailure = false
        }

        cancelProviderRetry()
        if changed {
            DrawerHaptics.shared.error()
        }
    }
}
