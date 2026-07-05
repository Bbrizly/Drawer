import DrawerCore
import SwiftUI

/// Hosts the planner's states in one window: a spinner while drafting, the
/// editable preview card, or a failure with retry.
struct PlannerPanel: View {
    @ObservedObject var controller: PlannerController
    let date: String

    var body: some View {
        switch controller.state {
        case .idle:
            Color.clear.frame(width: 440, height: 460)
        case .drafting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Drafting your day…").foregroundStyle(.secondary)
            }
            .frame(width: 440, height: 460)
        case let .preview(entries, capacityNote, prioritiesMissing):
            PlanPreviewCard(
                date: date, entries: entries, capacityNote: capacityNote,
                prioritiesMissing: prioritiesMissing,
                onAccept: { controller.accept(date: date, entries: $0) },
                onDiscard: { controller.discard() })
        case let .failed(message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text(message).multilineTextAlignment(.center).padding(.horizontal)
                HStack {
                    Button("Try again") { controller.plan(date: date) }
                    Button("Close") { controller.discard() }
                }
            }
            .frame(width: 440, height: 460)
        }
    }
}

/// The plan preview: draft entries with editable minutes, per-row remove, and
/// drag-to-reorder. Nothing is written until Accept. It is the clamp on the
/// model's durations — every minute value is visible and editable first.
struct PlanPreviewCard: View {
    let date: String
    @State var entries: [PlanDraftEntry]
    let capacityNote: String?
    let prioritiesMissing: Bool
    let onAccept: ([PlanDraftEntry]) -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Plan for \(date)").font(.headline)
                Spacer()
                Text("\(totalMinutes)m total").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()

            List {
                ForEach(entries.indices, id: \.self) { index in
                    row(index)
                }
                .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { entries.remove(atOffsets: $0) }
            }
            .listStyle(.plain)
            .frame(minHeight: 220)

            footer
        }
        .frame(width: 440, height: 460)
    }

    private func row(_ index: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entries[index].title).fontWeight(.medium)
                if let reason = entries[index].reason, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("min", value: Binding(
                get: { entries[index].minutes },
                set: { entries[index] = withMinutes(entries[index], max(1, $0)) }),
                format: .number)
                .frame(width: 44)
                .multilineTextAlignment(.trailing)
            Text("m").foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = capacityNote, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if prioritiesMissing {
                Label("Priorities file not found — planned without it.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Discard", role: .cancel, action: onDiscard)
                Spacer()
                Button("Accept") { onAccept(entries) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(entries.isEmpty)
            }
        }
        .padding(12)
    }

    private var totalMinutes: Int { entries.reduce(0) { $0 + $1.minutes } }

    private func withMinutes(_ entry: PlanDraftEntry, _ minutes: Int) -> PlanDraftEntry {
        PlanDraftEntry(title: entry.title, taskID: entry.taskID, minutes: minutes, reason: entry.reason)
    }
}
