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
    /// Which way the last move went, so Back slides back.
    @State private var forward = true
    @State private var hotkeyDone = false
    @State private var trusted = AccessibilityPermission.isTrusted
    @State private var askedForAccess = false
    /// What the mark above the steps is doing: shut or open, and how many good
    /// presses it has taken, which is what rattles it.
    @State private var drawerOpen = false
    @State private var presses = 0
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
            VStack(spacing: 0) {
                // The welcome is one block of mark and greeting, centred. Every
                // other step hangs from the top so its own content leads.
                if current == .welcome { Spacer(minLength: 0) }
                if showsMark {
                    DrawerMark(open: drawerOpen, shakes: presses)
                        .padding(.top, current == .welcome ? 0 : 24)
                }
                steps
                if current == .welcome { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 620, height: 580)
        .chromeThemed()
        .task {
            // One watcher for every step: the grant lands in another process,
            // and the user can flip it while looking at any of these screens.
            guard !appStoreBuild else { return }
            while !Task.isCancelled {
                trusted = AccessibilityPermission.isTrusted
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        // Until the shortcut lands once, the mark opens and shuts on its own.
        // That is the whole idea of the step in one picture, and it costs the
        // user nothing to watch. After that it only answers to their keys.
        .task(id: demoing) {
            guard demoing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                drawerOpen.toggle()
            }
        }
    }

    /// The last two steps drop the mark: their own content wants the page.
    private var showsMark: Bool {
        switch current {
        case .welcome, .access, .shortcut: return true
        case .files, .features: return false
        }
    }

    private var demoing: Bool { current == .shortcut && !hotkeyDone }

    @ViewBuilder
    private var steps: some View {
        switch current {
        case .welcome:
            WelcomeStep()
                .transition(stepTransition)
        case .access:
            AccessStep(trusted: trusted, asked: $askedForAccess)
                .transition(stepTransition)
        case .shortcut:
            HotkeyStep(done: $hotkeyDone, trusted: trusted,
                       drawerOpen: $drawerOpen, presses: $presses)
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
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
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
        // Set before the step changes: both the leaving and the arriving view
        // read this when SwiftUI builds their transitions.
        forward = next > step
        // Only a shortcut opens the drawer, so it is shut on every other step.
        if Self.order[min(next, lastStep)] != .shortcut { drawerOpen = false }
        withAnimation(.easeInOut(duration: DevTuningStore.shared.tuning.stepSeconds)) {
            step = next
        }
    }
}

/// Every number the knock is made of, in one place. These are the shipped
/// values. To find better ones, open Settings, Advanced, Developer: there is a
/// slider for each one and the mark reacts as you drag. When a set feels right,
/// hit "Copy Swift" and paste it over this struct.
struct MarkMotion: Codable, Equatable {
    /// How big the shut drawing is, in points.
    var size: CGFloat = 144
    /// How big the open drawing is. It carries a pulled-out drawer, so at the
    /// same frame the cube body reads smaller and off-centre. Its own size lets
    /// you match the two by eye, so the swap looks like one drawer opening, not
    /// two pictures of different size.
    var openSize: CGFloat = 168
    /// How far it throws sideways on the first swing, in points. Bigger reads
    /// heavier.
    var distance: CGFloat = 16
    /// How many times it crosses the middle before it stops. Around 2 is a
    /// knock, 5 is a buzz.
    var cycles: CGFloat = 2.5
    /// How long the whole thing takes, start to still.
    var duration: TimeInterval = 0.36
    /// How far it tips at full throw, in degrees. 0 is a flat slide.
    var tilt: Double = 6
    /// How much it squashes on the hit, then recovers. 1 is no squash.
    var punch: CGFloat = 0.93
    /// The idle drift: how far it rises and falls, and how slow.
    var driftBy: CGFloat = 5
    var driftSeconds: TimeInterval = 2.8

    static let standard = MarkMotion()
}

/// One knock: a sine that gets quieter until it is nothing. `animatableData`
/// counts presses, so the whole number is the resting state and the bit in
/// between is the swing. Nothing to reset and nothing to hold on to.
///
/// It has to be a GeometryEffect. A plain `.offset(x: mySine(t))` does not
/// work: SwiftUI would draw a straight line from the first offset to the last
/// one instead of following the curve. Only `animatableData` gets sampled
/// every frame.
struct Knock: GeometryEffect {
    var motion = MarkMotion.standard
    var animatableData: CGFloat = 0

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = animatableData - animatableData.rounded(.down)
        // Full throw at the start, nothing left at the end.
        let swing = sin(progress * .pi * 2 * motion.cycles) * (1 - progress)
        let squash = motion.punch + (1 - motion.punch) * progress
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        return ProjectionTransform(
            CGAffineTransform(translationX: middle.x + motion.distance * swing, y: middle.y)
                .rotated(by: motion.tilt * swing * .pi / 180)
                .scaledBy(x: squash, y: squash)
                .translatedBy(x: -middle.x, y: -middle.y)
        )
    }
}

/// Drawer's mark, open or shut, the same drawing the README uses. It sits
/// above the first three steps and never slides with them, so paging through
/// the walkthrough feels like one object you are getting to know.
struct DrawerMark: View {
    /// Which drawing to show. The shortcut step flips this. No fade: a drawer
    /// is open or it is shut, and the swap has to land on the same beat as the
    /// key.
    var open = true
    /// Counts presses. Every bump knocks it, like something inside slid.
    var shakes = 0
    /// Pass numbers to pin them. Leave it off and the mark follows the sliders
    /// in Settings, Advanced, Developer.
    var motion: MarkMotion?

    @ObservedObject private var store = DevTuningStore.shared
    /// Drives the slow idle drift. Flipped once on appear.
    @State private var adrift = false

    private var now: MarkMotion { motion ?? store.tuning.mark }

    var body: some View {
        art(open ? Self.openArt : Self.shutArt)
            .frame(width: open ? now.openSize : now.size, height: open ? now.openSize : now.size)
            // The swap is a cut, never a fade, and the size cuts with it. Both
            // the picture and its frame change on `open`, and this exempts them
            // from whatever animation the step change or the press is running,
            // so the drawer never slides from one size to the other.
            .animation(nil, value: open)
            .modifier(Knock(motion: now, animatableData: CGFloat(shakes)))
            // Ease out, so the first swing is the fast one. Try .linear here to
            // hear the raw sine, or a spring to let it overshoot on the way in.
            .animation(.easeOut(duration: now.duration), value: shakes)
            .offset(y: adrift ? -now.driftBy : now.driftBy)
            .animation(
                .easeInOut(duration: now.driftSeconds).repeatForever(autoreverses: true),
                value: adrift)
            // A repeating animation only starts when its value flips, so it has
            // to be stopped and started again to pick up retuned numbers.
            .task(id: now.driftBy + CGFloat(now.driftSeconds)) {
                adrift = false
                try? await Task.sleep(for: .milliseconds(20))
                adrift = true
            }
            .accessibilityLabel(open ? "Drawer, open" : "Drawer, shut")
    }

    private func art(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    private static let openArt = load("logo-open")
    private static let shutArt = load("logo-shut")

    private static func load(_ name: String) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let art = NSImage(contentsOf: url)
        else { return NSImage() }
        return art
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
    /// True on the steps with the mark above them, so the two do not drift
    /// apart. The rest sit in the middle of the page.
    var underMark = false
    @ViewBuilder var content: Content

    var body: some View {
        // One VStack, so a short step sits centred and a tall one (the feature
        // list) grows into the same space instead of leaving a hole.
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // Wide enough that a short second line is a phrase, not one
                    // stray word sitting on its own.
                    .frame(maxWidth: 460)
            }
            content
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(maxHeight: .infinity, alignment: underMark ? .top : .center)
    }
}

// MARK: - Step 1, hello

/// The mark above it does the talking, so this is only the two lines under it.
private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Welcome to Drawer")
                .font(.system(size: 32, weight: .semibold))
            Text("Today's tasks, one shortcut away.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
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
    /// Watched for the whole walkthrough by OnboardingView, so this only reads.
    let trusted: Bool
    @Binding var asked: Bool
    /// Set once the user has been sent to System Settings and the switch has
    /// not landed for a while, which on this Mac means a stale grant.
    @State private var stalled = false

    var body: some View {
        StepFrame(
            title: "Let Drawer see your keys",
            subtitle: "macOS keeps this behind a switch. Turn it on and a single key, "
                + "right \u{2318} or \u{2325}, can open the drawer from any app.",
            underMark: true
        ) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(trusted ? Color.green : Color.secondary)
                        .font(.system(size: 20))
                    Text(trusted ? "Drawer is allowed." : "Not allowed yet.")
                    Spacer(minLength: 12)
                    if !trusted {
                        Button(asked ? "Open it again" : "Open System Settings") { ask() }
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
                    if stalled {
                        stale
                    } else {
                        Text("Privacy & Security, then Accessibility. This window notices on its own.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: trusted)
        }
        // Restarts whenever the answer changes, so granting clears the hint.
        .task(id: asked && !trusted) {
            guard asked, !trusted else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { stalled = true }
        }
    }

    /// macOS ties the grant to the exact copy of the app it was given to. A
    /// rebuilt or replaced Drawer is a different copy, so the switch stays on
    /// while the new one is still shut out. Only removing the entry clears it.
    private var stale: some View {
        VStack(spacing: 8) {
            Text("Switch already on? Then macOS is holding an older copy of Drawer. "
                + "Select Drawer in that list, remove it with the minus button, then add "
                + "this one back with plus.")
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            Button("Show me Drawer in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
            .buttonStyle(.link)
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
    /// Live, so granting Accessibility on the step before (or in the middle of
    /// this one) clears the warning without a click.
    let trusted: Bool
    /// The mark above this step. Every good press slides it the other way, so
    /// the shortcut shows you what it does before there is a drawer to open.
    @Binding var drawerOpen: Bool
    /// Bumped on every good press, which is what rattles the mark.
    @Binding var presses: Int

    @State private var binding = HotkeyBinding.saved
    /// True while the whole shortcut is physically down, so the field lights up.
    @State private var held = false
    /// The modifiers down this instant, and whether the shortcut's own key is
    /// down. Between them every cap knows when it is under a finger.
    @State private var liveFlags: NSEvent.ModifierFlags = []
    @State private var keyIsDown = false
    @State private var recording = false
    @State private var modifiers: NSEvent.ModifierFlags = []
    @State private var rejected: String?
    @State private var recorder = HotkeyRecorder()
    @State private var monitor: Any?
    @State private var tapDetector = ModifierTapDetector()

    var body: some View {
        StepFrame(
            title: "Pick your shortcut",
            subtitle: "Click the keys and press what you want. One modifier on its own counts.",
            underMark: true
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
                    .strokeBorder(fieldEdge, lineWidth: recording || held ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        // No animation on the press. A key is down or it is not, and a fade in
        // between reads as lag.
        .animation(.easeOut(duration: 0.15), value: recording)
    }

    private var fieldEdge: Color {
        if recording || held { return theme.accent }
        return done ? .green : theme.primaryInk.opacity(0.12)
    }

    /// What the field shows: the live keys while recording, the saved shortcut
    /// otherwise. A press still waiting for its key gets a placeholder cap.
    private var caps: [String] {
        guard recording else { return binding.parts }
        return HotkeyBinding.modifierParts(modifiers) + ["?"]
    }

    private func keyCap(_ part: String) -> some View {
        let down = isDown(part)
        return Text(part)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(part == "?" ? .secondary : (down ? theme.accent : .primary))
            .frame(minWidth: 52, minHeight: 52)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(down ? AnyShapeStyle(theme.accent.opacity(0.16)) : AnyShapeStyle(.background.secondary))
                    .shadow(color: .black.opacity(down ? 0.05 : 0.18), radius: 3, y: down ? 0 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        down ? theme.accent : (self.done ? .green : Color.secondary.opacity(0.25)),
                        lineWidth: 1.5)
            )
            // Pressed keys sit a hair lower, the way a real one does.
            .offset(y: down ? 2 : 0)
    }

    /// One cap at a time: each lights under its own finger, the moment that key
    /// goes down. While recording every cap on screen is a key being held.
    private func isDown(_ part: String) -> Bool {
        if recording { return part != "?" }
        if binding.isModifierTap { return held }
        if part == binding.parts.last { return keyIsDown }
        return HotkeyBinding.modifierParts(liveFlags).contains(part)
    }

    @ViewBuilder
    private var status: some View {
        if let rejected {
            Label(rejected, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        } else if recording {
            Text(modifiers.isEmpty
                 ? "Press the keys you want. One modifier on its own counts."
                 : "Add a key, or let go to use \(HotkeyBinding.modifierParts(modifiers).joined()) on its own.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .multilineTextAlignment(.center)
        } else if done {
            Label("That is it. It works.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if binding.needsAccessibility, !trusted {
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
        modifiers = []
        held = false
        recording = true
        recorder.start(held: { modifiers = $0 }, capture: captured)
    }

    /// Ends the listening state and leaves the shortcut as it was.
    private func stopRecording() {
        recorder.stop()
        recording = false
        modifiers = []
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
        // A new shortcut has not been tried yet, so ask for it again, with the
        // drawer back the way it started.
        done = false
        drawerOpen = false
        held = false
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
            liveFlags = flags
            if binding.isModifierTap {
                trackTap(event, flags: flags)
            } else {
                // The modifiers of a combination, all down and nothing extra.
                held = !binding.eventFlags.isEmpty && flags == binding.eventFlags
            }
        case .keyDown:
            tapDetector.otherActivity()
            if binding.matches(event) {
                keyIsDown = true
                held = true
                succeed()
            }
        case .keyUp:
            if event.keyCode == UInt16(binding.keyCode) { keyIsDown = false }
            held = false
        default:
            break
        }
    }

    private func trackTap(_ event: NSEvent, flags: NSEvent.ModifierFlags) {
        guard let flag = binding.tapFlag, event.keyCode == UInt16(binding.keyCode) else {
            tapDetector.otherActivity()
            held = false
            return
        }
        if flags.contains(flag) {
            held = true
            tapDetector.down(at: event.timestamp)
        } else {
            held = false
            if tapDetector.up(at: event.timestamp) { succeed() }
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        held = false
        keyIsDown = false
        liveFlags = []
    }

    private func stopEverything() {
        stopWatching()
        recorder.stop()
    }

    /// A good press. It slides the mark the other way every single time, the
    /// way the real shortcut will, and marks the step done the first time.
    private func succeed() {
        drawerOpen.toggle()
        presses += 1
        // The third channel. Pixels alone never feel like anything.
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
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
            subtitle: "Markdown, in a folder you pick. Put it in your Obsidian vault and your tasks are just notes."
        ) {
            VStack(spacing: 16) {
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
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(what)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Anything that edits files can edit your day. Point Claude or ChatGPT at that folder and it adds tasks, ticks them off, and moves them to tomorrow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)

                if appStoreBuild, dataFolderPath.isEmpty {
                    Text("Pick a folder to carry on. Documents is a fine answer.")
                        .font(.callout)
                        .foregroundStyle(.orange)
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

// MARK: - Previews
//
// These only exist for Xcode's canvas. Open this package in Xcode (File, Open,
// pick Package.swift), put the cursor in here, and turn the canvas on with
// Option-Command-Return. Nothing below ships.

#if DEBUG

/// The mark on its own, both ways round.
#Preview("Mark") {
    HStack(spacing: 40) {
        DrawerMark(open: false)
        DrawerMark(open: true)
    }
    .padding(50)
}

/// The knob board. Drag a slider, hit Knock, feel it. When a set of numbers is
/// right, copy them into `MarkMotion` at the top of this file.
#Preview("Mark lab") {
    @Previewable @State var motion = MarkMotion.standard
    @Previewable @State var presses = 0
    @Previewable @State var slow = false

    VStack(spacing: 24) {
        DrawerMark(open: presses.isMultiple(of: 2), shakes: presses, motion: motion)
            // Slow motion: the only honest way to see what a 0.3s move does.
            .transaction { if slow { $0.animation = $0.animation?.speed(0.12) } }
            // Tall enough to hold the biggest the size slider goes.
            .frame(height: 300)

        HStack {
            Button("Knock") { presses += 1 }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            Toggle("Slow motion", isOn: $slow)
        }

        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            knob("size", $motion.size, 60...200)
            knob("distance", $motion.distance, 0...60)
            knob("cycles", $motion.cycles, 0.5...8)
            knob("duration", $motion.duration, 0.05...1.5)
            knob("tilt", $motion.tilt, 0...30)
            knob("punch", $motion.punch, 0.6...1)
            knob("drift by", $motion.driftBy, 0...30)
            knob("drift seconds", $motion.driftSeconds, 0.5...8)
        }
        .frame(width: 380)
    }
    .padding(40)
}

/// One row of the lab: name, slider, the number to copy back into the code.
@ViewBuilder
private func knob<V: BinaryFloatingPoint>(
    _ name: String, _ value: Binding<V>, _ range: ClosedRange<V>
) -> some View where V.Stride: BinaryFloatingPoint {
    GridRow {
        Text(name)
            .font(.caption)
            .gridColumnAlignment(.trailing)
        Slider(value: value, in: range)
        Text(String(format: "%.2f", Double(value.wrappedValue)))
            .font(.system(.caption, design: .monospaced))
            .frame(width: 44, alignment: .trailing)
    }
}

/// Every step of the walkthrough, paged from the canvas.
#Preview("Walkthrough") {
    @Previewable @State var step = 0

    VStack(spacing: 0) {
        OnboardingView(startStep: step) {}
            .id(step)
        Picker("Step", selection: $step) {
            ForEach(0..<OnboardingView.order.count, id: \.self) { Text("\($0)") }
        }
        .pickerStyle(.segmented)
        .padding(10)
    }
}

#endif
