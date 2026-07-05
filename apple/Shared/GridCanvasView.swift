import SwiftUI

/// 綾書グリッド本体。interactive = false で印刷/PDF 用の静的描画にも使う。
struct GridCanvasView: View {
    @ObservedObject var vm: EditorViewModel
    var interactive = true
    var paintEnabled = true
    var cellRadius: CGFloat = 12

    var body: some View {
        let geo = GridGeometry(cols: vm.cols, rows: vm.rowCount, cell: cellRadius)
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
        let gridLine = Color(white: 0.5).opacity(0.55)

        for r in 0..<geo.rows {
            for side in [BraidSide.left, .right] {
                for d in 0..<geo.cols {
                    let path = geo.diamondPath(at: geo.center(side: side, r: r, d: d))
                    let v = cells.value(side: side, r: r, d: d)
                    ctx.fill(path, with: .color(colors[min(max(v, 0), colors.count - 1)]))
                    ctx.stroke(path, with: .color(gridLine), lineWidth: 0.5)
                }
            }
            if let hi = highlighted, hi.contains(r) {
                for side in [BraidSide.left, .right] {
                    for d in 0..<geo.cols {
                        let path = geo.diamondPath(at: geo.center(side: side, r: r, d: d))
                        ctx.stroke(path, with: .color(.red), lineWidth: 1.4)
                    }
                }
            }
            // 段番号（両端）
            let yOuter = geo.center(side: .left, r: r, d: geo.cols - 1).y
            let num = Text("\(r + 1)").font(.system(size: 9)).foregroundColor(.secondary)
            ctx.draw(num, at: CGPoint(x: geo.margin + geo.numW - 6, y: yOuter), anchor: .trailing)
            ctx.draw(num, at: CGPoint(x: geo.size.width - geo.margin - geo.numW + 6, y: yOuter), anchor: .leading)
        }

        // 中央のジグザグ線（45°・一目ずつ左右に振れる。書籍 4-14 の中央線）
        var zigzag = Path()
        zigzag.move(to: CGPoint(x: geo.cx, y: geo.y0))
        for j in 0..<(geo.rows * 2) {
            let x = geo.cx + (j % 2 == 0 ? -geo.cell / 2 : geo.cell / 2)
            zigzag.addLine(to: CGPoint(x: x, y: geo.y0 + CGFloat(j) * geo.cell + geo.cell / 2))
        }
        zigzag.addLine(to: CGPoint(x: geo.cx, y: geo.y0 + CGFloat(geo.rows * 2) * geo.cell))
        ctx.stroke(zigzag, with: .color(.secondary.opacity(0.6)), lineWidth: 1.0)
    }
}
