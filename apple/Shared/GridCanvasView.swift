import SwiftUI

/// 綾書グリッド本体。interactive = false で印刷/PDF 用の静的描画にも使う。
struct GridCanvasView: View {
    @ObservedObject var vm: EditorViewModel
    var interactive = true
    var paintEnabled = true
    /// 表示倍率（1 = 等倍）。幾何ごと縮めるので当たり判定もそのまま合う
    var scale: CGFloat = 1

    var body: some View {
        let geo = AyagakiGeometry(braid: vm.braid, cols: vm.cols, rows: vm.rowCount, scale: scale)
        Canvas { ctx, _ in
            switch geo {
            case .yasuda(let g):
                Self.draw(ctx: ctx, geo: g, cells: vm.cells, palette: vm.palette,
                          highlighted: interactive ? vm.highlighted : nil)
            case .korai(let g):
                Self.drawKorai(ctx: ctx, geo: g, cells: vm.cells, palette: vm.palette,
                               highlighted: interactive ? vm.highlighted : nil)
            }
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

    /// 糸の輪郭（濃い茶灰色）
    static let gridLine = Color(red: 0x4a / 255.0, green: 0x43 / 255.0, blue: 0x30 / 255.0)

    static func draw(ctx: GraphicsContext, geo: GridGeometry,
                     cells: CellGrid, palette: [String],
                     highlighted: ClosedRange<Int>?) {
        let colors = palette.map { Color(hex: $0) }
        let gridLine = Self.gridLine
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

    /// 二枚高麗組（杉綾＝ヘリンボーンの目）。白い目に細い濃い輪郭・中央のジグザグ・両側に段番号。
    /// 上端が ∨ になるのは、外側の畝ほど早い段の高さに置かれる幾何から自然に出る
    static func drawKorai(ctx: GraphicsContext, geo: KoraiGeometry,
                          cells: CellGrid, palette: [String],
                          highlighted: ClosedRange<Int>?) {
        let colors = palette.map { Color(hex: $0) }
        let gridLine = Self.gridLine
        let s = geo.scale
        let edgeW = max(0.35, 0.7 * s)
        let hiW = max(0.9, 1.4 * s)
        let zigW = max(0.9, 1.6 * s)
        let numSize = max(7, 9 * s)

        for k in 1...max(geo.rows, 1) {
            for side in [BraidSide.left, .right] {
                for w in 0..<geo.wales {
                    let path = geo.tilePath(side: side, w: w, k: k)
                    let v = cells.value(side: side, r: k - 1,
                                        d: KoraiGeometry.column(forWale: w))
                    ctx.fill(path, with: .color(colors[min(max(v, 0), colors.count - 1)]))
                    ctx.stroke(path, with: .color(gridLine), lineWidth: edgeW)
                }
            }
            if let hi = highlighted, hi.contains(k - 1) {
                for side in [BraidSide.left, .right] {
                    for w in 0..<geo.wales {
                        ctx.stroke(geo.tilePath(side: side, w: w, k: k),
                                   with: .color(.red), lineWidth: hiW)
                    }
                }
            }
            // 段番号（両端。一番外側の目の高さに合わせる）
            let num = Text("\(k)").font(.system(size: numSize)).foregroundColor(.secondary)
            ctx.draw(num, at: CGPoint(x: geo.margin + geo.numW - max(2, 6 * s),
                                      y: geo.rowNumberY(side: .left, k: k)), anchor: .trailing)
            ctx.draw(num, at: CGPoint(x: geo.size.width - geo.margin - geo.numW + max(2, 6 * s),
                                      y: geo.rowNumberY(side: .right, k: k)), anchor: .leading)
        }
        // 中央のジグザグ（左右の半面の継ぎ目）
        ctx.stroke(geo.centerZigzagPath(), with: .color(gridLine), lineWidth: zigW)
    }
}
