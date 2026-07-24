import DrawerCore
import SwiftUI

/// Scrub through your week and watch the work happen. A slider across the
/// retained snapshots; above it, the reconstructed Drawer.md at that instant,
/// rendered read-only with the same parser the live drawer uses.
struct HistoryScrubberView: View {
    @ObservedObject var recorder: HistoryRecorder
    let today: String
    /// Standalone window sizes itself (400x540); the inline pane lets its column
    /// size it instead.
    var inline: Bool = false
    @State private var position: Double = 0
    @State private var cache = ParseCache()
    @State private var summary: [DayTally] = []

    private typealias DisplayBuckets = (
        today: [TodoItem], carried: [TodoItem],
        upcoming: [TodoItem], upcomingDate: String?,
        backlog: [TodoItem], archive: [TodoItem]
    )

    /// One-entry memo of the reconstructed + parsed snapshot, keyed by hash,
    /// so repeated body evaluations at the same position don't redo the disk
    /// read, SHA verify, and full parse. A reference type: filling it during
    /// body evaluation is legal and doesn't re-invalidate the view.
    private final class ParseCache {
        var hash: String?
        var display: DisplayBuckets? // nil (with hash set) = unavailable
    }

    private var records: [SnapshotRecord] { recorder.records }
    private var index: Int { min(max(0, Int(position.rounded())), max(0, records.count - 1)) }

    var body: some View {
        VStack(spacing: 0) {
            if records.isEmpty {
                emptyState
            } else {
                dayBand
                Divider()
                snapshot(records[index]).frame(maxHeight: .infinity)
                Divider()
                controls
            }
        }
        .frame(width: inline ? nil : 400, height: inline ? nil : 540)
        .frame(maxWidth: inline ? .infinity : nil, maxHeight: inline ? .infinity : nil, alignment: .topLeading)
        .onAppear { position = Double(max(0, records.count - 1)); rebuildSummary() }
        // Jump to newest on any new capture. Observe the newest snapshot's
        // timestamp, not the count, which stays pinned at 500 once retention
        // fills (prune-one, append-one).
        .onChange(of: records.last?.ts) {
            position = Double(max(0, records.count - 1))
            rebuildSummary()
        }
    }

    /// Reconstruct every retained snapshot, diff it, and roll the lifecycles up
    /// per day. Done once on open and on each new capture (not per frame): the
    /// blobs are small markdown files and retention caps the count at 500.
    /// ponytail: if this ever janks on open, hop it to a detached Task.
    private func rebuildSummary() {
        let snaps: [TimelineSnapshot] = records.compactMap { record in
            guard case let .available(bytes) = recorder.reconstruct(record),
                  let text = String(data: bytes, encoding: .utf8) else { return nil }
            return TimelineSnapshot(ts: record.ts, markdown: text)
        }
        summary = HistoryTimelineBuilder.dailySummary(HistoryTimelineBuilder.build(snapshots: snaps))
    }

    /// A left-to-right band of day cards (oldest first, matching the scrubber
    /// below), each showing how many tasks started and got done that day.
    @ViewBuilder
    private var dayBand: some View {
        if summary.contains(where: { $0.started > 0 || $0.completed > 0 }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(summary, id: \.day) { dayCard($0) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.trailing)
        }
    }

    private func dayCard(_ day: DayTally) -> some View {
        VStack(spacing: 3) {
            Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2).foregroundStyle(.secondary)
            Text(day.day.formatted(.dateTime.day()))
                .font(.callout.weight(.semibold))
            HStack(spacing: 5) {
                stat("plus", day.started, .secondary)
                stat("checkmark", day.completed, .green)
            }
        }
        .frame(width: 52)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.05)))
    }

    private func stat(_ symbol: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text("\(count)").font(.caption2.weight(.medium))
        }
        .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
            Text("History starts now").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            if records.count > 1 {
                Slider(value: $position, in: 0...Double(records.count - 1), step: 1)
            }
            HStack {
                Text(label(records[index].ts)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(index + 1) of \(records.count)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func parsed(_ record: SnapshotRecord) -> DisplayBuckets? {
        if cache.hash == record.hash { return cache.display }
        var display: DisplayBuckets?
        if case let .available(bytes) = recorder.reconstruct(record) {
            let text = String(data: bytes, encoding: .utf8) ?? ""
            display = TodoParser.display(sections: TodoParser.parse(text), today: today)
        }
        cache.hash = record.hash
        cache.display = display
        return display
    }

    @ViewBuilder
    private func snapshot(_ record: SnapshotRecord) -> some View {
        if let display = parsed(record) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("Today", display.today)
                    section("Carried over", display.carried)
                    section(display.upcomingDate.map { "Upcoming \($0)" } ?? "Upcoming", display.upcoming)
                    section("Backlog", display.backlog)
                    section("Archive", display.archive)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("This snapshot is unavailable.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [TodoItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(items) { row($0) }
            }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDone
                ? "checkmark.circle.fill"
                : (item.isInProgress ? "circle.lefthalf.filled" : "circle"))
                .foregroundStyle(item.isDone ? .green : .secondary)
            Text(item.title).strikethrough(item.isDone).foregroundStyle(item.isDone ? .secondary : .primary)
            Spacer()
            if item.minutes != 25 {
                Text("\(item.minutes)m").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func label(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
