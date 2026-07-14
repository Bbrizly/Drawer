import AppKit
import SwiftUI

/// The hidden tuning panel (spec "Tuning system"): a floating window of
/// sliders bound live to `bureau-tuning.json`, opened by a long-press on the
/// mode button. A game-dev feel workflow: drag until it feels right, the json
/// remembers.
///
/// ponytail: the feel-critical values get sliders; the long tail (volumes,
/// caps, flags) is a hand edit in the same hot-reloaded json.
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
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 480),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Bureau tuning"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: BureauTuningView(tuning: tuning))
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

private struct BureauTuningView: View {
    @ObservedObject var tuning: BureauTuning

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Transition") {
                    slider("Push ms", \.transition.pushMs, 80...900)
                }
                section("Physics") {
                    slider("Repulsion radius", \.physics.repulsionRadius, 20...240)
                    slider("Repulsion strength", \.physics.repulsionStrength, 1...40)
                    slider("Torque", \.physics.torque, 0...2)
                    slider("Gravity", \.physics.gravity, -12...0)
                }
                section("Print") {
                    slider("Step ms", \.print.stepMs, 10...160)
                    slider("Step px", \.print.stepPx, 1...20)
                    slider("Drop impulse", \.print.dropImpulse, 0...30)
                    slider("Queue stagger ms", \.print.queueStaggerMs, 0...800)
                }
                section("Stamp") {
                    slider("Arm in ms", \.stamp.armInMs, 40...600)
                    slider("Overshoot px", \.stamp.overshootPx, 0...60)
                    slider("Settle ms", \.stamp.settleMs, 20...500)
                    slider("Shiver px", \.stamp.shiverPx, 0...10)
                }
                section("Crumple") {
                    slider("Fly to tray ms", \.crumple.flyToTrayMs, 80...900)
                }
                section("Hover scroll") {
                    slider("Sensitivity", \.hoverScroll.sensitivity, 0.2...4)
                    slider("Inertia friction", \.hoverScroll.inertiaFriction, 0.5...0.99)
                }
                section("Sticky") {
                    slider("Pull-out scale", \.sticky.pullOutScale, 1.0...2.5)
                }
                section("Rustle") {
                    slider("Gain", \.rustle.gain, 0...1)
                }
                Text("Everything else lives in bureau-tuning.json, hot-reloaded.")
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
        return HStack {
            Text(label).font(.caption).frame(width: 118, alignment: .leading)
            Slider(value: binding, in: range)
            Text(String(format: "%.2f", binding.wrappedValue))
                .font(.caption2.monospacedDigit())
                .frame(width: 46, alignment: .trailing)
        }
    }
}
