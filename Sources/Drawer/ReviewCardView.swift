import DrawerCore
import SwiftUI

/// The review queue: the only path from a proposed match to the work log. Each
/// row shows the block's evidence and its matched task (or "Unattributed").
/// High-confidence rows are pre-checked for a fast "approve all checked".
struct ReviewCardView: View {
    @ObservedObject var controller: AttributionController
    let candidates: () -> [TaskCandidate]
    var onEditRules: () -> Void = {}

    @State private var checked: Set<UUID> = []
    @State private var lastApproved: WorkSession?

    private var entries: [AttributionQueueEntry] {
        controller.pending().sorted { $0.blockStart < $1.blockStart }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if entries.isEmpty {
                emptyState
            } else {
                ScrollView { LazyVStack(spacing: 0) { ForEach(entries) { row($0) } } }
            }
            if let session = lastApproved { undoBar(session) }
        }
        .frame(width: 460, height: 520)
        .onAppear { preCheckHighConfidence() }
    }

    private var header: some View {
        HStack {
            Text("Review time").font(.headline)
            Spacer()
            Button("Rules…", action: onEditRules)
            Button("Approve all checked", action: approveAllChecked)
                .disabled(checked.isEmpty)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.secondary)
            Text("Nothing to review").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: AttributionQueueEntry) -> some View {
        let matched = entry.proposed.taskTitle
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { checked.contains(entry.id) },
                    set: { isOn in
                        if isOn { checked.insert(entry.id) } else { checked.remove(entry.id) }
                    }))
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text(matched ?? "Unattributed")
                        .fontWeight(matched == nil ? .regular : .semibold)
                        .foregroundStyle(matched == nil ? .secondary : .primary)
                    Text(evidence(entry)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                confidenceDot(entry.disposition)
            }
            HStack(spacing: 8) {
                Button("Approve") { approve(entry, as: nil) }
                Menu("Reassign") {
                    ForEach(candidates(), id: \.id) { candidate in
                        Button(candidate.title) {
                            approve(entry, as: (candidate.id, candidate.title))
                        }
                    }
                }
                Button("Reject", role: .destructive) { controller.reject(entry.id) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.leading, 28)
        }
        .padding(10)
        Divider().padding(.leading, 10)
    }

    private func confidenceDot(_ disposition: QueueDisposition) -> some View {
        let color: Color = switch disposition {
        case .preChecked: .green
        case .needsReview: .yellow
        case .unattributed: .secondary
        }
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func undoBar(_ session: WorkSession) -> some View {
        HStack {
            Text("Logged \(session.taskTitle.isEmpty ? "unattributed time" : session.taskTitle)")
                .font(.caption)
            Spacer()
            Button("Undo") { controller.undo(session); lastApproved = nil }
        }
        .padding(10)
        .background(.thinMaterial)
    }

    private func evidence(_ entry: AttributionQueueEntry) -> String {
        let minutes = Int(entry.blockEnd.timeIntervalSince(entry.blockStart) / 60)
        let titles = entry.evidence.titles.prefix(2).joined(separator: ", ")
        return "\(entry.evidence.appName), \(titles), \(minutes)m"
    }

    private func preCheckHighConfidence() {
        checked = Set(entries.filter { $0.disposition == .preChecked }.map(\.id))
    }

    private func approve(_ entry: AttributionQueueEntry, as override: (taskID: String, title: String)?) {
        if let session = controller.approve(entry.id, as: override) { lastApproved = session }
        checked.remove(entry.id)
    }

    private func approveAllChecked() {
        for entry in entries where checked.contains(entry.id) {
            _ = controller.approve(entry.id, as: nil)
        }
        checked.removeAll()
    }
}
