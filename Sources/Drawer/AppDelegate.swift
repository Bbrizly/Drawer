import AppKit
import DrawerCore
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController!
    private var store: TodoStore!
    private var notesStore: NotesStore!
    private var boardStore: BoardStore!
    private var teleprompter: TeleprompterController!
    private var focusTimer: FocusTimer!
    private var pomodoroTimer: PomodoroTimer!
    private var workClock: WorkClock!
    private let hotkey = HotkeyManager()
    private var statusItem: NSStatusItem!
    private var escMonitor: Any?
    private var settingsWindow: NSWindow?
    private var toggleMenuItem: NSMenuItem?
    /// Repeats the time's-up chime while the finished timer waits for dismissal.
    private var alarmTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontLoader.registerBundledFonts() // the Pixel theme's typeface
        var defaults: [String: Any] = [
            "drawerFilePath": AppPaths.defaultDrawerFile,
            "panelWidth": 300.0,
            "panelCompactHeight": 440.0,
            "defaultMinutesText": "25",
            "completionSound": true,
            "showTomorrow": true,
            "drawerTheme": DrawerTheme.default.rawValue,
            "focusSoundKind": "pink",
            "focusSoundVolume": 0.5,
            "boardBackground": "dark",
            "boardDefaultColor": "yellow",
            "boardSwipeScale": 300.0,
            "boardZoomStep": 1.25,
            "taskFontSize": 13.0,
            "appFontDesign": "theme",
            "teleprompterSpeed": 45.0,
            "teleprompterFontSize": 34.0,
            "notesPaneHeight": 160.0,
            "exportWorkLogMarkdown": true,
        ]
        defaults.merge(PomodoroPreferences.defaults) { current, _ in current }
        UserDefaults.standard.register(defaults: defaults)
        // Every feature defaults to on.
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
            onBoardCoverage: { controller?.setBoardCoverage($0) }
        )
        controller = PanelController(rootView: rootView)
        panelController = controller
        store.start()

        let binding = HotkeyBinding.saved
        hotkey.register(keyCode: binding.keyCode, modifiers: binding.modifiers) { [weak self] in
            self?.panelController.toggle()
        }

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Esc belongs to whichever window is key; only the drawer's.
            if self.settingsWindow?.isKeyWindow == true { return event }
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
        workClock?.pause()    // flush an open work segment to the log
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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Drawer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    @objc private func toggleDrawer() {
        panelController.toggle()
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                onChooseFile: { [weak self] url in
                    self?.store.updateFileURL(url)
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
