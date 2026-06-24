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
    private var teleprompter: TeleprompterController!
    private var focusTimer: FocusTimer!
    private var workClock: WorkClock!
    private let hotkey = HotkeyManager()
    private var statusItem: NSStatusItem!
    private var escMonitor: Any?
    private var settingsWindow: NSWindow?
    private var toggleMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontLoader.registerBundledFonts() // the Pixel theme's typeface
        UserDefaults.standard.register(defaults: [
            "drawerFilePath": AppPaths.defaultDrawerFile,
            "panelWidth": 300.0,
            "panelCompactHeight": 440.0,
            "defaultMinutesText": "25",
            "completionSound": true,
            "showTomorrow": true,
            "drawerTheme": DrawerTheme.default.rawValue,
            "focusSoundKind": "pink",
            "focusSoundVolume": 0.5,
        ])
        // Every feature defaults to on.
        FeatureFlag.registerDefaults()

        // SMAppService replaces the manually-added login item; register once.
        if !UserDefaults.standard.bool(forKey: "didRegisterLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didRegisterLoginItem")
        }

        let path = UserDefaults.standard.string(forKey: "drawerFilePath")
            ?? AppPaths.defaultDrawerFile
        store = TodoStore(fileURL: URL(fileURLWithPath: path))
        notesStore = NotesStore(fileURL: AppPaths.notesFile)
        notesStore.load()
        teleprompter = TeleprompterController(store: notesStore)
        focusTimer = FocusTimer()
        focusTimer.onComplete = { [weak self] title in
            self?.notifyComplete(title)
        }

        workClock = WorkClock(log: WorkSessionLog(fileURL: AppPaths.workLogFile))
        workClock.restore()

        var controller: PanelController!
        let rootView = DrawerView(
            store: store,
            timer: focusTimer,
            workClock: workClock,
            onToggleSize: { controller?.toggleSize() },
            onNeedsKeyboard: { controller?.makeKeyIfShown() },
            notes: notesStore,
            onToggleTeleprompter: { [weak self] in self?.teleprompter.toggle() }
        )
        controller = PanelController(rootView: rootView)
        panelController = controller
        store.start()

        let preset = HotkeyPreset.saved
        hotkey.register(keyCode: preset.keyCode, modifiers: preset.modifiers) { [weak self] in
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
        workClock?.pause()    // flush an open work segment to the log
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "sidebar.left", accessibilityDescription: "Drawer"
        )
        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: "Toggle Drawer (\(HotkeyPreset.saved.label))",
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
                onHotkeyChange: { [weak self] preset in
                    guard let self else { return false }
                    let updated = self.hotkey.update(
                        keyCode: preset.keyCode,
                        modifiers: preset.modifiers
                    )
                    if updated {
                        self.toggleMenuItem?.title = "Toggle Drawer (\(preset.label))"
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

    private func notifyComplete(_ title: String) {
        // "Sound when timer ends" feature: off means no chime and no banner.
        guard UserDefaults.standard.bool(forKey: "completionSound") else { return }
        NSSound(named: "Glass")?.play()
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Focus session done"
        content.body = title
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
