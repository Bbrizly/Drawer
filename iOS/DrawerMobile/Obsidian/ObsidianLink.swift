import DrawerCore
import Foundation

struct ObsidianLink {
    let note: String

    static func first(in item: TodoItem) -> ObsidianLink? {
        first(in: item.title) ?? item.note.flatMap(first(in:))
    }

    static func first(in text: String) -> ObsidianLink? {
        guard let open = text.range(of: "[["),
              let close = text.range(of: "]]", range: open.upperBound..<text.endIndex)
        else { return nil }
        var target = String(text[open.upperBound..<close.lowerBound])
        if let pipe = target.firstIndex(of: "|") {
            target = String(target[..<pipe])
        }
        target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        return target.isEmpty ? nil : ObsidianLink(note: target)
    }

    func url(near drawerURL: URL?) -> URL? {
        guard let drawerURL else { return nil }
        // Drawer.md is expected to live in the vault root in the common setup.
        // If it doesn't, Obsidian still has a chance to resolve the file by
        // name; this is intentionally a hint, not a vault index.
        let vault = drawerURL.deletingLastPathComponent().lastPathComponent
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "file", value: note),
        ]
        return components.url
    }
}
