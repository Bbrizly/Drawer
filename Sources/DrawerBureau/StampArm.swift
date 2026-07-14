import AppKit
import SwiftUI

/// The two stamps (spec "The stamp"): green DONE files the task, red
/// POSTPONED sends the receipt back to the pile.
enum StampKind {
    case done
    case postponed

    var label: String {
        switch self {
        case .done: return BureauCopy.doneStampLabel
        case .postponed: return BureauCopy.postponedStampLabel
        }
    }

    var color: NSColor {
        switch self {
        case .done: return BureauPalette.stampGreen
        case .postponed: return BureauPalette.red
        }
    }
}

/// The stamp mechanism. Subtlety is the point (spec "The stamp"): the summon
/// buttons fade in ONLY while a live sticky sits in the right-edge zone of its
/// screen AND the cursor is also on the right side; otherwise the mechanism
/// does not exist. Pressing one runs the arm: sweep in from the right, pass the
/// rest point by `overshootPx`, ease back, settle with a small shiver, slam,
/// ink, thunk, haptic, then hand the consequence to the facade.
@MainActor
final class StampController {
    /// The right-edge band (fraction of screen width) that arms the mechanism.
    /// ponytail: fixed fraction, not tuned; the tunables are the arm keyframes.
    static let zoneFraction: CGFloat = 0.25

    /// Set by the facade: the live sticky windows to watch.
    var stickyFrames: (() -> [(id: UUID, frame: NSRect)])?
    /// Set by the facade: the slam landed (show ink, thunk, haptic).
    var onSlam: ((UUID, StampKind) -> Void)?
    /// Set by the facade: the ritual finished, apply the consequence.
    var onStamp: ((UUID, StampKind) -> Void)?
    /// Set by the facade: live tuning for the arm keyframes.
    var tuningProvider: (() -> BureauStampTuning)?

    private var timer: Timer?
    private var summon: NSPanel?
    private var summonID: UUID?
    private var armPanel: NSPanel?
    private var firing = false

    /// Watches for the summon condition while any sticky is live.
    /// ponytail: a 4Hz poll of frames + cursor, zero timers when no stickies;
    /// swap for a mouseMoved monitor if the fade-in ever feels late.
    func setWatching(_ watching: Bool) {
        if watching, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else if !watching {
            timer?.invalidate()
            timer = nil
            hideSummon()
        }
    }

    private func tick() {
        guard !firing else { return }
        guard let candidate = armedSticky() else {
            hideSummon()
            return
        }
        if summonID != candidate.id { showSummon(for: candidate) }
    }

    /// The sticky the mechanism should offer itself to: one whose center sits
    /// in the right-edge zone of its screen while the cursor is also in that
    /// zone. `nil` means the stamp stays nonexistent.
    private func armedSticky() -> (id: UUID, frame: NSRect)? {
        guard let frames = stickyFrames?(), !frames.isEmpty else { return nil }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else { return nil }
        let zoneMinX = screen.frame.maxX - screen.frame.width * Self.zoneFraction
        guard mouse.x >= zoneMinX else { return nil }
        return frames.first { $0.frame.midX >= zoneMinX }
    }

    // MARK: summon buttons

    private func showSummon(for sticky: (id: UUID, frame: NSRect)) {
        hideSummon()
        let size = CGSize(width: 44, height: 92)
        guard let screen = NSScreen.main else { return }
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - size.width - 4,
            y: min(max(sticky.frame.midY - size.height / 2, screen.visibleFrame.minY),
                   screen.visibleFrame.maxY - size.height)
        )
        let panel = makeOverlayPanel(frame: NSRect(origin: origin, size: size))
        let id = sticky.id
        let view = StampSummonView(
            fire: { [weak self] kind in self?.fire(id, kind) }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
        summon = panel
        summonID = id
    }

    private func hideSummon() {
        summon?.orderOut(nil)
        summon = nil
        summonID = nil
    }

    // MARK: the arm

    private func fire(_ id: UUID, _ kind: StampKind) {
        guard !firing, let frames = stickyFrames?(),
              let sticky = frames.first(where: { $0.id == id }),
              let screen = NSScreen.main
        else { return }
        firing = true
        hideSummon()

        let tuning = tuningProvider?() ?? BureauTuningDocument.defaults.stamp
        // The arm strip: from the sticky's right edge to the screen edge, tall
        // enough for the stamp head, riding at the sticky's vertical center.
        let height: CGFloat = 72
        let frame = NSRect(
            x: sticky.frame.midX,
            y: sticky.frame.midY - height / 2,
            width: max(80, screen.frame.maxX - sticky.frame.midX),
            height: height
        )
        let panel = makeOverlayPanel(frame: frame)
        panel.contentView = NSHostingView(rootView: StampArmView(
            kind: kind,
            tuning: tuning,
            travel: frame.width,
            onSlam: { [weak self] in self?.onSlam?(id, kind) },
            onFinished: { [weak self] in
                self?.armPanel?.orderOut(nil)
                self?.armPanel = nil
                self?.firing = false
                self?.onStamp?(id, kind)
            }
        ))
        panel.orderFrontRegardless()
        armPanel = panel
    }

    private func makeOverlayPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // One above the stickies so the arm passes over the note it stamps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        return panel
    }
}

/// The two summon buttons, stacked, in the Bureau palette.
private struct StampSummonView: View {
    var fire: (StampKind) -> Void

    var body: some View {
        VStack(spacing: 6) {
            stampButton(.done)
            stampButton(.postponed)
        }
        .padding(4)
    }

    private func stampButton(_ kind: StampKind) -> some View {
        Button(action: { fire(kind) }) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: kind.color))
                .frame(width: 36, height: 38)
                .overlay(
                    // A stamp seen from the side: handle knob over the die.
                    VStack(spacing: 2) {
                        Circle()
                            .fill(Color(nsColor: BureauPalette.ink).opacity(0.35))
                            .frame(width: 10, height: 10)
                        Rectangle()
                            .fill(Color(nsColor: BureauPalette.ink).opacity(0.35))
                            .frame(width: 22, height: 8)
                    }
                )
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(kind.label)
    }
}

/// The arm itself: a shaft with a stamp head that sweeps in from the right,
/// overshoots its rest point, eases back, shivers, slams, and retracts. All
/// four keyframe values come from tuning (spec "The stamp").
private struct StampArmView: View {
    let kind: StampKind
    let tuning: BureauStampTuning
    let travel: CGFloat
    var onSlam: () -> Void
    var onFinished: () -> Void

    /// Head offset from the contact point; starts a full travel off right.
    @State private var offset: CGFloat = 0
    @State private var slammed = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Head: the die face pointing left at the sticky.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: kind.color))
                    .frame(width: 34, height: slammed ? 44 : 40)
                // Shaft reaching back off the right edge.
                Rectangle()
                    .fill(Color(nsColor: BureauPalette.ink).opacity(0.6))
                    .frame(width: geo.size.width, height: 10)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .offset(x: offset)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
        .allowsHitTesting(false)
        .task { await run() }
    }

    private func run() async {
        offset = travel
        let inSeconds = max(0.01, tuning.armInMs / 1000)
        let settleSeconds = max(0.01, tuning.settleMs / 1000)

        // Sweep in past the rest point (the overshoot carries the weight).
        withAnimation(.easeIn(duration: inSeconds)) { offset = -CGFloat(tuning.overshootPx) }
        try? await Task.sleep(for: .seconds(inSeconds))

        // The slam lands at full extension: ink, thunk, haptic.
        slammed = true
        onSlam()
        try? await Task.sleep(for: .seconds(Double(max(1, tuning.slamFrames)) / 60))

        // Ease back right to rest, then the little left-right shiver.
        withAnimation(.easeOut(duration: settleSeconds)) { offset = 0 }
        try? await Task.sleep(for: .seconds(settleSeconds))
        let shiver = CGFloat(tuning.shiverPx)
        for i in 0..<max(0, tuning.shiverCount) {
            let dx = (i.isMultiple(of: 2) ? shiver : -shiver)
            withAnimation(.linear(duration: 0.04)) { offset = dx }
            try? await Task.sleep(for: .seconds(0.04))
        }
        withAnimation(.linear(duration: 0.04)) { offset = 0 }
        try? await Task.sleep(for: .seconds(0.2))

        // Retract and hand over.
        withAnimation(.easeIn(duration: inSeconds)) { offset = travel }
        try? await Task.sleep(for: .seconds(inSeconds))
        onFinished()
    }
}
