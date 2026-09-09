import SwiftUI

// MARK: - 手取り図（書籍 4-4〜4-9）

/// 手取り図 1 枚ぶんの内容。デザインから自動生成した綾名の単位列をもとに、
/// 糸をどうすくうか（下＝黒玉の左を回る／上＝白玉の右を回る）を描く。
struct TedoriFigure: Equatable {
    /// 上から順のスロット（true=上、false=下）。綾名の単位を逆順にしたもの
    var slots: [Bool]
    /// 図2（相方の手順。上下を入れかえた綾名）か
    var second: Bool
    /// 左半面（図3・図4）＝図1・図2 の左右鏡像
    var mirrored: Bool
    /// 片腕の糸数 N（60玉=15、68玉=17…）
    var threads: Int

    /// 書籍の図番号（右半面=1,2／左半面=3,4）
    var index: Int { (mirrored ? 3 : 1) + (second ? 1 : 0) }
}

/// 手取り図の座標系（1段の間隔を 1.0 とする正規化座標。写真 h_nami1/h_ue1_1 の実測から）
struct TedoriLayout {
    let n: Int          // 片腕の糸数 N
    let second: Bool
    /// 段の総数（図1・図2 とも N+1）
    var rows: Int { n + 1 }

    // 帯（糸列）の中心 x。左の対 A・B、間を空けて右の対 C・D
    let xA: CGFloat = 1.15, xB: CGFloat = 2.30, xC: CGFloat = 4.95, xD: CGFloat = 6.10
    /// 動かす糸が普段いる位置（C と D の間）
    var xGap: CGFloat { (xC + xD) / 2 }
    let bandHalfWidth: CGFloat = 0.33
    let dotRadius: CGFloat = 0.34
    /// ループが玉の外側へ張り出す量
    let loopReach: CGFloat = 0.80

    var width: CGFloat { 7.85 }
    var height: CGFloat { CGFloat(rows) + 3.0 }

    func y(_ row: Int) -> CGFloat { 1.35 + CGFloat(row - 1) }
    var bandTop: CGFloat { y(1) - 0.60 }
    var bandBottom: CGFloat { height - 0.15 }
    var countLabelY: CGFloat { y(1) - 1.00 }

    /// 各帯の玉（x, 最初の段, 最後の段, 黒玉か）。写真の実測:
    /// 図1: A=3…N+1(白), B=2…N+1(黒), C=1…N+1(黒), D=2…N+1(白) → 玉数 N-1, N, N+1, N
    /// 図2: A=2…N(白),   B=1…N+1(黒), C=1…N(黒),   D=1…N(白)   → 玉数 N-1, N+1, N, N
    var bands: [(x: CGFloat, first: Int, last: Int, filled: Bool)] {
        second
        ? [(xA, 2, n, false), (xB, 1, n + 1, true), (xC, 1, n, true), (xD, 1, n, false)]
        : [(xA, 3, n + 1, false), (xB, 2, n + 1, true), (xC, 1, n + 1, true), (xD, 2, n + 1, false)]
    }

    /// 綾の単位を置く段（上から）。図1 は 5,7,…,N ／ 図2 は 4,6,…,N-1
    func slotRows(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let last = second ? n - 1 : n
        return (0..<count).map { last - 2 * (count - 1 - $0) }
    }

    /// 動かす糸の経路（滑らかに繋ぐ前の通過点）
    func wavePoints(slots: [Bool]) -> [CGPoint] {
        var pts: [CGPoint] = []
        let y1 = y(1)
        // 始点: C の一番上の黒玉の左に小さくフックする
        pts.append(CGPoint(x: xC - 0.55, y: y1 - 0.34))
        pts.append(CGPoint(x: xC - 0.88, y: y1 + 0.04))
        pts.append(CGPoint(x: xC - 0.12, y: y1 + 0.40))
        if second {
            // 図2 は続けて D の一番上の白玉の右へ回ってから間に降りる（写真 h_nami2 / h_ue1_2）
            pts.append(CGPoint(x: xD + 0.60, y: y1 + 0.10))
        }
        pts.append(CGPoint(x: xGap, y: y1 + 0.90))

        let rowsOfSlots = slotRows(count: slots.count)
        for k in 2...rows {
            if let i = rowsOfSlots.firstIndex(of: k) {
                // 上 = その段の白玉（D）の右を回るループ、下 = 黒玉（C）の左を回るループ
                let center = slots[i] ? xD : xC
                let sign: CGFloat = slots[i] ? 1 : -1   // 外向き（上は右、下は左）
                let yk = y(k)
                pts.append(CGPoint(x: xGap, y: yk - 0.60))
                pts.append(CGPoint(x: center + sign * -0.10, y: yk - 0.52))
                pts.append(CGPoint(x: center + sign * 0.50, y: yk - 0.40))
                pts.append(CGPoint(x: center + sign * loopReach, y: yk))
                pts.append(CGPoint(x: center + sign * 0.50, y: yk + 0.40))
                pts.append(CGPoint(x: center + sign * -0.10, y: yk + 0.52))
                pts.append(CGPoint(x: xGap, y: yk + 0.60))
            } else {
                pts.append(CGPoint(x: xGap, y: y(k)))   // 素通り
            }
        }
        // 最後の段を素通りしてから左に曲がる
        pts.append(CGPoint(x: xGap, y: y(rows) + 0.80))
        pts.append(CGPoint(x: xGap - 0.55, y: y(rows) + 1.20))
        return pts
    }

    /// 矢印（左の対へ糸を渡す）の始点と先端
    var arrow: (from: CGPoint, to: CGPoint) {
        let yy = y(rows) + 1.20
        return (CGPoint(x: xGap - 0.55, y: yy), CGPoint(x: xB - 0.55, y: yy))
    }

    /// 上／下 のラベル位置
    func labelPoint(row: Int, over: Bool) -> CGPoint {
        CGPoint(x: over ? xD + 1.45 : xC - 1.45, y: y(row))
    }
}

// MARK: - 描画（SwiftUI Canvas）

struct TedoriCanvas: View {
    var figure: TedoriFigure
    /// 1段の間隔（ポイント）
    var unit: CGFloat = 20

    private var layout: TedoriLayout { TedoriLayout(n: figure.threads, second: figure.second) }

    var body: some View {
        let lay = layout
        Canvas { ctx, _ in draw(ctx, lay) }
            .frame(width: lay.width * unit, height: lay.height * unit)
    }

    /// 左半面は左右鏡像。位置だけ反転し、文字は反転させない
    private func pt(_ p: CGPoint, _ lay: TedoriLayout) -> CGPoint {
        CGPoint(x: (figure.mirrored ? lay.width - p.x : p.x) * unit, y: p.y * unit)
    }

    private func draw(_ ctx: GraphicsContext, _ lay: TedoriLayout) {
        let slots = figure.slots
        // 帯（糸列）
        for b in lay.bands {
            let x = (figure.mirrored ? lay.width - b.x : b.x) * unit
            let rect = CGRect(x: x - lay.bandHalfWidth * unit, y: lay.bandTop * unit,
                              width: lay.bandHalfWidth * 2 * unit,
                              height: (lay.bandBottom - lay.bandTop) * unit)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.gray.opacity(0.30)))
            // 糸数
            let count = b.last - b.first + 1
            ctx.draw(Text("\(count)").font(.system(size: unit * 0.62)).foregroundColor(.primary),
                     at: CGPoint(x: x, y: lay.countLabelY * unit))
            // 玉
            for k in b.first...b.last {
                let c = pt(CGPoint(x: b.x, y: lay.y(k)), lay)
                let r = lay.dotRadius * unit
                let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                if b.filled {
                    ctx.fill(circle, with: .color(.black))
                } else {
                    ctx.fill(circle, with: .color(Color(white: 0.98)))
                    ctx.stroke(circle, with: .color(.black.opacity(0.55)), lineWidth: max(0.8, unit * 0.045))
                }
            }
        }
        // 動かす糸
        let pts = lay.wavePoints(slots: slots).map { pt($0, lay) }
        ctx.stroke(Self.smoothPath(pts), with: .color(.black),
                   style: StrokeStyle(lineWidth: max(1.4, unit * 0.11), lineCap: .round, lineJoin: .round))
        // 矢印
        let a = lay.arrow
        let from = pt(a.from, lay), to = pt(a.to, lay)
        var line = Path(); line.move(to: from); line.addLine(to: to)
        ctx.stroke(line, with: .color(.black),
                   style: StrokeStyle(lineWidth: max(1.2, unit * 0.09), lineCap: .round))
        let dir: CGFloat = figure.mirrored ? 1 : -1   // 鏡像では右向き
        let hw = unit * 0.30, hl = unit * 0.70
        var head = Path()
        head.move(to: to)
        head.addLine(to: CGPoint(x: to.x - dir * hl, y: to.y - hw))
        head.addLine(to: CGPoint(x: to.x - dir * hl, y: to.y + hw))
        head.closeSubpath()
        ctx.fill(head, with: .color(.black))
        // 上／下 のラベル
        for (i, k) in lay.slotRows(count: slots.count).enumerated() {
            let over = slots[i]
            let p = pt(lay.labelPoint(row: k, over: over), lay)
            ctx.draw(Text(over ? "上" : "下").font(.system(size: unit * 0.72)).foregroundColor(.primary), at: p)
        }
    }

    /// 通過点を Catmull-Rom で滑らかに繋ぐ
    static func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i]
            let p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

// MARK: - パネル（記号表で選んだ段の手取り図）

struct TedoriPanel: View {
    @ObservedObject var vm: EditorViewModel
    var unit: CGFloat = 18

    /// 片腕の糸数 N（60玉=15）
    private var threads: Int { vm.tama / 4 }

    var body: some View {
        Group {
            if let row = selectedRow {
                let groups = vm.notationGroups
                VStack(alignment: .leading, spacing: 12) {
                    Text("手取り図").font(.headline)
                    half(title: "\(row + 1)段 右半面 \(symbol(groups, row, right: true))",
                         cells: vm.cells.R[row], mirrored: false)
                    half(title: "\(row + 1)段 左半面 \(symbol(groups, row, right: false))",
                         cells: vm.cells.L[row], mirrored: true)
                }
            } else {
                Text("手取り図：交換記号の段をタップすると表示されます")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var selectedRow: Int? {
        guard let r = vm.highlighted?.lowerBound, r >= 0, r < vm.cells.R.count else { return nil }
        return r
    }

    private func symbol(_ groups: [NotationGroup], _ row: Int, right: Bool) -> String {
        guard row < groups.count else { return "" }
        return right ? groups[row].right : groups[row].left
    }

    /// 半面ぶん（図1・図2、または図3・図4）
    private func half(title: String, cells: [Int], mirrored: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.accentColor)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach([false, true], id: \.self) { second in
                        VStack(spacing: 2) {
                            let fig = TedoriFigure(
                                slots: Notation.tedoriSlots(rowCells: cells, second: second),
                                second: second, mirrored: mirrored, threads: threads)
                            Text("図\(fig.index)").font(.caption2).foregroundColor(.secondary)
                            TedoriCanvas(figure: fig, unit: unit)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
