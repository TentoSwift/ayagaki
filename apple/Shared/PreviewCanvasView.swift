import SwiftUI

/// 仕上がりプレビュー（2 リピート、中央の隙間は隣接セルの多数決で埋める）
struct PreviewCanvasView: View {
    @ObservedObject var vm: EditorViewModel
    var cellRadius: CGFloat = 5
    var repeats = 2

    var body: some View {
        if vm.braid == .korai { koraiBody } else { yasudaBody }
    }

    /// 二枚高麗組: 杉綾の目を色で塗ったもの（輪郭は薄く）
    private var koraiBody: some View {
        let geo = KoraiGeometry(cols: vm.cols, rows: vm.rowCount * repeats,
                               c: cellRadius * 0.8, numW: 0, margin: 2)
        return Canvas { ctx, _ in
            let colors = vm.palette.map { Color(hex: $0) }
            for k in 1...max(geo.rows, 1) {
                let r = (k - 1) % vm.rowCount
                for side in [BraidSide.left, .right] {
                    for w in 0..<geo.wales {
                        let path = geo.tilePath(side: side, w: w, k: k)
                        var color = colors[min(max(vm.cells.value(
                            side: side, r: r, d: KoraiGeometry.column(forWale: w)), 0),
                                               colors.count - 1)]
                        // 糸の向きによる艶の違いを簡易表現
                        if side == .left { color = color.shaded(by: -6) }
                        ctx.fill(path, with: .color(color))
                        ctx.stroke(path, with: .color(color.shaded(by: -22)), lineWidth: 0.3)
                    }
                }
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    private var yasudaBody: some View {
        let n = vm.cols
        let s = cellRadius
        let totalRows = vm.rowCount * repeats
        let cx = CGFloat(n + 1) * s + 4
        let y0 = CGFloat(n) * s + 4
        let size = CGSize(width: CGFloat(2 * n + 1) * s + 8,
                          height: y0 + CGFloat(totalRows - 1) * 2 * s + 2 * s + 4)

        return Canvas { ctx, _ in
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
                        // 右段が先に始まる（グリッドと同じ配置。左半面が1目下がる）
                        let x = side == .right ? cx + CGFloat(d) * s : cx - (1 + CGFloat(d)) * s
                        let y = y0 + CGFloat(rr) * 2 * s - CGFloat(d) * s + (side == .left ? s : 0)
                        var color = colors[min(max(vm.cells.value(side: side, r: r, d: d), 0), colors.count - 1)]
                        // 糸の向きによる艶の違いを簡易表現
                        if side == .left { color = color.shaded(by: -6) }
                        diamond(x, y, color)
                    }
                }

            }
        }
        .frame(width: size.width, height: size.height)
    }
}
