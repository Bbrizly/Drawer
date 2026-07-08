import DrawerCore
import SwiftUI

/// The Work pane. Three stacked strips: what Drawer is watching right now (with
/// the live rule-stage guess), the time already captured today, and the hours
/// waiting to be confirmed. The review here is the only path from a proposed
/// match to the work log; approving writes, nothing else does.
struct WorkPaneView: View {
    @ObservedObject var controller: AttributionController
    /// True while the pane is open (not just mounted at width 0).
    var isActive: Bool = false

    @Environment(\.drawerTheme) private var theme
    @State private var lastApproved: (session: WorkSession, entry: AttributionQueueEntry)?

    /// The controller's cached queue (already sorted oldest first). The body
    /// re-evaluates on every live sample, so it must never read the disk here.
    private var pending: [AttributionQueueEntry] { controller.pendingEntries }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                watching
                capturedToday
                review
            }
        }
        .safeAreaInset(edge: .bottom) { if let a = lastApproved { undoBar(a.session, a.entry) } }
        .onAppear { controller.refreshDerived() }
        .onChange(of: isActive) { _, active in
            // Reopening re-reads the caches so a day rollover shows fresh.
            if active { controller.refreshDerived() }
        }
    }

    // MARK: - Watching now

    @ViewBuilder
    private var watching: some View {
        if controller.isObserving, let sample = controller.liveSample {
            VStack(alignment: .leading, spacing: 4) {
                Label("Watching", systemImage: "eye")
                    .font(theme.uiFont(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(watchTarget(sample))
                    .font(theme.uiFont(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(guessLine)
                    .font(theme.uiFont(size: 12))
                    .foregroundStyle(guessColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.accent.opacity(0.08)))
        } else {
            Label("Work Mode is off. Start a task to begin watching.", systemImage: "eye.slash")
                .font(theme.uiFont(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func watchTarget(_ sample: ActivitySample) -> String {
        guard let title = sample.windowTitle, !title.isEmpty else { return sample.appName }
        return "\(sample.appName): \(title)"
    }

    private var guessLine: String {
        guard let title = controller.liveGuess?.taskTitle else { return "No match yet" }
        return "Looks like \(title)"
    }

    private var guessColor: Color {
        controller.liveGuess?.taskTitle == nil ? .secondary : theme.accent
    }

    // MARK: - Captured today

    @ViewBuilder
    private var capturedToday: some View {
        let summary = controller.todaySummary
        if !summary.rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Captured today")
                        .font(theme.uiFont(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(duration(summary.total))
                        .font(theme.uiFont(size: 11, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                ForEach(summary.rows.indices, id: \.self) { i in
                    HStack {
                        Text(summary.rows[i].taskTitle.isEmpty ? "Unattributed" : summary.rows[i].taskTitle)
                            .font(theme.uiFont(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(duration(summary.rows[i].seconds))
                            .font(theme.uiFont(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Review (confirm your hours)

    @ViewBuilder
    private var review: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Confirm your hours")
                    .font(theme.uiFont(size: 13, weight: .semibold))
                Spacer()
                if !pending.isEmpty {
                    Text("\(pending.count)")
                        .font(theme.uiFont(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if pending.isEmpty {
                Label("All caught up. Nothing to confirm.", systemImage: "checkmark.seal")
                    .font(theme.uiFont(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pending) { reviewRow($0) }
                legend
            }
        }
    }

    private func reviewRow(_ entry: AttributionQueueEntry) -> some View {
        let matched = entry.proposed.taskTitle
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                confidenceDot(entry.disposition)
                Text(matched ?? "Unattributed")
                    .font(theme.uiFont(size: 13, weight: matched == nil ? .regular : .semibold))
                    .foregroundStyle(matched == nil ? .secondary : theme.primaryInk)
                Spacer(minLength: 0)
            }
            Text(evidence(entry))
                .font(theme.uiFont(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Approve") { approve(entry, as: nil) }
                ReassignMenu(
                    evidence: entry.evidence, candidates: controller.candidates(),
                    onPick: { approve(entry, as: ($0, $1)) })
                Button("Skip", role: .destructive) { controller.reject(entry.id) }
            }
            .buttonStyle(.borderless)
            .font(theme.uiFont(size: 12))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.primaryInk.opacity(0.04)))
    }

    /// Named legend for the confidence dots so the colors read as how sure
    /// Drawer is, not decoration.
    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(.green, "Confident")
            legendItem(.yellow, "Check it")
            legendItem(.secondary, "No match")
        }
        .font(theme.uiFont(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.top, 2)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    private func confidenceDot(_ disposition: QueueDisposition) -> some View {
        let color: Color = switch disposition {
        case .preChecked: .green
        case .needsReview: .yellow
        case .unattributed: .secondary
        }
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func undoBar(_ session: WorkSession, _ entry: AttributionQueueEntry) -> some View {
        HStack {
            Text("Logged \(session.taskTitle.isEmpty ? "unattributed time" : session.taskTitle)")
                .font(theme.uiFont(size: 11))
            Spacer()
            Button("Undo") {
                controller.undo(session, restoring: entry)
                lastApproved = nil
            }
            .font(theme.uiFont(size: 11))
        }
        .padding(10)
        .background(.thinMaterial)
    }

    private func evidence(_ entry: AttributionQueueEntry) -> String {
        let minutes = Int(entry.blockEnd.timeIntervalSince(entry.blockStart) / 60)
        let titles = entry.evidence.titles.prefix(2).joined(separator: ", ")
        return "\(entry.evidence.appName), \(titles), \(minutes)m"
    }

    private func approve(_ entry: AttributionQueueEntry, as override: (taskID: String, title: String)?) {
        if let session = controller.approve(entry.id, as: override) {
            lastApproved = (session, entry)
        }
    }

    /// "1h 05m" / "12m", a compact form for the summary strip.
    private func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        let (h, m) = (total / 60, total % 60)
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }
}
