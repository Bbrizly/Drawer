import AppKit
import DrawerCore
import SpriteKit
import SwiftUI

/// The SwiftUI host for the drawer scene. Wraps `SpriteView(scene:)`, overlays
/// the `PrinterSlot` at the top seam, and drives the two print flows:
///   - on entry, prints every currently queued receipt in sequence with the
///     tuning stagger (spec flow a's tail), then marks each in the drawer;
///   - while mounted, watches `TodoStore` for a newly added task and prints it
///     (spec flow b, print-on-add).
/// The scene is owned by the facade (not by this view), so receipts already in
/// the drawer survive leaving and re-entering Bureau mode. Pause is wired to
/// the panel's visibility (through the facade) and to whether Bureau mode is
/// entered, so the scene and view both sleep when hidden.
struct BureauView: View {
    let scene: BureauScene
    @ObservedObject var receipts: ReceiptStore
    @ObservedObject var tuning: BureauTuning
    @ObservedObject var store: TodoStore
    @ObservedObject var feature: BureauFeature
    let textures: TextureRenderer
    /// True while Bureau mode is the visible bottom region.
    var isActive: Bool

    private var slipSize: CGSize { feature.slipSize }
    private var scale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

    @State private var jobs: [PrintingJob] = []
    @State private var current: PrintingJob?
    @State private var previousTodayCount = 0

    private var isPaused: Bool { !isActive || !feature.panelVisible }

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: scene, isPaused: isPaused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PrinterSlot(
                job: current,
                tuning: tuning.document.print,
                onChatter: { feature.sounds.chatter(volume: tuning.document.print.chatterVolume) },
                onDing: { feature.sounds.ding(volume: tuning.document.print.dingVolume) }
            ) { finished in
                scene.dropIn(makeSprite(receiptID: finished.receiptID, image: finished.image))
                current = nil
                pumpQueue()
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear { configure() }
        .onChange(of: tuning.document) { _, doc in
            scene.tuning = doc
            feature.stickies.tuningChanged()
        }
        .onChange(of: store.todayItems) { old, new in handleTodayItemsChanged(from: old, to: new) }
    }

    // MARK: setup

    private func configure() {
        if !scene.isConfigured {
            scene.isConfigured = true
            scene.scaleMode = .resizeFill
            scene.tuning = tuning.document
            scene.setFiledCount(receipts.document.lifetimeFiled)
            spawnExistingReceipts()
        }
        // The Monday ceremony (spec Decision 4): a new ISO week empties the
        // tray; the animation only runs when something actually cleared.
        if tuning.document.filedTray.clearsMonday, receipts.clearTrayIfNewWeek() {
            scene.clearTray()
        }
        previousTodayCount = store.todayItems.count
        printQueuedReceipts()
        // Reopen any notes persisted as sticky, so entering the drawer never
        // leaves a receipt with no window and no sprite (spec "Pull-out" cap).
        feature.stickies.restore()
    }

    /// Places receipts already `inDrawer`, restoring each to its saved settle
    /// position/rotation when there is one (R2 deliverable 6), else spreading it
    /// fresh across the drawer.
    private func spawnExistingReceipts() {
        let width = max(120, scene.size.width)
        let height = max(160, scene.size.height)
        for link in receipts.document.receipts where link.state == .inDrawer {
            let sprite = makeSprite(receiptID: link.id, title: link.textSnapshot, age: link.ageFactor())
            let saved = CGPoint(x: link.position.x, y: link.position.y)
            let point: CGPoint
            if saved.x != 0 || saved.y != 0 {
                point = CGPoint(
                    x: min(max(saved.x, 10), width - 10),
                    y: min(max(saved.y, 10), height - 10)
                )
            } else {
                point = CGPoint(
                    x: CGFloat.random(in: width * 0.2...width * 0.8),
                    y: CGFloat.random(in: height * 0.4...height * 0.85)
                )
            }
            scene.addExisting(sprite, at: point, rotation: link.rotation != 0 ? CGFloat(link.rotation) : nil)
        }
        // The week's trophies so far: filed slips stack straight into the tray,
        // no crumple replay (R4, spec Decision 4).
        for link in receipts.document.receipts where link.state == .filed {
            scene.fileIntoTray(makeSprite(receiptID: link.id, title: link.textSnapshot), animated: false)
        }
    }

    /// Prints every still-queued receipt in sequence, staggered, then marks it
    /// in the drawer so re-entry does not reprint it. Runs on every entry so a
    /// task queued while in list mode prints the next time the drawer opens.
    private func printQueuedReceipts() {
        let queued = receipts.document.receipts.filter { $0.state == .queued }
        guard !queued.isEmpty else { return }
        let stagger = max(0, tuning.document.print.queueStaggerMs) / 1000
        for (i, link) in queued.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * stagger) {
                enqueuePrint(receiptID: link.id, title: link.textSnapshot)
                markInDrawer(link.id)
            }
        }
    }

    // MARK: print-on-add (flow b)

    private func handleTodayItemsChanged(from old: [TodoItem], to new: [TodoItem]) {
        defer { previousTodayCount = new.count }
        guard isActive else { return }
        // Only a genuine growth in the today section is an add. A toggle or a
        // rename changes an item's identity/line without changing the count, so
        // this never fires a spurious print for those (`TodoItem.id` folds in
        // the raw line, which a toggle rewrites).
        guard new.count > previousTodayCount else { return }
        for item in new.suffix(new.count - previousTodayCount) {
            let link = ReceiptLink(
                textSnapshot: item.title,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                state: .inDrawer,
                printedAt: Date()
            )
            receipts.add(link)
            enqueuePrint(receiptID: link.id, title: item.title)
        }
    }

    // MARK: print queue

    private func enqueuePrint(receiptID: UUID, title: String) {
        let image = textures.image(title: title, size: slipSize, scale: scale)
        jobs.append(PrintingJob(receiptID: receiptID, image: image))
        pumpQueue()
    }

    private func pumpQueue() {
        guard current == nil, !jobs.isEmpty else { return }
        current = jobs.removeFirst()
    }

    private func markInDrawer(_ id: UUID) {
        guard var link = receipts.document.receipts.first(where: { $0.id == id }) else { return }
        link.state = .inDrawer
        link.printedAt = Date()
        receipts.update(link)
        feature.refreshQueue()
    }

    // MARK: sprites

    private func makeSprite(receiptID: UUID, title: String, age: Double = 0) -> ReceiptSprite {
        let texture = textures.texture(title: title, size: slipSize, scale: scale, age: age)
        return ReceiptSprite(receiptID: receiptID, texture: texture, size: slipSize)
    }

    private func makeSprite(receiptID: UUID, image: NSImage) -> ReceiptSprite {
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return ReceiptSprite(receiptID: receiptID, texture: texture, size: slipSize)
    }
}
