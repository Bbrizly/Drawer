import DrawerCore
import SwiftUI

struct TaskRowView: View, Equatable {
    let item: TodoItem
    /// The store is only used to call mutators; the row never reads its
    /// published state, so it is a plain reference, not an observed one. That
    /// keeps a toggle from re-rendering every other row through the store.
    let store: TodoStore
    /// Makes the panel key so the note editor actually receives typing. The
    /// panel is non-activating, so a focused field alone is not enough.
    var requestKeyboard: () -> Void = {}
    @Environment(\.drawerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("taskCelebration") private var taskCelebration = true
    @AppStorage("taskCelebrationSound") private var taskCelebrationSound = true
    @AppStorage("feature.taskNotes") private var taskNotesEnabled = true
    @AppStorage("feature.minuteBadges") private var minuteBadgesEnabled = true
    @AppStorage("feature.swipeDelete") private var swipeDeleteEnabled = true
    @AppStorage("feature.swipeProgress") private var swipeProgressEnabled = true
    @AppStorage("feature.workMode") private var workModeEnabled = true
    /// Settings > Text. Titles use it directly; notes ride two points under.
    @AppStorage("taskFontSize") private var taskFontSize = 13.0
    @Environment(CelebrationCenter.self) private var celebration
    @Environment(SwipeCoordinator.self) private var swipe
    @Environment(WorkClock.self) private var workClock
    @State private var isCheckboxHovering = false
    @State private var isRowHovering = false
    @State private var checkboxFrame: CGRect = .zero
    @State private var isExpanded = false
    @State private var isEditingNote = false
    @State private var draftNote = ""
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var dragAxis: DragAxis?
    @FocusState private var noteFieldFocused: Bool
    @FocusState private var titleFieldFocused: Bool

    private enum DragAxis { case horizontal, vertical }

    /// Only `item` decides what the row draws. The store and the keyboard
    /// closure are stable, so two rows with an equal item are equal. Paired with
    /// `.equatable()` at the call site, this lets SwiftUI skip re-evaluating a
    /// row the parent rebuilt unchanged (e.g. every other row when one task is
    /// toggled). Dependency-driven updates still invalidate the row through their
    /// own channels: the theme and Reduce Motion (environment), the feature
    /// flags (AppStorage), the work clock (Observation), and the swipe offset.
    static func == (lhs: TaskRowView, rhs: TaskRowView) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        // Swipe left (mouse drag or two-finger trackpad) to slide the row off
        // the trailing edge, revealing a delete button that was sitting just
        // out of frame (clipped) underneath. Both inputs share one offset.
        let offset = swipe.offset(for: item.id)
        ZStack {
            // Right swipe slides the row off the leading edge, revealing the
            // in-progress affordance underneath. It triggers on release, it is
            // not a button you tap, so the row snaps straight back.
            progressReveal
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: -swipe.progressWidth + max(offset, 0))
            deleteButton
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: swipe.deleteWidth + min(offset, 0))
            rowContent
                .offset(x: offset)
                // Disable the swipe entirely when neither direction is on, but
                // keep the checkbox and tap-to-expand working (.subviews).
                .gesture(
                    swipeGesture,
                    including: swipeDeleteEnabled || swipeProgressEnabled ? .all : .subviews
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous))
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                checkbox

                if isEditingTitle {
                    TextField("Task", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(theme.titleFont(size: taskFontSize))
                        .focused($titleFieldFocused)
                        .onSubmit(saveTitle)
                        .onChange(of: titleFieldFocused) { _, focused in
                            if !focused { saveTitle() }   // save on blur, Apple-style
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(item.title)
                        .font(theme.titleFont(size: taskFontSize))
                        .fontWeight(item.isInProgress ? .semibold : .regular)
                        .lineSpacing(2)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true) // wrap, never truncate
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Double-click to rename; single tap still expands the row.
                        .highPriorityGesture(TapGesture(count: 2).onEnded { beginEditTitle() })
                }

                if taskNotesEnabled && item.note != nil && !isExpanded {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .help("Has a description")
                }

                if minuteBadgesEnabled && item.minutes != 25 && !item.isDone {
                    Text("\(item.minutes)m")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.8), in: Capsule())
                }

                if workModeEnabled && workClock.isOn && !item.isDone {
                    workTrackButton
                }
            }
            // Click anywhere on the task line, not just the title, to expand.
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleExpand)

            // Editing is double-click on the text itself (title and note), so
            // the expanded area carries no edit buttons.
            if isExpanded, taskNotesEnabled {
                noteArea
                    .padding(.leading, 32) // line up under the title, past the checkbox
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, theme.rowVerticalPadding)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            // A thin accent bar marks an in-progress or actively-tracked row.
            if item.isInProgress || isTrackedActive {
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous))
        .accessibilityAction(named: item.isInProgress ? "Clear in progress" : "Mark in progress") {
            store.setInProgress(item, !item.isInProgress)
        }
        .overlay(alignment: .bottom) {
            if theme == .notebook {
                // A ruled line under every row so tasks visibly sit on the paper.
                Rectangle()
                    .fill(Palette.paperLine.color)
                    .frame(height: 0.75)
            } else if theme.showsRowSeparators {
                // A hairline in the theme ink, so Medieval rules read walnut on
                // parchment instead of a system gray divider.
                Rectangle()
                    .fill(theme.primaryInk.opacity(0.14))
                    .frame(height: 0.75)
                    .padding(.leading, 40)
            }
        }
        .onHover { hovering in
            isRowHovering = hovering
            // Tell the scroll monitor which row a two-finger swipe should hit.
            if hovering {
                swipe.hoveredID = item.id
            } else if swipe.hoveredID == item.id {
                swipe.hoveredID = nil
            }
        }
    }

    private var checkboxSymbol: String {
        theme.checkboxSymbol(done: item.isDone, inProgress: item.isInProgress)
    }

    /// This row is the one the work clock is attributed to. Matched by id only,
    /// so two tasks that merely share a title never both light up or cross-wire
    /// the track button. (Log attribution is by title; the live pointer is by id.)
    private var isTracked: Bool {
        workClock.activeTaskID == item.id
    }

    private var isTrackedActive: Bool {
        workModeEnabled && workClock.isOn && isTracked
    }

    /// Start, pause, or resume tracking this task. A plain `track` on every tap
    /// would fragment the log and reset elapsed, so the active row toggles.
    private var workTrackButton: some View {
        let running = isTracked && workClock.phase == .running
        return Button {
            switch (isTracked, workClock.phase) {
            case (true, .running): workClock.pause()
            case (true, .paused): workClock.resume()
            default: workClock.track(taskID: item.id, title: item.title)
            }
        } label: {
            Image(systemName: running ? "pause.circle.fill" : "play.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(running ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(running ? "Pause time tracking" : "Track time on this task")
        .accessibilityLabel(running ? "Pause time tracking" : "Track time on this task")
    }

    /// In-progress rows get a soft accent wash so they read as "live" without
    /// shouting. Otherwise the usual hover tint.
    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous)
        if item.isInProgress || isTrackedActive {
            shape.fill(theme.accent.opacity(isRowHovering ? 0.22 : 0.16))
        } else if isRowHovering {
            shape.fill(theme.primaryInk.opacity(0.06))
        } else {
            shape.fill(Color.clear)
        }
    }

    /// Sits behind the leading edge, revealed by a right swipe. Mirrors the
    /// delete button on the trailing edge.
    private var progressReveal: some View {
        Image(systemName: "circle.lefthalf.filled")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(width: swipe.progressWidth)
            .frame(maxHeight: .infinity)
            .background(theme.accent)
            .accessibilityHidden(true)
    }

    private var checkbox: some View {
        Button {
            if swipe.isOpen(item.id) { closeSwipe() }
            let willComplete = !item.isDone
            if willComplete { workClock.taskCompleted(id: item.id, title: item.title) }
            if reduceMotion {
                store.toggle(item)
            } else {
                withAnimation(.snappy(duration: 0.25)) { store.toggle(item) }
            }
            if taskCelebration && willComplete {
                Celebration.fire(sound: taskCelebrationSound)
                if !reduceMotion {
                    celebration.fire(at: CGPoint(x: checkboxFrame.midX, y: checkboxFrame.midY))
                }
            }
        } label: {
            Image(systemName: checkboxSymbol)
                .font(.system(size: theme.checkboxSize, weight: .medium))
                .foregroundStyle(
                    item.isDone || item.isInProgress
                        ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary)
                )
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .background(
                    // Theme ink, not a system gray, so the hover ring matches
                    // the row hover wash on the art-directed surfaces.
                    isCheckboxHovering ? theme.primaryInk.opacity(0.08) : Color.clear,
                    in: Circle()
                )
                .padding(6) // enlarge the click target without shifting layout
                .contentShape(Circle())
                .padding(-6)
                .background(
                    // Track the checkbox center in panel space so the
                    // unclipped confetti layer can burst from exactly here.
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { checkboxFrame = geo.frame(in: .named("panel")) }
                            .onChange(of: geo.frame(in: .named("panel"))) { _, f in
                                checkboxFrame = f
                            }
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isDone ? "Mark task incomplete" : "Complete task")
        .accessibilityValue(item.title)
        .accessibilityHint("Update this task in the markdown file.")
        .help(item.isDone ? "Mark incomplete" : "Mark complete")
        .onHover { isCheckboxHovering = $0 }
    }

    /// The expanded description: shows the note and an edit button, or an
    /// inline editor while editing. Writes back to the markdown file on save.
    @ViewBuilder
    private var noteArea: some View {
        if isEditingNote {
            // No Save/Cancel: type, then click away to save, same as the title.
            TextField("Add details", text: $draftNote, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: max(10, taskFontSize - 2)))
                .foregroundStyle(.secondary)
                .lineLimit(1...8)
                .focused($noteFieldFocused)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: noteFieldFocused) { _, focused in
                    if !focused { saveNote() }   // save on blur
                }
        } else if let note = item.note, !note.isEmpty {
            Text(linkified(note))
                .font(.system(size: max(10, taskFontSize - 2)))
                .foregroundStyle(.secondary)
                // Links take the theme accent, not a hardcoded blue, so they
                // sit right on parchment, paper, and the dark surfaces alike.
                .tint(theme.accent)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                // Double-click the note to edit it, same as the title. Text
                // selection is off so word-select cannot eat the double-click;
                // single clicks still open links.
                .highPriorityGesture(TapGesture(count: 2).onEnded { beginEditNote() })
                .help("Double-click to edit")
        } else {
            Button(action: beginEditNote) {
                Label("Add note", systemImage: "plus")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
    }

    private var deleteButton: some View {
        Button(action: deleteItem) {
            Image(systemName: "trash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.onAccent)
                .frame(width: swipe.deleteWidth)
                .frame(maxHeight: .infinity)
                .background(theme.danger)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete task")
        .accessibilityValue(item.title)
        .help("Delete")
    }

    /// Mouse click-drag that opens/closes the delete button. The axis is locked
    /// once at the first move and held for the whole drag, so a gesture that
    /// starts horizontal but ends vertical can never fire the action on release.
    /// Shares the coordinator with the trackpad scroll path, so they never clash.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal else { return }
                swipe.drag(id: item.id, translationX: value.translation.width)
            }
            .onEnded { _ in
                let wasHorizontal = dragAxis == .horizontal
                dragAxis = nil
                guard wasHorizontal else { return } // vertical drag: never settles or fires
                let settle = { swipe.end(id: item.id) }
                if reduceMotion { settle() } else { withAnimation(.snappy(duration: 0.22), settle) }
            }
    }

    private func toggleExpand() {
        if swipe.isOpen(item.id) { closeSwipe(); return }
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        }
    }

    /// The title exactly as written in the file, including any "(15m)" duration
    /// hint, so editing it does not silently drop the hint. Falls back to the
    /// parsed title if the checkbox prefix can't be found.
    private var writtenTitle: String {
        if let m = item.rawLine.firstMatch(of: #/^\s*- \[[ xX/]\]\s+/#) {
            return String(item.rawLine[m.range.upperBound...])
        }
        return item.title
    }

    private func beginEditTitle() {
        if swipe.isOpen(item.id) { closeSwipe(); return }
        draftTitle = writtenTitle
        isEditingTitle = true
        requestKeyboard() // panel must be key or the field gets no typing
        titleFieldFocused = true
    }

    private func saveTitle() {
        guard isEditingTitle else { return }
        isEditingTitle = false
        titleFieldFocused = false
        store.rename(item, to: draftTitle)
    }

    private func beginEditNote() {
        draftNote = item.note ?? ""
        isEditingNote = true
        requestKeyboard() // panel must be key or the note field gets no typing
        noteFieldFocused = true
    }

    private func saveNote() {
        isEditingNote = false
        noteFieldFocused = false
        store.setNote(item, draftNote)
    }

    private func closeSwipe() {
        let settle = { swipe.close(id: item.id) }
        if reduceMotion { settle() } else { withAnimation(.snappy(duration: 0.2), settle) }
    }

    private func deleteItem() {
        swipe.close(id: item.id)
        if reduceMotion {
            store.delete(item)
        } else {
            withAnimation(.snappy(duration: 0.2)) { store.delete(item) }
        }
    }
}
