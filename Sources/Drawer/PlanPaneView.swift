import DrawerCore
import SwiftUI

/// The Plan pane. Kicks off the on-device planner, edits the draft inline, and
/// after Accept shows today's saved timed schedule. Accepting writes a private
/// sidecar (`DayScheduleStore`); the task file is never rewritten. The saved
/// agenda is the visible "it did something".
struct PlanPaneView: View {
    @ObservedObject var planner: PlannerController
    /// True while the pane is actually open. The pane stays mounted (width 0)
    /// when closed, so we reload the saved schedule each time it reopens to
    /// catch task-file edits made while it was hidden.
    var isActive: Bool = false
    var onNeedsKeyboard: () -> Void = {}

    @Environment(\.drawerTheme) private var theme
    /// Computed, not captured: the pane stays mounted across midnight, so a
    /// stored date would go stale and save schedules under yesterday's key.
    private var date: String { TodoStore.localToday() }
    /// Loaded on appear, on reopen, and after Accept; reconciling reads the file.
    @State private var schedule: ResolvedSchedule?

    var body: some View {
        Group {
            switch planner.state {
            case .idle:
                savedAgenda
            case .drafting:
                loading
            case let .preview(entries, capacityNote, prioritiesMissing):
                PlanDraftEditor(
                    date: date, entries: entries, capacityNote: capacityNote,
                    prioritiesMissing: prioritiesMissing, theme: theme,
                    onNeedsKeyboard: onNeedsKeyboard,
                    onAccept: accept, onDiscard: planner.discard)
            case let .failed(message):
                failure(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: reload)
        .onChange(of: isActive) { _, active in if active { reload() } }
        // Accept can also happen in the separate planner window (same
        // controller); its return to .idle is the cue to re-read the agenda.
        .onChange(of: planner.state) { _, newState in
            if newState == .idle { reload() }
        }
    }

    private func accept(_ entries: [PlanDraftEntry]) {
        // Day start defaults to now, rounded to :15; not editable yet.
        planner.accept(date: date, entries: entries)
        reload()
    }

    private func reload() { schedule = planner.savedSchedule(for: date) }

    // MARK: - Saved agenda

    @ViewBuilder
    private var savedAgenda: some View {
        if let schedule, !schedule.blocks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if schedule.needsReview { reviewBanner }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(schedule.blocks.indices, id: \.self) { i in
                            blockRow(schedule.blocks[i])
                        }
                    }
                }
                planButton("Re-plan today")
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("No plan yet for today.")
                    .font(theme.uiFont(size: 14, weight: .semibold))
                Text("Draft a timed agenda from your open tasks. Accepting writes a private schedule, never your task file.")
                    .font(theme.uiFont(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                planButton("Plan today")
                Spacer(minLength: 0)
            }
        }
    }

    private func blockRow(_ b: ResolvedBlock) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(b.start.formatted(date: .omitted, time: .shortened))
                .font(theme.uiFont(size: 12, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.block.title).font(theme.uiFont(size: 13))
                if case .unlinked = b.link {
                    Text("agenda only")
                        .font(theme.uiFont(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Text("\(b.block.minutes)m")
                .font(theme.uiFont(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var reviewBanner: some View {
        Label(
            "Your tasks changed since this plan was made. Some blocks may be stale.",
            systemImage: "exclamationmark.triangle")
            .font(theme.uiFont(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Other states

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Drafting your day…")
                .font(theme.uiFont(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(theme.uiFont(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Try again") { planner.plan(date: date) }
                Button("Close", action: planner.discard)
            }
            .font(theme.uiFont(size: 12))
            Spacer(minLength: 0)
        }
    }

    private func planButton(_ label: String) -> some View {
        Button(label) { planner.plan(date: date) }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(!planner.available)
    }
}

/// The inline draft editor: per-row minutes (the clamp on the model's
/// durations) and delete, in a pane-width scroll. Nothing is saved until Accept.
private struct PlanDraftEditor: View {
    let date: String
    @State var entries: [PlanDraftEntry]
    let capacityNote: String?
    let prioritiesMissing: Bool
    let theme: DrawerTheme
    var onNeedsKeyboard: () -> Void
    let onAccept: ([PlanDraftEntry]) -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Draft for \(date)")
                    .font(theme.uiFont(size: 13, weight: .semibold))
                Spacer()
                Text("\(totalMinutes)m")
                    .font(theme.uiFont(size: 12))
                    .foregroundStyle(.secondary)
            }
            // The panel is non-activating; make it key while editing so the
            // minutes fields receive typing (same path the add-task field uses).
            .onAppear(perform: onNeedsKeyboard)
            ScrollView {
                VStack(spacing: 6) {
                    // Minutes + delete only; entries arrive pre-ordered from the draft.
                    ForEach($entries) { $entry in
                        editorRow($entry)
                    }
                }
            }
            if let note = capacityNote, !note.isEmpty {
                Text(note)
                    .font(theme.uiFont(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if prioritiesMissing {
                Label("Priorities file not found, planned without it.", systemImage: "info.circle")
                    .font(theme.uiFont(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Discard", role: .cancel, action: onDiscard)
                Spacer()
                Button("Accept") { onAccept(entries) }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(entries.isEmpty)
            }
            .font(theme.uiFont(size: 12))
        }
    }

    private func editorRow(_ entry: Binding<PlanDraftEntry>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.wrappedValue.title).font(theme.uiFont(size: 13))
                if let reason = entry.wrappedValue.reason, !reason.isEmpty {
                    Text(reason)
                        .font(theme.uiFont(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            TextField("min", value: Binding(
                get: { entry.wrappedValue.minutes },
                set: { entry.wrappedValue.minutes = max(1, $0) }),
                format: .number)
                .frame(width: 38)
                .multilineTextAlignment(.trailing)
            Text("m")
                .font(theme.uiFont(size: 12))
                .foregroundStyle(.secondary)
            Button {
                entries.removeAll { $0.id == entry.wrappedValue.id }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var totalMinutes: Int { entries.reduce(0) { $0 + $1.minutes } }
}
