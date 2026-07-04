import AppKit
import DrawerCore
import SwiftUI

/// SwiftUI wrapper around the layer-backed canvas. Pushes the store's items and
/// viewport into the NSView, and turns the view's callbacks back into store
/// mutations through the coordinator. Text is edited inline on the canvas, so
/// there is no SwiftUI editor here.
struct BoardCanvas: NSViewRepresentable {
    @ObservedObject var store: BoardStore
    /// Bumped by the header button to re-center the camera on the cards.
    var recenterRequests: Int = 0
    /// Clear backdrop so the panel's glass (and the desktop) shows through.
    var transparentBackground = false
    /// Arm the off-app Option-drag pan (only while the board is open + transparent).
    var globalPanEnabled = false
    /// Ruled-paper backdrop (Notebook theme).
    var paperBackground = false
    /// Bliss-style desktop (Windows XP theme).
    var xpBackground = false
    /// Color new cards start as (Settings default).
    var defaultCardColor: String?

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> BoardCanvasView {
        let view = BoardCanvasView()
        let coord = context.coordinator
        coord.view = view
        view.onMoveMany = { positions in store.setPositions(positions) }
        view.onBringToFront = { store.bringToFront($0) }
        view.onMoveAndResize = { id, rect, font in store.moveAndResize(id, to: rect, fontSize: font) }
        view.onCommitText = { id, title, body in store.updateText(id, title: title, body: body) }
        view.onSetColor = { id, key in store.setColor(id, key) }
        view.onAddText = { [weak coord] p in
            guard let coord, let view = coord.view else { return }
            // Double-click drops plain text (no colored card box). color: nil.
            let item = coord.store.addText(title: "", body: "", at: p, color: nil)
            view.setItems(coord.store.document.items) // realize the new text now
            view.beginInlineEdit(item.id)
        }
        view.onViewport = { store.setViewport($0) }
        view.onDeleteMany = { store.removeMany($0) }
        view.onDropText = { text, p in coord.dropText(text, at: p) }
        view.onDropImage = { data, p in coord.importImage(data, at: p) }
        view.thumbnailProvider = { item, done in coord.thumbnail(for: item, completion: done) }
        view.onUndo = { [weak store] in store?.undo() }
        view.onRedo = { [weak store] in store?.redo() }
        view.canUndo = { [weak store] in store?.canUndo ?? false }
        view.canRedo = { [weak store] in store?.canRedo ?? false }
        view.setItems(store.document.items)
        view.setViewport(store.document.viewport)
        view.setTransparent(transparentBackground)
        view.setPaper(paperBackground)
        view.setXPBackground(xpBackground)
        view.setGlobalPanEnabled(globalPanEnabled)
        view.defaultCardColor = defaultCardColor
        return view
    }

    func updateNSView(_ view: BoardCanvasView, context: Context) {
        view.setItems(store.document.items)
        view.setViewport(store.document.viewport)
        view.setTransparent(transparentBackground)
        view.setPaper(paperBackground)
        view.setXPBackground(xpBackground)
        view.setGlobalPanEnabled(globalPanEnabled)
        view.defaultCardColor = defaultCardColor
        if recenterRequests != context.coordinator.lastRecenter {
            context.coordinator.lastRecenter = recenterRequests
            view.recenter()
        }
    }

    @MainActor
    final class Coordinator {
        let store: BoardStore
        weak var view: BoardCanvasView?
        var lastRecenter = 0
        private let cache = ThumbnailCache()

        init(store: BoardStore) { self.store = store }

        func dropText(_ text: String, at point: CGPoint) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let parts = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let title = String(parts.first ?? "")
            let body = parts.count > 1 ? String(parts[1]) : ""
            store.addText(title: title, body: body, at: point)
        }

        func importImage(_ data: Data, at point: CGPoint) {
            let store = self.store
            let mediaDir = store.mediaDirectory
            // Persist + decode off the main thread, then hop back to the main
            // actor to mutate the store.
            DispatchQueue.global(qos: .userInitiated).async {
                guard let imported = try? ImageImporter.persist(data, into: mediaDir, now: Date()) else { return }
                let natural = CGSize(width: imported.naturalWidth, height: imported.naturalHeight)
                let display = Coordinator.displaySize(for: natural, maxEdge: 360)
                Task { @MainActor in
                    store.addImage(
                        file: imported.relativeFile,
                        naturalSize: natural,
                        displaySize: display,
                        at: point
                    )
                }
            }
        }

        func thumbnail(for item: BoardItem, completion: @escaping (CGImage?) -> Void) {
            guard let file = item.file else { completion(nil); return }
            let url = store.directory.appendingPathComponent(file)
            let maxPixel = Int(max(item.width, item.height) * 2)
            cache.thumbnail(file: url, maxPixel: maxPixel, completion: completion)
        }

        nonisolated private static func displaySize(for natural: CGSize, maxEdge: CGFloat) -> CGSize {
            guard natural.width > 0, natural.height > 0 else {
                return CGSize(width: maxEdge, height: maxEdge)
            }
            let longest = max(natural.width, natural.height)
            guard longest > maxEdge else { return natural }
            let scale = maxEdge / longest
            return CGSize(width: natural.width * scale, height: natural.height * scale)
        }
    }
}

/// Decodes downsampled thumbnails off the main thread and caches them. Never
/// decodes on the main thread or during a drag.
final class ThumbnailCache {
    private final class Box { let image: CGImage; init(_ i: CGImage) { image = i } }
    private let cache = NSCache<NSString, Box>()
    private let queue = DispatchQueue(label: "drawer.board.thumbs", qos: .userInitiated)

    func thumbnail(file: URL, maxPixel: Int, completion: @escaping (CGImage?) -> Void) {
        let key = "\(file.path)@\(maxPixel)" as NSString
        if let box = cache.object(forKey: key) { completion(box.image); return }
        queue.async { [weak self] in
            let image = ImageImporter.downsample(fileURL: file, maxPixelSize: maxPixel)
            DispatchQueue.main.async {
                if let image { self?.cache.setObject(Box(image), forKey: key) }
                completion(image)
            }
        }
    }
}
