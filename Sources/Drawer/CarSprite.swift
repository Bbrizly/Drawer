import SwiftUI

/// A top-down car in the old GTA style. Draws in a 300x128 design space
/// scaled to fit. Colour is the flat body paint; everything else is fixed.
/// Nose faces right; mirror with scaleEffect(x: -1) to face left.
struct CarSprite: View {
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 300
            let sy = size.height / 128
            let s = min(sx, sy)
            func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
                Path(roundedRect: CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy),
                     cornerRadius: r * s)
            }
            func poly(_ pts: [(Double, Double)]) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: pts[0].0 * sx, y: pts[0].1 * sy))
                for pt in pts.dropFirst() {
                    p.addLine(to: CGPoint(x: pt.0 * sx, y: pt.1 * sy))
                }
                p.closeSubpath()
                return p
            }
            let outline = Color(red: 0.055, green: 0.055, blue: 0.07)
            let glass = Color(red: 0.10, green: 0.145, blue: 0.19)
            let tyre = Color(red: 0.078, green: 0.078, blue: 0.094)

            // Wheels first, so the body sits on top of them.
            for (x, y) in [(54.0, 8.0), (196, 8), (54, 106), (196, 106)] {
                ctx.fill(box(x, y, 46, 14, 2), with: .color(tyre))
            }
            let bodyPath = box(8, 17, 284, 94, 22)
            ctx.fill(bodyPath, with: .color(color))
            ctx.stroke(bodyPath, with: .color(outline), lineWidth: 3 * s)
            // A light band along the top edge sells the roof curve.
            ctx.fill(box(14, 20, 272, 26, 14), with: .color(.white.opacity(0.08)))
            // Raked glass, front then rear.
            let windshield = poly([(198, 30), (222, 44), (222, 84), (198, 98)])
            ctx.fill(windshield, with: .color(glass))
            ctx.stroke(windshield, with: .color(outline), lineWidth: 2.5 * s)
            let rear = poly([(96, 30), (76, 44), (76, 84), (96, 98)])
            ctx.fill(rear, with: .color(glass))
            ctx.stroke(rear, with: .color(outline), lineWidth: 2.5 * s)
            // Roof shade between the glass.
            ctx.fill(box(96, 26, 102, 76, 6), with: .color(.black.opacity(0.07)))
            // Headlights at the nose, red tails at the tail.
            let lamp = Color(red: 1.0, green: 0.933, blue: 0.706)
            let tail = Color(red: 0.788, green: 0.208, blue: 0.173)
            ctx.fill(box(270, 30, 16, 13, 3), with: .color(lamp))
            ctx.fill(box(270, 85, 16, 13, 3), with: .color(lamp))
            ctx.fill(box(12, 30, 12, 13, 3), with: .color(tail))
            ctx.fill(box(12, 85, 12, 13, 3), with: .color(tail))
            // Wing mirrors.
            ctx.fill(box(196, 22, 9, 7, 2), with: .color(outline))
            ctx.fill(box(196, 99, 9, 7, 2), with: .color(outline))
        }
        .aspectRatio(300.0 / 128.0, contentMode: .fit)
    }
}
