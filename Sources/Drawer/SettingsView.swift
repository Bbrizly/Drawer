import AppKit
import DrawerCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var onChooseFile: (URL) -> Void
    var onHotkeyChange: (HotkeyBinding) -> Bool
    var onLayoutChange: () -> Void

    private enum Tab: String, CaseIterable {
        case general = "General"
        case features = "Features"
        case board = "Board"
        case advanced = "Advanced"
        case help = "Help"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .features: return "switch.2"
            case .board: return "square.grid.2x2"
            case .advanced: return "slider.horizontal.3"
            case .help: return "questionmark.circle"
            }
        }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button {
                        tab = item
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.icon).font(.system(size: 16))
                            Text(item.rawValue).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(tab == item ? Color.accentColor.opacity(0.18) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(tab == item ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
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
                    onLayoutChange: onLayoutChange
                )
            case .features:
                FeatureSettingsView()
            case .board:
                BoardSettingsView()
            case .advanced:
                AdvancedSettingsView()
            case .help:
                HelpView()
            }
        }
        .frame(width: 440, height: 580)
    }
}

private struct BoardSettingsView: View {
    @AppStorage("boardBackground") private var boardBackground = "dark"
    @AppStorage("boardDefaultColor") private var defaultColor = "yellow"
    @AppStorage("boardSwipeScale") private var swipeScale = 300.0
    @AppStorage("boardZoomStep") private var zoomStep = 1.25

    private let colors = Palette.cardKeys

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
                    "Dark is a solid board. Transparent shows your desktop through the canvas. "
                    + "Paper adds ruled lines. The Notebook theme always uses paper."
                )
            }
            Section("New cards") {
                HStack(spacing: 10) {
                    ForEach(colors, id: \.self) { key in
                        Circle()
                            .fill(Palette.card(key).color)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(
                                    .primary.opacity(defaultColor == key ? 0.9 : 0.15),
                                    lineWidth: defaultColor == key ? 2.5 : 1)
                            )
                            .accessibilityLabel("\(key) card color")
                            .onTapGesture { defaultColor = key }
                    }
                    Spacer()
                }
                SettingsCaption("Tap a color. New text cards and sticky notes start in that shade.")
            }
            Section("Gestures") {
                HStack {
                    Text("Swipe to open")
                    Slider(value: $swipeScale, in: 150...600, step: 25)
                    Text("\(Int(swipeScale))")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                }
                SettingsCaption(
                    "How far you swipe the task list to reveal the idea board. "
                    + "Lower numbers mean a shorter swipe covers more of the screen."
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

private struct GeneralSettingsView: View {
    var onChooseFile: (URL) -> Void
    var onHotkeyChange: (HotkeyBinding) -> Bool
    var onLayoutChange: () -> Void

    @AppStorage("drawerFilePath") private var filePath = AppPaths.defaultDrawerFile
    @State private var hotkey = HotkeyBinding.saved
    @AppStorage("defaultMinutesText") private var defaultMinutes = "25"
    @AppStorage("feature.focusTimer") private var focusTimerEnabled = true
    @AppStorage("feature.pomodoro") private var pomodoroEnabled = true
    @AppStorage("feature.workMode") private var stopwatchEnabled = true
    @AppStorage(PomodoroPreferences.focusMinutesKey) private var pomodoroFocusMinutes =
        PomodoroTimer.Settings.standard.focusMinutes
    @AppStorage(PomodoroPreferences.shortBreakMinutesKey) private var pomodoroShortBreakMinutes =
        PomodoroTimer.Settings.standard.shortBreakMinutes
    @AppStorage(PomodoroPreferences.longBreakMinutesKey) private var pomodoroLongBreakMinutes =
        PomodoroTimer.Settings.standard.longBreakMinutes
    @AppStorage(PomodoroPreferences.sessionsUntilLongBreakKey)
    private var pomodoroSessionsUntilLongBreak =
        PomodoroTimer.Settings.standard.sessionsUntilLongBreak
    @AppStorage("panelWidth") private var panelWidth = 300.0
    @AppStorage("panelCompactHeight") private var panelHeight = 440.0
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
    @AppStorage("appFontDesign") private var appFontDesign = "theme"
    @AppStorage("taskFontSize") private var taskFontSize = 13.0
    @AppStorage("focusSoundKind") private var focusSoundKind = "pink"
    @AppStorage("focusSoundVolume") private var focusSoundVolume = 0.5
    @AppStorage("checkOffSound") private var checkOffSound = CheckOffSound.chimeID
    @AppStorage("checkOffSoundVolume") private var checkOffSoundVolume = 0.8
    @State private var checkOffOptions = CheckOffSound.options()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showHotkeyError = false
    @State private var isRecordingHotkey = false
    @State private var hotkeyRecorder = HotkeyRecorder()

    private var pomodoroSettings: PomodoroTimer.Settings {
        PomodoroPreferences.settings(
            focusMinutes: pomodoroFocusMinutes,
            shortBreakMinutes: pomodoroShortBreakMinutes,
            longBreakMinutes: pomodoroLongBreakMinutes,
            sessionsUntilLongBreak: pomodoroSessionsUntilLongBreak
        )
    }

    var body: some View {
        ScrollView {
            Form {
                Section("Look") {
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
                        "Each theme changes the panel surface, type, and accent. "
                        + "Art-directed themes also reshape the chrome."
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
                    "Font restyles the whole drawer. Theme default keeps each theme's own face "
                    + "(Medieval serif, Pixel bitmap). Size drives task titles; notes sit two points under."
                )
            }
            Section("Focus sound") {
                Picker("Sound", selection: $focusSoundKind) {
                    ForEach(FocusSoundPlayer.options, id: \.id) { opt in
                        Text(opt.label).tag(opt.id)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $focusSoundVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                SettingsCaption(
                    "Play from the speaker button in the header too. Pink masks chatter, "
                    + "brown is deeper, ocean swells like surf. Turn the feature off under Features."
                )
            }
            Section("Check-off sound") {
                HStack {
                    Picker("Sound", selection: $checkOffSound) {
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
                        CheckOffSoundPlayer.shared.play(
                            id: checkOffSound, volume: checkOffSoundVolume
                        )
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
                    + "(wav, aiff, caf, mp3, m4a). Plays only when Sound on check-off is on under Features."
                )
            }
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
                    "A markdown file with dated ## headings and - [ ] checkboxes. "
                    + "Drawer reads it live, so edits in Obsidian or iCloud show up here. "
                    + "See the Help tab for the full format."
                )
            }
            Section("Shortcut") {
                HStack {
                    Text("Toggle drawer")
                    Spacer()
                    Text(isRecordingHotkey ? "Press a key…" : hotkey.label)
                        .foregroundStyle(.secondary)
                    Button(isRecordingHotkey ? "Cancel" : "Record…") {
                        if isRecordingHotkey {
                            stopHotkeyRecording()
                        } else {
                            startHotkeyRecording()
                        }
                    }
                }
                if hotkey.isTypingKey {
                    SettingsCaption("That key is used while typing. F13–F19 are safer, or remap Caps Lock to F13.")
                        .foregroundStyle(.orange)
                }
                SettingsCaption(
                    "Shows or hides the drawer from anywhere. One-key shortcuts work best on "
                    + "F13–F19. Remap Caps Lock in System Settings → Keyboard → Modifier Keys."
                )
                HStack(spacing: 6) {
                    ForEach(HotkeyBinding.singleKeyPresets) { binding in
                        Button(binding.label) {
                            let previous = hotkey
                            hotkey = binding
                            applyHotkey(binding, revertingTo: previous)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                DisclosureGroup("Shortcuts with modifiers") {
                    Picker("Preset", selection: $hotkey) {
                        ForEach(HotkeyBinding.modifierPresets) { binding in
                            Text(binding.label).tag(binding)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: hotkey) { old, new in
                        guard !isRecordingHotkey else { return }
                        applyHotkey(new, revertingTo: old)
                    }
                }
            }
            Section("Timers") {
                TimerFeatureToggleGrid(
                    focusTimerEnabled: $focusTimerEnabled,
                    pomodoroEnabled: $pomodoroEnabled,
                    stopwatchEnabled: $stopwatchEnabled,
                    palette: .standard
                )
                SettingsCaption(
                    "Choose which timer pills appear at the top. Stopwatch is the task time "
                    + "tracker formerly shown as Work Mode."
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
                    "Pre-fills the focus timer when you tap play. A task can override this "
                    + "with a duration like (15m) in the markdown file."
                )
                PomodoroCadenceSettings(
                    focusMinutes: $pomodoroFocusMinutes,
                    shortBreakMinutes: $pomodoroShortBreakMinutes,
                    longBreakMinutes: $pomodoroLongBreakMinutes,
                    sessionsUntilLongBreak: $pomodoroSessionsUntilLongBreak,
                    palette: .standard,
                    applyPreset: applyPomodoroPreset
                )
                SettingsCaption(
                    "The tuned default is 25 minutes of focus, 5 minutes off, and a "
                    + "15-minute reset after four focus rounds."
                )
            }
            Section("Panel size") {
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
                    "Compact height is the default slide-out size. Use the expand arrows in the "
                    + "header to grow to full screen height; that toggle is separate from these numbers."
                )
            }
            Section {
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
        }
        .formStyle(.grouped)
        .onAppear {
            hotkey = HotkeyBinding.saved
            launchAtLogin = SMAppService.mainApp.status == .enabled
            checkOffOptions = CheckOffSound.options()
            sanitizePomodoroSettings()
        }
        .onDisappear { stopHotkeyRecording() }
        .onChange(of: panelWidth) { _, _ in onLayoutChange() }
        .onChange(of: panelHeight) { _, _ in onLayoutChange() }
        .onChange(of: pomodoroFocusMinutes) { _, _ in sanitizePomodoroSettings() }
        .onChange(of: pomodoroShortBreakMinutes) { _, _ in sanitizePomodoroSettings() }
        .onChange(of: pomodoroLongBreakMinutes) { _, _ in sanitizePomodoroSettings() }
        .onChange(of: pomodoroSessionsUntilLongBreak) { _, _ in sanitizePomodoroSettings() }
        .alert("Shortcut unavailable", isPresented: $showHotkeyError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That shortcut could not be registered. The previous shortcut is still active.")
        }
    }

    private func startHotkeyRecording() {
        isRecordingHotkey = true
        hotkeyRecorder.start { keyCode in
            let candidate = HotkeyBinding(keyCode: keyCode, modifiers: 0)
            stopHotkeyRecording()
            let previous = hotkey
            hotkey = candidate
            applyHotkey(candidate, revertingTo: previous)
        }
    }

    private func stopHotkeyRecording() {
        isRecordingHotkey = false
        hotkeyRecorder.stop()
    }

    private func applyHotkey(_ binding: HotkeyBinding, revertingTo previous: HotkeyBinding) {
        guard onHotkeyChange(binding) else {
            hotkey = previous
            showHotkeyError = true
            return
        }
        binding.save()
    }

    private func chooseFile() {
        guard let path = SettingsPickers.run(.markdownFile, startingAt: filePath) else { return }
        filePath = path
        onChooseFile(URL(fileURLWithPath: path))
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
        .buttonStyle(PomodoroPressStyle())
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
        .buttonStyle(PomodoroPressStyle())
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
        .buttonStyle(PomodoroPressStyle())
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

private struct PomodoroPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

private struct FeatureSettingsView: View {
    @StateObject private var model = FeatureFlagsModel()

    var body: some View {
        Form {
            Section {
                SettingsCaption(
                    "Turn features on or off without touching code. Minimal keeps only today's "
                    + "tasks and carried-over work. Everything turns the full drawer back on."
                )
                HStack {
                    Button("Minimal") { model.applyMinimal() }
                    Button("Everything") { model.applyEverything() }
                    Spacer()
                }
            }
            ForEach(FeatureFlag.groupsInOrder, id: \.self) { group in
                Section(group) {
                    ForEach(FeatureFlag.allCases.filter { $0.group == group }) { flag in
                        Toggle(isOn: model.binding(flag)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flag.title)
                                Text(flag.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettingsView: View {
    @AppStorage(AppPaths.notesFilePathKey) private var notesFilePath = ""
    @AppStorage(AppPaths.workLogFilePathKey) private var workLogFilePath = ""
    @AppStorage(AppPaths.workLogMarkdownFilePathKey) private var workLogMarkdownPath = ""
    @AppStorage(AppPaths.ideasDirectoryPathKey) private var ideasDirectoryPath = ""
    @AppStorage(AppPaths.plannerPrioritiesPathKey) private var plannerPrioritiesPath = AppPaths.defaultPrioritiesFile
    @AppStorage("exportWorkLogMarkdown") private var exportWorkLogMarkdown = true
    @AppStorage("teleprompterSpeed") private var teleprompterSpeed = 45.0
    @AppStorage("teleprompterFontSize") private var teleprompterFontSize = 34.0
    @AppStorage("notesPaneHeight") private var notesPaneHeight = 160.0
    @AppStorage("hideCompleted") private var hideCompleted = false
    @AppStorage("uncheckedFirst") private var uncheckedFirst = false
    @AppStorage("backlogExpanded") private var backlogExpanded = false
    @AppStorage("archiveExpanded") private var archiveExpanded = false
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            Form {
                Section {
                    SettingsCaption(
                        "Niche options and file locations. Changing a data path takes effect "
                        + "after you quit and reopen Drawer."
                    )
                }
                Section("Data files") {
                    SettingsPathRow(
                        title: "Notes scratchpad",
                        caption: "The in-drawer notes pad. Kept out of your task vault by default.",
                        storedPath: $notesFilePath,
                        defaultPath: AppPaths.defaultNotesFile
                    )
                    SettingsPathRow(
                        title: "Work session log",
                        caption: "Raw JSONL log of work-mode time segments. The summary card reads this.",
                        storedPath: $workLogFilePath,
                        defaultPath: AppPaths.defaultWorkLogFile,
                        pickKind: .jsonlFile
                    )
                    Toggle("Export work log to markdown", isOn: $exportWorkLogMarkdown)
                    if exportWorkLogMarkdown {
                        SettingsPathRow(
                            title: "Work log markdown",
                            caption: "Regenerated when work mode ends or you edit a day summary. "
                                + "Handy beside your other notes.",
                            storedPath: $workLogMarkdownPath,
                            defaultPath: AppPaths.defaultWorkLogMarkdownFile
                        )
                    }
                    SettingsPathRow(
                        title: "Idea board folder",
                        caption: "board.json and pasted images live here. One folder can hold multiple boards.",
                        storedPath: $ideasDirectoryPath,
                        defaultPath: AppPaths.defaultIdeasDirectory,
                        pickKind: .directory
                    )
                    SettingsPathRow(
                        title: "Planner priorities",
                        caption: "The AI day planner reads this file to rank tasks. Clear it to plan "
                            + "without priorities.",
                        storedPath: $plannerPrioritiesPath,
                        defaultPath: AppPaths.defaultPrioritiesFile
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
                    SettingsCaption("How tall the notes pane opens inside the drawer. You can still drag to resize.")
                }
                Section("Task list defaults") {
                    Toggle("Hide completed on open", isOn: $hideCompleted)
                    Toggle("Unchecked first on open", isOn: $uncheckedFirst)
                    Toggle("Expand Backlog on open", isOn: $backlogExpanded)
                    Toggle("Expand Archive on open", isOn: $archiveExpanded)
                    SettingsCaption(
                        "Starting state when the drawer opens. The filter menu and section headers "
                        + "still let you change these live."
                    )
                }
                Section {
                    Button("Reset advanced settings…", role: .destructive) {
                        showResetConfirm = true
                    }
                    SettingsCaption("Clears custom paths and advanced toggles. Themes, sounds, and your task file stay as they are.")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset advanced settings?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetAdvanced() }
        } message: {
            Text("Custom file paths, teleprompter tuning, and list defaults go back to built-in values. Quit and reopen Drawer if you changed a file path.")
        }
    }

    private func resetAdvanced() {
        notesFilePath = ""
        workLogFilePath = ""
        workLogMarkdownPath = ""
        ideasDirectoryPath = ""
        exportWorkLogMarkdown = true
        teleprompterSpeed = 45.0
        teleprompterFontSize = 34.0
        notesPaneHeight = 160.0
        hideCompleted = false
        uncheckedFirst = false
        backlogExpanded = false
        archiveExpanded = false
    }
}

private struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                helpBlock(
                    "How it works",
                    "Drawer shows one markdown file as your day list. "
                    + "Edit the file anywhere (Obsidian, a text editor, another device "
                    + "via iCloud) and the drawer updates within a second. "
                    + "Checking a task in the drawer writes it back to the file."
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
                    Text("A \"##\" heading containing a date starts a day. "
                         + "Weekday prefixes like \"Mon\" are fine. Tasks under it "
                         + "belong to that day. \"## Backlog\" and \"## Archive\" "
                         + "collect non-day tasks, shown collapsed at the bottom. "
                         + "Other headings without a date (like \"## Someday\") are "
                         + "kept in the file but not shown.")
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
                    Text("Inside Backlog or Archive, \"###\" subheadings become "
                         + "group labels in the expanded list. Prose lines between "
                         + "tasks are ignored.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                helpBlock(
                    "What the drawer shows",
                    "Today: today's tasks. "
                    + "Carried over: unchecked tasks from the most recent earlier day. "
                    + "Tomorrow: the next planned day, so evening planning works. "
                    + "Backlog: someday tasks, collapsed at the bottom. Move a line "
                    + "under a day heading when you commit to it. "
                    + "Archive: parked explorations and ideas, collapsed below Backlog."
                )

                helpBlock(
                    "Work mode",
                    "Tap the briefcase to start tracking real hours. Tap a task to clock time "
                    + "on it. End work mode for a day summary you can edit. Hours are logged to "
                    + "a JSONL file; optionally exported as markdown under Advanced."
                )

                helpBlock(
                    "Idea board",
                    "Swipe the task list sideways to open the canvas. Drop text cards and images, "
                    + "zoom with + / −, and switch boards from the title menu. Board settings live "
                    + "under the Board tab."
                )

                helpBlock(
                    "Settings tabs",
                    "General: look, sounds, task file, hotkey, and panel size. "
                    + "Features: turn parts of the app on or off. "
                    + "Board: canvas background, card color, swipe and zoom. "
                    + "Advanced: file paths, teleprompter, and list defaults. "
                    + "Most changes apply immediately; file path changes need a restart."
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

/// A live preview tile for one theme: the real panel surface behind a couple of
/// stand-in ink bars, with the theme's accent and a selection ring. Tapping it
/// switches the drawer instantly.
private struct ThemeSwatch: View {
    let theme: DrawerTheme
    let selected: Bool

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                PanelBackground(theme: theme)
                    .clipShape(shape)
                VStack(alignment: .leading, spacing: 5) {
                    Circle().fill(theme.accent).frame(width: 9, height: 9)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.primaryInk.opacity(0.85))
                        .frame(width: 48, height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.primaryInk.opacity(0.5))
                        .frame(width: 34, height: 5)
                }
                .padding(11)
            }
            .frame(height: 62)
            .overlay(
                shape.strokeBorder(
                    selected ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: selected ? 2.5 : 1
                )
            )
            Text(theme.displayName)
                .font(.caption)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
