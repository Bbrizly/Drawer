import Observation
import SwiftUI

/// Coordinates task-completion confetti at the panel level.
///
/// Rows can't host the burst themselves: they live inside the scrolling list,
/// which clips, so pieces flying past a row edge (the checkbox sits near the
/// left edge) get chopped instantly. Instead a row reports its checkbox point
/// in the "panel" coordinate space and this center emits a burst on the
/// unclipped overlay above the scroll view.
@MainActor
@Observable
final class CelebrationCenter {
    struct Burst: Identifiable {
        let id = UUID()
        let point: CGPoint
        let created: Date
        let pieces: [Piece]
    }

    private(set) var bursts: [Burst] = []

    func fire(at point: CGPoint) {
        let burst = Burst(
            point: point,
            created: Date(),
            pieces: Piece.make(count: 16, palette: ConfettiLayer.palette.shuffled())
        )
        bursts.append(burst)
        // Remove once the pieces have fully faded (see PieceView duration).
        DispatchQueue.main.asyncAfter(deadline: .now() + Piece.lifetime + 0.2) { [weak self] in
            self?.bursts.removeAll { $0.id == burst.id }
        }
    }
}

/// The unclipped confetti overlay. Lives at the panel root in the "panel"
/// coordinate space and draws each active burst at the checkbox it came from.
struct ConfettiLayer: View {
    var center: CelebrationCenter

    static let palette: [Color] = [
        .pink, .orange, .yellow, .green, .blue, .purple, .mint, .red,
    ]

    var body: some View {
        ZStack {
            ForEach(center.bursts) { burst in
                BurstView(pieces: burst.pieces, created: burst.created)
                    .position(burst.point)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A burst is driven purely by elapsed time since `created`, so it never
/// restarts when the view re-renders (the old onAppear + keyframeAnimator
/// version replayed every time the task list republished after a toggle).
private struct BurstView: View {
    let pieces: [Piece]
    let created: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(created)
            ZStack {
                ForEach(pieces) { PieceView(piece: $0, t: t) }
            }
        }
    }
}

struct Piece: Identifiable {
    let id = UUID()
    let angle: Double
    let distance: Double
    let color: Color
    let size: CGSize
    let spin: Double

    static let lifetime: Double = 1.05

    static func make(count: Int, palette: [Color]) -> [Piece] {
        (0..<count).map { _ in
            Piece(
                angle: .random(in: 0...(2 * .pi)),
                distance: .random(in: 28...56),
                color: palette.randomElement() ?? .pink,
                size: CGSize(width: .random(in: 4...6), height: .random(in: 7...11)),
                spin: .random(in: -280...280)
            )
        }
    }
}

/// Stateless: every transform is a function of `t` (seconds since the burst
/// fired). Pop in, fling outward with easing, hold solid, fade only at the end.
private struct PieceView: View {
    let piece: Piece
    let t: Double

    var body: some View {
        let popIn = eased(t / 0.18) // 0...1 over first 0.18s
        let fling = eased(t / 0.55) // 0...1 over first 0.55s
        let progress = min(max(t / Piece.lifetime, 0), 1)
        let dist = piece.distance * fling
        let opacity = t < 0.72 ? 1.0 : max(0, 1 - (t - 0.72) / 0.33)

        return RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(piece.color)
            .frame(width: piece.size.width, height: piece.size.height)
            .scaleEffect(0.3 + 0.7 * popIn)
            .rotationEffect(.degrees(piece.spin * progress))
            .offset(
                x: cos(piece.angle) * dist,
                y: sin(piece.angle) * dist + 16 * progress // a little gravity
            )
            .opacity(opacity)
    }

    /// easeOutCubic, clamped.
    private func eased(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return 1 - pow(1 - c, 3)
    }
}
