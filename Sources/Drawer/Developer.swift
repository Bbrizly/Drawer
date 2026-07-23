import AppKit
import SwiftUI

/// The switch for the Developer section in Settings, Advanced.
///
/// True: the sliders show, and the numbers you drag are saved and used by the
/// running app, so you can feel a change straight away.
///
/// False: the section is gone and every saved number is ignored, so the app
/// behaves exactly as the values written in the code say. Flip it before a
/// release and nobody but you ever sees the knobs.
enum DevTools {
    static let enabled = true
}

/// A cubic ease, the four control points Core Animation wants.
struct DevCurve: Codable, Equatable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    var timing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
    }
}

/// Every hand-picked number the Developer sliders can move, with the value the
/// code ships as its default. Nothing here is a user setting: these are the
/// choices behind how the app feels, parked somewhere you can drag them.
struct DevTuning: Codable, Equatable {
    /// The drawer drawing in the first run walkthrough.
    var mark = MarkMotion.standard
    /// How long one walkthrough step takes to slide to the next.
    var stepSeconds: TimeInterval = 0.22
    /// The panel sliding in from the left edge.
    var slideIn = DevCurve(x1: 0.16, y1: 1, x2: 0.3, y2: 1)
    /// And sliding back out.
    var slideOut = DevCurve(x1: 0.4, y1: 0, x2: 1, y2: 1)

    static let standard = DevTuning()
}

/// What the running app reads. Saved as one blob, so a new knob never means a
/// new defaults key.
///
/// With `DevTools.enabled` off this always holds the shipped values and never
/// writes anything, so a build a stranger runs cannot be carrying tuning left
/// over from your machine.
@MainActor
final class DevTuningStore: ObservableObject {
    static let shared = DevTuningStore()
    private static let key = "devTuning"

    @Published var tuning: DevTuning {
        didSet {
            guard DevTools.enabled, tuning != oldValue else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(tuning), forKey: Self.key)
        }
    }

    private init() {
        if DevTools.enabled,
           let saved = UserDefaults.standard.data(forKey: Self.key),
           let tuned = try? JSONDecoder().decode(DevTuning.self, from: saved) {
            tuning = tuned
        } else {
            tuning = .standard
        }
    }

    /// Back to the numbers written in the code.
    func reset() {
        tuning = .standard
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

// MARK: - Back into the code

/// Short and readable: 144, not 144.00.
private func plain(_ value: Double) -> String {
    let rounded = (value * 100).rounded() / 100
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
}

extension DevTuning {
    /// The Swift to paste back over the defaults, with the file each block
    /// belongs to. This is the whole point of the sliders: they find the
    /// numbers, the code keeps them.
    var swiftSource: String {
        """
        // Onboarding.swift, MarkMotion
        var size: CGFloat = \(plain(mark.size))
        var distance: CGFloat = \(plain(mark.distance))
        var cycles: CGFloat = \(plain(mark.cycles))
        var duration: TimeInterval = \(plain(mark.duration))
        var tilt: Double = \(plain(mark.tilt))
        var punch: CGFloat = \(plain(mark.punch))
        var driftBy: CGFloat = \(plain(mark.driftBy))
        var driftSeconds: TimeInterval = \(plain(mark.driftSeconds))

        // Onboarding.swift, OnboardingView.go
        withAnimation(.easeInOut(duration: \(plain(stepSeconds)))) { step = next }

        // PanelController.swift
        static let showTiming = CAMediaTimingFunction(
            controlPoints: \(plain(slideIn.x1)), \(plain(slideIn.y1)), \
        \(plain(slideIn.x2)), \(plain(slideIn.y2)))
        static let hideTiming = CAMediaTimingFunction(
            controlPoints: \(plain(slideOut.x1)), \(plain(slideOut.y1)), \
        \(plain(slideOut.x2)), \(plain(slideOut.y2)))
        """
    }
}

// MARK: - The section in Settings

/// The knob board. Drag a slider and the thing it drives changes as you drag.
/// When a set of numbers feels right, "Copy Swift" puts them on the clipboard
/// ready to paste over the defaults in the code.
struct DeveloperSettings: View {
    @ObservedObject private var store = DevTuningStore.shared
    @State private var open = false
    @State private var presses = 0
    @State private var copied = false

    private var tuning: Binding<DevTuning> { $store.tuning }

    var body: some View {
        Section("Developer") {
            SettingsCaption(
                "Not user settings. These are the numbers behind how the app feels, "
                + "live so they can be tuned by eye. Copy Swift writes them out to "
                + "paste into the code, and DevTools.enabled hides all of this."
            )
        }
        Section("Walkthrough drawer") {
            VStack(spacing: 12) {
                DrawerMark(open: open, shakes: presses)
                    // Room for the size slider at its top, and no more: the
                    // sliders have to stay on screen with the drawer.
                    .frame(height: 210)
                HStack(spacing: 10) {
                    Button("Knock") { knock() }
                        .buttonStyle(.borderedProminent)
                    Text(open ? "Open" : "Shut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            // The walkthrough window is 620 by 580, so past 200 the drawer
            // starts crowding the words under it.
            slider("Size", tuning.mark.size, 60...200, step: 2)
            slider("Throw", tuning.mark.distance, 0...60, step: 1)
            slider("Swings", tuning.mark.cycles, 0.5...8, step: 0.5)
            slider("Time", tuning.mark.duration, 0.05...1.5, step: 0.01)
            slider("Tilt", tuning.mark.tilt, 0...30, step: 1)
            slider("Squash", tuning.mark.punch, 0.6...1, step: 0.01)
            slider("Float by", tuning.mark.driftBy, 0...30, step: 1)
            slider("Float time", tuning.mark.driftSeconds, 0.5...8, step: 0.1)
            SettingsCaption(
                "The drawer on the first three walkthrough steps. Knock is one press "
                + "of the shortcut: the picture cuts, the drawer swings."
            )
        }
        Section("Walkthrough paging") {
            slider("Step slide", tuning.stepSeconds, 0.05...0.8, step: 0.01)
            SettingsCaption("How long one walkthrough step takes to slide to the next.")
        }
        Section("Panel slide") {
            Text("Opening")
                .font(.caption)
                .foregroundStyle(.secondary)
            curve(tuning.slideIn)
            Text("Closing")
                .font(.caption)
                .foregroundStyle(.secondary)
            curve(tuning.slideOut)
            SettingsCaption(
                "The ease the drawer slides on. Four control points, the same shape a "
                + "design tool calls a cubic bezier. Press your shortcut to feel it; "
                + "the length of the slide is a real setting, under General, Panel."
            )
        }
        Section {
            HStack {
                Button(copied ? "Copied" : "Copy Swift") { copy() }
                Button("Reset") { store.reset() }
                Spacer()
            }
        }
    }

    private func knock() {
        open.toggle()
        presses += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.tuning.swiftSource, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    @ViewBuilder
    private func curve(_ value: Binding<DevCurve>) -> some View {
        slider("Out x", value.x1, 0...1, step: 0.01)
        slider("Out y", value.y1, 0...1.5, step: 0.01)
        slider("In x", value.x2, 0...1, step: 0.01)
        slider("In y", value.y2, 0...1.5, step: 0.01)
    }

    /// Name, slider, and the number that ends up in the code.
    @ViewBuilder
    private func slider<V: BinaryFloatingPoint>(
        _ name: String, _ value: Binding<V>, _ range: ClosedRange<V>, step: V.Stride
    ) -> some View where V.Stride: BinaryFloatingPoint {
        HStack {
            Text(name)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%g", Double(value.wrappedValue)))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
