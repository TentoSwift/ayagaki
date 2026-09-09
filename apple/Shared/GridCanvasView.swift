import SwiftUI

/// 綾書グリッド本体。interactive = false で印刷/PDF 用の静的描画にも使う。
struct GridCanvasView: View {
    @ObservedObject var vm: EditorViewModel
    var interactive = true
    var paintEnabled = true
    /// 表示倍率（1 = 等倍）。幾何ごと縮めるので当たり判定もそのまま合う
    var scale: CGFloat = 1

    var body: some View {
        let geo = GridGeometry(cols: vm.cols, rows: vm.rowCount, scale: scale)
        Canvas { ctx, _ in
            Self.draw(ctx: ctx, geo: geo,
                      cells: vm.cells, palette: vm.palette,
                      highlighted: interactive ? vm.highlighted : nil)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard interactive, paintEnabled else { return }
                    vm.strokeChanged(at: g.location, geometry: geo)
                }
                .onEnded { _ in
                    guard interactive, paintEnabled else { return }
                    vm.strokeEnded()
                },
            including: (interactive && paintEnabled) ? .gesture : .none
        )
        .onTapGesture { location in
            // スクロールモードでも単発タップでは塗れるようにする
            guard interactive, !paintEnabled else { return }
            vm.tap(at: location, geometry: geo)
        }
    }

    static func draw(ctx: GraphicsContext, geo: GridGeometry,
                     cells: CellGrid, palette: [String],
                     highlighted: ClosedRange<Int>?) {
        let colors = palette.map { Color(hex: $0) }
        // 糸の輪郭（濃い茶灰色）
        let gridLine = Color(red: 0x4a / 255.0, green: 0x43 / 255.0, blue: 0x30 / 255.0)
        // 縮小時も見えるよう、線幅と段番号の文字は下限を設ける
        let s = geo.scale
        let edgeW = max(0.35, 0.6 * s)
        let hiW = max(0.9, 1.4 * s)
        let zigW = max(0.9, 1.4 * s)
        let numSize = max(7, 9 * s)

        for r in 0..<geo.rows {
            for side in [BraidSide.left, .right] {
                for d in 0..<geo.cols {
                    let (fill, edges) = geo.bandPaths(side: side, r: r, d: d)
                    let v = cells.value(side: side, r: r, d: d)
                    ctx.fill(fill, with: .color(colors[min(max(v, 0), colors.count - 1)]))
                    // 濃い線は長辺2本だけ（短い端は開いたまま）
                    ctx.stroke(edges, with: .color(gridLine), lineWidth: edgeW)
                }
            }
            if let hi = highlighted, hi.contains(r) {
                for side in [BraidSide.left, .right] {
                    for d in 0..<geo.cols {
                        let path = geo.bandPath(side: side, r: r, d: d)
                        ctx.stroke(path, with: .color(.red), lineWidth: hiW)
                    }
                }
            }
            // 段番号（両端。右半面は1目ずれる）
            let yLeft = geo.center(side: .left, r: r, d: geo.cols - 1).y
            let yRight = geo.center(side: .right, r: r, d: geo.cols - 1).y
            let num = Text("\(r + 1)").font(.system(size: numSize)).foregroundColor(.secondary)
            ctx.draw(num, at: CGPoint(x: geo.margin + geo.numW - max(2, 6 * s), y: yLeft), anchor: .trailing)
            ctx.draw(num, at: CGPoint(x: geo.size.width - geo.margin - geo.numW + max(2, 6 * s), y: yRight), anchor: .leading)
        }
        // 中央のジグザグ
        ctx.stroke(geo.centerZigzagPath(), with: .color(gridLine), lineWidth: zigW)
    }
}
