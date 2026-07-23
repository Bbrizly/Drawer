import AppKit
import SwiftUI

/// The first-run walkthrough: hello, the permission behind a one-key shortcut,
/// the shortcut, where your files live, then the features you want. On first
/// run the rest of launch waits for it, because every store built afterwards
/// resolves a path this decides.
@MainActor
enum Onboarding {
    static let doneKey = "didOnboard"

    /// Held while the window is up, so it is not deallocated and a second call
    /// brings the same one forward.
    private static var window: NSWindow?

    static var needed: Bool {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return false }
        // Someone upgrading already has a file and a shortcut, so a first-run
        // walkthrough would be noise. The App Store build still asks, because
        // it has to get their files out of the hidden container either way.
        let existingInstall = FileManager.default.fileExists(atPath: AppPaths.drawerFile)
        return appStoreBuild ? !DataFolder.isSet : !existingInstall
    }

    /// Runs the walkthrough on a first launch, then calls `then`. Launch carries
    /// on inside that closure, so the stores below it read the folder the user
    /// just picked.
    static func runIfNeeded(then: @escaping () -> Void) {
        guard needed else {
            UserDefaults.standard.set(true, forKey: doneKey)
            then()
            return
        }
        run(onFinish: then)
    }

    /// Opens the walkthrough. Never modal: a nested modal loop started from a
    /// button in Settings leaves this window drawn but deaf, since the click
    /// that opened it is still being tracked by the window underneath.
    static func run(onFinish: (() -> Void)? = nil) {
        if let open = window, open.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            open.makeKeyAndOrderFront(nil)
            return
        }
        // First run has no close button: the App Store build needs a folder out
        // of it, and every step can be skipped from inside. A redo from
        // Settings is only a look, so that one closes.
        let firstRun = onFinish != nil
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
            styleMask: firstRun ? [.titled, .fullSizeContentView] : [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView {
            UserDefaults.standard.set(true, forKey: doneKey)
            window.close()
            onFinish?()
        })
        Self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Internal, not private, so the visual render test can shoot each step.
struct OnboardingView: View {
    let onFinish: () -> Void

    /// The walkthrough always opens on the first step; the visual render test
    /// passes a later one so it can shoot each screen.
    init(startStep: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: startStep)
    }

    @State private var step: Int
    @State private var hotkeyDone = false
    @State private var trusted = false
    @State private var askedForAccess = false
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
    @AppStorage(AppPaths.dataFolderPathKey) private var dataFolderPath = ""

    enum Step {
        case welcome, access, shortcut, files, features
    }

    /// The App Store build has no permission step: the sandbox denies the
    /// Accessibility API outright, so there is nothing to grant.
    static var order: [Step] {
        appStoreBuild
            ? [.welcome, .shortcut, .files, .features]
            : [.welcome, .access, .shortcut, .files, .features]
    }

    private var lastStep: Int { Self.order.count - 1 }
    private var current: Step { Self.order[min(step, lastStep)] }

    private var theme: DrawerTheme { DrawerTheme(rawValue: themeRaw) ?? .default }

    private var canContinue: Bool {
        switch current {
        // Granting is the point of the step, so it holds. Once the user has
        // been sent to System Settings they can move on either way: a
        // permission that sometimes wants a relaunch must not strand a launch.
        case .access: return trusted || askedForAccess
        // The sandbox cannot write to a folder it was never handed, so the
        // store build waits for the pick. The direct build has a default.
        case .files: return !appStoreBuild || !dataFolderPath.isEmpty
        // The shortcut step does not wait for a successful press: a
        // combination the system swallows first would never arrive, and that
        // is a dead end, not a lesson.
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            steps
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 620, height: 580)
        .chromeThemed()
    }

    @ViewBuilder
    private var steps: some View {
        switch current {
        case .welcome:
            WelcomeStep()
                .transition(stepTransition)
        case .access:
            AccessStep(trusted: $trusted, asked: $askedForAccess)
                .transition(stepTransition)
        case .shortcut:
            HotkeyStep(done: $hotkeyDone)
                .transition(stepTransition)
        case .files:
            FilesStep()
                .transition(stepTransition)
        case .features:
            FeaturesStep()
                .transition(stepTransition)
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { go(to: step - 1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? theme.accent : Color.secondary.opacity(0.25))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: step)
            Spacer()
            Button(step == lastStep ? "Start using Drawer" : "Continue") {
                if step == lastStep { onFinish() } else { go(to: step + 1) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        // A hair darker than the page, so the bar reads as a bar without
        // dropping a system gray onto the paper.
        .background(theme.primaryInk.opacity(0.05))
        .background(theme.chromeSurface)
        .overlay(alignment: .top) { Divider() }
    }

    private func go(to next: Int) {
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }
}

/// Drawer's own icon, the one in the Dock, at whatever size is asked for.
/// Never a stand-in glyph.
struct AppLogo: View {
    var size: CGFloat = 92

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    /// The bundled copy of the icon art, not the running app's icon: a test
    /// host or an unsigned run would hand back a generic folder, and a
    /// stand-in logo is worse than no walkthrough.
    private static let icon: NSImage = {
        if let url = Bundle.module.url(forResource: "app-icon", withExtension: "png"),
           let art = NSImage(contentsOf: url) {
            return art
        }
        return NSApp?.applicationIconImage ?? NSImage()
    }()
}

/// Shared chrome so the steps line up exactly as you page through them.
private struct StepFrame<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        // One VStack, so a short step sits centred and a tall one (the feature
        // list) grows into the same space instead of leaving a hole.
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            }
            content
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 34)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Step 1, hello

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            AppLogo(size: 124)
            VStack(spacing: 10) {
                Text("Welcome to Drawer")
                    .font(.system(size: 30, weight: .semibold))
                Text("Today's tasks, one shortcut away.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
    }
}

// The look picker, parked. It shipped as the first step and looked wrong
// there, so the walkthrough opens on the welcome instead. Settings still
// has the full theme grid under Appearance.
// // MARK: - Step 1, the look
//
// private struct ThemeStep: View {
//     @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
//
//     var body: some View {
//         StepFrame(
//             icon: "paintbrush",
//             title: "Pick a look",
//             subtitle: "Notebook is the one it ships with: ruled paper, pen ink, a red margin. "
//                 + "Tap another and the whole app follows, this window included."
//         ) {
//             // Three across, so the nine themes land as a tidy square.
//             LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
//                       spacing: 12) {
//                 ForEach(DrawerTheme.allCases) { theme in
//                     ThemeSwatch(theme: theme, selected: themeRaw == theme.id, height: 58)
//                         .onTapGesture {
//                             withAnimation(.snappy(duration: 0.2)) { themeRaw = theme.id }
//                         }
//                 }
//             }
//         }
//     }
// }

// MARK: - Step 2, the permission behind a one-key shortcut

/// macOS will not let any app watch the keyboard until you say so, and a
/// shortcut that is one modifier key on its own can only be caught that way.
/// Direct download only: the sandbox denies the whole API.
private struct AccessStep: View {
    @Environment(\.drawerTheme) private var theme
    @Binding var trusted: Bool
    @Binding var asked: Bool
    @State private var poll: Timer?

    var body: some View {
        StepFrame(
            title: "Let Drawer see your keys",
            subtitle: "macOS keeps this behind a switch. Turn it on and a single key, "
                + "right \u{2318} or \u{2325}, can open the drawer from any app."
        ) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(trusted ? Color.green : Color.secondary)
                        .font(.system(size: 20))
                    Text(trusted ? "Drawer is allowed." : "Not allowed yet.")
                    Spacer(minLength: 12)
                    if !trusted {
                        Button("Open System Settings") { ask() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
                .frame(width: 430)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.primaryInk.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(trusted ? .green : theme.primaryInk.opacity(0.12), lineWidth: 1)
                )
                if !trusted {
                    Text("Privacy & Security, then Accessibility. This window notices on its own.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
        }
        .onAppear {
            trusted = AccessibilityPermission.isTrusted
            // The grant lands in another process, so watch for it rather than
            // guess when. Common mode: the walkthrough animates over this.
            let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in trusted = AccessibilityPermission.isTrusted }
            }
            RunLoop.main.add(timer, forMode: .common)
            poll = timer
        }
        .onDisappear {
            poll?.invalidate()
            poll = nil
        }
    }

    private func ask() {
        asked = true
        AccessibilityPermission.prompt()
        AccessibilityPermission.openSettings()
    }
}

// MARK: - Step 3, the shortcut

private struct HotkeyStep: View {
    @Environment(\.drawerTheme) private var theme
    @Binding var done: Bool

    @State private var binding = HotkeyBinding.saved
    @State private var recording = false
    @State private var held: NSEvent.ModifierFlags = []
    @State private var rejected: String?
    /// True while the shortcut itself is physically down, so the caps light up
    /// under your fingers and you can see it land.
    @State private var pressing = false
    @State private var recorder = HotkeyRecorder()
    @State private var monitor: Any?
    @State private var tapDetector = ModifierTapDetector()

    var body: some View {
        StepFrame(
            title: "Pick your shortcut",
            subtitle: "Click the keys and press what you want. One modifier on its own counts."
        ) {
            VStack(spacing: 18) {
                field
                status
                Menu("Pick a ready-made one") {
                    if !appStoreBuild {
                        ForEach(HotkeyBinding.tapPresets) { preset in
                            Button("Tap \(preset.label)") { set(preset) }
                        }
                        Divider()
                    }
                    ForEach(HotkeyBinding.modifierPresets) { preset in
                        Button(preset.label) { set(preset) }
                    }
                    ForEach(HotkeyBinding.singleKeyPresets) { preset in
                        Button(preset.label) { set(preset) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.callout)
            }
        }
        .onAppear(perform: watchKeys)
        .onDisappear(perform: stopEverything)
    }

    /// Click it and it listens. Same shape either way, so the keys you press
    /// land where the old ones were.
    private var field: some View {
        Button { recording ? stopRecording() : startRecording() } label: {
            HStack(spacing: 8) {
                ForEach(Array(caps.enumerated()), id: \.offset) { _, part in
                    keyCap(part)
                }
                Spacer(minLength: 14)
                Text(recording ? "Esc to keep the old one" : "Click to change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 430)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.primaryInk.opacity(recording ? 0.08 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(fieldEdge, lineWidth: recording || pressing ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: pressing)
        .animation(.easeOut(duration: 0.15), value: recording)
    }

    private var fieldEdge: Color {
        if recording || pressing { return theme.accent }
        return done ? .green : theme.primaryInk.opacity(0.12)
    }

    /// What the field shows: the live keys while recording, the saved shortcut
    /// otherwise. A press still waiting for its key gets a placeholder cap.
    private var caps: [String] {
        guard recording else { return binding.parts }
        return HotkeyBinding.modifierParts(held) + ["?"]
    }

    private func keyCap(_ part: String) -> some View {
        Text(part)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(capInk(part))
            .frame(minWidth: 52, minHeight: 52)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(pressing ? AnyShapeStyle(theme.accent.opacity(0.16)) : AnyShapeStyle(.background.secondary))
                    .shadow(color: .black.opacity(pressing ? 0.05 : 0.18), radius: 3, y: pressing ? 0 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        pressing ? theme.accent : (done ? .green : Color.secondary.opacity(0.25)),
                        lineWidth: 1.5)
            )
            // Pressed keys sit a hair lower, the way a real one does.
            .offset(y: pressing ? 2 : 0)
    }

    private func capInk(_ part: String) -> Color {
        if part == "?" { return .secondary }
        return pressing ? theme.accent : .primary
    }

    @ViewBuilder
    private var status: some View {
        if let rejected {
            Label(rejected, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        } else if recording {
            Text(held.isEmpty
                 ? "Press the keys you want. One modifier on its own counts."
                 : "Add a key, or let go to use \(HotkeyBinding.modifierParts(held).joined()) on its own.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .multilineTextAlignment(.center)
        } else if done {
            Label("That is it. It works.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if binding.needsAccessibility, !AccessibilityPermission.isTrusted {
            Label("Works here, but needs Accessibility to work in other apps.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        } else {
            Text(binding.isModifierTap ? "Tap it now to try it." : "Press it now to try it.")
                .foregroundStyle(.secondary)
        }
    }

    private func startRecording() {
        stopWatching()
        rejected = nil
        held = []
        pressing = false
        recording = true
        recorder.start(held: { held = $0 }, capture: captured)
    }

    /// Ends the listening state and leaves the shortcut as it was.
    private func stopRecording() {
        recorder.stop()
        recording = false
        held = []
        watchKeys()
    }

    private func captured(_ candidate: HotkeyBinding) {
        // Esc backs out, the same way it does everywhere else on the Mac.
        if candidate.isEscape {
            rejected = nil
            stopRecording()
            return
        }
        // Keep listening on a bad one, so a stray key is not a dead end.
        if let problem = candidate.problem {
            rejected = problem
            return
        }
        rejected = nil
        stopRecording()
        set(candidate)
    }

    private func set(_ new: HotkeyBinding) {
        binding = new
        new.save()  // AppDelegate re-registers it off the defaults change
        // A new shortcut has not been tried yet, so ask for it again.
        done = false
        pressing = false
        rejected = nil
        watchKeys()
    }

    /// Watches our own window for the shortcut, so the press can be confirmed
    /// before macOS has been told to trust Drawer anywhere else.
    private func watchKeys() {
        stopWatching()
        tapDetector = ModifierTapDetector()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            handle(event)
            // Swallow a matching press: the drawer it would open is not built
            // yet on a first run.
            return binding.matches(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
            if binding.isModifierTap {
                trackTap(event, flags: flags)
            } else {
                // The modifiers of a combination, all down and nothing extra.
                pressing = !binding.eventFlags.isEmpty && flags == binding.eventFlags
            }
        case .keyDown:
            tapDetector.otherActivity()
            if binding.matches(event) {
                pressing = true
                succeed()
            }
        case .keyUp:
            pressing = false
        default:
            break
        }
    }

    private func trackTap(_ event: NSEvent, flags: NSEvent.ModifierFlags) {
        guard let flag = binding.tapFlag, event.keyCode == UInt16(binding.keyCode) else {
            tapDetector.otherActivity()
            pressing = false
            return
        }
        if flags.contains(flag) {
            pressing = true
            tapDetector.down(at: event.timestamp)
        } else {
            pressing = false
            if tapDetector.up(at: event.timestamp) { succeed() }
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pressing = false
    }

    private func stopEverything() {
        stopWatching()
        recorder.stop()
    }

    private func succeed() {
        guard !done else { return }
        withAnimation(.easeOut(duration: 0.2)) { done = true }
    }
}

// MARK: - Step 3, where the files live

private struct FilesStep: View {
    @AppStorage(AppPaths.dataFolderPathKey) private var dataFolderPath = ""

    private var shown: String {
        dataFolderPath.isEmpty
            ? URL(fileURLWithPath: AppPaths.defaultDrawerFile).deletingLastPathComponent().path
            : dataFolderPath
    }

    var body: some View {
        StepFrame(
            title: "Your tasks are plain files",
            subtitle: "Markdown, in a folder you own. Drop it in your Obsidian vault if you keep one."
        ) {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: dataFolderPath.isEmpty ? "questionmark.folder" : "checkmark.circle.fill")
                            .foregroundStyle(dataFolderPath.isEmpty ? Color.secondary : Color.green)
                        Text(shown)
                            .font(.callout)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button(dataFolderPath.isEmpty ? "Choose…" : "Change…") { DataFolder.choose() }
                    }
                    Divider()
                    ForEach(Self.files, id: \.0) { name, what in
                        HStack(spacing: 8) {
                            Text(name)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(what)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if appStoreBuild, dataFolderPath.isEmpty {
                    Text("Pick a folder to carry on. Documents is a fine answer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let files: [(String, String)] = [
        ("Drawer.md", "your tasks, one heading per day"),
        ("Notes.md", "the scratchpad in the header"),
        ("Ideas/", "the idea board and anything pasted onto it"),
        ("Parking lot.md", "loose ideas, if you turn the lot on"),
    ]
}

// MARK: - Step 4, curate

private struct FeaturesStep: View {
    @Environment(\.drawerTheme) private var theme
    @StateObject private var model = FeatureFlagsModel()
    @State private var preset: String?

    /// Settings leaves the timer flags out of its generic list because they
    /// have dedicated controls on another tab. Here they are just features, so
    /// put them back, first, and let Integrations (the MCP flag, which gates
    /// nothing in-app) stay out.
    private static let groups = ["Timers", "Focus"] + FeatureFlag.groupsInOrder

    var body: some View {
        StepFrame(
            title: "Make it yours",
            subtitle: "Turn off what you do not want. It is all in Settings later."
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    presetButton("Minimal", "Just the list") { model.applyMinimal() }
                    presetButton("Recommended", "The defaults") { model.applyDefaults() }
                    presetButton("Everything", "All of it") { model.applyEverything() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Self.groups, id: \.self) { group in
                            let flags = FeatureFlag.availableCases.filter { $0.group == group }
                            if !flags.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                    ForEach(flags) { flag in
                                        Toggle(isOn: model.binding(flag)) {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(flag.title)
                                                    .font(.callout)
                                                Text(flag.blurb)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                            // Without this the switch hugs the
                                            // label and every row lands at a
                                            // different x.
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .toggleStyle(.switch)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)
                // The list runs past the fold, so fade the last rows rather
                // than cutting a group in half on a hard edge.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.9),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
    }

    private func presetButton(_ title: String, _ blurb: String, action: @escaping () -> Void) -> some View {
        Button {
            preset = title
            action()
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(blurb).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(preset == title ? theme.accent.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(preset == title ? theme.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
