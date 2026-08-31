import SwiftUI

struct DrawerConnectionView: View {
    let needsPermission: Bool
    let message: String?
    let chooseFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            Image("DrawerMark")
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
                .padding(.bottom, 30)

            Text(needsPermission ? "Reconnect your drawer." : "Your day is already a file.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .tracking(-0.8)

            Text(needsPermission
                 ? "iOS lost access to the file. Choose the same Drawer.md again and everything picks up where it left off."
                 : "Choose Drawer.md from On My iPhone, iCloud Drive, or the Files location your vault uses. Drawer edits that file in place — no account, import, or second database.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 14)
                .padding(.horizontal, 12)

            if let message, !message.isEmpty {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)
            }

            Button(action: chooseFile) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                    Text(needsPermission ? "Choose Drawer.md Again" : "Choose Drawer.md")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(.tint, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.985))
            .padding(.top, 30)

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
}
