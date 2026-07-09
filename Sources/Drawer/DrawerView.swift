import AppKit
import DrawerCore
import SwiftUI

struct DrawerView: View {
    @ObservedObject var store: TodoStore
    var timer: FocusTimer
    var pomodoroTimer: PomodoroTimer
    var workClock: WorkClock
    var onToggleSize: () -> Void = {}
    var onNeedsKeyboard: () -> Void = {}
    /// Hide the whole drawer (a left swipe on the task page, like Esc).
    var onHide: () -> Void = {}
    var notes: NotesStore? = nil
    var onToggleTeleprompter: () -> Void = {}
    var ideas: BoardStore? = nil
    /// Resize the panel to the board coverage the swipe dialed in (0...1).
    var onBoardCoverage: (CGFloat) -> Void = { _ in }
    /// The companion pane's open/closed state. Opened only by the top-bar
    /// buttons below; drives the pane column and the panel grow-right.
    var router = PaneRouter()
    /// Tell the panel to widen (pane open) or collapse (closed).
    var onPaneWidthChange: (Bool) -> Void = { _ in }
    /// Drives the Plan pane. Optional so the visual render tests (which never
    /// open the pane) can construct the drawer without an on-device model.
    var planner: PlannerController? = nil
    var attribution: AttributionController? = nil
    var history: HistoryRecorder? = nil

    @State private var showingAdd = false
    @State private var showingNotes = false
    @State private var showingCapture = false
    @State private var endSummary: WorkSummary?
    @AppStorage("notesPaneHeight") private var notesPaneHeight = 160.0
    @State private var newTaskTitle = ""
    @State private var addDestination = AddDestination.today
    @State private var addIsHeader = false
    @FocusState private var addFieldFocused: Bool
    @AppStorage("hideCompleted") private var hideCompleted = false
    @AppStorage("uncheckedFirst") private var uncheckedFirst = false
    @AppStorage("showTomorrow") private var showTomorrow = true
    @AppStorage("backlogExpanded") private var backlogExpanded = false
    @AppStorage("archiveExpanded") private var archiveExpanded = false
    @AppStorage("drawerExpanded") private var drawerExpanded = false
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
    @AppStorage("panelWidth") private var panelWidth = 300.0
    // Feature flags (see FeatureFlag). Each gates a slice of the UI so the app
    // can be stripped to the bare task list.
    @AppStorage("typeOnOpen") private var typeOnOpen = false
    @AppStorage("feature.focusTimer") private var focusTimerEnabled = true
    @AppStorage("feature.pomodoro") private var pomodoroEnabled = true
    @AppStorage("feature.focusSound") private var focusSoundEnabled = true
    @AppStorage("feature.filterMenu") private var filterMenuEnabled = true
    @AppStorage("feature.notes") private var notesEnabled = true
    @AppStorage("feature.carriedSection") private var carriedSectionEnabled = true
    @AppStorage("feature.backlogSection") private var backlogSectionEnabled = true
    @AppStorage("feature.archiveSection") private var archiveSectionEnabled = true
    @AppStorage("feature.workMode") private var workModeEnabled = false
    @AppStorage("feature.ideas") private var ideasEnabled = true
    @AppStorage("feature.ideaCapture") private var ideaCaptureEnabled = false
    // Companion-pane sections. The pane and its top-bar button only appear when
    // at least one of these is on, so the whole extra panel stays out of the way
    // until a feature that fills it is enabled.
    @AppStorage("feature.planner") private var plannerEnabled = false
    @AppStorage("feature.attribution") private var attributionEnabled = false
    @AppStorage("feature.history") private var historyEnabled = false
    @AppStorage("boardBackground") private var boardBackground = "dark"
    private var boardTransparent: Bool { boardBackground == "transparent" }
    @AppStorage("feature.swipeDelete") private var swipeDeleteEnabled = true
    @AppStorage("feature.swipeProgress") private var swipeProgressEnabled = true
    @AppStorage("focusSoundKind") private var focusSoundKind = "pink"
    @AppStorage("focusSoundVolume") private var focusSoundVolume = 0.5
    // Settings > Text. "theme" follows the theme's own design; anything else
    // overrides it drawer-wide.
    @AppStorage("appFontDesign") private var appFontDesign = "theme"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme
    @State private var celebration = CelebrationCenter()
    @State private var swipe = SwipeCoordinator()
    @StateObject private var scrollMonitor = ScrollSwipeMonitor()
    @StateObject private var sound = FocusSoundPlayer()

    private var theme: DrawerTheme { DrawerTheme(rawValue: themeRaw) ?? .default }
    private var notebookWritingInset: CGFloat {
        theme == .notebook ? Palette.notebookMargin - 2 : 0
    }
    private var floatingControlFill: AnyShapeStyle {
        theme.usesXPChrome ? theme.controlFill : AnyShapeStyle(.quaternary.opacity(0.65))
    }
    private var floatingControlRadius: CGFloat { theme.usesXPChrome ? 0 : 11 }

    @ViewBuilder
    private func floatingPanelBackground() -> some View {
        if theme.usesXPChrome {
            XPSunkenPanel()
        } else {
            RoundedRectangle(cornerRadius: floatingControlRadius)
                .fill(.quaternary.opacity(0.55))
        }
    }

    @ViewBuilder
    private func addFieldBackground() -> some View {
        if theme.usesXPChrome {
            XPSunkenPanel()
        } else {
            RoundedRectangle(cornerRadius: floatingControlRadius)
                .fill(floatingControlFill)
        }
    }

    /// The focus and work pills, laid out by ViewThatFits in the header.
    @ViewBuilder private var timerPills: some View {
        if focusTimerEnabled {
            TimerHeaderView(timer: timer)
        }
        if pomodoroEnabled {
            PomodoroHeaderView(timer: pomodoroTimer)
        }
        if workModeEnabled && workClock.isOn {
            WorkModeHeaderView(clock: workClock)
        }
    }

    /// The drawer-wide font design: the theme's own, unless overridden in
    /// Settings > Text. (Pixel's bitmap task face is a font, not a design, so
    /// it is untouched by this; see DrawerTheme.titleFont.)
    private var resolvedFontDesign: Font.Design {
        switch appFontDesign {
        case "system": return .default
        case "rounded": return .rounded
        case "serif": return .serif
        case "mono": return .monospaced
        default: return theme.fontDesign
        }
    }

    /// Where the add field drops the new line. Today routes through the existing
    /// add path; Backlog/Archive create the section if it is missing.
    enum AddDestination: Hashable {
        case today, backlog, archive
        var label: String {
            switch self {
            case .today: return "Today"
            case .backlog: return "Backlog"
            case .archive: return "Archive"
            }
        }
    }

    private func commitAdd() {
        let t = newTaskTitle.trimmingCharacters(in: .whitespaces)
        defer { newTaskTitle = ""; showingAdd = false; addIsHeader = false }
        guard !t.isEmpty else { return }
        switch addDestination {
        case .today:
            let today = TodoStore.localToday()
            addIsHeader
                ? store.addHeader(t, toSectionKey: today, displayHeading: today)
                : store.add(t)
        case .backlog:
            addIsHeader
                ? store.addHeader(t, toSectionKey: "backlog", displayHeading: "Backlog")
                : store.addTask(t, toSectionKey: "backlog", displayHeading: "Backlog")
        case .archive:
            addIsHeader
                ? store.addHeader(t, toSectionKey: "archive", displayHeading: "Archive")
                : store.addTask(t, toSectionKey: "archive", displayHeading: "Archive")
        }
    }

    /// The companion-pane sections whose feature is enabled, in display order.
    /// Empty means the pane (and its button) stays hidden.
    private var availablePanes: [Pane] {
        var panes: [Pane] = []
        if plannerEnabled { panes.append(.plan) }
        if attributionEnabled { panes.append(.work) }
        if historyEnabled { panes.append(.history) }
        return panes
    }

    /// Which section the (possibly-closed, width-0) pane renders. Kept valid as
    /// flags change so a just-disabled section never leaves a stale pane mounted.
    private var paneToShow: Pane? {
        if let active = router.activePane, availablePanes.contains(active) { return active }
        if availablePanes.contains(router.lastOpened) { return router.lastOpened }
        return availablePanes.first
    }

    /// Opens (or toggles closed) the companion pane, landing on the last section
    /// still enabled (or the first available). Opening asks the panel for the
    /// keyboard so the pane's fields are ready to type into.
    private func openPane() {
        if router.activePane != nil { router.activePane = nil; return }
        guard let first = availablePanes.first else { return }
        router.activePane = availablePanes.contains(router.lastOpened) ? router.lastOpened : first
        onNeedsKeyboard()
    }

    var body: some View {
        // One continuous panel plate spans the whole (possibly widened) window;
        // the task column and the companion pane are columns on top of it, so the
        // pane shares the theme's surface instead of floating over a clear window.
        // topLeading anchoring keeps the task column pinned to the left while the
        // pane extends right and the window edge clips it until it is opened.
        ZStack(alignment: .topLeading) {
            if !(swipe.showingBoard && boardTransparent) {
                PanelBackground(theme: theme)
                    .environment(\.controlActiveState, .active)
            }

            HStack(spacing: 0) {
                // Pinned to its set width unless the board takes the whole frame.
                // Constant width means the window-resize animation is the ONLY
                // motion when the pane opens: the task list never reflows.
                taskColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .frame(width: swipe.showingBoard ? nil : panelWidth)
                    .opacity(swipe.showingBoard && boardTransparent ? 0 : 1)
            }
            // The pane is laid out full width and pinned just past the task
            // column's right edge, as an overlay so it never widens the task
            // row (a widened row would force SwiftUI to center the overflow and
            // shove the task column off the left). When closed it sits beyond
            // the window's right edge; the panel's animated resize is the single
            // motion that reveals or hides it, so the pane edge can never drift
            // from the window edge. Nothing inside the content moves.
            .overlay(alignment: .topLeading) {
                if !swipe.showingBoard, let shown = paneToShow {
                    CompanionPaneView(
                        pane: shown,
                        panes: availablePanes,
                        router: router,
                        planner: planner,
                        attribution: attribution,
                        history: history,
                        isActive: router.activePane != nil,
                        onNeedsKeyboard: onNeedsKeyboard
                    )
                    .frame(width: PanelController.paneWidth)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: panelWidth)
                    .accessibilityHidden(router.activePane == nil)
                }
            }

            ConfettiLayer(center: celebration)

            if ideasEnabled, let ideas {
                IdeaBoardPage(store: ideas, theme: theme) {
                    swipe.showingBoard = false
                }
                .offset(x: swipe.showingBoard ? 0 : -3000)
            }
        }
        .coordinateSpace(.named("panel"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(theme.usesXPChrome ? FontLoader.xpFont(size: 13) : .body)
        .fontDesign(resolvedFontDesign)
        .tint(theme.accent)
        .foregroundStyle(theme.primaryInk)
        .environment(\.drawerTheme, theme)
        .environment(\.colorScheme, theme.forcedColorScheme ?? systemScheme)
        .environment(celebration)
        .environment(swipe)
        .environment(workClock)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showingAdd)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showingNotes)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showingCapture)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: swipe.showingBoard)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: sound.isPlaying)
        .onAppear { configureSwipeCoordinator() }
        .onReceive(NotificationCenter.default.publisher(for: .drawerDidOpen)) { _ in
            guard typeOnOpen else { return }
            addIsHeader = false
            showingAdd = true
            onNeedsKeyboard()
            addFieldFocused = true
        }
        .onChange(of: swipeDeleteEnabled) { _, on in swipe.deleteEnabled = on }
        .onChange(of: swipeProgressEnabled) { _, on in swipe.progressEnabled = on }
        .onChange(of: swipe.boardCoverage) { _, c in onBoardCoverage(c) }
        .onChange(of: swipe.showingBoard) { _, shown in handleBoardVisibility(shown) }
        .onChange(of: router.activePane) { _, pane in onPaneWidthChange(pane != nil) }
        // If the open section's feature is switched off in Settings, close the
        // pane so it can't strand a widened, empty panel.
        .onChange(of: availablePanes) { _, panes in
            if let active = router.activePane, !panes.contains(active) { router.activePane = nil }
        }
        .onDisappear { scrollMonitor.stop() }
    }

    /// The task list column (header toolbar + content), the drawer's normal
    /// contents. Split out so the companion pane can sit beside it over the same
    /// shared panel background.
    private var taskColumn: some View {
        Group {
            if theme.usesXPChrome {
                // Classic XP window: blue title bar, a beige menu/toolbar band,
                // then the white client area.
                VStack(spacing: 0) {
                    XPTitleBar(
                        onMinimize: onHide,
                        onMaximize: onToggleSize,
                        onClose: onHide
                    )
                    .padding(.horizontal, 3)
                    .padding(.top, 3)
                    headerToolbarRow
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(XPMenuBand())
                        .padding(.horizontal, 3)
                    drawerMainContent
                        .padding(14)
                }
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    headerToolbarRow
                    drawerMainContent
                }
                .padding(14)
            }
        }
    }

    private var headerToolbarRow: some View {
        HStack(spacing: 10) {
            if !theme.usesXPChrome { Spacer(minLength: 0) }
            HStack(spacing: 2) {
                if focusSoundEnabled {
                    if sound.isPlaying {
                        headerSoundControls
                            .transition(soundControlsTransition)
                    }
                    DrawerIconButton(
                        systemName: sound.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        accessibilityLabel: sound.isPlaying ? "Stop focus sound" : "Play focus sound",
                        helpText: "Play focus noise. Pick the sound and volume here.",
                        isProminent: sound.isPlaying
                    ) {
                        sound.toggle()
                    }
                }
                DrawerIconButton(
                    systemName: "plus",
                    accessibilityLabel: "Add task",
                    helpText: "Show a field for adding a task.",
                    isSelected: showingAdd
                ) {
                    showingAdd.toggle()
                    if showingAdd {
                        onNeedsKeyboard()
                        addFieldFocused = true
                    }
                }
                if notesEnabled && notes != nil {
                    DrawerIconButton(
                        systemName: "note.text",
                        accessibilityLabel: "Notes",
                        helpText: "Open a scratchpad with a teleprompter.",
                        isSelected: showingNotes
                    ) {
                        showingNotes.toggle()
                        if showingNotes { onNeedsKeyboard() }
                    }
                }
                if ideas != nil {
                    if ideaCaptureEnabled {
                        DrawerIconButton(
                            systemName: "lightbulb",
                            accessibilityLabel: "Jot an idea",
                            helpText: "Jot an idea and park it on the board.",
                            isSelected: showingCapture
                        ) {
                            showingCapture.toggle()
                            if showingCapture { onNeedsKeyboard() }
                        }
                    }
                    if ideasEnabled {
                        DrawerIconButton(
                            systemName: "square.grid.2x2",
                            accessibilityLabel: "Open idea board",
                            helpText: "Open the board of parked ideas.",
                            isSelected: swipe.showingBoard
                        ) {
                            swipe.showingBoard = true
                        }
                    }
                }
                if filterMenuEnabled { filterMenuButton }
                if workModeEnabled {
                    DrawerIconButton(
                        systemName: workClock.isOn ? "briefcase.fill" : "briefcase",
                        accessibilityLabel: workClock.isOn ? "End work mode" : "Start work mode",
                        helpText: "Track real hours on your tasks. Tap a task to start the clock.",
                        isSelected: workClock.isOn
                    ) {
                        if workClock.isOn {
                            endSummary = workClock.end(today: TodoStore.localToday())
                            AppPaths.exportWorkLog(workClock)
                        } else {
                            workClock.enter()
                        }
                    }
                }
                if !availablePanes.isEmpty {
                    DrawerIconButton(
                        systemName: "sidebar.right",
                        accessibilityLabel: "Companion pane",
                        helpText: "Open the side pane for the features you have on.",
                        isSelected: router.activePane != nil
                    ) {
                        openPane()
                    }
                }
                DrawerIconButton(
                    systemName: drawerExpanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    accessibilityLabel: drawerExpanded ? "Collapse drawer" : "Expand drawer",
                    helpText: "Expand the drawer to full height or collapse it.",
                    isSelected: drawerExpanded
                ) {
                    onToggleSize()
                }
            }
            .padding(3)
            .background {
                if !theme.usesXPChrome {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.controlFill)
                }
            }
            if theme.usesXPChrome { Spacer(minLength: 0) }
        }
    }

    private var filterMenuButton: some View {
        Menu {
            Toggle("Hide completed", isOn: $hideCompleted)
            Toggle("Unchecked first", isOn: $uncheckedFirst)
        } label: {
            if theme.usesXPChrome {
                XPToolbarIcon(
                    systemName: "line.3.horizontal.decrease",
                    active: hideCompleted || uncheckedFirst
                )
            } else {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        hideCompleted || uncheckedFirst
                            ? AnyShapeStyle(theme.accent)
                            : AnyShapeStyle(.secondary)
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        hideCompleted || uncheckedFirst
                            ? theme.accent.opacity(0.14)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 30)
        .accessibilityLabel("Filter tasks")
        .accessibilityHint("Show task filtering and sorting options.")
        .help("Filter and sort")
    }

    @ViewBuilder
    private var drawerMainContent: some View {
                if focusTimerEnabled || pomodoroEnabled || (workModeEnabled && workClock.isOn) {
                    if theme.usesXPChrome {
                        // Full-width stacked bars so the timers line up and match,
                        // like a stack of XP toolbars rather than floating pills.
                        VStack(alignment: .leading, spacing: 6) { timerPills }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 6) { timerPills }
                            VStack(alignment: .leading, spacing: 6) { timerPills }
                        }
                        .padding(.leading, notebookWritingInset)
                    }
                }

                if showingAdd {
                    HStack(spacing: 8) {
                        Image(systemName: addIsHeader ? "number" : "plus.circle.fill")
                            .foregroundStyle(.tint)
                        TextField(addIsHeader ? "Add a header" : "Add a task", text: $newTaskTitle)
                            .textFieldStyle(.plain)
                            .focused($addFieldFocused)
                            .onSubmit(commitAdd)
                        Menu {
                            Picker("Where", selection: $addDestination) {
                                Text("Today").tag(AddDestination.today)
                                Text("Backlog").tag(AddDestination.backlog)
                                Text("Archive").tag(AddDestination.archive)
                            }
                            Toggle("As header", isOn: $addIsHeader)
                        } label: {
                            HStack(spacing: 3) {
                                Text(addDestination.label)
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                            }
                            .font(theme.uiFont(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background { addFieldBackground() }
                    .padding(.leading, notebookWritingInset)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showingCapture, ideaCaptureEnabled, let ideas {
                    IdeaCaptureBar(store: ideas, reduceMotion: reduceMotion) {
                        showingCapture = false
                    }
                    .padding(.leading, notebookWritingInset)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showingNotes, let notes {
                    NotesPaneView(
                        notes: notes,
                        height: $notesPaneHeight,
                        onToggleTeleprompter: onToggleTeleprompter,
                        onNeedsKeyboard: onNeedsKeyboard
                    )
                    .padding(.leading, notebookWritingInset)
                }

                ScrollView {
                    // Lazy so only the rows near the viewport are built. Bounds
                    // every per-row cost (rebuilds, gestures, geometry) to what
                    // is actually on screen rather than the whole list.
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if let endSummary {
                            WorkSummaryCard(
                                summary: endSummary,
                                requestKeyboard: onNeedsKeyboard,
                                onEdit: { title, seconds, day in
                                    self.endSummary = workClock.editSummary(
                                        title: title, seconds: seconds, on: day)
                                    AppPaths.exportWorkLog(workClock)
                                },
                                onDone: { self.endSummary = nil }
                            )
                            .padding(.bottom, 4)
                        }
                        if let msg = store.statusMessage {
                            statusView(msg)
                        }
                        if let wmMsg = workClock.statusMessage {
                            statusView(wmMsg)
                        }
                        let today = arranged(store.todayItems)
                        let carried = carriedSectionEnabled ? arranged(store.carriedItems) : []
                        if !today.isEmpty {
                            sectionHeader("Today", count: today.count, isPrimary: true)
                            ForEach(today) { item in
                                taskRow(item)
                            }
                        }
                        if !carried.isEmpty {
                            sectionHeader("Carried over", count: carried.count)
                                .padding(.top, 8)
                            ForEach(carried) { item in
                                taskRow(item)
                            }
                        }
                        let upcoming = showTomorrow ? arranged(store.upcomingItems) : []
                        if !upcoming.isEmpty {
                            sectionHeader(store.upcomingLabel, count: upcoming.count)
                                .padding(.top, 8)
                            ForEach(upcoming) { item in
                                taskRow(item)
                            }
                        }
                        if backlogSectionEnabled {
                            collapsibleSection(
                                title: "BACKLOG",
                                items: store.backlogItems,
                                isExpanded: $backlogExpanded,
                                helpText: "Tasks under \"## Backlog\" in the file"
                            )
                        }
                        if archiveSectionEnabled {
                            collapsibleSection(
                                title: "ARCHIVE",
                                items: store.archiveItems,
                                isExpanded: $archiveExpanded,
                                helpText: "Tasks under \"## Archive\" in the file"
                            )
                        }
                        if today.isEmpty && carried.isEmpty && upcoming.isEmpty
                            && store.statusMessage == nil {
                            emptyState
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.leading, notebookWritingInset)
    }

    private func configureSwipeCoordinator() {
        scrollMonitor.start(swipe)
        swipe.deleteEnabled = swipeDeleteEnabled
        swipe.progressEnabled = swipeProgressEnabled
        swipe.onProgress = { [weak store] id in
            guard let store, let item = store.item(withID: id) else { return }
            store.setInProgress(item, !item.isInProgress)
        }
        swipe.onCloseDrawer = onHide
    }

    private func handleBoardVisibility(_ shown: Bool) {
        if shown {
            // The board owns the whole frame; close any open pane so nothing
            // fights it for the width.
            router.activePane = nil
            // Pinch-zoom events reach only the key window; the cooperative
            // no-arg activate doesn't reliably front the app on first open, so
            // makeKey below wouldn't stick and pinch stayed dead until a click.
            NSApp.activate(ignoringOtherApps: true)
            onNeedsKeyboard()
            if swipe.boardCoverage == 0 {
                swipe.boardCoverage = swipe.lastBoardCoverage
            }
        } else {
            if swipe.boardCoverage > 0.05 {
                swipe.lastBoardCoverage = swipe.boardCoverage
            }
            swipe.boardCoverage = 0
        }
    }

    /// One run of consecutive tasks sharing a "### " subheading (or none).
    private struct TaskGroup: Identifiable {
        let id: Int
        let title: String?
        var items: [TodoItem]
    }

    /// Splits items into consecutive subsection runs (file order), then
    /// applies the user's filter/sort prefs within each run so groups stay
    /// intact under "Unchecked first".
    private func grouped(_ items: [TodoItem]) -> [TaskGroup] {
        var groups: [TaskGroup] = []
        for item in items {
            if let last = groups.indices.last, groups[last].title == item.subsection {
                groups[last].items.append(item)
            } else {
                groups.append(TaskGroup(id: groups.count, title: item.subsection, items: [item]))
            }
        }
        return groups
            .map { TaskGroup(id: $0.id, title: $0.title, items: arranged($0.items)) }
            .filter { !$0.items.isEmpty }
    }

    /// Collapsible task group (Backlog, Archive): chevron header with a
    /// count, rows shown only while expanded, grouped under their "### "
    /// subheadings. Renders nothing when empty.
    @ViewBuilder
    private func collapsibleSection(
        title: String,
        items: [TodoItem],
        isExpanded: Binding<Bool>,
        helpText: String
    ) -> some View {
        // The collapsed header only needs a count; skip the group/sort work
        // until the section is actually open. The count matches what grouping
        // would show (only the hide-completed filter changes it).
        let count = hideCompleted
            ? items.lazy.filter { !$0.isDone }.count
            : items.count
        if count > 0 {
            Button {
                if reduceMotion {
                    isExpanded.wrappedValue.toggle()
                } else {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isExpanded.wrappedValue.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue
                          ? "chevron.down" : "chevron.right")
                        .font(theme.usesXPChrome
                              ? FontLoader.xpFont(size: 9, weight: .bold)
                              : .system(size: 9, weight: .bold))
                    Text(theme.usesXPChrome ? title.capitalized : title)
                        .font(theme.usesXPChrome
                              ? FontLoader.xpFont(size: 10, weight: .bold)
                              : .system(size: 10, weight: .bold))
                        .tracking(theme.usesXPChrome ? 0 : 0.7)
                    Text("\(count)")
                        .font(theme.usesXPChrome
                              ? FontLoader.xpFont(size: 10, weight: .semibold)
                              : .system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .help(helpText)
            if isExpanded.wrappedValue {
                ForEach(grouped(items)) { group in
                    if let subtitle = group.title {
                        Text(theme.usesXPChrome ? subtitle : subtitle.uppercased())
                            .font(theme.usesXPChrome
                                  ? FontLoader.xpFont(size: 9, weight: .semibold)
                                  : .system(size: 9, weight: .semibold))
                            .tracking(theme.usesXPChrome ? 0 : 0.6)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }
                    ForEach(group.items) { item in
                        taskRow(item)
                    }
                }
            }
        }
    }

    /// One task row, wired so its note editor can ask the panel for the
    /// keyboard (the panel is non-activating, so a focused field is not
    /// enough on its own).
    private func taskRow(_ item: TodoItem) -> some View {
        // .equatable() lets SwiftUI skip rows whose item is unchanged when the
        // parent rebuilds, so toggling one task does not re-evaluate the rest.
        TaskRowView(item: item, store: store, requestKeyboard: onNeedsKeyboard)
            .equatable()
    }

    private func sectionHeader(
        _ title: String,
        count: Int,
        isPrimary: Bool = false
    ) -> some View {
        let headerStyle = theme.sectionHeaderStyle
        let titleColor: AnyShapeStyle = headerStyle
            ?? (theme.sectionHeaderTinted
                ? AnyShapeStyle(.tint)
                : AnyShapeStyle(isPrimary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
        return HStack(spacing: 7) {
            if isPrimary && !theme.sectionHeaderTinted && headerStyle == nil && !theme.usesXPChrome {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 5, height: 5)
            }
            Text(theme.sectionHeaderUppercased ? title.uppercased() : title)
                .font(theme.sectionHeaderFont)
                .tracking(theme.sectionHeaderUppercased ? 0.8 : 0)
                .foregroundStyle(titleColor)
            Spacer()
            Text("\(count)")
                .font(theme.usesXPChrome
                      ? FontLoader.xpFont(size: 10, weight: .semibold)
                      : .system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var soundControlsTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .move(edge: .trailing).combined(with: .opacity)
    }

    /// Compact sound picker and volume, inline in the header toolbar left of the
    /// speaker button. Fixed slider width keeps the cluster short on narrow panels.
    private var headerSoundControls: some View {
        HStack(spacing: 5) {
            Menu {
                ForEach(FocusSoundPlayer.options, id: \.id) { opt in
                    Button { focusSoundKind = opt.id } label: {
                        Label(opt.label, systemImage: opt.symbol)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: currentSound.symbol)
                        .font(.system(size: 10, weight: .semibold))
                    Text(currentSound.label)
                        .font(theme.uiFont(size: 11, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(theme.tertiaryInk)
                }
                .foregroundStyle(theme.primaryInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background {
                    if theme.usesXPChrome {
                        XPSunkenPanel()
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(floatingControlFill)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: theme.usesXPChrome ? 0 : 8))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Focus sound type")
            .accessibilityValue(currentSound.label)

            Slider(value: $focusSoundVolume, in: 0...1)
                .controlSize(.mini)
                .frame(width: 72)
                .accessibilityLabel("Focus sound volume")
        }
        .padding(.trailing, 4)
    }

    private var currentSound: (id: String, label: String, symbol: String) {
        FocusSoundPlayer.options.first { $0.id == focusSoundKind }
            ?? FocusSoundPlayer.options[1]
    }

    private func statusView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.ellipsis")
            Text(message)
        }
        .font(theme.uiFont(size: 15))
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { floatingPanelBackground() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(hideCompleted && !(store.todayItems.isEmpty && store.carriedItems.isEmpty)
                 ? "All done for today"
                 : "Nothing planned for today")
                .font(theme.uiFont(size: 17, weight: .semibold))
            Text("Add a task or enjoy the clear list.")
                .font(theme.uiFont(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    /// Applies the user's filter/sort prefs. Sort is stable (keeps file order
    /// within each group).
    private func arranged(_ items: [TodoItem]) -> [TodoItem] {
        var out = items
        if hideCompleted {
            out = out.filter { !$0.isDone }
        }
        if uncheckedFirst {
            out = out.enumerated()
                .sorted { a, b in
                    if a.element.isDone != b.element.isDone { return !a.element.isDone }
                    return a.offset < b.offset
                }
                .map(\.element)
        }
        // In-progress tasks always float to the very top of their section, so
        // what you are actively working on stays in view. Stable otherwise.
        // Skip the sort entirely when nothing is in progress, the common case,
        // so a plain list does not pay for a sort on every body evaluation.
        if out.contains(where: \.isInProgress) {
            out = out.enumerated()
                .sorted { a, b in
                    if a.element.isInProgress != b.element.isInProgress {
                        return a.element.isInProgress
                    }
                    return a.offset < b.offset
                }
                .map(\.element)
        }
        return out
    }
}
