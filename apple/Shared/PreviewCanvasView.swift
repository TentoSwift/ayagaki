import SwiftUI

/// 仕上がりプレビュー（2 リピート、中央の隙間は隣接セルの多数決で埋める）
struct PreviewCanvasView: View {
    @ObservedObject var vm: EditorViewModel
    var cellRadius: CGFloat = 5
    var repeats = 2

    var body: some View {
        let n = vm.cols
        let s = cellRadius
        let totalRows = vm.rowCount * repeats
        let cx = CGFloat(n + 1) * s + 4
        let y0 = CGFloat(n) * s + 4
        let size = CGSize(width: 2 * CGFloat(n + 1) * s + 8,
                          height: y0 + CGFloat(totalRows - 1) * 2 * s + s + 4)

        Canvas { ctx, _ in
            let colors = vm.palette.map { Color(hex: $0) }

            func diamond(_ x: CGFloat, _ y: CGFloat, _ color: Color) {
                var p = Path()
                p.move(to: CGPoint(x: x, y: y - s))
                p.addLine(to: CGPoint(x: x + s, y: y))
                p.addLine(to: CGPoint(x: x, y: y + s))
                p.addLine(to: CGPoint(x: x - s, y: y))
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
                ctx.stroke(p, with: .color(color.shaded(by: -18)), lineWidth: 0.3)
            }

            for rr in 0..<totalRows {
                let r = rr % vm.rowCount
                for side in [BraidSide.left, .right] {
                    for d in 0..<n {
                        let dx = s + CGFloat(d) * s
                        let x = side == .right ? cx + dx : cx - dx
                        let y = y0 + CGFloat(rr) * 2 * s - CGFloat(d) * s
                        var color = colors[min(max(vm.cells.value(side: side, r: r, d: d), 0), colors.count - 1)]
                        // 糸の向きによる艶の違いを簡易表現
                        if side == .left { color = color.shaded(by: -6) }
                        diamond(x, y, color)
                    }
                }
                // 中央の隙間（隣接4マスの多数決で補間）
                if rr < totalRows - 1 {
                    let rNext = (rr + 1) % vm.rowCount
                    let around = [vm.cells.L[r][0], vm.cells.R[r][0],
                                  vm.cells.L[rNext][0], vm.cells.R[rNext][0]]
                    var counts: [Int: Int] = [:]
                    for v in around { counts[v, default: 0] += 1 }
                    let val = counts.max { $0.value < $1.value }?.key ?? 0
                    diamond(cx, y0 + CGFloat(rr) * 2 * s + s,
                            colors[min(max(val, 0), colors.count - 1)])
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
