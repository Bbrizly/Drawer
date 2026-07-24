import AppKit
import DrawerCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
#if canImport(DrawerBureau)
import DrawerBureau
#endif

struct SettingsView: View {
    var onChooseFile: (URL) -> Void
    var onHotkeyChange: (HotkeyBinding) -> Bool
    var onLayoutChange: () -> Void
    /// The drawer's open state right now, read once when the shortcut mark
    /// appears so it starts matching the real panel instead of guessing shut.
    var isDrawerOpen: () -> Bool = { false }
    #if canImport(DrawerBureau)
    /// The Bureau tuning object, passed in when the feature is wired so the
    /// Settings window can embed its slider controls. Nil leaves the tab out.
    var bureauTuning: BureauTuning? = nil
    #endif

    private enum Tab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case timers = "Timers"
        case features = "Features"
        case board = "Board"
        case bureau = "Bureau"
        case advanced = "Advanced"
        case help = "Help"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            case .timers: return "timer"
            case .features: return "switch.2"
            case .board: return "square.grid.2x2"
            case .bureau: return "tray.full"
            case .advanced: return "slider.horizontal.3"
            case .help: return "questionmark.circle"
            }
        }
    }

    @State private var tab: Tab = .general
    @AppStorage("feature.bureau") private var bureauEnabled = false
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue

    private var accent: Color { (DrawerTheme(rawValue: themeRaw) ?? .default).accent }

    /// The Bureau tab only shows when the feature is on and its tuning is wired.
    private var bureauShowsTuning: Bool {
        #if canImport(DrawerBureau)
        return bureauEnabled && bureauTuning != nil
        #else
        return false
        #endif
    }

    private var visibleTabs: [Tab] {
        Tab.allCases.filter { $0 != .bureau || bureauShowsTuning }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(visibleTabs, id: \.self) { item in
                    Button {
                        tab = item
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.icon).font(.system(size: 16))
                            Text(item.rawValue)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(tab == item ? accent.opacity(0.18) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(tab == item ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == item ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(8)
            Divider()

            switch tab {
            case .general:
                GeneralSettingsView(
                    onChooseFile: onChooseFile,
                    onHotkeyChange: onHotkeyChange,
                    onLayoutChange: onLayoutChange,
                    isDrawerOpen: isDrawerOpen
                )
            case .appearance:
                AppearanceSettingsView()
            case .timers:
                TimersSettingsView()
            case .features:
                FeatureSettingsView()
            case .board:
                BoardSettingsView()
            case .bureau:
                bureauTab
            case .advanced:
                AdvancedSettingsView()
            case .help:
                HelpView()
            }
        }
        .frame(width: 540, height: 580)
        .chromeThemed()
        .onChange(of: bureauShowsTuning) { _, shows in
            // If the Bureau tab was open and the feature is turned off, fall
            // back to General so the content does not sit on a hidden tab.
            if !shows, tab == .bureau { tab = .general }
        }
    }

    @ViewBuilder
    private var bureauTab: some View {
        #if canImport(DrawerBureau)
        if let bureauTuning {
            BureauSettingsView(tuning: bureauTuning)
        }
        #else
        EmptyView()
        #endif
    }
}

#if canImport(DrawerBureau)
/// The Bureau tab: the same slider controls the long-press panel shows, so the
/// tuning is findable without the hidden gesture. A caption points at the
/// long-press too.
private struct BureauSettingsView: View {
    @ObservedObject var tuning: BureauTuning

    var body: some View {
        VStack(spacing: 0) {
            BureauTuningControls(tuning: tuning)
            Divider()
            SettingsCaption(
                "Bureau feel and layout. Long press the tray button in the drawer "
                + "header to open this as a window."
            )
            .padding(10)
        }
    }
}
#endif

private struct BoardSettingsView: View {
    @AppStorage("boardBackground") private var boardBackground = "dark"
    @AppStorage("boardSwipeScale") private var swipeScale = 300.0
    @AppStorage("boardZoomStep") private var zoomStep = 1.25

    var body: some View {
        Form {
            Section("Background") {
                Picker("Style", selection: $boardBackground) {
                    Text("Dark").tag("dark")
                    Text("Transparent").tag("transparent")
                    Text("Paper").tag("paper")
                }
                .pickerStyle(.segmented)
                SettingsCaption(
                    "Dark is solid. Transparent shows your desktop. Paper adds ruled "
                    + "lines. Notebook always uses paper."
                )
            }
            Section("Gestures") {
                HStack {
                    Text("Swipe to open")
                    Slider(value: $swipeScale, in: 150...600, step: 25)
                    Text("\(Int(swipeScale))")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                }
                SettingsCaption(
                    "How far to swipe the task list to reach the board. "
                    + "Lower means a shorter swipe."
                )
                HStack {
                    Text("Zoom step")
                    Slider(value: $zoomStep, in: 1.05...1.6, step: 0.05)
                    Text(String(format: "%.2f", zoomStep))
                        .font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                }
                SettingsCaption("How much each + or − press zooms the canvas.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
    @AppStorage("appFontDesign") private var appFontDesign = "theme"
    @AppStorage("taskFontSize") private var taskFontSize = 13.0

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 108), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(DrawerTheme.allCases) { theme in
                        ThemeSwatch(theme: theme, selected: themeRaw == theme.id)
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.2)) {
                                    themeRaw = theme.id
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
                SettingsCaption(
                    "Each theme changes the surface, type, and accent. "
                    + "Some also reshape the chrome."
                )
            }
            Section("Text") {
                Picker("Font", selection: $appFontDesign) {
                    Text("Theme default").tag("theme")
                    Text("System").tag("system")
                    Text("Rounded").tag("rounded")
                    Text("Serif").tag("serif")
                    Text("Monospaced").tag("mono")
                }
                HStack {
                    Text("Task text size")
                    Slider(value: $taskFontSize, in: 11...17, step: 0.5)
                    Text(String(format: "%.1f pt", taskFontSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                Button("Reset to defaults") {
                    appFontDesign = "theme"
                    taskFontSize = 13.0
                }
                .disabled(appFontDesign == "theme" && taskFontSize == 13.0)
                SettingsCaption(
                    "Font restyles the whole drawer. Theme default keeps each theme's own face. "
                    + "Size sets task titles. Notes sit two points smaller."
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct TimersSettingsView: View {
    @AppStorage("defaultMinutesText") private var defaultMinutes = "25"
    @AppStorage("feature.focusTimer") private var focusTimerEnabled = true
    @AppStorage("feature.pomodoro") private var pomodoroEnabled = true
    @AppStorage("feature.workMode") private var stopwatchEnabled = FeatureFlag.workMode.defaultValue
    @AppStorage("feature.focusSound") private var focusSoundEnabled = true
    @AppStorage("completionSound") private var timerEndSoundEnabled = true
    @AppStorage(PomodoroPreferences.focusMinutesKey) private var pomodoroFocusMinutes =
        PomodoroTimer.Settings.standard.focusMinutes
    @AppStorage(PomodoroPreferences.shortBreakMinutesKey) private var pomodoroShortBreakMinutes =
        PomodoroTimer.Settings.standard.shortBreakMinutes
    @AppStorage(PomodoroPreferences.longBreakMinutesKey) private var pomodoroLongBreakMinutes =
        PomodoroTimer.Settings.standard.longBreakMinutes
    @AppStorage(PomodoroPreferences.sessionsUntilLongBreakKey)
    private var pomodoroSessionsUntilLongBreak =
        PomodoroTimer.Settings.standard.sessionsUntilLongBreak
    @AppStorage("focusSoundKind") private var focusSoundKind = "pink"
    @AppStorage("focusSoundVolume") private var focusSoundVolume = 0.5
    @Environment(\.drawerTheme) private var theme

    private var palette: SettingsPalette { .forTheme(theme) }

    private var pomodoroSettings: PomodoroTimer.Settings {
        PomodoroPreferences.settings(
            focusMinutes: pomodoroFocusMinutes,
            shortBreakMinutes: pomodoroShortBreakMinutes,
            longBreakMinutes: pomodoroLongBreakMinutes,
            sessionsUntilLongBreak: pomodoroSessionsUntilLongBreak
        )
    }

    var body: some View {
        Form {
            Section("Timer pills") {
                TimerFeatureToggleGrid(
                    focusTimerEnabled: $focusTimerEnabled,
                    pomodoroEnabled: $pomodoroEnabled,
                    stopwatchEnabled: $stopwatchEnabled,
                    palette: palette
                )
                SettingsCaption(
                    "Pick which timer pills show at the top. Stopwatch tracks time per task."
                )
                Divider()
                HStack {
                    Text("Focus timer default")
                    Spacer()
                    TextField("", text: $defaultMinutes)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .accessibilityLabel("Focus timer default minutes")
                        .onChange(of: defaultMinutes) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(3))
                            if digits != newValue { defaultMinutes = digits }
                        }
                }
                SettingsCaption(
                    "Fills the focus timer when you tap play. A task can set its own "
                    + "time with (15m) in the file."
                )
            }
            Section("Pomodoro") {
                PomodoroCadenceSettings(
                    focusMinutes: $pomodoroFocusMinutes,
                    shortBreakMinutes: $pomodoroShortBreakMinutes,
                    longBreakMinutes: $pomodoroLongBreakMinutes,
                    sessionsUntilLongBreak: $pomodoroSessionsUntilLongBreak,
                    palette: palette,
                    applyPreset: applyPomodoroPreset
                )
                SettingsCaption(
                    "Default is 25 minutes on, 5 off, and a 15 minute break after four rounds."
                )
            }
            Section("Sounds") {
                Toggle("Focus sound", isOn: $focusSoundEnabled)
                Picker("Sound", selection: $focusSoundKind) {
                    ForEach(FocusSoundPlayer.options, id: \.id) { opt in
                        Text(opt.label).tag(opt.id)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!focusSoundEnabled)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $focusSoundVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .disabled(!focusSoundEnabled)
                SettingsCaption(
                    "The speaker button in the header plays this. Pink masks chatter, "
                    + "brown is deeper, ocean sounds like surf."
                )
                Divider()
                Toggle("Sound when timer ends", isOn: $timerEndSoundEnabled)
                SettingsCaption("A chime and notice when a session ends.")
            }
        }
        .formStyle(.grouped)
        .onAppear { sanitizePomodoroSettings() }
        .onChange(of: pomodoroFocusMinutes) { _, _ in sanitizePomodoroSettings() }
        .onChange(of: pomodoroShortBreakMinutes) { _, _ in sanitizePomodoroSettings() }
        .onChange(of: pomodoroLongBreakMinutes) { _, _ in sanitizePomodoroSettings() }
        .onChange(of: pomodoroSessionsUntilLongBreak) { _, _ in sanitizePomodoroSettings() }
    }

    private func sanitizePomodoroSettings() {
        let clean = pomodoroSettings
        if pomodoroFocusMinutes != clean.focusMinutes {
            pomodoroFocusMinutes = clean.focusMinutes
        }
        if pomodoroShortBreakMinutes != clean.shortBreakMinutes {
            pomodoroShortBreakMinutes = clean.shortBreakMinutes
        }
        if pomodoroLongBreakMinutes != clean.longBreakMinutes {
            pomodoroLongBreakMinutes = clean.longBreakMinutes
        }
        if pomodoroSessionsUntilLongBreak != clean.sessionsUntilLongBreak {
            pomodoroSessionsUntilLongBreak = clean.sessionsUntilLongBreak
        }
    }

    private func applyPomodoroPreset(_ preset: PomodoroPreferences.Preset) {
        let settings = preset.settings
        withAnimation(.snappy(duration: 0.22)) {
            pomodoroFocusMinutes = settings.focusMinutes
            pomodoroShortBreakMinutes = settings.shortBreakMinutes
            pomodoroLongBreakMinutes = settings.longBreakMinutes
            pomodoroSessionsUntilLongBreak = settings.sessionsUntilLongBreak
        }
    }
}

private struct GeneralSettingsView: View {
    var onChooseFile: (URL) -> Void
    var onHotkeyChange: (HotkeyBinding) -> Bool
    var onLayoutChange: () -> Void
    var isDrawerOpen: () -> Bool = { false }

    /// The little mark under the Shortcut headline, mirroring the real drawer.
    /// Seeded from `isDrawerOpen()` on appear so pressing the shortcut with the
    /// drawer already open swaps it shut, never the wrong way round.
    @State private var markOpen = false
    /// Bumped on every open or close so the mark knocks the way it does in the
    /// walkthrough.
    @State private var markKnocks = 0

    @AppStorage("drawerFilePath") private var filePath = AppPaths.defaultDrawerFile
    @State private var hotkey = HotkeyBinding.saved
    @AppStorage("panelWidth") private var panelWidth = 520.0
    @AppStorage("panelCompactHeight") private var panelHeight = 440.0
    @AppStorage("panelSlideDuration") private var panelSlideDuration = 0.11
    @AppStorage("startExpanded") private var startExpanded = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showHotkeyError = false
    @AppStorage("typeOnOpen") private var typeOnOpen = false
    @State private var axTrusted = AccessibilityPermission.isTrusted

    var body: some View {
        Form {
            Section("Tasks file") {
                HStack(alignment: .firstTextBaseline) {
                    Text(filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(2)
                    Spacer()
                    Button("Open") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
                    }
                    Button("Choose…") { chooseFile() }
                }
                SettingsCaption(
                    "A markdown file with dated ## headings and checkboxes. "
                    + "Drawer reads it live, so edits in Obsidian or iCloud show up here. "
                    + "See Help for the format."
                )
            }
            Section("Shortcut") {
                DrawerMark(open: markOpen, shakes: markKnocks)
                    .scaleEffect(0.66)
                    .frame(height: 128)
                    .frame(maxWidth: .infinity)
                    .onAppear { markOpen = isDrawerOpen() }
                    .onReceive(NotificationCenter.default.publisher(for: .drawerDidOpen)) { _ in
                        markOpen = true
                        markKnocks += 1
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .drawerDidClose)) { _ in
                        markOpen = false
                        markKnocks += 1
                    }
                HotkeyRecorderField(
                    binding: $hotkey,
                    trusted: axTrusted,
                    onCommit: { pick($0) }
                )
                .frame(maxWidth: .infinity)
                if hotkey.isTypingKey {
                    SettingsCaption("That key types text. F13 to F19 are safer, or remap Caps Lock to F13.")
                        .foregroundStyle(.orange)
                }
                if hotkey.needsAccessibility, !axTrusted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Waiting for Accessibility access.")
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") { AccessibilityPermission.openSettings() }
                            .controlSize(.small)
                    }
                    SettingsCaption(
                        "A one modifier shortcut needs Accessibility to work outside Drawer. "
                        + "Turn Drawer on in Privacy & Security, then Accessibility. Already listed "
                        + "but off, or stale after an update? Remove it with the minus button and add it again."
                    )
                    .foregroundStyle(.orange)
                }
                SettingsCaption(
                    "Shows or hides the drawer from anywhere. Record any combination, or tap "
                    + "one modifier alone. A plain key works best on F13 to F19."
                )
                HStack(spacing: 6) {
                    ForEach(HotkeyBinding.singleKeyPresets) { binding in
                        presetButton(binding, label: binding.label)
                    }
                }
                // Tapped modifiers ride Accessibility, which the sandbox denies.
                if !appStoreBuild {
                    HStack(spacing: 6) {
                        ForEach(HotkeyBinding.tapPresets) { binding in
                            presetButton(binding, label: "Tap \(binding.label)")
                        }
                    }
                }
                DisclosureGroup("Shortcuts with modifiers") {
                    // Its own binding, not $hotkey: sharing that state made a
                    // preset button apply twice, once for the tap and once for
                    // the picker noticing the same change.
                    Picker("Preset", selection: Binding(
                        get: { hotkey },
                        set: { pick(_: $0) }
                    )) {
                        ForEach(HotkeyBinding.modifierPresets) { binding in
                            Text(binding.label).tag(binding)
                        }
                    }
                    .labelsHidden()
                }
                Divider()
                Toggle("Start typing a new task on open", isOn: $typeOnOpen)
                SettingsCaption("Opening the drawer starts a new task, ready to type.")
            }
            Section("Panel") {
                HStack {
                    Text("Width")
                    Slider(value: $panelWidth, in: 260...820, step: 10)
                    Text("\(Int(panelWidth))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                HStack {
                    Text("Height")
                    Slider(value: $panelHeight, in: 320...700, step: 20)
                    Text("\(Int(panelHeight))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                SettingsCaption(
                    "Compact is the default size. The header arrows, and the toggle below, "
                    + "grow it to full height."
                )
                HStack {
                    Text("Slide speed")
                    Slider(value: $panelSlideDuration, in: 0...0.25, step: 0.01)
                    Text(panelSlideDuration == 0 ? "off" : "\(Int(panelSlideDuration * 1000))ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                SettingsCaption(
                    "How long the drawer takes to slide. Lower is snappier. 0 is instant."
                )
                Divider()
                Toggle("Open at full height", isOn: $startExpanded)
                SettingsCaption("Open the drawer at full height instead of compact.")
            }
            Section {
                Button("Redo onboarding") { Onboarding.run() }
                SettingsCaption("Walks the setup again: shortcut, files, features.")
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                SettingsCaption("Starts Drawer quietly in the menu bar when you sign in.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hotkey = HotkeyBinding.saved
            launchAtLogin = SMAppService.mainApp.status == .enabled
            axTrusted = AccessibilityPermission.isTrusted
        }
        .task {
            // Keep the status fresh so it flips right after the user grants
            // access. The App Store build shows no accessibility UI; skip.
            guard !appStoreBuild else { return }
            while !Task.isCancelled {
                axTrusted = AccessibilityPermission.isTrusted
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        // The walkthrough writes the shortcut straight to defaults, so follow
        // it instead of showing whatever was saved when this tab opened.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let live = HotkeyBinding.saved
            if live != hotkey { hotkey = live }
        }
        .onChange(of: panelWidth) { _, _ in onLayoutChange() }
        .onChange(of: panelHeight) { _, _ in onLayoutChange() }
        .alert("Shortcut unavailable", isPresented: $showHotkeyError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That shortcut could not be set. The old one still works.")
        }
    }

    private func presetButton(_ binding: HotkeyBinding, label: String) -> some View {
        Button(label) { pick(binding) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    /// One way in for every control that sets the shortcut.
    private func pick(_ binding: HotkeyBinding) {
        guard binding != hotkey else { return }
        let previous = hotkey
        hotkey = binding
        applyHotkey(binding, revertingTo: previous)
    }

    private func applyHotkey(_ binding: HotkeyBinding, revertingTo previous: HotkeyBinding) {
        // A tapped modifier is a fine shortcut that simply cannot run yet.
        // Save it, ask for the permission, and let the app pick it up on the
        // grant rather than rejecting the choice.
        if binding.needsAccessibility, !AccessibilityPermission.isTrusted {
            binding.save()
            AccessibilityPermission.prompt()
            AccessibilityPermission.openSettings()
            return
        }
        guard onHotkeyChange(binding) else {
            hotkey = previous
            showHotkeyError = true
            return
        }
        binding.save()
    }

    private func chooseFile() {
        guard let path = SettingsPickers.run(.markdownFile, startingAt: filePath) else { return }
        SandboxBookmarks.save(
            url: URL(fileURLWithPath: path), forSetting: AppPaths.drawerFilePathKey)
        filePath = path
        onChooseFile(URL(fileURLWithPath: path))
    }
}

private struct TimerFeatureToggleGrid: View {
    @Binding var focusTimerEnabled: Bool
    @Binding var pomodoroEnabled: Bool
    @Binding var stopwatchEnabled: Bool
    let palette: SettingsPalette

    var body: some View {
        HStack(spacing: 8) {
            TimerFeatureToggleCard(
                title: "Focus",
                subtitle: "Countdown",
                icon: "timer",
                isOn: $focusTimerEnabled,
                palette: palette
            )
            TimerFeatureToggleCard(
                title: "Pomodoro",
                subtitle: "Cadence",
                icon: "target",
                isOn: $pomodoroEnabled,
                palette: palette
            )
            TimerFeatureToggleCard(
                title: "Stopwatch",
                subtitle: "Work log",
                icon: "briefcase",
                isOn: $stopwatchEnabled,
                palette: palette
            )
        }
    }
}

private struct TimerFeatureToggleCard: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    let palette: SettingsPalette

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                isOn.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOn ? palette.accent : palette.secondary)
                    Spacer()
                    PomodoroMiniSwitch(isOn: isOn, palette: palette)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isOn ? palette.accentFill : palette.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isOn ? palette.selectedStroke : palette.stroke,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

private struct PomodoroMiniSwitch: View {
    let isOn: Bool
    let palette: SettingsPalette

    var body: some View {
        Capsule()
            .fill(isOn ? palette.accent.opacity(0.20) : palette.controlFillStrong)
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? palette.accent : palette.secondary.opacity(0.72))
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.18), value: isOn)
            .accessibilityHidden(true)
    }
}

private struct PomodoroCadenceSettings: View {
    @Binding var focusMinutes: Int
    @Binding var shortBreakMinutes: Int
    @Binding var longBreakMinutes: Int
    @Binding var sessionsUntilLongBreak: Int
    let palette: SettingsPalette
    let applyPreset: (PomodoroPreferences.Preset) -> Void

    private var settings: PomodoroTimer.Settings {
        PomodoroPreferences.settings(
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes,
            sessionsUntilLongBreak: sessionsUntilLongBreak
        )
    }

    private var selectedPreset: PomodoroPreferences.Preset? {
        PomodoroPreferences.Preset.matching(settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Pomodoro rhythm", systemImage: "timer")
                    .font(.headline)
                Spacer()
                Text("\(focusMinutes)/\(shortBreakMinutes)/\(longBreakMinutes)")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 7) {
                ForEach(PomodoroPreferences.Preset.allCases) { preset in
                    PomodoroPresetChip(
                        preset: preset,
                        selected: selectedPreset == preset,
                        palette: palette
                    ) {
                        applyPreset(preset)
                    }
                }
                PomodoroCustomChip(isSelected: selectedPreset == nil, palette: palette)
            }

            HStack(spacing: 8) {
                PomodoroDurationTile(
                    title: "Focus",
                    icon: "target",
                    value: $focusMinutes,
                    range: PomodoroTimer.Settings.focusRange,
                    palette: palette
                )
                PomodoroDurationTile(
                    title: "Short",
                    icon: "cup.and.saucer.fill",
                    value: $shortBreakMinutes,
                    range: PomodoroTimer.Settings.shortBreakRange,
                    palette: palette
                )
                PomodoroDurationTile(
                    title: "Long",
                    icon: "sparkles",
                    value: $longBreakMinutes,
                    range: PomodoroTimer.Settings.longBreakRange,
                    palette: palette
                )
            }

            PomodoroRoundControl(
                value: $sessionsUntilLongBreak,
                range: PomodoroTimer.Settings.sessionsUntilLongBreakRange,
                palette: palette
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

private struct PomodoroPresetChip: View {
    let preset: PomodoroPreferences.Preset
    let selected: Bool
    let palette: SettingsPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(preset.subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? palette.accentFill : palette.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selected ? palette.selectedStroke : palette.stroke,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(preset.title) Pomodoro preset")
        .help(preset.subtitle)
    }
}

private struct PomodoroCustomChip: View {
    let isSelected: Bool
    let palette: SettingsPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Custom")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Text("Live")
                .font(.caption2)
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .foregroundStyle(palette.primary)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? palette.accentFill : palette.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isSelected ? palette.selectedStroke : palette.stroke,
                    lineWidth: 1
                )
        )
        .accessibilityLabel("Custom Pomodoro cadence")
    }
}

private struct PomodoroDurationTile: View {
    let title: String
    let icon: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let palette: SettingsPalette

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = min(max(Int($0.rounded()), range.lowerBound), range.upperBound) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.secondary)
            }
            HStack(spacing: 5) {
                PomodoroNudgeButton(systemName: "minus", palette: palette) { decrement() }
                    .disabled(value <= range.lowerBound)
                Spacer(minLength: 0)
                Text("\(value)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.primary)
                    .monospacedDigit()
                    .frame(minWidth: 34)
                Text("m")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
                PomodoroNudgeButton(systemName: "plus", palette: palette) { increment() }
                    .disabled(value >= range.upperBound)
            }
            Slider(value: sliderValue, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .tint(palette.accent)
                .controlSize(.small)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }

    private func decrement() {
        withAnimation(.snappy(duration: 0.16)) {
            value = max(range.lowerBound, value - 1)
        }
    }

    private func increment() {
        withAnimation(.snappy(duration: 0.16)) {
            value = min(range.upperBound, value + 1)
        }
    }
}

private struct PomodoroNudgeButton: View {
    let systemName: String
    let palette: SettingsPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.accent)
                .frame(width: 24, height: 24)
                .background(palette.accentFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
    }
}

private struct PomodoroRoundControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let palette: SettingsPalette

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Long break every")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.secondary)
                Text("\(value) focus rounds")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.primary)
                    .monospacedDigit()
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<range.upperBound, id: \.self) { index in
                    Circle()
                        .fill(index < value ? palette.accent : palette.tertiary.opacity(0.35))
                        .frame(width: 5, height: 5)
                        .opacity(index < range.lowerBound || index < value ? 1 : 0.55)
                }
            }
            PomodoroNudgeButton(systemName: "minus", palette: palette) {
                withAnimation(.snappy(duration: 0.16)) {
                    value = max(range.lowerBound, value - 1)
                }
            }
            .disabled(value <= range.lowerBound)
            PomodoroNudgeButton(systemName: "plus", palette: palette) {
                withAnimation(.snappy(duration: 0.16)) {
                    value = min(range.upperBound, value + 1)
                }
            }
            .disabled(value >= range.upperBound)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

private struct FeatureSettingsView: View {
    @StateObject private var model = FeatureFlagsModel()
    @AppStorage("checkOffSound") private var checkOffSound = CheckOffSound.chimeID
    @AppStorage("checkOffSoundVolume") private var checkOffSoundVolume = 0.8
    @State private var checkOffOptions = CheckOffSound.options()
    @AppStorage("hideCompleted") private var hideCompleted = false
    @AppStorage("uncheckedFirst") private var uncheckedFirst = false
    @AppStorage("backlogExpanded") private var backlogExpanded = false
    @AppStorage("archiveExpanded") private var archiveExpanded = false

    var body: some View {
        Form {
            Section {
                SettingsCaption(
                    "Turn features on or off. Minimal keeps only today and carried-over "
                    + "tasks. Recommended is the default. Everything turns it all on."
                )
                HStack {
                    Button("Minimal") { model.applyMinimal() }
                    Button("Recommended") { model.applyDefaults() }
                    Button("Everything") { model.applyEverything() }
                    Spacer()
                }
                SettingsCaption("These presets also switch the timer pills on the Timers tab.")
            }
            ForEach(FeatureFlag.groupsInOrder, id: \.self) { group in
                Section(group) {
                    ForEach(FeatureFlag.availableCases.filter { $0.group == group }) { flag in
                        Toggle(isOn: model.binding(flag)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flag.title)
                                Text(flag.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if group == "Feedback" { checkOffSoundPicker }
                    if group == "Controls" {
                        Divider()
                        Toggle("Hide completed on open", isOn: $hideCompleted)
                        Toggle("Unchecked first on open", isOn: $uncheckedFirst)
                        SettingsCaption("Starting state for the filter menu when the drawer opens.")
                    }
                    if group == "Sections" {
                        Divider()
                        Toggle("Expand Backlog on open", isOn: $backlogExpanded)
                        Toggle("Expand Archive on open", isOn: $archiveExpanded)
                        SettingsCaption("Start these sections open. Headers still collapse them live.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { checkOffOptions = CheckOffSound.options() }
    }

    /// The check-off sound picker, shown under its "Sound on check-off" toggle.
    private var checkOffSoundPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Check-off sound", selection: $checkOffSound) {
                    ForEach(checkOffOptions) { opt in
                        Text(opt.label).tag(opt.id)
                    }
                }
                .onChange(of: checkOffSound) { _, id in
                    // Play it as you browse so the choice is audible.
                    CheckOffSoundPlayer.shared.play(id: id, volume: checkOffSoundVolume)
                }
                Slider(value: $checkOffSoundVolume, in: 0...1)
                    .frame(width: 90)
                Button {
                    CheckOffSoundPlayer.shared.play(id: checkOffSound, volume: checkOffSoundVolume)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Preview")
            }
            HStack {
                Button("Add custom…") { importCheckOffSound() }
                Button("Open Sounds folder") { openSoundsFolder() }
                Spacer()
            }
            SettingsCaption(
                "Built-in chime, a macOS system sound, or your own file "
                + "(wav, aiff, caf, mp3, m4a). Plays only when Sound on check-off is on."
            )
        }
    }

    /// Copy a chosen audio file into the Sounds folder and select it.
    private func importCheckOffSound() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let dir = CheckOffSound.soundsDir
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let dest = dir.appendingPathComponent(src.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            checkOffOptions = CheckOffSound.options()
            checkOffSound = "custom:\(src.lastPathComponent)"
        } catch {
            NSSound.beep()
        }
    }

    private func openSoundsFolder() {
        let dir = CheckOffSound.soundsDir
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(dir)
    }
}

private struct AdvancedSettingsView: View {
    @AppStorage(AppPaths.dataFolderPathKey) private var dataFolderPath = ""
    @AppStorage(AppPaths.notesFilePathKey) private var notesFilePath = ""
    @AppStorage(AppPaths.workLogFilePathKey) private var workLogFilePath = ""
    @AppStorage(AppPaths.workLogMarkdownFilePathKey) private var workLogMarkdownPath = ""
    @AppStorage(AppPaths.ideasDirectoryPathKey) private var ideasDirectoryPath = ""
    @AppStorage(AppPaths.plannerPrioritiesPathKey) private var plannerPrioritiesPath = AppPaths.defaultPrioritiesFile
    @AppStorage(AppPaths.parkingLotFilePathKey) private var parkingLotPath = ""
    @AppStorage(FeatureFlag.parkingLot.key) private var parkingLotEnabled =
        FeatureFlag.parkingLot.defaultValue
    @AppStorage("exportWorkLogMarkdown") private var exportWorkLogMarkdown =
        AppPaths.defaultExportWorkLogMarkdown
    @AppStorage("teleprompterSpeed") private var teleprompterSpeed = 45.0
    @AppStorage("teleprompterFontSize") private var teleprompterFontSize = 34.0
    @AppStorage("notesPaneHeight") private var notesPaneHeight = 160.0
    @AppStorage(DevTools.key) private var devToolsEnabled = false
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section {
                SettingsCaption(
                    "Niche options and file paths. A path change takes effect "
                    + "after you quit and reopen Drawer."
                )
            }
            Section("Data files") {
                // Sandboxed, so every file sits in this folder unless a row
                // below points somewhere else. Same pick as first run, so
                // the files move with it either way.
                if appStoreBuild {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Drawer folder")
                            .font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            Text(dataFolderPath.isEmpty ? "Not set" : dataFolderPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Button("Choose…") { DataFolder.choose() }
                        }
                        SettingsCaption(
                            "Where Drawer keeps your task file, notes, and ideas. "
                            + "Changing it brings those files along."
                        )
                    }
                }
                SettingsPathRow(
                    title: "Notes scratchpad",
                    caption: "The in-drawer notes pad. Kept out of your task vault by default.",
                    storedPath: $notesFilePath,
                    defaultPath: AppPaths.defaultNotesFile,
                    settingKey: AppPaths.notesFilePathKey
                )
                SettingsPathRow(
                    title: "Work session log",
                    caption: "JSONL log of work-mode time. The summary card reads this.",
                    storedPath: $workLogFilePath,
                    defaultPath: AppPaths.defaultWorkLogFile,
                    settingKey: AppPaths.workLogFilePathKey,
                    pickKind: .jsonlFile
                )
                Toggle("Export work log to markdown", isOn: $exportWorkLogMarkdown)
                if exportWorkLogMarkdown {
                    SettingsPathRow(
                        title: "Work log markdown",
                        caption: "Rewritten when work mode ends or you edit a summary. "
                            + "Handy beside your notes.",
                        storedPath: $workLogMarkdownPath,
                        defaultPath: AppPaths.defaultWorkLogMarkdownFile,
                        settingKey: AppPaths.workLogMarkdownFilePathKey
                    )
                }
                SettingsPathRow(
                    title: "Idea board folder",
                    caption: "board.json and pasted images live here. One folder can hold multiple boards.",
                    storedPath: $ideasDirectoryPath,
                    defaultPath: AppPaths.defaultIdeasDirectory,
                    settingKey: AppPaths.ideasDirectoryPathKey,
                    pickKind: .directory
                )
                if parkingLotEnabled {
                    SettingsPathRow(
                        title: "Parking lot",
                        caption: "The file behind the parking lot board. Sits next to your "
                            + "task file unless you move it.",
                        storedPath: $parkingLotPath,
                        defaultPath: AppPaths.defaultParkingLotFile,
                        settingKey: AppPaths.parkingLotFilePathKey
                    )
                }
                SettingsPathRow(
                    title: "Planner priorities",
                    caption: "The AI day planner reads this file to rank tasks. Clear it to plan "
                        + "without priorities.",
                    storedPath: $plannerPrioritiesPath,
                    defaultPath: AppPaths.defaultPrioritiesFile,
                    settingKey: AppPaths.plannerPrioritiesPathKey
                )
                Button("Open Drawer data folder") {
                    let dir = AppPaths.drawerDataDirectory
                    try? FileManager.default.createDirectory(
                        at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
            }
            Section("Teleprompter") {
                HStack {
                    Text("Scroll speed")
                    Slider(value: $teleprompterSpeed, in: 10...120, step: 5)
                    Text("\(Int(teleprompterSpeed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                HStack {
                    Text("Font size")
                    Slider(value: $teleprompterFontSize, in: 20...60, step: 2)
                    Text("\(Int(teleprompterFontSize)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                SettingsCaption(
                    "The floating reader over your notes. Spacebar pauses while its window is focused."
                )
            }
            Section("Notes pad") {
                HStack {
                    Text("Default height")
                    Slider(value: $notesPaneHeight, in: 100...320, step: 10)
                    Text("\(Int(notesPaneHeight))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                SettingsCaption("How tall the notes pane opens. You can still drag to resize.")
            }
            Section {
                Button("Reset advanced settings…", role: .destructive) {
                    showResetConfirm = true
                }
                SettingsCaption("Clears custom paths and advanced toggles. Themes, sounds, and your task file stay as they are.")
            }
            StorageSection()
            Section {
                Toggle("Developer tools", isOn: $devToolsEnabled)
                    .onChange(of: devToolsEnabled) { _, _ in DevTuningStore.shared.refresh() }
                SettingsCaption("Shows the tuning sliders below. They tweak how the app feels, not real settings.")
            }
            if devToolsEnabled { DeveloperSettings() }
        }
        .formStyle(.grouped)
        .alert("Reset advanced settings?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetAdvanced() }
        } message: {
            Text("File paths and teleprompter tuning go back to defaults. Quit and reopen if you changed a path.")
        }
    }

    private func resetAdvanced() {
        notesFilePath = ""
        workLogFilePath = ""
        workLogMarkdownPath = ""
        ideasDirectoryPath = ""
        plannerPrioritiesPath = AppPaths.defaultPrioritiesFile
        exportWorkLogMarkdown = AppPaths.defaultExportWorkLogMarkdown
        teleprompterSpeed = 45.0
        teleprompterFontSize = 34.0
        notesPaneHeight = 160.0
    }
}

/// Advanced > storage. What Drawer keeps on disk and how big it is, with a
/// confirmed clear for each. These are Drawer's own derived stores; your task
/// file, notes, and boards are never listed or touched here. The live history
/// scrubber self-heals to the cleared state on its next capture.
private struct StorageSection: View {
    private struct Store: Identifiable {
        let id: String
        let name: String
        let caption: String
        let targets: [URL]  // the files or folders this store owns
    }

    private var stores: [Store] {
        [
            Store(id: "history", name: "History snapshots",
                  caption: "The time-lapse of your task file. Clearing keeps your tasks.",
                  targets: [AppPaths.historyDirectory]),
            Store(id: "activity", name: "Activity log",
                  caption: "Raw work-mode activity and the queue before it is summarized.",
                  targets: [AppPaths.rawActivityFile, AppPaths.attributionQueueFile]),
            Store(id: "summaries", name: "Day summaries and schedules",
                  caption: "The AI day summaries and planned schedules work mode built.",
                  targets: [AppPaths.daySummariesFile, AppPaths.daySchedulesFile]),
        ]
    }

    @State private var sizes: [String: Int64] = [:]
    @State private var confirming: Store?

    var body: some View {
        Section("Storage") {
            ForEach(stores) { store in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.name)
                        SettingsCaption(store.caption)
                    }
                    Spacer(minLength: 12)
                    Text(sizeLabel(sizes[store.id] ?? 0))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Button("Clear") { confirming = store }
                        .disabled((sizes[store.id] ?? 0) == 0)
                }
            }
            SettingsCaption("Sizes on disk. Clearing a store cannot be undone.")
        }
        .onAppear(perform: refresh)
        .alert(
            "Clear \(confirming?.name.lowercased() ?? "this data")?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { store in
            Button("Cancel", role: .cancel) {}
            Button("Clear \(sizeLabel(sizes[store.id] ?? 0))", role: .destructive) { clear(store) }
        } message: { _ in
            Text("This deletes it for good. Your task file, notes, and boards are not touched.")
        }
    }

    private func refresh() {
        var out: [String: Int64] = [:]
        for store in stores {
            out[store.id] = store.targets.reduce(0) { $0 + Self.size(of: $1) }
        }
        sizes = out
    }

    private func clear(_ store: Store) {
        for url in store.targets { try? FileManager.default.removeItem(at: url) }
        confirming = nil
        refresh()
    }

    private func sizeLabel(_ bytes: Int64) -> String {
        bytes == 0 ? "Empty" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Bytes on disk for a file, or the recursive total for a folder. Missing
    /// paths are 0, so a never-created store just reads as Empty.
    private static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

private struct HelpView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    AppLogo(size: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drawer").font(.title2.weight(.semibold))
                        if !version.isEmpty {
                            Text("Version \(version)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                helpBlock(
                    "How it works",
                    "Drawer shows one markdown file as your day list. "
                    + "Edit it anywhere (Obsidian, a text editor, iCloud on another device) "
                    + "and the drawer updates in a second. "
                    + "Checking a task writes back to the file."
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Task format").font(.headline)
                    Text("""
                    ## Mon 2026-06-08
                    - [ ] Call the landlord
                    - [x] Done task
                    """)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    Text("A ## heading with a date starts a day. A weekday like Mon is fine. "
                         + "Tasks under it belong to that day. ## Backlog and ## Archive hold "
                         + "non-day tasks, collapsed at the bottom. Other dateless headings "
                         + "stay in the file but do not show.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Grouping with \"###\"").font(.headline)
                    Text("""
                    ## Archive
                    ### Games
                    - [ ] parked game idea
                    ### AI / apps
                    - [ ] parked app idea
                    """)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    Text("Inside Backlog or Archive, ### subheadings become group labels. "
                         + "Prose between tasks is ignored.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                helpBlock(
                    "What the drawer shows",
                    "Today: today's tasks. "
                    + "Carried over: unchecked tasks from the last day. "
                    + "Tomorrow: the next planned day, for evening planning. "
                    + "Backlog: someday tasks, collapsed at the bottom. "
                    + "Archive: parked ideas, collapsed below Backlog."
                )

                helpBlock(
                    "Work mode",
                    "Tap the briefcase to track real hours. Tap a task to clock time on it. "
                    + "End work mode for a summary you can edit. Hours log to JSONL, and to "
                    + "markdown if you turn that on in Advanced."
                )

                helpBlock(
                    "Idea board",
                    "Swipe the task list sideways to open the canvas. Drop text cards and images, "
                    + "zoom with + or −, switch boards from the title menu. Settings live "
                    + "under the Board tab."
                )

                helpBlock(
                    "Settings tabs",
                    "General: hotkey, task file, and panel size. "
                    + "Appearance: theme and fonts. "
                    + "Timers: timer pills, Pomodoro, and focus sound. "
                    + "Features: turn parts of the app on or off. "
                    + "Board: canvas background, swipe and zoom. "
                    + "Advanced: file paths and teleprompter. "
                    + "Most changes apply right away. File path changes need a restart."
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Controls").font(.headline)
                    controlRow("Hotkey (General)", "show / hide the drawer")
                    controlRow("Esc", "hide, after clicking into the panel")
                    controlRow("+", "add a task to today's section")
                    controlRow("Note", "open the notes pad and teleprompter")
                    controlRow("☰", "hide completed, unchecked first")
                    controlRow("Briefcase", "start or end work mode")
                    controlRow("Speaker", "play a focus sound")
                    controlRow("⤡", "expand to full height / collapse")
                    controlRow("◯", "check off (writes to the file)")
                    controlRow("▶", "start the focus timer (top left)")
                    controlRow("Swipe left", "delete a task (if enabled)")
                    controlRow("Swipe right", "mark in progress (if enabled)")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func helpBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func controlRow(_ key: String, _ what: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 140, alignment: .leading)
            Text(what)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
