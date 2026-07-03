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
        CGSize(width: 2 * CGFloat(cols + 1) * cell + 2 * (margin + numW),
               height: y0 + CGFloat(rows - 1) * 2 * cell + cell + margin)
    }

    func center(side: BraidSide, r: Int, d: Int) -> CGPoint {
        let dx = cell + CGFloat(d) * cell
        return CGPoint(x: side == .right ? cx + dx : cx - dx,
                       y: y0 + CGFloat(r) * 2 * cell - CGFloat(d) * cell)
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

    /// タッチ位置 → セル（菱形の内包判定つき）
    func hitTest(_ p: CGPoint) -> (side: BraidSide, r: Int, d: Int)? {
        let side: BraidSide = p.x >= cx ? .right : .left
        let dx = abs(p.x - cx)
        let dEst = Int((dx / cell).rounded()) - 1
        guard dEst >= -1, dEst <= cols else { return nil }
        for d in (dEst - 1)...(dEst + 1) where d >= 0 && d < cols {
            let rEst = Int(((p.y - y0 + CGFloat(d) * cell) / (2 * cell)).rounded())
            for r in (rEst - 1)...(rEst + 1) where r >= 0 && r < rows {
                let c = center(side: side, r: r, d: d)
                if abs(p.x - c.x) + abs(p.y - c.y) <= cell {
                    return (side, r, d)
                }
            }
        }
        return nil
    }
}
