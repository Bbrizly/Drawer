import DrawerCore
import SwiftUI

/// The lot: bays from the markdown as blocks of painted stalls, one car per
/// stall in file order. A bay overflows into the next block right; blocks
/// alternate the way they nose in so each faces the bare gap on its own side.
/// There is no road. Zoom magnifies, nothing else.
struct ParkingLotView: View {
    @ObservedObject var lot: ParkingLotStore

    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    @Namespace private var carSpace

    struct IdeaRef: Hashable {
        var bay: Int
        var idea: Int
    }

    private let stallWidth: CGFloat = 168
    private let stallHeight: CGFloat = 108
    private let gapWidth: CGFloat = 56
    private let asphalt = Color(red: 0.165, green: 0.165, blue: 0.18)
    private let paint = Color.white.opacity(0.16)
    private let stencilInk = Color.white.opacity(0.5)

    private struct Block: Identifiable {
        var id: Int
        var bay: Int
        var range: Range<Int>
        var showsLabel: Bool
        /// Odd blocks mirror so their cars nose left, into the shared gap.
        var mirrored: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let stallsPerColumn = max(1, Int((geo.size.height - 80) / stallHeight))
            ScrollView([.horizontal, .vertical]) {
                lotBody(stallsPerColumn: stallsPerColumn)
                    .padding(24)
                    .scaleEffect(zoom * gestureZoom, anchor: .topLeading)
            }
            .background(asphalt)
            .gesture(
                MagnifyGesture()
                    .onChanged { gestureZoom = $0.magnification }
                    .onEnded { _ in
                        zoom = min(2.5, max(0.5, zoom * gestureZoom))
                        gestureZoom = 1
                    }
            )
        }
    }

    private func blocks(stallsPerColumn: Int) -> [Block] {
        var out: [Block] = []
        for (b, bay) in lot.document.bays.enumerated() {
            let cols = ParkingLotLayout.columns(bay.ideas.count, stallsPerColumn: stallsPerColumn)
            for (i, range) in cols.enumerated() {
                out.append(Block(
                    id: out.count, bay: b, range: range,
                    showsLabel: i == 0, mirrored: out.count % 2 == 1))
            }
        }
        return out
    }

    private func lotBody(stallsPerColumn: Int) -> some View {
        let blocks = blocks(stallsPerColumn: stallsPerColumn)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(blocks) { block in
                blockView(block)
                gapView(index: block.id)
            }
        }
    }

    private func blockView(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(block.showsLabel ? lot.document.bays[block.bay].name.uppercased() : " ")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.4))
                .frame(height: 18)
                .padding(.bottom, 8)
            ForEach(block.range, id: \.self) { i in
                stall(bay: block.bay, idea: i, mirrored: block.mirrored)
            }
        }
    }

    private func stall(bay: Int, idea: Int, mirrored: Bool) -> some View {
        let ref = IdeaRef(bay: bay, idea: idea)
        let parked = lot.document.bays[bay].ideas[idea]
        return VStack(spacing: 5) {
            CarSprite(color: Palette.card(parked.color).color)
                .frame(width: stallWidth - 28)
                .scaleEffect(x: mirrored ? -1 : 1)
                .matchedGeometryEffect(id: ref, in: carSpace)
            Text(parked.title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(stencilInk)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: stallWidth - 28)
        }
        .frame(width: stallWidth, height: stallHeight)
        .overlay(stallLines(mirrored: mirrored))
    }

    /// Painted stall lines: top, bottom, and the closed end. The open end
    /// faces the gap the car noses into.
    private func stallLines(mirrored: Bool) -> some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width
                let h = geo.size.height
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: w, y: 0))
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: w, y: h))
                let closedX: CGFloat = mirrored ? w : 0
                p.move(to: CGPoint(x: closedX, y: 0))
                p.addLine(to: CGPoint(x: closedX, y: h))
            }
            .stroke(paint, lineWidth: 2)
        }
    }

    private func gapView(index: Int) -> some View {
        Color.clear.frame(width: gapWidth, height: 1)
    }
}
