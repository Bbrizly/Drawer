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
    private let todayProvider: @MainActor () -> String
    private let prioritiesProvider: @MainActor () -> (text: String?, missing: Bool)

    init(
        store: TodoStore,
        workLog: WorkSessionLog,
        todayProvider: @escaping @MainActor () -> String,
        prioritiesProvider: @escaping @MainActor () -> (text: String?, missing: Bool)
    ) {
        self.store = store
        self.workLog = workLog
        self.todayProvider = todayProvider
        self.prioritiesProvider = prioritiesProvider
    }

    /// Foundation Models availability, read fresh so the button hides the moment
    /// Apple Intelligence goes away.
    var available: Bool { makeDayPlannerIfAvailable() != nil }

    func plan(date: String? = nil) {
        guard let planner = makeDayPlannerIfAvailable() else { return }
        let day = date ?? todayProvider()
        let priorities = prioritiesProvider()
        let sections = TodoParser.parse((try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? "")
        let context = PlanContextBuilder.build(
            date: day, sections: sections, today: todayProvider(),
            sessions: workLog.all(), priorities: priorities.text)

        state = .drafting
        Task { @MainActor in
            do {
                let draft = try await planner.draft(context: context)
                guard !draft.entries.isEmpty else {
                    state = .failed("Could not draft a plan. Try again.")
                    return
                }
                state = .preview(
                    entries: draft.entries, capacityNote: draft.capacityNote,
                    prioritiesMissing: priorities.missing)
            } catch {
                state = .failed("Could not draft a plan. Try again.")
            }
        }
    }

    /// Commits the (possibly edited) draft. On a PlanWriter rejection the card
    /// shows why instead of silently doing nothing.
    func accept(date: String, entries: [PlanDraftEntry]) {
        do {
            try store.writeDayPlan(date: date, entries: entries.map(\.planEntry), replace: false)
            state = .idle
        } catch {
            state = .failed("That plan was rejected: \(error).")
        }
    }

    func discard() { state = .idle }
}
