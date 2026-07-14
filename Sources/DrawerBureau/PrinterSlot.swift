import AppKit
import SwiftUI

/// One receipt being printed: the pre-rendered slip image and the id it will
/// carry into the scene once it tears off.
struct PrintingJob: Identifiable, Equatable {
    let id = UUID()
    let receiptID: UUID
    let image: NSImage

    static func == (lhs: PrintingJob, rhs: PrintingJob) -> Bool { lhs.id == rhs.id }
}

/// The printer slot at the seam between the top strip and the drawer. A receipt
/// emerges line by line, stepped and incremental like a thermal printer (not
/// smooth-scrolled): it reveals `stepPx` more every `stepMs` from the top edge,
/// then, after a short tear pause, hands the finished slip to `onTorn` so the
/// scene can drop it in (spec "The printer", flow b).
///
struct PrinterSlot: View {
    let job: PrintingJob?
    let tuning: BureauPrintTuning
    /// One dot-matrix tick per revealed step and the terminal ding at the end
    /// (R4); nil hooks keep the printer silent.
    var onChatter: (() -> Void)?
    var onDing: (() -> Void)?
    var onTorn: (PrintingJob) -> Void

    @State private var revealed: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            if let job {
                Image(nsImage: job.image)
                    .interpolation(.none) // chunky, nearest-neighbor
                    .resizable()
                    .frame(width: job.image.size.width, height: job.image.size.height)
                    // Reveal only `revealed` points from the top: the slip grows
                    // downward out of the seam.
                    .frame(height: max(1, revealed), alignment: .top)
                    .clipped()
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .task(id: job?.id) {
            await runPrint()
        }
    }

    private func runPrint() async {
        revealed = 0
        guard let job else { return }
        let full = job.image.size.height
        let step = max(1, CGFloat(tuning.stepPx))
        let stepNanos = UInt64(max(1, tuning.stepMs) * 1_000_000)

        while revealed < full {
            try? await Task.sleep(nanoseconds: stepNanos)
            if Task.isCancelled { return }
            revealed = min(full, revealed + step)
            onChatter?()
        }
        onDing?()
        try? await Task.sleep(nanoseconds: UInt64(max(1, tuning.tearMs) * 1_000_000))
        if Task.isCancelled { return }
        onTorn(job)
    }
}
