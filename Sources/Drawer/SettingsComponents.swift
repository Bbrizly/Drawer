import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsPathRow: View {
    let title: String
    let caption: String
    @Binding var storedPath: String
    let defaultPath: String
    /// The UserDefaults key behind `storedPath`, so the sandboxed App Store
    /// build can persist a security-scoped bookmark for the pick.
    let settingKey: String
    var pickKind: SettingsPickKind = .markdownFile

    private var effectivePath: String {
        storedPath.isEmpty ? defaultPath : storedPath
    }

    private var usesDefault: Bool { storedPath.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(effectivePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(2)
                if usesDefault {
                    Text("(default)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Button("Open") { open() }
                Button("Choose…") { choose() }
                if !usesDefault {
                    Button("Reset") { storedPath = "" }
                }
            }
            SettingsCaption(caption)
        }
    }

    private func open() {
        let url = URL(fileURLWithPath: effectivePath)
        if pickKind == .directory {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(url.deletingLastPathComponent())
            }
        } else if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func choose() {
        guard let picked = SettingsPickers.run(pickKind, startingAt: effectivePath) else { return }
        SandboxBookmarks.save(url: URL(fileURLWithPath: picked), forSetting: settingKey)
        storedPath = picked
    }
}

enum SettingsPickKind {
    case markdownFile
    case jsonlFile
    case directory
}

enum SettingsPickers {
    @discardableResult
    static func run(_ kind: SettingsPickKind, startingAt path: String) -> String? {
        switch kind {
        case .markdownFile:
            guard let md = UTType(filenameExtension: "md") else { return nil }
            return chooseFile(startingAt: path, types: [md])
        case .jsonlFile:
            guard let jsonl = UTType(filenameExtension: "jsonl") else { return nil }
            return chooseFile(startingAt: path, types: [jsonl])
        case .directory:
            return chooseDirectory(startingAt: path)
        }
    }

    private static func chooseFile(startingAt path: String, types: [UTType]) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = types
        panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    private static func chooseDirectory(startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        var isDir: ObjCBool = false
        let start = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            panel.directoryURL = start
        } else {
            panel.directoryURL = start.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
