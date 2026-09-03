import DrawerCore
import SwiftUI

/// What the scrubber knows about the snapshot the slider is sitting on.
/// Loading is its own state on purpose: reconstruction is a disk read plus a
/// parse on another actor, and showing "unavailable" while that is in flight
/// made every normal scrub look like corrupted history.
enum HistorySnapshotState {
    case idle
    case loading(hash: String)
    case loaded(hash: String, HistoryDisplay)
    case unavailable(hash: String)

    /// The display to draw for this snapshot, or nil for the quiet loading
    /// state. A result carrying a different hash never counts, so the previous
    /// step's tasks cannot sit under a newer slider position.
    func display(for hash: String) -> HistoryDisplay? {
        if case let .loaded(loaded, display) = self, loaded == hash { return display }
        return nil
    }

    /// Only a snapshot proven missing or corrupt says so. Still loading is not
    /// unavailable, which is the whole reason this is an enum.
    func isUnavailable(for hash: String) -> Bool {
        if case let .unavailable(failed) = self { return failed == hash }
        return false
    }
}

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
    @State private var snapshotState: HistorySnapshotState = .idle
    @State private var loadTask: Task<Void, Never>?
    @State private var loadGeneration = 0
    @State private var summary: [DayTally] = []
    /// A tapped day, showing its completed/started task titles below the band.
    /// nil = the live snapshot scrubber instead.
    @State private var selectedDay: Date?

    private var records: [SnapshotRecord] { recorder.records }
    private var index: Int { min(max(0, Int(position.rounded())), max(0, records.count - 1)) }

    var body: some View {
        VStack(spacing: 0) {
            if records.isEmpty {
                emptyState
            } else {
                dayBand
                Divider()
                if let selectedDay, let tally = summary.first(where: { $0.day == selectedDay }) {
                    dayDetail(tally).frame(maxHeight: .infinity)
                } else {
                    snapshot(records[index]).frame(maxHeight: .infinity)
                    Divider()
                    controls
                }
            }
        }
        .frame(width: inline ? nil : 400, height: inline ? nil : 540)
        .frame(maxWidth: inline ? .infinity : nil, maxHeight: inline ? .infinity : nil, alignment: .topLeading)
        .onAppear {
            position = Double(max(0, records.count - 1))
            requestSummary()
            requestDisplay()
        }
        // Jump to newest on any new capture. Observe the newest snapshot's
        // timestamp, not the count, which stays pinned at 500 once retention
        // fills (prune-one, append-one).
        .onChange(of: records.last?.ts) {
            position = Double(max(0, records.count - 1))
            requestSummary()
            requestDisplay()
        }
        .onChange(of: index) { requestDisplay() }
    }

    /// Reconstruct every retained snapshot, diff it, and roll the lifecycles up
    /// per day. Done once on open and on each new capture (not per frame): the
    /// blobs are small markdown files and retention caps the count at 500.
    ///
    /// It did jank, so the diff is off the main thread now. Five hundred
    /// snapshots is five hundred full markdown parses, and running that inline
    /// in `onAppear` stopped the whole drawer for about a second every time
    /// this view came back on screen, which is what made leaving the idea
    /// board feel broken.
    private func requestSummary() {
        let current = records
        Task { @MainActor in
            summary = await recorder.dailySummary(for: current)
        }
    }

    /// Moving the slider shows loading straight away, then swaps in whatever
    /// comes back. Two guards keep a slow load off a newer selection: the
    /// previous task is cancelled, and the generation is checked on arrival in
    /// case it had already passed the cancellation point.
    private func requestDisplay() {
        loadTask?.cancel()
        guard !records.isEmpty else {
            snapshotState = .idle
            return
        }
        let record = records[index]
        loadGeneration += 1
        let generation = loadGeneration
        guard snapshotState.display(for: record.hash) == nil else { return }
        snapshotState = .loading(hash: record.hash)
        loadTask = Task { @MainActor in
            let result = await recorder.display(for: record, today: today)
            guard !Task.isCancelled, generation == loadGeneration else { return }
            snapshotState = result.map { .loaded(hash: record.hash, $0) }
                ?? .unavailable(hash: record.hash)
        }
    }

    /// A left-to-right band of day cards (oldest first, matching the scrubber
    /// below), each showing how many tasks started and got done that day. The
    /// chevrons step between days: swiping the band sideways is caught by the
    /// board-swipe monitor, so the arrows are the reliable way across.
    @ViewBuilder
    private var dayBand: some View {
        if summary.contains(where: { !$0.started.isEmpty || !$0.completed.isEmpty }) {
            ScrollViewReader { proxy in
                HStack(spacing: 2) {
                    dayStepButton("chevron.left") { stepDay(-1, proxy) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(summary, id: \.day) { dayCard($0).id($0.day) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .defaultScrollAnchor(.trailing)
                    dayStepButton("chevron.right") { stepDay(1, proxy) }
                }
                .padding(.horizontal, 6)
            }
        }
    }

    private func dayStepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.callout.weight(.semibold))
                .frame(width: 22, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    /// Move the picked day by `delta` (clamped), or start at the newest day when
    /// nothing is picked yet, and scroll the band so the new card is in view.
    private func stepDay(_ delta: Int, _ proxy: ScrollViewProxy) {
        guard !summary.isEmpty else { return }
        let current = selectedDay.flatMap { day in summary.firstIndex { $0.day == day } }
        let next = current.map { min(max($0 + delta, 0), summary.count - 1) } ?? summary.count - 1
        selectedDay = summary[next].day
        withAnimation { proxy.scrollTo(summary[next].day, anchor: .center) }
    }

    private func dayCard(_ day: DayTally) -> some View {
        let selected = selectedDay == day.day
        return VStack(spacing: 3) {
            Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2).foregroundStyle(.secondary)
            Text(day.day.formatted(.dateTime.day()))
                .font(.callout.weight(.semibold))
            HStack(spacing: 5) {
                stat("plus", day.started.count, .secondary)
                stat("checkmark", day.completed.count, .green)
            }
        }
        .frame(width: 52)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(.primary.opacity(selected ? 0.14 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(.primary.opacity(selected ? 0.25 : 0), lineWidth: 1))
        .contentShape(Rectangle())
        // Tap a day to read its tasks; tap the open one again to go back.
        .onTapGesture { selectedDay = selected ? nil : day.day }
    }

    private func stat(_ symbol: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text("\(count)").font(.caption2.weight(.medium))
        }
        .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
    }

    /// The picked day's tasks by name: what got checked off, then what started.
    private func dayDetail(_ tally: DayTally) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(tally.day.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                detailSection("Completed", tally.completed, "checkmark.circle.fill", .green, strike: true)
                detailSection("Started", tally.started, "circle", .secondary, strike: false)
                if tally.completed.isEmpty && tally.started.isEmpty {
                    Text("Nothing tracked this day.").foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func detailSection(_ title: String, _ titles: [String], _ symbol: String, _ color: Color, strike: Bool) -> some View {
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) (\(titles.count))")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(titles.enumerated()), id: \.offset) { _, name in
                    HStack(spacing: 8) {
                        Image(systemName: symbol).foregroundStyle(color)
                        Text(name).strikethrough(strike).foregroundStyle(strike ? .secondary : .primary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
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

    @ViewBuilder
    private func snapshot(_ record: SnapshotRecord) -> some View {
        // Anything not about this exact snapshot reads as still loading, so the
        // previous step's tasks never sit under the new slider position.
        if let display = snapshotState.display(for: record.hash) {
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
        } else if snapshotState.isUnavailable(for: record.hash) {
            Text("This snapshot is unavailable.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            loadingState
        }
    }

    /// Deliberately quiet: scrubbing lands here between every step, so a
    /// spinner or a message would strobe.
    private var loadingState: some View {
        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading snapshot")
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
