import SwiftUI

struct DrawerConnectionView: View {
    let needsPermission: Bool
    let waitingForProvider: Bool
    let message: String?
    let chooseFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            Image("DrawerMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.bottom, 24)

            Text(title)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .multilineTextAlignment(.center)
                .tracking(-0.8)

            Text(explanation)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 14)
                .padding(.horizontal, 12)

            if waitingForProvider {
                ProgressView()
                    .controlSize(.regular)
                    .padding(.top, 22)
                    .accessibilityLabel("Waiting for Drawer.md to become available")
            }

            if let message, !message.isEmpty {
                Label(
                    message,
                    systemImage: waitingForProvider ? "icloud.and.arrow.down" : "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
            }

            Button(action: chooseFile) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                    Text(buttonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(DrawerPalette.ink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .foregroundStyle(DrawerPalette.canvas)
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.985))
            .padding(.top, 24)

            Text("Markdown stays canonical. Local or cloud, Drawer never replaces it with a private task database.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Spacer(minLength: 56)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if waitingForProvider { return "Getting Drawer.md ready." }
        if needsPermission { return "Reconnect your drawer." }
        return "Your day is already a file."
    }

    private var explanation: String {
        if waitingForProvider {
            return "Files has granted access, but the selected cloud file isn't current on this iPhone yet. Drawer is bringing down the canonical copy and will open it automatically when it's safe to edit."
        }
        if needsPermission {
            return "iOS lost access to the file. Choose the same Drawer.md again and everything picks up where it left off."
        }
        return "Choose Drawer.md from On My iPhone, iCloud Drive, or the Files location your vault uses. Drawer edits that file in place — no account, import, or second database."
    }

    private var buttonTitle: String {
        if waitingForProvider { return "Choose a Different Drawer.md" }
        if needsPermission { return "Choose Drawer.md Again" }
        return "Choose Drawer.md"
    }
}
