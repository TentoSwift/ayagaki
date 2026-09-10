import SwiftUI

/// 二枚高麗組の綾書グリッドの幾何（杉綾＝ヘリンボーンの目）。
///
/// 目は 45° に傾いた 2:1 の長方形（短辺 s = c·√2、長辺 2s）。
/// 各半面は縦の畝（wale）が `wales` 本（60玉・片面13目なら 7 本）並び、
/// 同じ畝の目は縦に積み上がる（ピッチ 2c）。
///
/// - 右半面: w が奇数（1,3,5）の畝が ／ 向き＝綾（手取り）の目、
///   偶数（0,2,4,6）が ＼ 向き＝糸交換の目（w=0 が中央の目「1」、w=6 が端の目）
/// - 左半面はその鏡像（向きが逆。半段のずれも逆）
///
/// データは既存の `CellGrid` をそのまま使い、**畝 w の目 k を L/R[k-1][2w]** に入れる
/// （奇数 d は高麗組では未使用。C 配列も使わない）。
struct KoraiGeometry {
    var cols: Int               // 片面の目数（CellGrid の列数。13 → 畝 7 本）
    var rows: Int
    var c: CGFloat = 9          // 畝の間隔の半分
    var numW: CGFloat = 30      // 段番号の帯幅
    var margin: CGFloat = 8

    /// 基準寸法（scale = 1 のとき）
    static let baseC: CGFloat = 9
    static let baseNumW: CGFloat = 30
    static let baseMargin: CGFloat = 8

    var scale: CGFloat { c / Self.baseC }

    /// 片半面の畝の本数
    var wales: Int { BraidSpec.wales(forCols: cols) }

    /// 目（長方形）の半分の寸法。長辺方向 = s = c√2、短辺方向 = s/2
    var halfLong: CGFloat { c * CGFloat(2.0.squareRoot()) }
    var halfShort: CGFloat { halfLong / 2 }
    /// 目の外接半径（x にも y にも 1.5c まで張り出す）
    var reach: CGFloat { 1.5 * c }

    // MARK: 座標

    /// 段番号の帯を除いた、中心線から外端までの幅
    var halfWidth: CGFloat { CGFloat(2 * wales - 1) * c + reach }
    var cx: CGFloat { margin + numW + halfWidth }

    /// 平行移動前の y（畝 w・通し番号 k = 1 始まり）。
    /// 外側の畝ほど早い段の高さになる（＝定規が 45° に上がる。上端が ∨ になる）
    private func rawY(side: BraidSide, w: Int, k: Int) -> CGFloat {
        let halfStep = side == .right ? (w % 2 == 0) : (w % 2 == 1)
        return CGFloat(k - 1) * 2 * c - CGFloat(w - 1) * 2 * c + (halfStep ? c : 0)
    }

    /// 全ての目が上端に収まるようにずらす量
    var y0: CGFloat {
        var minY: CGFloat = 0
        for side in [BraidSide.left, .right] {
            for w in 0..<wales { minY = min(minY, rawY(side: side, w: w, k: 1)) }
        }
        return -minY + reach + margin
    }

    var size: CGSize {
        var maxY: CGFloat = 0
        for side in [BraidSide.left, .right] {
            for w in 0..<wales { maxY = max(maxY, rawY(side: side, w: w, k: rows)) }
        }
        return CGSize(width: 2 * (halfWidth + margin + numW),
                      height: y0 + maxY + reach + margin)
    }

    /// 目の中心（w = 畝 0..<wales、k = その畝の通し番号 1..rows）
    func center(side: BraidSide, w: Int, k: Int) -> CGPoint {
        let dx = CGFloat(1 + 2 * w) * c
        return CGPoint(x: side == .right ? cx + dx : cx - dx,
                       y: y0 + rawY(side: side, w: w, k: k))
    }

    /// 目の向き。true = ／（右上がり）。右半面は奇数の畝が ／、左半面はその鏡像
    func isSlash(side: BraidSide, w: Int) -> Bool {
        side == .right ? (w % 2 == 1) : (w % 2 == 0)
    }

    /// CellGrid の列番号（d）。畝 w の目は d = 2w に入る
    static func column(forWale w: Int) -> Int { 2 * w }
    /// 列番号 d が高麗組の目に対応するか（奇数 d は未使用）
    static func wale(forColumn d: Int) -> Int? { d % 2 == 0 ? d / 2 : nil }

    // MARK: パス

    /// 目（45° に傾いた 2:1 の長方形）の輪郭。
    /// roundOuter = true のとき外側の短辺だけを半円に丸める（書籍の外端の折り返し）
    static func tilePath(at p: CGPoint, halfLong a: CGFloat, halfShort b: CGFloat,
                         slash: Bool, roundOuter: Bool = false,
                         outerSign: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        if roundOuter {
            let sx: CGFloat = outerSign >= 0 ? 1 : -1
            let arcX = sx * (a - b)
            path.move(to: CGPoint(x: -sx * a, y: -b))
            path.addLine(to: CGPoint(x: arcX, y: -b))
            path.addArc(center: CGPoint(x: arcX, y: 0), radius: b,
                        startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: sx < 0)
            path.addLine(to: CGPoint(x: -sx * a, y: b))
            path.closeSubpath()
        } else {
            path.addRect(CGRect(x: -a, y: -b, width: 2 * a, height: 2 * b))
        }
        let angle: CGFloat = slash ? -.pi / 4 : .pi / 4
        var t = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: angle)
        return path.copy(using: &t) ?? path
    }

    /// 畝 w・通し番号 k の目の輪郭（CoreGraphics）
    func tileCGPath(side: BraidSide, w: Int, k: Int) -> CGPath {
        Self.tilePath(at: center(side: side, w: w, k: k),
                      halfLong: halfLong, halfShort: halfShort,
                      slash: isSlash(side: side, w: w),
                      roundOuter: w == wales - 1,
                      outerSign: side == .right ? 1 : -1)
    }

    /// 畝 w・通し番号 k の目の輪郭（SwiftUI）
    func tilePath(side: BraidSide, w: Int, k: Int) -> Path {
        Path(tileCGPath(side: side, w: w, k: k))
    }

    /// 中央のジグザグ（右半面 w=0 の目の左端の角と、左半面 w=0 の目の右端の角を交互に結ぶ）。
    /// 実際の目の辺の上を通るので、左右の半面の継ぎ目そのものになる
    func centerZigzagPoints() -> [CGPoint] {
        var pts: [CGPoint] = []
        for k in 1...max(rows, 1) {
            let l = center(side: .left, w: 0, k: k)
            let r = center(side: .right, w: 0, k: k)
            pts.append(CGPoint(x: cx + c / 2, y: l.y - c / 2))   // 左半面の目の右端の角
            pts.append(CGPoint(x: cx - c / 2, y: r.y - c / 2))   // 右半面の目の左端の角
        }
        return pts
    }

    func centerZigzagPath() -> Path {
        var p = Path()
        for (i, pt) in centerZigzagPoints().enumerated() {
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    /// 段番号を書く y（その段の一番外側の目の高さ）
    func rowNumberY(side: BraidSide, k: Int) -> CGFloat {
        center(side: side, w: wales - 1, k: k).y
    }

    // MARK: 当たり判定

    /// タッチ位置 → 目（side, r = k-1, d = 2w）。座標はこの幾何と同じ倍率の表示座標
    func hitTest(_ p: CGPoint) -> (side: BraidSide, r: Int, d: Int)? {
        for side in [BraidSide.right, .left] {
            let dx = side == .right ? (p.x - cx) : (cx - p.x)
            guard dx > -reach else { continue }
            let wEst = Int(((dx / c) - 1) / 2)
            for w in max(0, wEst - 1)...min(wales - 1, wEst + 1) {
                let kEst = Int(((p.y - y0 - rawY(side: side, w: w, k: 1)) / (2 * c)).rounded()) + 1
                for k in max(1, kEst - 1)...min(rows, kEst + 1) {
                    let ctr = center(side: side, w: w, k: k)
                    let ex = p.x - ctr.x, ey = p.y - ctr.y
                    // 目の局所座標（長辺方向 u・短辺方向 v）に落として内包判定
                    let slash = isSlash(side: side, w: w)
                    let u = slash ? (ex - ey) : (ex + ey)
                    let v = slash ? (ex + ey) : (ex - ey)
                    let root2 = CGFloat(2.0.squareRoot())
                    if abs(u) <= halfLong * root2 && abs(v) <= halfShort * root2 {
                        return (side, k - 1, Self.column(forWale: w))
                    }
                }
            }
        }
        return nil
    }

    /// 与えられた表示領域に全体が収まる倍率
    static func fitScale(cols: Int, rows: Int, in available: CGSize) -> CGFloat {
        let base = KoraiGeometry(cols: cols, rows: rows, scale: 1)
        guard base.size.width > 0, base.size.height > 0,
              available.width > 0, available.height > 0 else { return 1 }
        return min(available.width / base.size.width, available.height / base.size.height)
    }
}

// MARK: - 組み方でグリッドの幾何を切り替えるラッパ

/// 安田組（菱形）／高麗組（杉綾）の幾何を同じ入口で扱う。
/// 描画と当たり判定が必ず同じ座標系になるよう、View から ViewModel へはこれを渡す
enum AyagakiGeometry {
    case yasuda(GridGeometry)
    case korai(KoraiGeometry)

    init(braid: BraidType, cols: Int, rows: Int, scale: CGFloat) {
        switch braid {
        case .yasuda: self = .yasuda(GridGeometry(cols: cols, rows: rows, scale: scale))
        case .korai: self = .korai(KoraiGeometry(cols: cols, rows: rows, scale: scale))
        }
    }

    var size: CGSize {
        switch self {
        case .yasuda(let g): return g.size
        case .korai(let g): return g.size
        }
    }

    func hitTest(_ p: CGPoint) -> (side: BraidSide, r: Int, d: Int)? {
        switch self {
        case .yasuda(let g): return g.hitTest(p)
        case .korai(let g): return g.hitTest(p)
        }
    }

    static func fitScale(braid: BraidType, cols: Int, rows: Int, in available: CGSize) -> CGFloat {
        switch braid {
        case .yasuda: return GridGeometry.fitScale(cols: cols, rows: rows, in: available)
        case .korai: return KoraiGeometry.fitScale(cols: cols, rows: rows, in: available)
        }
    }
}

extension KoraiGeometry {
    init(cols: Int, rows: Int, scale: CGFloat) {
        self.init(cols: cols, rows: rows,
                  c: KoraiGeometry.baseC * scale,
                  numW: KoraiGeometry.baseNumW * scale,
                  margin: KoraiGeometry.baseMargin * scale)
    }
}
