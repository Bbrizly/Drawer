import AppKit
import SwiftUI

/// The hidden tuning panel (spec "Tuning system"): a floating window of
/// sliders bound live to `bureau-tuning.json`, opened by a long-press on the
/// mode button. A game-dev feel workflow: drag until it feels right, the json
/// remembers.
///
/// Bassam wanted full control, so every feel and layout number gets a control
/// here. The one thing left to a hand edit is the transition easing curve (a
/// 4-point cubic bezier, not slider-shaped), noted in the caption.
@MainActor
final class BureauTuningPanel {
    private var panel: NSPanel?

    func toggle(tuning: BureauTuning) {
        if let panel {
            panel.orderOut(nil)
            self.panel = nil
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 620),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Bureau tuning"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: BureauTuningControls(tuning: tuning))
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

/// The full slider panel body, split out from the floating `NSPanel` so both
/// the long-press panel and the Settings window embed the identical controls
/// (feedback 3: Bassam could not find the tuning, so it also lives in Settings).
public struct BureauTuningControls: View {
    @ObservedObject var tuning: BureauTuning

    public init(tuning: BureauTuning) {
        self.tuning = tuning
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Transition") {
                    slider("Push ms", \.transition.pushMs, 80...900)
                    slider("Reduce-motion ms", \.transition.reduceMotionCrossfadeMs, 40...600)
                }
                section("Physics") {
                    slider("Repulsion radius", \.physics.repulsionRadius, 20...240)
                    slider("Repulsion strength", \.physics.repulsionStrength, 1...40)
                    slider("Torque", \.physics.torque, 0...2)
                    slider("Friction", \.physics.friction, 0...1)
                    slider("Restitution", \.physics.restitution, 0...1)
                    slider("Linear damping", \.physics.linearDamping, 0...10)
                    slider("Angular damping", \.physics.angularDamping, 0...10)
                    slider("Gravity", \.physics.gravity, -12...0)
                    slider("Push scale", \.physics.pushScale, 0...0.1)
                    slider("Torque scale", \.physics.torqueScale, 0...0.01)
                    toggle("Rotation", \.physics.rotationEnabled)
                    slider("Max tilt deg", \.physics.maxTiltDeg, 0...180)
                    toggle("Papers collide", \.physics.papersCollide)
                }
                section("Rustle") {
                    slider("Gain", \.rustle.gain, 0...1)
                    slider("Velocity threshold", \.rustle.velocityThreshold, 0...1)
                    slider("Max volume", \.rustle.maxVolume, 0...1)
                    slider("Rate cap ms", \.rustle.rateCapMs, 0...800)
                    slider("Speed ref", \.rustle.speedRef, 40...600)
                }
                section("Print") {
                    slider("Step ms", \.print.stepMs, 10...160)
                    slider("Step px", \.print.stepPx, 1...20)
                    slider("Chatter volume", \.print.chatterVolume, 0...1)
                    slider("Ding volume", \.print.dingVolume, 0...1)
                    slider("Tear ms", \.print.tearMs, 20...600)
                    slider("Drop impulse", \.print.dropImpulse, 0...30)
                    slider("Queue stagger ms", \.print.queueStaggerMs, 0...800)
                    slider("Spread deg", \.print.spreadDeg, 0...180)
                    slider("Impulse variance", \.print.impulseVariance, 0...1)
                    slider("Print spin", \.print.spin, 0...1)
                }
                section("Stamp rack") {
                    slider("Rack width px", \.stamp.rackWidthPx, 120...320)
                    slider("Stamp size px", \.stamp.stampSizePx, 32...110)
                    slider("Extend ms", \.stamp.extendMs, 60...600)
                    slider("Press ms", \.stamp.pressMs, 30...400)
                    slider("Lift ms", \.stamp.liftMs, 30...400)
                    slider("Ink rotation min", \.stamp.inkRotationMinDeg, 0...12)
                    slider("Ink rotation max", \.stamp.inkRotationMaxDeg, 0...20)
                    slider("Double-strike px", \.stamp.doubleStrikeOffsetPx, 0...6)
                    slider("Thunk volume", \.stamp.thunkVolume, 0...1)
                    slider("Slide volume", \.stamp.slideVolume, 0...1)
                    toggle("Haptic", \.stamp.hapticEnabled)
                }
                section("Crumple") {
                    intSlider("Frames", \.crumple.frames, 1...16)
                    slider("Fly to tray ms", \.crumple.flyToTrayMs, 80...900)
                }
                section("Hover scroll") {
                    slider("Sensitivity", \.hoverScroll.sensitivity, 0.2...4)
                    slider("Inertia friction", \.hoverScroll.inertiaFriction, 0.5...0.99)
                    slider("Min delta", \.hoverScroll.minDelta, 0...4)
                    slider("Max velocity", \.hoverScroll.maxVelocity, 5...120)
                }
                section("Sticky") {
                    intSlider("Live cap", \.sticky.liveCap, 1...40)
                    intSlider("Subtask cap", \.sticky.subtaskVisibleCap, 1...20)
                    slider("Pull-out scale", \.sticky.pullOutScale, 1.0...2.5)
                    slider("Slip width", \.sticky.slipWidth, 60...160)
                    slider("Slip height", \.sticky.slipHeight, 90...240)
                    slider("Grow response", \.sticky.growSpringResponse, 0.1...0.8)
                    slider("Grow damping", \.sticky.growSpringDamping, 0.4...1.0)
                    slider("Grow start", \.sticky.growStart, 0.2...1.0)
                    slider("Clamp min visible", \.sticky.clampMinVisible, 10...120)
                    slider("Settle debounce ms", \.sticky.settleDebounceMs, 80...900)
                }
                section("Drawer") {
                    slider("Tray height frac", \.drawer.trayHeightFraction, 0.05...0.4)
                    slider("Tray min height", \.drawer.trayMinHeight, 20...100)
                    slider("Lip height px", \.drawer.lipHeightPx, 0...20)
                    slider("Tray slot spacing", \.drawer.traySlotSpacing, 8...60)
                    slider("Tray scale", \.drawer.trayScale, 0.2...1.0)
                    intSlider("Tray visible cap", \.drawer.trayVisibleCap, 1...20)
                    slider("Spawn tilt range", \.drawer.spawnRotationRange, 0...0.6)
                }
                section("Return drop") {
                    slider("Impulse", \.returnDrop.impulse, 0...12)
                    slider("Spin", \.returnDrop.spin, 0...1)
                }
                section("Shredder") {
                    slider("Width px", \.shredder.widthPx, 30...120)
                    slider("Shred ms", \.shredder.shredMs, 80...800)
                    slider("Volume", \.shredder.volume, 0...1)
                    slider("Overlay width px", \.shredder.overlayWidthPx, 100...320)
                    slider("Overlay height px", \.shredder.overlayHeightPx, 40...160)
                }
                section("Texture / tray") {
                    toggle("Re-render on edit only", \.texture.rerenderOnEditOnly)
                    toggle("Tray clears Monday", \.filedTray.clearsMonday)
                }
                Text("The transition easing curve stays a hand edit in bureau-tuning.json (a 4-point cubic bezier), hot-reloaded like everything else.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold())
            rows()
        }
    }

    private func slider(
        _ label: String,
        _ keyPath: WritableKeyPath<BureauTuningDocument, Double>,
        _ range: ClosedRange<Double>
    ) -> some View {
        let binding = Binding<Double>(
            get: { tuning.document[keyPath: keyPath] },
            set: { value in
                var doc = tuning.document
                doc[keyPath: keyPath] = value
                tuning.update(doc)
            }
        )
        return row(label, value: String(format: "%.3f", binding.wrappedValue)) {
            Slider(value: binding, in: range)
        }
    }

    private func intSlider(
        _ label: String,
        _ keyPath: WritableKeyPath<BureauTuningDocument, Int>,
        _ range: ClosedRange<Int>
    ) -> some View {
        let binding = Binding<Double>(
            get: { Double(tuning.document[keyPath: keyPath]) },
            set: { value in
                var doc = tuning.document
                doc[keyPath: keyPath] = Int(value.rounded())
                tuning.update(doc)
            }
        )
        return row(label, value: "\(tuning.document[keyPath: keyPath])") {
            Slider(value: binding, in: Double(range.lowerBound)...Double(range.upperBound),
                   step: 1)
        }
    }

    private func toggle(
        _ label: String,
        _ keyPath: WritableKeyPath<BureauTuningDocument, Bool>
    ) -> some View {
        let binding = Binding<Bool>(
            get: { tuning.document[keyPath: keyPath] },
            set: { value in
                var doc = tuning.document
                doc[keyPath: keyPath] = value
                tuning.update(doc)
            }
        )
        return HStack {
            Text(label).font(.caption).frame(width: 118, alignment: .leading)
            Toggle("", isOn: binding).labelsHidden()
            Spacer()
        }
    }

    private func row(_ label: String, value: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 118, alignment: .leading)
            control()
            Text(value)
                .font(.caption2.monospacedDigit())
                .frame(width: 46, alignment: .trailing)
        }
    }
}
