import DrawerCore
import SwiftUI

/// Light-bulb capture. First line is the title, the rest the body. Park saves
/// the idea to the board and the note drives off to the left, toward the drawer.
struct IdeaCaptureBar: View {
    @ObservedObject var store: BoardStore
    var reduceMotion: Bool
    var onDone: () -> Void

    @Environment(\.drawerTheme) private var theme
    @State private var text = ""
    @State private var parking = false   // the car is mounted
    @State private var driving = false   // animate it (and the note) away
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            card
                .offset(x: driving ? -340 : 0)
                .opacity(driving ? 0 : 1)
                .scaleEffect(driving ? 0.5 : 1, anchor: .leading)

            if parking {
                CarBadge()
                    .frame(width: 46, height: 22)
                    .offset(x: driving ? -300 : 6)
                    .opacity(driving ? 0 : 1)
            }
        }
        .onAppear { focused = true }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Jot an idea. First line is the title.")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .frame(height: 78)
                    .font(theme.usesXPChrome
                          ? FontLoader.xpFont(size: 13)
                          : .system(size: 13))
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { reset() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button(action: park) {
                    Text("Park ◂")
                        .font(theme.usesXPChrome
                              ? FontLoader.xpFont(size: 12, weight: .semibold)
                              : .system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if theme.usesXPChrome {
                                XPRaisedPanel()
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(.tint)
                            }
                        }
                        .foregroundStyle(theme.usesXPChrome ? Palette.xpInk : Palette.onAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background {
            if theme.usesXPChrome {
                XPSunkenPanel()
            } else {
                RoundedRectangle(cornerRadius: 11).fill(.quaternary.opacity(0.65))
            }
        }
    }

    private func park() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { reset(); return }
        let parts = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        store.addText(
            title: String(parts.first ?? ""),
            body: parts.count > 1 ? String(parts[1]) : ""
        )

        guard !reduceMotion else { reset(); return }
        parking = true                          // car sits at rest first
        DispatchQueue.main.async {              // next tick so the drive-off animates
            withAnimation(.easeIn(duration: 0.55)) { driving = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { reset() }
    }

    private func reset() {
        text = ""
        parking = false
        driving = false
        onDone()
    }
}

/// A tiny stylized car for the parking animation.
private struct CarBadge: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.35, style: .continuous)
                    .fill(.tint)
                    .frame(width: w, height: h * 0.62)
                Circle().fill(.black.opacity(0.7))
                    .frame(width: h * 0.34, height: h * 0.34)
                    .offset(x: -w * 0.26, y: h * 0.26)
                Circle().fill(.black.opacity(0.7))
                    .frame(width: h * 0.34, height: h * 0.34)
                    .offset(x: w * 0.26, y: h * 0.26)
            }
        }
    }
}
