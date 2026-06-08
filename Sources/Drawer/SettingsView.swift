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

            HelpView()
                .tabItem { Label("Help", systemImage: "questionmark.circle") }
        }
        .frame(width: 420, height: 460)
    }
}

private struct GeneralSettingsView: View {
    var onChooseFile: (URL) -> Void
    var onHotkeyChange: (HotkeyPreset) -> Bool
    var onLayoutChange: () -> Void

    @AppStorage("drawerFilePath") private var filePath = AppPaths.defaultDrawerFile
    @AppStorage("hotkeyPreset") private var hotkeyRaw = HotkeyPreset.ctrlOptSpace.rawValue
    @AppStorage("defaultMinutesText") private var defaultMinutes = "25"
    @AppStorage("completionSound") private var completionSound = true
    @AppStorage("panelWidth") private var panelWidth = 300.0
    @AppStorage("panelCompactHeight") private var panelHeight = 440.0
    @AppStorage("showTomorrow") private var showTomorrow = true
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var revertingHotkey = false
    @State private var showHotkeyError = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $themeRaw) {
                    ForEach(DrawerTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
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
                Toggle("Sound when timer ends", isOn: $completionSound)
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
                Toggle("Show Tomorrow section", isOn: $showTomorrow)
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

enum AppPaths {
    static let defaultDrawerFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents")
        .appendingPathComponent("My life/1 Projects/Drawer.md")
        .path
}
