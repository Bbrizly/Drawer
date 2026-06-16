import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var onChooseFile: (URL) -> Void
    var onHotkeyChange: (HotkeyPreset) -> Bool
    var onLayoutChange: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(
                onChooseFile: onChooseFile,
                onHotkeyChange: onHotkeyChange,
                onLayoutChange: onLayoutChange
            )
            .tabItem { Label("General", systemImage: "gearshape") }

            FeatureSettingsView()
                .tabItem { Label("Features", systemImage: "switch.2") }

            HelpView()
                .tabItem { Label("Help", systemImage: "questionmark.circle") }
        }
        .frame(width: 420, height: 520)
    }
}

private struct GeneralSettingsView: View {
    var onChooseFile: (URL) -> Void
    var onHotkeyChange: (HotkeyPreset) -> Bool
    var onLayoutChange: () -> Void

    @AppStorage("drawerFilePath") private var filePath = AppPaths.defaultDrawerFile
    @AppStorage("hotkeyPreset") private var hotkeyRaw = HotkeyPreset.ctrlOptSpace.rawValue
    @AppStorage("defaultMinutesText") private var defaultMinutes = "25"
    @AppStorage("panelWidth") private var panelWidth = 300.0
    @AppStorage("panelCompactHeight") private var panelHeight = 440.0
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
    @AppStorage("focusSoundKind") private var focusSoundKind = "pink"
    @AppStorage("focusSoundVolume") private var focusSoundVolume = 0.5
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var revertingHotkey = false
    @State private var showHotkeyError = false

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
                Text("Also adjustable from the speaker button in the header. "
                     + "Pink masks chatter, brown is deeper, ocean swells like surf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
            Section("Shortcut") {
                Picker("Toggle drawer", selection: $hotkeyRaw) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.label).tag(preset.rawValue)
                    }
                }
                .onChange(of: hotkeyRaw) { oldRaw, raw in
                    if revertingHotkey {
                        revertingHotkey = false
                        return
                    }
                    guard let preset = HotkeyPreset(rawValue: raw),
                          !onHotkeyChange(preset)
                    else {
                        return
                    }
                    revertingHotkey = true
                    hotkeyRaw = oldRaw
                    showHotkeyError = true
                }
            }
            Section("Timer") {
                HStack {
                    Text("Default minutes")
                    Spacer()
                    TextField("25", text: $defaultMinutes)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .onChange(of: defaultMinutes) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(3))
                            if digits != newValue { defaultMinutes = digits }
                        }
                }
            }
            Section("Panel") {
                HStack {
                    Text("Width")
                    Slider(value: $panelWidth, in: 260...420, step: 10)
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
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Status can change externally (System Settings); never show stale.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: panelWidth) { _, _ in onLayoutChange() }
        .onChange(of: panelHeight) { _, _ in onLayoutChange() }
        .alert("Shortcut unavailable", isPresented: $showHotkeyError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That shortcut could not be registered. The previous shortcut is still active.")
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let md = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [md]
        }
        panel.directoryURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
            onChooseFile(url)
        }
    }
}

private struct FeatureSettingsView: View {
    @StateObject private var model = FeatureFlagsModel()

    var body: some View {
        Form {
            Section {
                Text("Turn any feature on or off. Minimal strips Drawer to just "
                     + "your task list (Today and carried-over). Everything turns "
                     + "it all back on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                            Text(flag.title)
                            Text(flag.blurb)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Controls").font(.headline)
                    controlRow("Hotkey (see General)", "show / hide the drawer")
                    controlRow("Esc", "hide, after clicking into the panel")
                    controlRow("+", "add a task to today's section")
                    controlRow("☰", "hide completed, unchecked first")
                    controlRow("⤡", "expand to full height / collapse")
                    controlRow("◯", "check off (writes to the file)")
                    controlRow("▶", "start the focus timer (top left)")
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

enum AppPaths {
    static let defaultDrawerFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents")
        .appendingPathComponent("My life/1 Projects/Drawer.md")
        .path

    /// The scratchpad lives in Application Support, out of the iCloud vault so
    /// it never shows up as a stray note.
    static var notesFile: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Drawer", isDirectory: true)
            .appendingPathComponent("notes.md")
    }
}
