import AppKit
import DrawerCore
import SwiftUI

/// The scrolling reader. White text on near-black, the way speech prompters
/// look, with the playback controls down the left edge. Reads the live notes
/// text, so edits in the drawer flow straight through.
struct TeleprompterView: View {
    @ObservedObject var store: NotesStore
    var onClose: () -> Void

    @AppStorage("teleprompterSpeed") private var speed = 45.0
    @AppStorage("teleprompterFontSize") private var fontSize = 34.0
    @State private var isPlaying = true
    @State private var scroll = TeleprompterScroll(speed: 45)
    @State private var rawContentHeight: Double = 0
    @State private var viewportHeight: Double = 0
    @State private var lastTick: Date?
    @State private var hostWindow: NSWindow?
    @State private var resizeBase: NSRect?

    private var displayText: String {
        store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Type in the notes pad and it scrolls here."
            : store.text
    }

    var body: some View {
        HStack(spacing: 0) {
            controls
            reader
        }
        .frame(minWidth: 420, minHeight: 160)
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) { resizeCorner }
        .background(HostWindowReader { hostWindow = $0 })
        // Spacebar toggles playback when the window is key.
        .background(
            Button("") { togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
                .hidden()
        )
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 18) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close teleprompter")
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: restart) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Back to top")

                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(Color.white, in: Circle())
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Pause (space)" : "Play (space)")
            }

            sliderBlock(
                label: "Speed",
                systemImage: "gauge.with.dots.needle.67percent",
                value: $speed, range: 12...160
            )
            sliderBlock(
                label: "Size",
                systemImage: "textformat.size",
                value: $fontSize, range: 18...72
            )

            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .frame(width: 124)
        .background(Color.white.opacity(0.05))
    }

    private func sliderBlock(
        label: String, systemImage: String,
        value: Binding<Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .labelStyle(.titleAndIcon)
            Slider(value: value, in: range)
                .controlSize(.mini)
                .tint(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Reader

    private var reader: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { timeline in
            GeometryReader { geo in
                Text(displayText)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(fontSize * 0.32)
                    .multilineTextAlignment(.leading)
                    // Take the full natural height so long notes never truncate.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .offset(y: 24 - scroll.offset)
                    .onAppear { viewportHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in viewportHeight = h }
                    .onChange(of: timeline.date) { _, now in advance(to: now) }
            }
            .clipped()
            .overlay(alignment: .top) {
                // The reading line: a faint marker for where the eye rests.
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 2)
                    .padding(.top, 24)
            }
        }
        .onPreferenceChange(ContentHeightKey.self) { rawContentHeight = $0 }
    }

    // MARK: Actions

    private func togglePlay() {
        isPlaying.toggle()
        lastTick = nil // resume cleanly, no jump
    }

    private func restart() {
        scroll.restart()
        lastTick = nil
    }

    private func advance(to now: Date) {
        guard isPlaying else { lastTick = now; return }
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0, dt < 1 else { return } // skip first frame and long stalls
        scroll.speed = speed
        scroll.viewportHeight = viewportHeight
        // Trailing slack equal to a viewport so the last line can reach the top.
        scroll.contentHeight = rawContentHeight + viewportHeight
        scroll.tick(dt)
    }

    // MARK: Resize

    private var resizeCorner: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard let window = hostWindow else { return }
                        let base = resizeBase ?? window.frame
                        if resizeBase == nil { resizeBase = window.frame }
                        // Keep the top edge pinned; grow right and down.
                        let topY = base.origin.y + base.height
                        let newW = max(420, base.width + value.translation.width)
                        let newH = max(160, base.height + value.translation.height)
                        window.setFrame(
                            NSRect(x: base.origin.x, y: topY - newH, width: newW, height: newH),
                            display: true
                        )
                    }
                    .onEnded { _ in resizeBase = nil }
            )
            .help("Drag to resize")
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}

/// Hands back the AppKit window hosting this SwiftUI view, so the resize corner
/// can move the panel directly.
private struct HostWindowReader: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
