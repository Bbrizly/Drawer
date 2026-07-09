import AppKit
import Combine
import DrawerCore
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panelController: PanelController!
    private let paneRouter = PaneRouter()
    private var store: TodoStore!
    private var notesStore: NotesStore!
    private var boardStore: BoardStore!
    private var teleprompter: TeleprompterController!
    private var focusTimer: FocusTimer!
    private var pomodoroTimer: PomodoroTimer!
    private var workClock: WorkClock!
    private var attribution: AttributionController!
    private var planner: PlannerController!
    private var plannerWindow: NSWindow?
    private var historyRecorder: HistoryRecorder!
    private var historyWindow: NSWindow?
    private var historyMenuItem: NSMenuItem?
    private let hotkey = HotkeyManager()
    private let rightCommandTap = RightCommandTapMonitor()
    /// Waits for accessibility to be granted after the user opts in, then
    /// starts the tap monitor without needing a relaunch.
    private var rightCommandTapPoll: Timer?
    private var statusItem: NSStatusItem!
    private var escMonitor: Any?
    private var settingsWindow: NSWindow?
    private var reviewWindow: NSWindow?
    private var attributionRulesWindow: NSWindow?
    private var toggleMenuItem: NSMenuItem?
    private var reviewMenuItem: NSMenuItem?
    private var plannerMenuItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []
    // Whether the feature is permitted in Settings (the permission gate). The
    // watcher itself only runs while Work Mode is on (see `syncAttribution`).
    private var attributionPermitted = false
    // Last activation actually handed to the controller, so unrelated UserDefaults
    // writes and repeat phase notifications don't restart the sampler. Seeded to
    // .endSession so launching with Work Mode already off is a dedup no-op: no
    // sampler ran, so there is no day to summarize. A launch *into* Work Mode
    // still applies normally (.observe/.suspend differ from the seed), and a real
    // running-to-off transition later still summarizes.
    private var lastAttributionActivation: AttributionActivation? = .endSession
    /// Repeats the time's-up chime while the finished timer waits for dismissal.
    private var alarmTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontLoader.registerBundledFonts() // the Pixel theme's typeface
        var defaults: [String: Any] = [
            "drawerFilePath": AppPaths.defaultDrawerFile,
            "panelWidth": 300.0,
            "panelCompactHeight": 440.0,
            "panelSlideDuration": 0.11,
            "defaultMinutesText": "25",
            "completionSound": true,
            "showTomorrow": true,
            "drawerTheme": DrawerTheme.default.rawValue,
            "focusSoundKind": "pink",
            "focusSoundVolume": 0.5,
            "boardBackground": "dark",
            "boardSwipeScale": 300.0,
            "boardZoomStep": 1.25,
            "taskFontSize": 13.0,
            "appFontDesign": "theme",
            "teleprompterSpeed": 45.0,
            "teleprompterFontSize": 34.0,
            "notesPaneHeight": 160.0,
            "exportWorkLogMarkdown": true,
            "rightCommandTapEnabled": false,
        ]
        defaults.merge(PomodoroPreferences.defaults) { current, _ in current }
        UserDefaults.standard.register(defaults: defaults)
        // Each feature's default comes from FeatureFlag.defaultValue (the
        // finicky, watch-heavy ones ship off).
        FeatureFlag.registerDefaults()

        // SMAppService replaces the manually-added login item; register once.
        if !UserDefaults.standard.bool(forKey: "didRegisterLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didRegisterLoginItem")
        }

        let path = AppPaths.drawerFile
        store = TodoStore(fileURL: URL(fileURLWithPath: path))
        notesStore = NotesStore(fileURL: AppPaths.notesFile)
        notesStore.load()
        boardStore = BoardStore(directory: AppPaths.ideasDirectory)
        boardStore.load()
        teleprompter = TeleprompterController(store: notesStore)
        focusTimer = FocusTimer()
        focusTimer.onComplete = { [weak self] title in
            self?.timerFinished(title, notificationTitle: "Focus session done")
        }
        pomodoroTimer = PomodoroTimer()
        pomodoroTimer.onComplete = { [weak self] segment in
            self?.pomodoroFinished(segment)
        }

        workClock = WorkClock(log: WorkSessionLog(fileURL: AppPaths.workLogFile))
        workClock.restore()

        setupAttribution()
        setupPlanner()
        setupHistory()

        var controller: PanelController!
        let rootView = DrawerView(
            store: store,
            timer: focusTimer,
            pomodoroTimer: pomodoroTimer,
            workClock: workClock,
            onToggleSize: { controller?.toggleSize() },
            onNeedsKeyboard: { controller?.makeKeyIfShown() },
            onHide: { controller?.hide() },
            notes: notesStore,
            onToggleTeleprompter: { [weak self] in self?.teleprompter.toggle() },
            ideas: boardStore,
            onBoardCoverage: { controller?.setBoardCoverage($0) },
            router: paneRouter,
            onPaneWidthChange: { controller?.setPaneOpen($0) },
            planner: planner,
            attribution: attribution,
            history: historyRecorder
        )
        controller = PanelController(rootView: rootView)
        panelController = controller
        // Park the 0.5s display tickers whenever the panel is hidden. The
        // panel starts hidden, so park them now too (restore() may have
        // started the work clock ticker already).
        panelController.onVisibilityChange = { [weak self] visible in
            self?.focusTimer.setDisplayActive(visible)
            self?.pomodoroTimer.setDisplayActive(visible)
            self?.workClock.setDisplayActive(visible)
        }
        panelController.onVisibilityChange?(false)
        store.start()

        let binding = HotkeyBinding.saved
        hotkey.register(keyCode: binding.keyCode, modifiers: binding.modifiers) { [weak self] in
            self?.panelController.toggle()
        }

        // Restore the opt-in right-Command tap. Do not prompt on launch; only
        // start if the user already granted access.
        applyRightCommandTap(
            enabled: UserDefaults.standard.bool(forKey: "rightCommandTapEnabled"),
            prompt: false
        )

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Esc belongs to whichever window is key. Only hide the drawer
            // when no other app window (settings, review, planner, history,
            // rules) owns the keyboard.
            if NSApp.keyWindow != nil, !self.panelController.isPanelKey {
                return event
            }
            if event.keyCode == 53, self.panelController.isShown {
                self.panelController.hide()
                return nil
            }
            return event
        }

        setupStatusItem()
        setupEditMenu()
        requestNotificationAuth()
    }

    /// This is a menu-bar app with no menu of its own, so the standard editing
    /// shortcuts (copy, paste, cut, select all) have nothing to bind to and go
    /// dead in the notes pad. A minimal Edit menu wires them back to whatever
    /// text view is first responder.
    private func setupEditMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        notesStore?.saveNow() // flush anything typed in the last moment
        boardStore?.saveNow() // flush the board layout
        workClock?.pause()               // flush an open work segment to the log
        // Always flush the in-progress block into the review queue, don't drop it;
        // only summarize the day when attribution is permitted.
        attribution?.apply(attributionPermitted ? .endSession : .suspend)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The Drawer mark, drawn as a template so it tints for light and dark menu bars.
        if let url = Bundle.module.url(forResource: "menubar-logo", withExtension: "png"),
           let logo = NSImage(contentsOf: url) {
            logo.size = NSSize(width: 18, height: 16)
            logo.isTemplate = true
            statusItem.button?.image = logo
        } else {
            statusItem.button?.image = NSImage(
                systemSymbolName: "sidebar.left", accessibilityDescription: "Drawer"
            )
        }
        statusItem.button?.image?.accessibilityDescription = "Drawer"
        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: "Toggle Drawer (\(HotkeyBinding.saved.label))",
            action: #selector(toggleDrawer), keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let reviewItem = NSMenuItem(
            title: "Review time…", action: #selector(openReview), keyEquivalent: "")
        reviewItem.target = self
        reviewItem.isHidden = !attributionPermitted
        menu.addItem(reviewItem)
        reviewMenuItem = reviewItem
        updateReviewMenu()

        let planItem = NSMenuItem(title: "Plan today…", action: #selector(openPlanner), keyEquivalent: "")
        planItem.target = self
        planItem.isHidden = !plannerVisible
        menu.addItem(planItem)
        plannerMenuItem = planItem

        let historyItem = NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        historyItem.isHidden = !historyEnabled
        menu.addItem(historyItem)
        historyMenuItem = historyItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Drawer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
        menu.delegate = self  // refresh the attribution/planner items each open
        statusItem.menu = menu
        updateStatusDot()
    }

    @objc private func toggleDrawer() {
        panelController.toggle()
    }

    /// Keep the attribution/planner menu items in sync with their feature flags
    /// and Foundation Models availability, which can both change after launch.
    func menuWillOpen(_ menu: NSMenu) {
        reviewMenuItem?.isHidden = !attributionPermitted
        plannerMenuItem?.isHidden = !plannerVisible
        historyMenuItem?.isHidden = !historyEnabled
    }

    // MARK: - History scrubber (spec 04)

    private func setupHistory() {
        historyRecorder = HistoryRecorder(
            store: SnapshotStore(directory: AppPaths.historyDirectory),
            fileURL: URL(fileURLWithPath: AppPaths.drawerFile))
        if historyEnabled { historyRecorder.start() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncHistory),
            name: UserDefaults.didChangeNotification, object: nil)
    }

    private var historyEnabled: Bool {
        UserDefaults.standard.object(forKey: FeatureFlag.history.key) as? Bool ?? FeatureFlag.history.defaultValue
    }

    @objc private func syncHistory() {
        if historyEnabled {
            historyRecorder.start()
        } else {
            historyRecorder.stop()
            historyWindow?.close()  // don't leave a live timeline open when gated off
        }
    }

    @objc private func openHistory() {
        guard historyEnabled else { return }
        if historyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "History"
            window.isReleasedWhenClosed = false
            window.center()
            historyWindow = window
        }
        // Rebuild the root on every open: `today` is captured by value, so a
        // cached view would classify Today/Carried against a stale day.
        historyWindow?.contentView = NSHostingView(
            rootView: HistoryScrubberView(recorder: historyRecorder, today: TodoStore.localToday()))
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Planner (spec 03)

    private func setupPlanner() {
        planner = PlannerController(
            store: store,
            workLog: WorkSessionLog(fileURL: AppPaths.workLogFile),
            scheduleStore: DayScheduleStore(fileURL: AppPaths.daySchedulesFile),
            todayProvider: { TodoStore.localToday() },
            prioritiesProvider: {
                guard let path = AppPaths.plannerPrioritiesFile else { return (nil, false) }
                if let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) {
                    return (text, false)
                }
                return (nil, true)  // configured but missing/unreadable
            })
        planner.$state
            .sink { [weak self] state in
                if case .idle = state { self?.plannerWindow?.close() }
            }
            .store(in: &cancellables)
    }

    /// The planner button is visible only with the flag on AND Foundation Models
    /// available right now (read fresh, never cached).
    private var plannerVisible: Bool {
        let flagOn = UserDefaults.standard.object(forKey: FeatureFlag.planner.key) as? Bool ?? FeatureFlag.planner.defaultValue
        return flagOn && planner?.available == true
    }

    @objc private func openPlanner() {
        guard plannerVisible else { return }  // flag AND Foundation Models
        let today = TodoStore.localToday()
        if plannerWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 460),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Plan Today"
            window.isReleasedWhenClosed = false
            window.center()
            plannerWindow = window
        }
        // Rebuild the root on every open: PlannerPanel captures `date` by
        // value, so a cached view would accept tomorrow's plan under
        // yesterday's key after midnight.
        plannerWindow?.contentView = NSHostingView(
            rootView: PlannerPanel(controller: planner, date: today))
        planner.plan(date: today)
        NSApp.activate(ignoringOtherApps: true)
        plannerWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Attribution (spec 02)

    private func setupAttribution() {
        let workLog = WorkSessionLog(fileURL: AppPaths.workLogFile)
        attribution = AttributionController(
            raw: RawActivityStore(fileURL: AppPaths.rawActivityFile),
            service: AttributionService(
                queue: AttributionQueueStore(fileURL: AppPaths.attributionQueueFile), log: workLog),
            workLog: workLog,
            daySummaries: DaySummaryStore(fileURL: AppPaths.daySummariesFile),
            rulesURL: AppPaths.attributionRulesFile,
            candidatesProvider: { [weak self] in self?.attributionCandidates() ?? [] },
            manualSpansProvider: { [weak self] range in self?.manualSpans(overlapping: range, log: workLog) ?? [] },
            todayProvider: { TodoStore.localToday() })

        attribution.$isObserving
            .sink { [weak self] _ in self?.updateStatusDot() }.store(in: &cancellables)
        attribution.$pendingCount
            .sink { [weak self] _ in self?.updateReviewMenu() }.store(in: &cancellables)

        syncAttribution()
        observeWorkPhase()
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncAttribution),
            name: UserDefaults.didChangeNotification, object: nil)
    }

    /// Attribution rides Work Mode, so re-sync every time the work phase changes
    /// (briefcase on/off, a task starting or stopping). `withObservationTracking`
    /// fires once, so re-arm it each time. The change lands via a hop so the sync
    /// reads the new phase, not the old one.
    private func observeWorkPhase() {
        withObservationTracking { _ = workClock.phase } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncAttribution()
                self?.observeWorkPhase()
            }
        }
    }

    /// Candidate tasks for matching: today, carried, upcoming, backlog;
    /// in-progress and carried are weighted first.
    private func attributionCandidates() -> [TaskCandidate] {
        var out: [TaskCandidate] = []
        for item in store.todayItems where !item.isDone {
            out.append(TaskCandidate(id: item.id, title: item.title, priority: item.isInProgress))
        }
        for item in store.carriedItems where !item.isDone {
            out.append(TaskCandidate(id: item.id, title: item.title, priority: true))
        }
        for item in store.upcomingItems + store.backlogItems where !item.isDone {
            out.append(TaskCandidate(id: item.id, title: item.title, priority: false))
        }
        return out
    }

    /// Manual stopwatch spans overlapping a block, subtracted so attribution
    /// never queues a competing match for time already tracked by hand. Filtered
    /// by overlap (not by day) so a cross-midnight manual span still counts.
    private func manualSpans(overlapping range: TimeRange, log: WorkSessionLog) -> [TimeRange] {
        log.all()
            .filter { $0.source == nil }
            .map { TimeRange(start: $0.start, end: $0.end) }
            .filter { $0.overlaps(range) }
    }

    /// Map the current (permission, work phase) to an attribution activation and
    /// apply it. Settings grants permission; the briefcase is the on-switch. Fired
    /// from both the defaults observer (permission flips) and the work-phase
    /// observer, deduped so noise doesn't churn the sampler.
    @objc private func syncAttribution() {
        let wasPermitted = attributionPermitted
        attributionPermitted =
            UserDefaults.standard.object(forKey: FeatureFlag.attribution.key) as? Bool ?? false
        // Opting out deletes the raw window-title trail right away; the 7-day
        // retention is a ceiling, not a license to keep titles after opt-out.
        if wasPermitted, !attributionPermitted { attribution.eraseRawTrail() }
        reviewMenuItem?.isHidden = !attributionPermitted
        let activation = attributionActivation(
            workPhase: workClock.phase, permitted: attributionPermitted)
        guard activation != lastAttributionActivation else { return }
        lastAttributionActivation = activation
        attribution.apply(activation)
        updateStatusDot()
    }

    @objc private func openReview() {
        if reviewWindow == nil {
            let view = ReviewCardView(
                controller: attribution,
                candidates: { [weak self] in self?.attributionCandidates() ?? [] },
                onEditRules: { [weak self] in self?.openAttributionRules() })
            let window = NSWindow(
                contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Review Time"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            reviewWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        reviewWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAttributionRules() {
        if attributionRulesWindow == nil {
            let window = NSWindow(
                contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Attribution Rules"
            window.contentView = NSHostingView(rootView: AttributionSettingsView(controller: attribution))
            window.isReleasedWhenClosed = false
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            attributionRulesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        attributionRulesWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateReviewMenu() {
        let count = attribution?.pendingCount ?? 0
        reviewMenuItem?.title = count > 0 ? "Review time (\(count))…" : "Review time…"
    }

    /// The observing dot: a small green mark on the menu-bar icon while
    /// attribution is sampling. This is the honesty signal and is not optional.
    private func updateStatusDot() {
        guard let button = statusItem?.button, let base = baseStatusImage() else { return }
        guard attribution?.isObserving == true else {
            button.image = base
            return
        }
        let size = base.size
        let rect = NSRect(origin: .zero, size: size)
        let composite = NSImage(size: size)
        composite.lockFocus()
        // A non-template composite is required to keep the dot green, but that
        // makes the template logo draw as its raw (light) pixels. Tint the
        // silhouette to the menu-bar color so the icon looks unchanged.
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            base.draw(in: rect)
            NSColor.controlTextColor.set()
            rect.fill(using: .sourceAtop)
        }
        NSColor.systemGreen.setFill()
        let dot = NSRect(x: size.width - 5, y: size.height - 5, width: 5, height: 5)
        NSBezierPath(ovalIn: dot).fill()
        composite.unlockFocus()
        composite.isTemplate = false  // keep the dot green, not tinted
        button.image = composite
    }

    private func baseStatusImage() -> NSImage? {
        if let url = Bundle.module.url(forResource: "menubar-logo", withExtension: "png"),
           let logo = NSImage(contentsOf: url) {
            logo.size = NSSize(width: 18, height: 16)
            logo.isTemplate = true
            return logo
        }
        return NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Drawer")
    }

    // MARK: - Right Command tap

    /// Turns the right-Command tap trigger on or off. When turning on without
    /// accessibility yet, prompts once (if asked) and waits for the grant.
    func applyRightCommandTap(enabled: Bool, prompt: Bool) {
        rightCommandTapPoll?.invalidate()
        rightCommandTapPoll = nil

        rightCommandLog.notice(
            "apply tap enabled=\(enabled) prompt=\(prompt) trusted=\(AccessibilityPermission.isTrusted)"
        )
        guard enabled else {
            rightCommandTap.stop()
            return
        }
        if AccessibilityPermission.isTrusted {
            startRightCommandTap()
            return
        }
        if prompt { AccessibilityPermission.prompt() }
        pollForRightCommandTapPermission()
    }

    private func startRightCommandTap() {
        rightCommandTap.start { [weak self] in
            self?.panelController.toggle()
        }
    }

    /// Global key monitors only deliver once the process is trusted, and an
    /// already-installed monitor may miss a late grant, so restart it the
    /// moment access appears.
    private func pollForRightCommandTapPermission() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                guard UserDefaults.standard.bool(forKey: "rightCommandTapEnabled") else {
                    timer.invalidate()
                    self.rightCommandTapPoll = nil
                    return
                }
                if AccessibilityPermission.isTrusted {
                    rightCommandLog.notice("accessibility granted, starting tap monitor")
                    self.rightCommandTap.stop()
                    self.startRightCommandTap()
                    timer.invalidate()
                    self.rightCommandTapPoll = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rightCommandTapPoll = timer
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                onChooseFile: { [weak self] url in
                    self?.store.updateFileURL(url)
                    self?.historyRecorder.repoint(to: url)  // follow the new drawer file
                },
                onHotkeyChange: { [weak self] binding in
                    guard let self else { return false }
                    let updated = self.hotkey.update(
                        keyCode: binding.keyCode,
                        modifiers: binding.modifiers
                    )
                    if updated {
                        self.toggleMenuItem?.title = "Toggle Drawer (\(binding.label))"
                    }
                    return updated
                },
                onLayoutChange: { [weak self] in
                    self?.panelController.refreshFrame()
                },
                onRightCommandTapChange: { [weak self] enabled in
                    self?.applyRightCommandTap(enabled: enabled, prompt: true)
                }
            )
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Drawer Settings"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Notifications

    private func requestNotificationAuth() {
        // UNUserNotificationCenter crashes outside a real bundle (swift run).
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// The timer hit zero. Surface the drawer so the Time's Up card is seen,
    /// ring until it is dismissed, and post a banner for other Spaces.
    private func timerFinished(_ title: String, notificationTitle: String) {
        if !panelController.isShown { panelController.show() }
        startAlarm()
        notifyComplete(title, notificationTitle: notificationTitle)
    }

    private func pomodoroFinished(_ segment: PomodoroTimer.Segment) {
        switch segment {
        case .focus:
            timerFinished("Start a break when you are ready.", notificationTitle: "Pomodoro focus done")
        case .shortBreak:
            timerFinished("Short break complete.", notificationTitle: "Pomodoro break done")
        case .longBreak:
            timerFinished("Long break complete.", notificationTitle: "Pomodoro cycle done")
        }
    }

    /// Repeats a chime every few seconds while the timer sits in `finished`.
    /// Stops itself the moment the card is dismissed (or a new timer starts).
    private func startAlarm() {
        guard UserDefaults.standard.bool(forKey: "completionSound") else { return }
        alarmTimer?.invalidate()
        NSSound(named: "Glass")?.play()
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.focusTimer.phase == .finished || self.pomodoroTimer.phase == .finished {
                    NSSound(named: "Glass")?.play()
                } else {
                    self.alarmTimer?.invalidate()
                    self.alarmTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        alarmTimer = timer
    }

    private func notifyComplete(_ body: String, notificationTitle: String) {
        // Banner rides the same "Sound when timer ends" flag; the in-drawer
        // alarm card shows regardless.
        guard UserDefaults.standard.bool(forKey: "completionSound") else { return }
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = notificationTitle
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
