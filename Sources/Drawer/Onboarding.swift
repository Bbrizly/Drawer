import AppKit
import SwiftUI

/// The first-run walkthrough. Three steps: learn the shortcut, put your files
/// somewhere you own, pick the features you want. It runs modally before the
/// rest of launch because every store built afterwards resolves a path this
/// decides.
@MainActor
enum Onboarding {
    static let doneKey = "didOnboard"

    static var needed: Bool {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return false }
        // Someone upgrading already has a file and a shortcut, so a first-run
        // walkthrough would be noise. The App Store build still asks, because
        // it has to get their files out of the hidden container either way.
        let existingInstall = FileManager.default.fileExists(atPath: AppPaths.drawerFile)
        return appStoreBuild ? !DataFolder.isSet : !existingInstall
    }

    static func runIfNeeded() {
        guard needed else {
            UserDefaults.standard.set(true, forKey: doneKey)
            return
        }
        run()
    }

    static func run() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
            // No close button on purpose: the App Store build needs a folder
            // out of this, and every step can be skipped from inside.
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView {
            UserDefaults.standard.set(true, forKey: doneKey)
            NSApp.stopModal()
            window.close()
        })
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
    }
}

private struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    @State private var hotkeyDone = false
    @AppStorage(AppPaths.dataFolderPathKey) private var dataFolderPath = ""

    private let lastStep = 2

    private var canContinue: Bool {
        switch step {
        case 0: return hotkeyDone
        // The sandbox cannot write a user folder it was never handed, so the
        // store build waits for the pick. The direct build can use its default.
        case 1: return !appStoreBuild || !dataFolderPath.isEmpty
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
        .background(.background)
    }

    @ViewBuilder
    private var steps: some View {
        switch step {
        case 0:
            HotkeyStep(done: $hotkeyDone)
                .transition(stepTransition)
        case 1:
            FilesStep()
                .transition(stepTransition)
        default:
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
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25))
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
        .background(.quaternary.opacity(0.35))
        .overlay(alignment: .top) { Divider() }
    }

    private func go(to next: Int) {
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }
}

/// Shared chrome so the three steps line up exactly as you page through them.
private struct StepFrame<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        // One VStack, so a short step sits centred and a tall one (the feature
        // list) grows into the same space instead of leaving a hole.
        VStack(spacing: 26) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            content
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 34)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Step 1, the shortcut

private struct HotkeyStep: View {
    @Binding var done: Bool

    @State private var binding = HotkeyBinding.saved
    @State private var monitor: Any?
    @State private var tapMonitor = RightCommandTapMonitor()
    @State private var trustPoll: Timer?
    @State private var waitingForTrust = false
    @State private var caughtRightCommand = false

    var body: some View {
        StepFrame(
            icon: "menubar.arrow.down.rectangle",
            title: "Drawer lives in your menu bar",
            subtitle: "It stays out of the way until you call it. One shortcut slides it out, "
                + "the same one puts it back."
        ) {
            VStack(spacing: 22) {
                keyCaps
                status
                if !appStoreBuild { rightCommandOption }
                Menu("Use a different shortcut") {
                    ForEach(HotkeyBinding.modifierPresets) { preset in
                        Button(preset.label) { pick(preset) }
                    }
                    ForEach(HotkeyBinding.singleKeyPresets) { preset in
                        Button(preset.label) { pick(preset) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: watchKeys)
        .onDisappear(perform: stopWatching)
    }

    private var keyCaps: some View {
        HStack(spacing: 8) {
            ForEach(Array(binding.parts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .frame(minWidth: 52, minHeight: 52)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.background.secondary)
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(done ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1.5)
                    )
            }
        }
        .scaleEffect(done ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: done)
    }

    @ViewBuilder
    private var status: some View {
        if done {
            Label(
                caughtRightCommand ? "That is the right Command tap. Both work." : "That is it. Try it any time.",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        } else if waitingForTrust {
            Label("Waiting for Accessibility. Turn Drawer on in the list, then tap right ⌘.", systemImage: "hourglass")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        } else {
            Text("Press it now.")
                .foregroundStyle(.secondary)
        }
    }

    /// The right-Command tap rides the Accessibility API, which the sandbox
    /// denies, so this whole option is direct-download only.
    @ViewBuilder
    private var rightCommandOption: some View {
        if !done, !waitingForTrust {
            Button("Or tap the right ⌘ key instead") { startRightCommand() }
                .buttonStyle(.link)
        }
    }

    private func pick(_ preset: HotkeyBinding) {
        binding = preset
        preset.save()
    }

    private func watchKeys() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard binding.matches(event) else { return event }
            succeed(rightCommand: false)
            return nil  // swallow it, the drawer is not built yet
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        trustPoll?.invalidate()
        trustPoll = nil
        tapMonitor.stop()
    }

    private func startRightCommand() {
        UserDefaults.standard.set(true, forKey: "rightCommandTapEnabled")
        AccessibilityPermission.prompt()
        AccessibilityPermission.openSettings()
        waitingForTrust = true
        // The grant lands in another process, so poll rather than guess when.
        trustPoll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                guard AccessibilityPermission.isTrusted else { return }
                trustPoll?.invalidate()
                trustPoll = nil
                tapMonitor.start { succeed(rightCommand: true) }
            }
        }
    }

    private func succeed(rightCommand: Bool) {
        guard !done else { return }
        caughtRightCommand = rightCommand
        waitingForTrust = false
        withAnimation(.easeOut(duration: 0.2)) { done = true }
    }
}

// MARK: - Step 2, where the files live

private struct FilesStep: View {
    @AppStorage(AppPaths.dataFolderPathKey) private var dataFolderPath = ""

    private var shown: String {
        dataFolderPath.isEmpty
            ? URL(fileURLWithPath: AppPaths.defaultDrawerFile).deletingLastPathComponent().path
            : dataFolderPath
    }

    var body: some View {
        StepFrame(
            icon: "folder",
            title: "Your tasks are plain files",
            subtitle: "Drawer keeps a markdown file per day heading, nothing locked away. "
                + "Put it inside your Obsidian vault if you keep one: it stays readable to "
                + "you, to Obsidian, and to any AI you point at it."
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

// MARK: - Step 3, curate

private struct FeaturesStep: View {
    @StateObject private var model = FeatureFlagsModel()
    @State private var preset: String?

    var body: some View {
        StepFrame(
            icon: "slider.horizontal.3",
            title: "Curate it to how you work",
            subtitle: "Drawer ships with the useful things on. Turn off what you do not want. "
                + "All of this lives in Settings later too."
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    presetButton("Minimal", "Just the list") { model.applyMinimal() }
                    presetButton("Recommended", "The defaults") { model.applyDefaults() }
                    presetButton("Everything", "All of it") { model.applyEverything() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(FeatureFlag.groupsInOrder, id: \.self) { group in
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
                    .fill(preset == title ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(preset == title ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
