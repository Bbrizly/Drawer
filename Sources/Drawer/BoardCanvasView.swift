import AppKit
import DrawerCore
import QuartzCore

/// The fast layer-backed canvas. One CALayer per item, never a view. Every
/// geometry change is wrapped in a disabled-action CATransaction so dragging
/// and panning are instant with no implicit animation. contentsScale is pinned
/// to the screen so text and images stay crisp on Retina.
///
/// Text is edited inline: an NSTextView is laid over the card while editing, so
/// there is no separate window. The first line is the title, everything after
/// the first newline is the body.
final class BoardCanvasView: NSView, NSTextViewDelegate {
    // Reported back to the coordinator (which mutates the store).
    var onMoveMany: ([UUID: CGPoint]) -> Void = { _ in }
    var onBringToFront: (UUID) -> Void = { _ in }
    var onViewport: (BoardViewport) -> Void = { _ in }
    var onDropImage: (Data, CGPoint) -> Void = { _, _ in }
    var onDropText: (String, CGPoint) -> Void = { _, _ in }
    var onDeleteMany: (Set<UUID>) -> Void = { _ in }
    var onMoveAndResize: (UUID, CGRect, Double?) -> Void = { _, _, _ in }
    var onCommitText: (UUID, String, String) -> Void = { _, _, _ in }
    var onSetColor: (UUID, String) -> Void = { _, _ in }
    var onSetFontSize: (UUID, Double) -> Void = { _, _ in }
    /// Double-click on empty canvas: make a new text card here and edit it.
    var onAddText: (CGPoint) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var canUndo: () -> Bool = { false }
    var canRedo: () -> Bool = { false }
    /// Async thumbnail fetch for an image item.
    var thumbnailProvider: ((BoardItem, @escaping (CGImage?) -> Void) -> Void)?

    private let contentLayer = CALayer()
    private let paperLayer = CALayer()        // ruled paper, in content space so it pans/zooms with items
    private let handleLayer = CALayer()       // resize grip on the selected item
    private var itemLayers: [UUID: CALayer] = [:]
    private var imageFiles: [UUID: String] = [:]
    private var loadingThumbnails: Set<UUID> = []
    private var items: [BoardItem] = []
    private var viewport = BoardViewport()

    private var selectedIDs: Set<UUID> = []
    private var soleSelection: UUID? { selectedIDs.count == 1 ? selectedIDs.first : nil }
    private var moving = false                 // dragging the selected set
    private var moveLast = CGPoint.zero        // last board point during a move
    private var marqueeStart: CGPoint?         // drag-select rectangle origin
    private let marqueeLayer = CALayer()
    private var panning = false               // Option + drag pans the board
    private var resizeID: UUID?               // non-nil while dragging the grip
    private var resizeTop: CGFloat = 0        // fixed top edge during a resize
    private var resizeLeft: CGFloat = 0       // fixed left edge during a resize
    private let handleSize: CGFloat = 14

    private var editingID: UUID?
    private var editor: NSTextView?
    private var globalPanActive = false       // armed while the board is open
    private var globalPanMonitor: Any?
    private var magnifyMonitor: Any?
    private var keyboardMonitor: Any?
    private var transparentBg = false
    private var paperBg = false
    private var xpBg = false
    private var showingPaper: Bool { paperBg && !transparentBg && !xpBg }

    override var isFlipped: Bool { false }            // bottom-left, matches board space
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.boardDark.ns.cgColor
        layer?.masksToBounds = true // clip cards to the board, no bleed outside it
        contentLayer.anchorPoint = .zero
        contentLayer.bounds = CGRect(x: 0, y: 0, width: 8000, height: 8000)
        layer?.addSublayer(contentLayer)

        // Ruled lines live in content space (a big tiled layer under the items),
        // so they pan and zoom with the text instead of staying pinned behind it.
        paperLayer.anchorPoint = .zero
        paperLayer.bounds = CGRect(x: 0, y: 0, width: 40_000, height: 40_000)
        paperLayer.position = CGPoint(x: -20_000, y: -20_000)
        paperLayer.zPosition = -1_000_000 // under every item
        paperLayer.backgroundColor = NSColor(patternImage: Self.paperLineTile).cgColor
        paperLayer.isHidden = true
        contentLayer.addSublayer(paperLayer)

        handleLayer.bounds = CGRect(x: 0, y: 0, width: handleSize, height: handleSize)
        handleLayer.cornerRadius = handleSize / 2
        handleLayer.backgroundColor = NSColor.white.cgColor
        handleLayer.borderColor = NSColor.controlAccentColor.cgColor
        handleLayer.borderWidth = 2
        handleLayer.zPosition = 1_000_000
        handleLayer.isHidden = true
        contentLayer.addSublayer(handleLayer)

        marqueeLayer.borderColor = NSColor.controlAccentColor.cgColor
        marqueeLayer.borderWidth = 1
        marqueeLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        marqueeLayer.zPosition = 999_999
        marqueeLayer.isHidden = true
        contentLayer.addSublayer(marqueeLayer)

        registerForDraggedTypes([.png, .tiff, .fileURL, .string])
        applyTransform()
        installPanMonitors()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let globalPanMonitor { NSEvent.removeMonitor(globalPanMonitor) }
        if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pinContentsScale()
    }

    /// The panel resizes live while a swipe dials the board coverage. The
    /// content is anchored bottom-left, so without this a shrink clips the top
    /// of the board and nothing recovers until the next pan writes a viewport.
    /// Shift the viewport by half the size delta so the visual center holds
    /// through any resize, in either direction.
    override func setFrameSize(_ newSize: NSSize) {
        let old = frame.size
        super.setFrameSize(newSize)
        guard old.width > 0, old.height > 0, old != newSize else { return }
        viewport.x += (newSize.width - old.width) / 2
        viewport.y += (newSize.height - old.height) / 2
        applyTransform()
        // Persist after the layout pass; publishing a store change from inside
        // setFrameSize would re-enter the SwiftUI update that resized us.
        let v = viewport
        DispatchQueue.main.async { [weak self] in self?.onViewport(v) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        pinContentsScale()
    }

    private func pinContentsScale() {
        let s = scale
        layer?.contentsScale = s
        contentLayer.contentsScale = s
        paperLayer.contentsScale = s
        for l in itemLayers.values {
            l.contentsScale = s
            l.sublayers?.forEach { $0.contentsScale = s }
        }
    }

    // MARK: rendering

    /// Diff the incoming items against the current layers: create, update, drop.
    func setItems(_ newItems: [BoardItem]) {
        items = newItems
        let incoming = Set(newItems.map(\.id))

        for (id, layer) in itemLayers where !incoming.contains(id) {
            layer.removeFromSuperlayer()
            itemLayers[id] = nil
            imageFiles[id] = nil
            loadingThumbnails.remove(id)
        }

        for item in newItems {
            let layer = itemLayers[item.id] ?? makeLayer(for: item)
            configure(layer, for: item)
            if itemLayers[item.id] == nil {
                itemLayers[item.id] = layer
                contentLayer.addSublayer(layer)
            }
        }
        updateSelection()
    }

    func setViewport(_ v: BoardViewport) {
        viewport = v
        applyTransform()
    }

    func setTransparent(_ on: Bool) { transparentBg = on; updateBackground() }
    func setPaper(_ on: Bool) { paperBg = on; updateBackground() }
    func setXPBackground(_ on: Bool) {
        xpBg = on
        handleLayer.cornerRadius = on ? 0 : handleSize / 2
        handleLayer.borderColor = (on ? NSColor.black : NSColor.controlAccentColor).cgColor
        handleLayer.borderWidth = on ? 1 : 2
        marqueeLayer.borderColor = (on ? Palette.xpSelectionRGBA.ns : NSColor.controlAccentColor).cgColor
        marqueeLayer.backgroundColor = (on ? Palette.xpSelectionRGBA.ns : NSColor.controlAccentColor)
            .withAlphaComponent(on ? 0.18 : 0.12).cgColor
        updateBackground()
    }

    private func updateBackground() {
        let color: NSColor
        if transparentBg {
            color = Palette.hitClear.ns
        } else if xpBg {
            color = Palette.xpDesktopRGBA.ns
        } else if paperBg {
            color = Palette.paperFill.ns
        } else {
            color = Palette.boardDark.ns
        }
        layer?.backgroundColor = color.cgColor
        layer?.contents = nil
        paperLayer.isHidden = !showingPaper
        reinkText()
        refreshCardChrome()
    }

    /// Re-apply card fills and borders when the surface changes.
    private func refreshCardChrome() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in items {
            guard let layer = itemLayers[item.id] else { continue }
            applyCardChrome(to: layer, for: item)
        }
        CATransaction.commit()
    }

    /// Re-apply the adaptive ink to every text layer (called when the background
    /// changes, so white-on-dark text does not vanish on the light paper).
    private func reinkText() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in items where item.kind == .text {
            if let t = itemLayers[item.id]?.sublayers?.first(where: { $0.name == "text" }) as? CATextLayer {
                t.string = attributedText(for: item)
            }
        }
        CATransaction.commit()
    }

    /// A transparent tile with one blue rule line. Tiled on the content-space
    /// paperLayer so the lines pan and zoom with the text sitting on them. The
    /// cream fill is the board's own background, so only the lines move.
    private static let paperLineTile: NSImage = {
        let size = NSSize(width: 64, height: 28)
        let img = NSImage(size: size)
        img.lockFocus()
        Palette.paperLine.ns.setStroke()
        let line = NSBezierPath()
        line.lineWidth = 0.75
        line.move(to: NSPoint(x: 0, y: 0.5))
        line.line(to: NSPoint(x: size.width, y: 0.5))
        line.stroke()
        img.unlockFocus()
        return img
    }()

    private func makeLayer(for item: BoardItem) -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.cornerRadius = xpBg ? 0 : 12
        layer.contentsScale = scale
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = xpBg ? 0.45 : 0.32
        layer.shadowRadius = xpBg ? 0 : 7
        layer.shadowOffset = xpBg ? CGSize(width: 2, height: -2) : CGSize(width: 0, height: -2)
        if item.kind == .text {
            let text = CATextLayer()
            text.name = "text"
            text.contentsScale = scale
            text.isWrapped = true
            text.truncationMode = .end
            layer.addSublayer(text)
            if !xpBg {
                layer.backgroundColor = NSColor.clear.cgColor
                layer.shadowOpacity = 0
                layer.cornerRadius = 0
            }
        } else {
            let img = CALayer()
            img.name = "image"
            img.contentsScale = scale
            img.cornerRadius = xpBg ? 0 : 12
            img.masksToBounds = true
            img.backgroundColor = Palette.imageBackdrop.ns.cgColor
            layer.addSublayer(img)
        }
        return layer
    }

    private func applyCardChrome(to layer: CALayer, for item: BoardItem) {
        guard item.kind == .text else { return }
        if xpBg {
            let fill = item.color.map { Self.cardColor($0) } ?? Palette.xpStickyNote.ns
            layer.backgroundColor = fill.cgColor
            layer.borderWidth = 2
            layer.borderColor = Palette.xpBevelShadowRGBA.ns.cgColor
            layer.shadowOpacity = 0.45
            layer.cornerRadius = 0
        } else {
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderWidth = 0
            layer.shadowOpacity = 0
            layer.cornerRadius = 0
        }
    }

    private func configure(_ layer: CALayer, for item: BoardItem) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(x: 0, y: 0, width: item.width, height: item.height)
        // Don't yank a card back while it is being moved or resized.
        let manipulating = (moving && selectedIDs.contains(item.id)) || resizeID == item.id
        if !manipulating {
            layer.position = CGPoint(x: item.x, y: item.y)
        }
        layer.zPosition = CGFloat(item.z)
        if let text = layer.sublayers?.first(where: { $0.name == "text" }) as? CATextLayer {
            text.frame = CGRect(x: 12, y: 10, width: item.width - 24, height: item.height - 20)
            text.string = attributedText(for: item)
            text.isHidden = editingID == item.id
        }
        applyCardChrome(to: layer, for: item)
        if item.kind == .text, !xpBg {
            layer.backgroundColor = NSColor.clear.cgColor
        }
        if let img = layer.sublayers?.first(where: { $0.name == "image" }) {
            img.frame = CGRect(x: 0, y: 0, width: item.width, height: item.height)
            configureThumbnail(for: item, into: img)
        }
        CATransaction.commit()
    }

    /// The named card colors, from the shared palette (nil = yellow).
    static func cardColor(_ key: String?) -> NSColor { Palette.card(key).ns }

    /// Ink for plain board text: a chosen color tints it; otherwise it adapts to
    /// the surface so it stays legible (dark on paper, light on the dark board).
    private func textInk(for item: BoardItem) -> NSColor {
        if xpBg { return Palette.xpInkRGBA.ns }
        if let key = item.color { return Palette.card(key).ns }
        return showingPaper ? Palette.cardInk.ns : .white
    }

    static let defaultFontSize: CGFloat = 15

    private func attributedText(for item: BoardItem) -> NSAttributedString {
        attributedText(for: item, size: CGFloat(item.fontSize ?? Double(Self.defaultFontSize)))
    }

    /// Builds the card's text at an explicit title size (body derives from it).
    /// The size argument lets a live resize re-render without touching the model.
    private func attributedText(for item: BoardItem, size: CGFloat) -> NSAttributedString {
        let ink = textInk(for: item)
        let titleWeight: NSFont.Weight = .bold
        let bodyWeight: NSFont.Weight = .regular
        let titleFont = xpBg
            ? FontLoader.xpNSFont(size: size, weight: titleWeight)
            : NSFont.systemFont(ofSize: size, weight: titleWeight)
        let bodyFont = xpBg
            ? FontLoader.xpNSFont(size: size * 0.82, weight: bodyWeight)
            : NSFont.systemFont(ofSize: size * 0.82, weight: bodyWeight)
        let out = NSMutableAttributedString(
            string: item.title ?? "",
            attributes: [
                .font: titleFont,
                .foregroundColor: ink,
            ]
        )
        if let body = item.body, !body.isEmpty {
            out.append(NSAttributedString(
                string: "\n" + body,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: ink.withAlphaComponent(0.75),
                ]
            ))
        }
        return out
    }

    private func configureThumbnail(for item: BoardItem, into img: CALayer) {
        let file = item.file ?? ""
        if imageFiles[item.id] != file {
            imageFiles[item.id] = file
            loadingThumbnails.remove(item.id)
            img.contents = nil
        }
        guard img.contents == nil, !loadingThumbnails.contains(item.id) else { return }
        requestThumbnail(for: item, into: img)
    }

    private func requestThumbnail(for item: BoardItem, into img: CALayer) {
        guard let thumbnailProvider else { return }
        loadingThumbnails.insert(item.id)
        thumbnailProvider(item) { [weak self, weak img] cg in
            self?.loadingThumbnails.remove(item.id)
            guard let img, let cg else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            img.contents = cg
            CATransaction.commit()
        }
    }

    // MARK: geometry

    private func applyTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.position = CGPoint(x: viewport.x, y: viewport.y)
        contentLayer.transform = CATransform3DMakeScale(viewport.zoom, viewport.zoom, 1)
        CATransaction.commit()
    }

    private func boardPoint(_ viewPoint: CGPoint) -> CGPoint {
        BoardGeometry.toBoard(viewPoint, viewport: viewport)
    }

    private func topItem(at board: CGPoint) -> BoardItem? {
        guard let id = BoardGeometry.hitTest(board, items: items) else { return nil }
        return items.first { $0.id == id }
    }

    /// Re-fit the viewport so every item is centered and visible. Empty board
    /// recenters to the origin.
    func recenter() {
        guard !items.isEmpty else { return }
        let minX = items.map(\.x).min()!
        let minY = items.map(\.y).min()!
        let maxX = items.map { $0.x + $0.width }.max()!
        let maxY = items.map { $0.y + $0.height }.max()!
        let pad = 50.0
        let zoom = min(4, max(0.25, min(
            (bounds.width - pad * 2) / max(maxX - minX, 1),
            (bounds.height - pad * 2) / max(maxY - minY, 1)
        )))
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        viewport.zoom = zoom
        viewport.x = bounds.width / 2 - cx * zoom
        viewport.y = bounds.height / 2 - cy * zoom
        applyTransform()
        onViewport(viewport)
    }

    // MARK: selection + resize chrome

    /// Accent border on the selected item, plus the resize grip.
    private func updateSelection() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, layer) in itemLayers {
            let on = selectedIDs.contains(id)
            layer.borderWidth = on ? (xpBg ? 2 : 3) : 0
            layer.borderColor = on
                ? (xpBg ? Palette.xpSelectionRGBA.ns : NSColor.controlAccentColor).cgColor
                : nil
        }
        updateHandle()
        CATransaction.commit()
    }

    /// The grip sits on the item's bottom-right corner (origin is bottom-left).
    private func updateHandle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let id = soleSelection, let layer = itemLayers[id] {
            handleLayer.isHidden = false
            handleLayer.position = CGPoint(
                x: layer.position.x + layer.bounds.width,
                y: layer.position.y
            )
        } else {
            handleLayer.isHidden = true // no grip for a multi-selection
        }
        CATransaction.commit()
    }

    private func layoutContents(of layer: CALayer, size: CGSize) {
        if let text = layer.sublayers?.first(where: { $0.name == "text" }) as? CATextLayer {
            text.frame = CGRect(x: 12, y: 10, width: size.width - 24, height: size.height - 20)
        }
        if let img = layer.sublayers?.first(where: { $0.name == "image" }) {
            img.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }
    }

    private func aspect(of item: BoardItem) -> CGFloat? {
        guard item.kind == .image else { return nil }
        let w = item.naturalWidth ?? item.width
        let h = item.naturalHeight ?? item.height
        return h > 0 ? CGFloat(w / h) : nil
    }

    // MARK: input

    override func mouseDown(with event: NSEvent) {
        endInlineEdit() // commit any open editor first
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.option) { // Option + drag = pan tool
            panning = true
            NSCursor.closedHand.set()
            return
        }
        let bp = boardPoint(convert(event.locationInWindow, from: nil))

        // Double-click a text card to edit it; double-click empty to make one.
        if event.clickCount == 2 {
            if let hit = topItem(at: bp) {
                if hit.kind == .text { beginInlineEdit(hit.id) }
                return
            }
            onAddText(bp)
            return
        }

        // Resize grip (only when exactly one card is selected).
        if let id = soleSelection, let layer = itemLayers[id] {
            let corner = CGPoint(x: layer.position.x + layer.bounds.width, y: layer.position.y)
            if hypot(bp.x - corner.x, bp.y - corner.y) <= handleSize {
                resizeID = id
                resizeTop = layer.position.y + layer.bounds.height
                resizeLeft = layer.position.x
                return
            }
        }

        let shift = event.modifierFlags.contains(.shift)
        if let hit = topItem(at: bp) {
            if shift {
                if selectedIDs.contains(hit.id) { selectedIDs.remove(hit.id) }
                else { selectedIDs.insert(hit.id) }
            } else if !selectedIDs.contains(hit.id) {
                selectedIDs = [hit.id] // clicking an unselected card selects just it
            }
            onBringToFront(hit.id)
            updateSelection()
            if selectedIDs.contains(hit.id) { // drag moves the whole selection
                moving = true
                moveLast = bp
            }
        } else {
            // Empty space: drag a rectangle to select (Shift keeps the set).
            if !shift { selectedIDs = []; updateSelection() }
            marqueeStart = bp
            showMarquee(from: bp, to: bp)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if panning { panBy(event.deltaX, event.deltaY); return }
        let bp = boardPoint(convert(event.locationInWindow, from: nil))

        if let id = resizeID, let layer = itemLayers[id] {
            let it = items.first { $0.id == id }
            let w = max(80, bp.x - resizeLeft)
            var h = max(50, resizeTop - bp.y)
            if let it, let aspect = aspect(of: it) {
                h = w / aspect // images keep their shape; width drives height
            }
            // Text: the grip resizes the box freely and the text wraps to fit.
            // Font size is unchanged here — set it from the right-click menu.
            let y = resizeTop - h
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            layer.position = CGPoint(x: resizeLeft, y: y)
            layoutContents(of: layer, size: CGSize(width: w, height: h))
            CATransaction.commit()
            updateHandle()
            return
        }

        if let start = marqueeStart {
            showMarquee(from: start, to: bp)
            selectMarquee(from: start, to: bp)
            return
        }

        guard moving else { return }
        let dx = bp.x - moveLast.x, dy = bp.y - moveLast.y
        moveLast = bp
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in selectedIDs where itemLayers[id] != nil {
            itemLayers[id]!.position.x += dx
            itemLayers[id]!.position.y += dy
        }
        CATransaction.commit()
        updateHandle()
    }

    private func showMarquee(from a: CGPoint, to b: CGPoint) {
        marqueeLayer.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        marqueeLayer.frame = CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        CATransaction.commit()
    }

    private func selectMarquee(from a: CGPoint, to b: CGPoint) {
        let rect = CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        selectedIDs = Set(items.filter { rect.intersects($0.frame) }.map(\.id))
        updateSelection()
    }

    override func mouseUp(with event: NSEvent) {
        if panning { panning = false; NSCursor.arrow.set(); return }
        if let id = resizeID, let layer = itemLayers[id] {
            onMoveAndResize(id, CGRect(origin: layer.position, size: layer.bounds.size), nil)
            resizeID = nil
            return
        }
        if marqueeStart != nil {
            marqueeStart = nil
            marqueeLayer.isHidden = true
            return
        }
        if moving {
            moving = false
            var positions: [UUID: CGPoint] = [:]
            for id in selectedIDs where itemLayers[id] != nil { positions[id] = itemLayers[id]!.position }
            onMoveMany(positions)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Cmd + scroll zooms, a reliable alternative to the pinch gesture.
        if event.modifierFlags.contains(.command) {
            applyZoom(factor: 1 + event.scrollingDeltaY * 0.01,
                      at: convert(event.locationInWindow, from: nil))
            return
        }
        viewport.x += event.scrollingDeltaX
        viewport.y -= event.scrollingDeltaY
        applyTransform()
        onViewport(viewport)
    }

    // No magnify(with:) override: it would consume the pinch and starve SwiftUI's
    // MagnificationGesture, which is the path that actually gets delivered here.

    /// Pan the board by a view-space delta (drag right -> content right).
    private func panBy(_ dx: CGFloat, _ dy: CGFloat) {
        viewport.x += dx
        viewport.y -= dy
        applyTransform()
        onViewport(viewport)
    }

    /// Armed while the board is open, so Option + drag pans from anywhere.
    func setGlobalPanEnabled(_ on: Bool) {
        globalPanActive = on
        if on {
            window?.makeFirstResponder(self)
        }
    }

    /// Drags onto our panel are panned in `mouseDown`/`mouseDragged`. This global
    /// monitor adds the off-window case: Option + drag out on the desktop or
    /// another app (the transparent board at partial coverage shows them
    /// through). Gated by `globalPanActive` so a closed board never pans.
    private func installPanMonitors() {
        globalPanMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged]
        ) { [weak self] event in
            guard let self, self.globalPanActive, event.modifierFlags.contains(.option) else { return }
            self.panBy(event.deltaX, event.deltaY)
        }
        // Pinch zoom. The SwiftUI hosting view swallows `magnify(with:)` before it
        // reaches this NSView, so catch it with a LOCAL monitor instead, which
        // sees every event first (the same trick the row-swipe scroll monitor
        // uses). Only acts on a pinch over the board while it is open.
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify]) { [weak self] event in
            guard let self, self.globalPanActive else { return event } // board open only
            self.applyZoom(factor: 1 + event.magnification,
                           at: CGPoint(x: self.bounds.midX, y: self.bounds.midY))
            return event // observe, don't consume
        }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.shouldHandleBoardUndoRedo(for: event) else { return event }
            if event.modifierFlags.contains(.shift) {
                self.onRedo()
            } else {
                self.onUndo()
            }
            return nil
        }
    }

    private func shouldHandleBoardUndoRedo(for event: NSEvent) -> Bool {
        guard globalPanActive, editingID == nil, window?.isKeyWindow == true else { return false }
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "z" else { return false }
        return true
    }

    @objc func undo(_ sender: Any?) {
        guard editingID == nil else { return }
        onUndo()
    }

    @objc func redo(_ sender: Any?) {
        guard editingID == nil else { return }
        onRedo()
    }

    @objc func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo) { return editingID == nil && canUndo() }
        if item.action == #selector(redo) { return editingID == nil && canRedo() }
        return true
    }

    /// Zoom about a view point, clamped 0.25...4, keeping that point fixed.
    private func applyZoom(factor: CGFloat, at p: CGPoint) {
        let under = boardPoint(p)
        let newZoom = min(4, max(0.25, viewport.zoom * factor))
        viewport.x = p.x - under.x * newZoom
        viewport.y = p.y - under.y * newZoom
        viewport.zoom = newZoom
        applyTransform()
        onViewport(viewport)
    }

    override func keyDown(with event: NSEvent) {
        if shouldHandleBoardUndoRedo(for: event) {
            if event.modifierFlags.contains(.shift) { onRedo() } else { onUndo() }
            return
        }
        // Delete / Forward-delete removes the whole selection.
        if (event.keyCode == 51 || event.keyCode == 117), !selectedIDs.isEmpty {
            onDeleteMany(selectedIDs)
            selectedIDs = []
            updateSelection()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: inline text editing

    func beginInlineEdit(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.kind == .text else { return }
        selectedIDs = [id]
        updateSelection()
        editingID = id

        let origin = BoardGeometry.toView(CGPoint(x: item.x, y: item.y), viewport: viewport)
        let tv = NSTextView(frame: CGRect(
            x: origin.x, y: origin.y,
            width: item.width * viewport.zoom, height: item.height * viewport.zoom
        ))
        tv.delegate = self
        tv.isRichText = false
        tv.drawsBackground = false
        let fontSize = CGFloat(item.fontSize ?? Double(Self.defaultFontSize))
        tv.font = NSFont.systemFont(ofSize: fontSize * viewport.zoom)
        tv.textColor = textInk(for: item)   // match the plain text ink (legible on any surface)
        tv.insertionPointColor = textInk(for: item)
        tv.textContainerInset = NSSize(width: 10, height: 8)
        tv.string = inlineString(for: item)
        addSubview(tv)
        editor = tv

        itemLayers[id]?.sublayers?.first { $0.name == "text" }?.isHidden = true
        window?.makeKey() // the panel is non-activating; make it key so typing lands
        window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
    }

    /// Commit and tear down the inline editor. Idempotent.
    private func endInlineEdit() {
        guard let id = editingID, let tv = editor else { return }
        editingID = nil
        editor = nil
        let parts = tv.string.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = parts.first.map(String.init) ?? ""
        let body = parts.count > 1 ? String(parts[1]) : ""
        tv.removeFromSuperview()
        itemLayers[id]?.sublayers?.first { $0.name == "text" }?.isHidden = false
        onCommitText(id, title, body)
    }

    private func inlineString(for item: BoardItem) -> String {
        (item.title ?? "") + (item.body.map { "\n" + $0 } ?? "")
    }

    func textDidEndEditing(_ notification: Notification) { endInlineEdit() }

    // MARK: context menu (color + delete)

    override func menu(for event: NSEvent) -> NSMenu? {
        let bp = boardPoint(convert(event.locationInWindow, from: nil))
        guard let hit = topItem(at: bp) else { return nil }
        if !selectedIDs.contains(hit.id) { selectedIDs = [hit.id] }
        updateSelection()

        let menu = NSMenu()
        if items.contains(where: { selectedIDs.contains($0.id) && $0.kind == .text }) {
            let sizeItem = NSMenuItem(title: "Text Size", action: nil, keyEquivalent: "")
            let sizeMenu = NSMenu()
            for (name, size) in [("Small", 12.0), ("Medium", 15.0), ("Large", 22.0), ("Huge", 32.0)] {
                let mi = NSMenuItem(title: name, action: #selector(pickFontSize(_:)), keyEquivalent: "")
                mi.representedObject = size
                mi.target = self
                sizeMenu.addItem(mi)
            }
            sizeItem.submenu = sizeMenu
            menu.addItem(sizeItem)
            menu.addItem(.separator())
            for key in ["yellow", "pink", "blue", "green", "purple", "gray"] {
                let mi = NSMenuItem(title: key.capitalized, action: #selector(pickColor(_:)), keyEquivalent: "")
                mi.representedObject = key
                mi.target = self
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }
        let del = NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        return menu
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        for it in items where selectedIDs.contains(it.id) && it.kind == .text {
            onSetColor(it.id, key)
        }
    }

    @objc private func pickFontSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        for it in items where selectedIDs.contains(it.id) && it.kind == .text {
            onSetFontSize(it.id, size)
        }
    }

    @objc private func deleteSelected() {
        guard !selectedIDs.isEmpty else { return }
        onDeleteMany(selectedIDs)
        selectedIDs = []
        updateSelection()
    }

    // MARK: drag and drop in

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let bp = boardPoint(convert(sender.draggingLocation, from: nil))
        let pb = sender.draggingPasteboard
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            onDropImage(data, bp)
            return true
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first, let data = try? Data(contentsOf: url) {
            onDropImage(data, bp)
            return true
        }
        if let text = pb.string(forType: .string) {
            onDropText(text, bp)
            return true
        }
        return false
    }

    // MARK: paste (Cmd-V routes here via the app's Edit menu)

    @objc func paste(_ sender: Any?) {
        let center = boardPoint(CGPoint(x: bounds.midX, y: bounds.midY))
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            onDropImage(data, center)
        } else if let s = pb.string(forType: .string) {
            onDropText(s, center)
        }
    }
}
