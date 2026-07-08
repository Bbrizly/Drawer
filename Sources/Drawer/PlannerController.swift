import DrawerCore
import Foundation
import SwiftUI

/// Drives the one-button day planner: builds the deterministic context, calls
/// the on-device model, and holds the editable draft for the preview card. The
/// preview is the clamp — the model's minutes are trusted only because you see
/// and can edit every one before Accept, which commits through PlanWriter.
@MainActor
final class PlannerController: ObservableObject {
    enum State: Equatable {
        case idle
        case drafting
        case preview(entries: [PlanDraftEntry], capacityNote: String?, prioritiesMissing: Bool)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let store: TodoStore
    private let workLog: WorkSessionLog
    private let scheduleStore: DayScheduleStore
    private let todayProvider: @MainActor () -> String
    private let prioritiesProvider: @MainActor () -> (text: String?, missing: Bool)
    /// Hash of the task file the current draft was built from, captured in
    /// `plan()`. Used as the schedule's `sourceFileHash` at accept so
    /// `needsReview` flags any edit made between drafting and accepting.
    private var draftFileHash: String?
    /// Increments per plan() so a stale model reply can never overwrite the
    /// state a newer request (or the user's edits) produced.
    private var planGeneration = 0

    init(
        store: TodoStore,
        workLog: WorkSessionLog,
        scheduleStore: DayScheduleStore,
        todayProvider: @escaping @MainActor () -> String,
        prioritiesProvider: @escaping @MainActor () -> (text: String?, missing: Bool)
    ) {
        self.store = store
        self.workLog = workLog
        self.scheduleStore = scheduleStore
        self.todayProvider = todayProvider
        self.prioritiesProvider = prioritiesProvider
    }

    /// Today's saved schedule, re-attached to the current task file. Reads the
    /// sidecar and reconciles against live tasks; nil when nothing is saved for
    /// the date. `needsReview` on the result flags a drifted task file.
    func savedSchedule(for date: String) -> ResolvedSchedule? {
        guard let saved = scheduleStore.latest(for: date) else { return nil }
        return saved.reconciled(against: liveTasks(), currentHash: currentFileHash())
    }

    private func liveTasks() -> [TodoItem] {
        store.todayItems + store.carriedItems + store.upcomingItems + store.backlogItems
    }

    private func currentFileHash() -> String {
        let text = (try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? ""
        return SnapshotStore.sha256Hex(Data(text.utf8))
    }

    /// Foundation Models availability, read fresh so the button hides the moment
    /// Apple Intelligence goes away.
    var available: Bool { makeDayPlannerIfAvailable() != nil }

    func plan(date: String? = nil) {
        // Re-invoking while a draft is in flight or a preview is open (the
        // menu item again, reopening the pane) must not silently discard the
        // user's edits or race two model calls; the existing surface just
        // comes forward. "Try again" goes through discard() first.
        switch state {
        case .drafting, .preview: return
        case .idle, .failed: break
        }
        guard let planner = makeDayPlannerIfAvailable() else { return }
        let day = date ?? todayProvider()
        let priorities = prioritiesProvider()
        let text = (try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? ""
        draftFileHash = SnapshotStore.sha256Hex(Data(text.utf8))
        let sections = TodoParser.parse(text)
        let context = PlanContextBuilder.build(
            date: day, sections: sections, today: todayProvider(),
            sessions: workLog.all(), priorities: priorities.text)

        // Nothing to plan: the model can only reorder open tasks (plus at most one
        // new task from priorities), so an empty board can never produce a plan.
        // Say that plainly instead of letting the model return empty and blaming it.
        guard !context.openTasks.isEmpty else {
            state = .failed("No open tasks to plan. Add tasks (today, carried, or backlog) first.")
            return
        }

        state = .drafting
        planGeneration += 1
        let generation = planGeneration
        Task { @MainActor in
            do {
                let draft = try await planner.draft(context: context)
                guard generation == planGeneration else { return } // superseded
                guard !draft.entries.isEmpty else {
                    state = .failed("The planner picked no tasks. Try again, or set a priorities file in Settings.")
                    return
                }
                state = .preview(
                    entries: draft.entries, capacityNote: draft.capacityNote,
                    prioritiesMissing: priorities.missing)
            } catch {
                guard generation == planGeneration else { return }
                // Surface the real reason (e.g. context-window overflow from a large
                // priorities file, or the model being reclaimed) so a failure is
                // diagnosable instead of a dead-end "try again".
                state = .failed("Planner error: \(error)")
            }
        }
    }

    /// Commits the (possibly edited) draft as a non-destructive schedule sidecar.
    /// `Drawer.md` is never rewritten; the pane's Plan view then reads it back as
    /// today's timed agenda. On a save failure the card shows why.
    func accept(date: String, entries: [PlanDraftEntry], startTime: Date = DaySchedule.defaultStart()) {
        let schedule = DaySchedule(
            date: date, startTime: startTime,
            sourceFileHash: draftFileHash ?? currentFileHash(),
            draft: entries, liveTasks: liveTasks())
        do {
            try scheduleStore.save(schedule)
            state = .idle
        } catch {
            state = .failed("Could not save that schedule: \(error).")
        }
    }

    func discard() { state = .idle }
}
