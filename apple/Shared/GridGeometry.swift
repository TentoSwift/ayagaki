import SwiftUI

/// 綾書グリッドの幾何。d = 中央からの距離（0 = 中央寄り, cols-1 = 外端）。
/// 各段は中央が最も低い「∨」型（高台の組み口の形）。
struct GridGeometry {
    var cols: Int
    var rows: Int
    var cell: CGFloat = 12      // 菱形の半径（横 = 縦、45°）
    var numW: CGFloat = 30      // 段番号の帯幅
    var margin: CGFloat = 8

    var cx: CGFloat { margin + numW + CGFloat(cols + 1) * cell }
    var y0: CGFloat { margin + CGFloat(cols) * cell }

    var size: CGSize {
        // 右半面は1目ぶん下・内側にずれて左半面と連続タイルになる（隙間なし・書籍と同じ1段ずれ）
        CGSize(width: CGFloat(2 * cols + 1) * cell + 2 * (margin + numW),
               height: y0 + CGFloat(rows - 1) * 2 * cell + 2 * cell + margin)
    }

    /// 中央目の半径（半サイズ）
    var centerRadius: CGFloat { cell / 2 }

    func center(side: BraidSide, r: Int, d: Int) -> CGPoint {
        if side == .center {
            // 中央の上ル目: 各段に2目（r は通し番号 j = 0..2*rows-1）。
            // 偶数=右半面（／向き）、奇数=左半面（＼向き）のマスが一目ずつ交互に並ぶ
            return CGPoint(x: cx, y: y0 + CGFloat(r) * cell + cell / 2)
        }
        if side == .right {
            // 右半面: d=0 が中央線上、左半面と1目（c）ずれて連続タイルになる
            return CGPoint(x: cx + CGFloat(d) * cell,
                           y: y0 + CGFloat(r) * 2 * cell - CGFloat(d) * cell + cell)
        }
        return CGPoint(x: cx - (1 + CGFloat(d)) * cell,
                       y: y0 + CGFloat(r) * 2 * cell - CGFloat(d) * cell)
    }

    /// 中央目のマス（45°に傾いた平行四辺形）の4頂点。偶数=右半面（／）、奇数=左半面（＼）。
    /// 高さは1目分（c）で、上辺・下辺を隣の目と共有して互いに重ならず交互に下へ進む
    func centerBarCorners(_ j: Int) -> [CGPoint] {
        let p = center(side: .center, r: j, d: 0)
        let h = cell / 2
        if j % 2 == 0 {
            // ／（右半面）: 上辺が右側、下辺が左側
            return [CGPoint(x: p.x + cell, y: p.y - h),
                    CGPoint(x: p.x, y: p.y - h),
                    CGPoint(x: p.x - cell, y: p.y + h),
                    CGPoint(x: p.x, y: p.y + h)]
        } else {
            // ＼（左半面）: 上辺が左側、下辺が右側
            return [CGPoint(x: p.x - cell, y: p.y - h),
                    CGPoint(x: p.x, y: p.y - h),
                    CGPoint(x: p.x + cell, y: p.y + h),
                    CGPoint(x: p.x, y: p.y + h)]
        }
    }

    func diamondPath(at c: CGPoint, radius: CGFloat? = nil) -> Path {
        let s = radius ?? cell
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - s))
        p.addLine(to: CGPoint(x: c.x + s, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + s))
        p.addLine(to: CGPoint(x: c.x - s, y: c.y))
        p.closeSubpath()
        return p
    }

    /// タッチ位置 → セル（菱形の内包判定つき。境界付近は両半面を試す）
    func hitTest(_ p: CGPoint) -> (side: BraidSide, r: Int, d: Int)? {
        for side in [BraidSide.right, .left] {
            let dxRaw = side == .right ? (p.x - cx) : (cx - p.x)
            let dEst = side == .right ? Int((dxRaw / cell).rounded())
                                      : Int((dxRaw / cell).rounded()) - 1
            guard dEst >= -1, dEst <= cols else { continue }
            let yOff: CGFloat = side == .right ? cell : 0
            for d in (dEst - 1)...(dEst + 1) where d >= 0 && d < cols {
                let rEst = Int(((p.y - y0 + CGFloat(d) * cell - yOff) / (2 * cell)).rounded())
                for r in (rEst - 1)...(rEst + 1) where r >= 0 && r < rows {
                    let c = center(side: side, r: r, d: d)
                    if abs(p.x - c.x) + abs(p.y - c.y) <= cell {
                        return (side, r, d)
                    }
                }
            }
        }
        return nil
    }
}
