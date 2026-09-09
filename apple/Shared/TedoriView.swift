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
    /// ⬆（中央で上ル）が付く段か。下端の交差で渡る糸が相手の上を通る（上ル）／下を通る（下ル）
    var rise: Bool = false

    /// 書籍の図番号（右半面=1,2／左半面=3,4）
    var index: Int { (mirrored ? 3 : 1) + (second ? 1 : 0) }
}

/// 糸交換の印（書籍 4-8 下段 A/B）。number = 手前（下）から数えた位置、circled = 戻し（丸数字）
struct TedoriMark: Equatable {
    var number: Int
    var circled: Bool

    var label: String { circled ? Notation.circledText(number) : "\(number)" }
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

    /// 糸交換の印を描く段（手前＝下から数える。一番下=1）
    func exchangeRow(_ number: Int) -> Int { rows + 1 - min(max(number, 1), n) }

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
        // 最後の段を素通りしてから左に曲がる（下端の交差へ入る）
        pts.append(CGPoint(x: xGap, y: y(rows) + 0.60))
        pts.append(CGPoint(x: xGap - 0.55, y: crossY - crossDY))
        return pts
    }

    /// 下端の交差の中心の y と傾き
    var crossY: CGFloat { y(rows) + 1.20 }
    var crossDY: CGFloat { 0.40 }
    /// 動かした糸が反対の対へ渡る線（右上 → 左下）
    var arrow: (from: CGPoint, to: CGPoint) {
        (CGPoint(x: xGap - 0.55, y: crossY - crossDY),
         CGPoint(x: xB - 0.55, y: crossY + crossDY))
    }
    /// 反対の対から渡ってくる相手の糸（左上 → 右下。動かした糸と中央で交差する）
    var partnerArrow: (from: CGPoint, to: CGPoint) {
        (CGPoint(x: xB - 0.55, y: crossY - crossDY),
         CGPoint(x: xGap - 0.55, y: crossY + crossDY))
    }
    /// 「上ル」／「下ル」のラベル位置（交差の下）
    var crossLabelPoint: CGPoint {
        CGPoint(x: ((xGap - 0.55) + (xB - 0.55)) / 2, y: crossY + 1.05)
    }

    /// 上／下 のラベル位置
    func labelPoint(row: Int, over: Bool) -> CGPoint {
        CGPoint(x: over ? xD + 1.45 : xC - 1.45, y: y(row))
    }
}

// MARK: - 描画（SwiftUI Canvas）

/// 帯（糸列）・糸数・玉を描く（手取り図と糸交換の印の図で共通）
private func drawBands(_ ctx: GraphicsContext, _ lay: TedoriLayout,
                       mirrored: Bool, unit: CGFloat) {
    for b in lay.bands {
        let x = (mirrored ? lay.width - b.x : b.x) * unit
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
            let c = CGPoint(x: x, y: lay.y(k) * unit)
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
}

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
        // 帯（糸列）・糸数・玉
        drawBands(ctx, lay, mirrored: figure.mirrored, unit: unit)
        // 動かす糸
        let pts = lay.wavePoints(slots: slots).map { pt($0, lay) }
        ctx.stroke(Self.smoothPath(pts), with: .color(.black),
                   style: StrokeStyle(lineWidth: max(1.4, unit * 0.11), lineCap: .round, lineJoin: .round))
        // 下端の交差: 動かした糸（黒・反対の対へ渡る）と、反対の対から渡ってくる相手の糸（灰・逆向き）。
        // ⬆ の段は動かした糸が相手の上を通る（上ル）＝相手の線を交差で途切れさせる。
        // ⬆ の無い段は下を通る（下ル）＝動かした糸を交差で途切れさせる（ユーザー確認 2026-09-09）
        let a = lay.arrow, p = lay.partnerArrow
        let from = pt(a.from, lay), to = pt(a.to, lay)
        let pFrom = pt(p.from, lay), pTo = pt(p.to, lay)
        let gap = unit * 0.30
        let gray = Color(white: 0.60)
        crossLine(ctx, pFrom, pTo, color: gray, width: max(1.0, unit * 0.06),
                  cut: figure.rise, gap: gap)
        arrowHead(ctx, pFrom, pTo, color: gray, length: unit * 0.50, halfWidth: unit * 0.22)
        crossLine(ctx, from, to, color: .black, width: max(1.2, unit * 0.09),
                  cut: !figure.rise, gap: gap)
        arrowHead(ctx, from, to, color: .black, length: unit * 0.70, halfWidth: unit * 0.30)
        // 交差の横に「上ル」／「下ル」
        ctx.draw(Text(figure.rise ? "上ル" : "下ル")
                    .font(.system(size: unit * 0.58)).foregroundColor(.primary),
                 at: pt(lay.crossLabelPoint, lay))
        // 上／下 のラベル
        for (i, k) in lay.slotRows(count: slots.count).enumerated() {
            let over = slots[i]
            let p = pt(lay.labelPoint(row: k, over: over), lay)
            ctx.draw(Text(over ? "上" : "下").font(.system(size: unit * 0.72)).foregroundColor(.primary), at: p)
        }
    }

    /// 交差で途切れさせながら線を引く（cut=true で中央に隙間を空ける）
    private func crossLine(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint,
                           color: Color, width: CGFloat, cut: Bool, gap: CGFloat) {
        let style = StrokeStyle(lineWidth: width, lineCap: .round)
        var path = Path()
        if cut {
            let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let vx = b.x - a.x, vy = b.y - a.y
            let len = max(0.001, sqrt(vx * vx + vy * vy))
            let ux = vx / len, uy = vy / len
            path.move(to: a)
            path.addLine(to: CGPoint(x: m.x - ux * gap, y: m.y - uy * gap))
            path.move(to: CGPoint(x: m.x + ux * gap, y: m.y + uy * gap))
            path.addLine(to: b)
        } else {
            path.move(to: a)
            path.addLine(to: b)
        }
        ctx.stroke(path, with: .color(color), style: style)
    }

    /// 矢じり（終点 b、向きは a→b）
    private func arrowHead(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint,
                           color: Color, length: CGFloat, halfWidth: CGFloat) {
        let vx = b.x - a.x, vy = b.y - a.y
        let len = max(0.001, sqrt(vx * vx + vy * vy))
        let ux = vx / len, uy = vy / len
        var head = Path()
        head.move(to: b)
        head.addLine(to: CGPoint(x: b.x - ux * length - uy * halfWidth,
                                 y: b.y - uy * length + ux * halfWidth))
        head.addLine(to: CGPoint(x: b.x - ux * length + uy * halfWidth,
                                 y: b.y - uy * length - ux * halfWidth))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
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

// MARK: - 糸交換の図（書籍 4-8 下段 A/B）

/// 記号に糸交換の数字（2.3. など）や戻しの丸数字（②〜⑨）がある段に添える図。
/// 帯と玉だけを描き、C と D の対応する玉の間に小さな両矢印と番号を置く（線は描かない）
struct TedoriExchangeCanvas: View {
    var marks: [TedoriMark]
    var mirrored: Bool
    var threads: Int
    var unit: CGFloat = 20

    private var layout: TedoriLayout { TedoriLayout(n: threads, second: false) }

    var body: some View {
        let lay = layout
        Canvas { ctx, _ in draw(ctx, lay) }
            .frame(width: lay.width * unit, height: lay.height * unit)
    }

    private func mx(_ x: CGFloat, _ lay: TedoriLayout) -> CGFloat {
        (mirrored ? lay.width - x : x) * unit
    }

    private func draw(_ ctx: GraphicsContext, _ lay: TedoriLayout) {
        drawBands(ctx, lay, mirrored: mirrored, unit: unit)
        let lw = max(1.0, unit * 0.075)
        for m in marks {
            let k = lay.exchangeRow(m.number)
            let yk = lay.y(k) * unit
            let xc = mx(lay.xC, lay), xd = mx(lay.xD, lay)
            let inset = lay.dotRadius * 0.45 * unit
            let dir: CGFloat = xd > xc ? 1 : -1
            let a = CGPoint(x: xc + dir * inset, y: yk)
            let b = CGPoint(x: xd - dir * inset, y: yk)
            let bow = 0.38 * unit
            // 上側の弧（C→D）と下側の弧（D→C）で両矢印にする
            arc(ctx, from: a, to: b, bow: -bow, lineWidth: lw)
            arc(ctx, from: b, to: a, bow: bow, lineWidth: lw)
            // 番号（鏡像でも文字は反転させない）
            let lx = mx(lay.xD + 0.95, lay)
            ctx.draw(Text(m.label).font(.system(size: unit * 0.62)).foregroundColor(.primary),
                     at: CGPoint(x: lx, y: yk))
        }
    }

    /// 弧＋終点の矢じり
    private func arc(_ ctx: GraphicsContext, from: CGPoint, to: CGPoint,
                     bow: CGFloat, lineWidth: CGFloat) {
        let c = CGPoint(x: (from.x + to.x) / 2, y: from.y + bow)
        var p = Path()
        p.move(to: from)
        p.addQuadCurve(to: to, control: c)
        ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        // 矢じり（制御点から終点への向き）
        let vx = to.x - c.x, vy = to.y - c.y
        let len = max(0.001, sqrt(vx * vx + vy * vy))
        let ux = vx / len, uy = vy / len
        let hl = unit * 0.34, hw = unit * 0.17
        var head = Path()
        head.move(to: to)
        head.addLine(to: CGPoint(x: to.x - ux * hl - uy * hw, y: to.y - uy * hl + ux * hw))
        head.addLine(to: CGPoint(x: to.x - ux * hl + uy * hw, y: to.y - uy * hl - ux * hw))
        head.closeSubpath()
        ctx.fill(head, with: .color(.black))
    }
}

/// 記号の構造化データ → 糸交換の印（数字＝糸交換、丸数字＝戻し）
func tedoriMarks(_ sym: RowSymbol) -> [TedoriMark] {
    (sym.plain.map { TedoriMark(number: $0, circled: false) }
     + sym.circled.map { TedoriMark(number: $0, circled: true) })
        .sorted { $0.number < $1.number }
}

// MARK: - 半面ぶんの図（図1・図2 ＋ 糸交換の印）

/// 片半面の手取り図（右半面=図1・図2／左半面=図3・図4）。
/// 記号に糸交換の数字・戻しの丸数字があれば、その横に糸交換の図（書籍 4-8 A/B）を足す
struct TedoriHalfView: View {
    var title: String
    var cells: [Int]
    var symbol: RowSymbol
    var mirrored: Bool
    var threads: Int
    var unit: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.accentColor)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach([false, true], id: \.self) { second in
                        VStack(spacing: 2) {
                            let fig = TedoriFigure(
                                slots: Notation.tedoriSlots(rowCells: cells, second: second),
                                second: second, mirrored: mirrored, threads: threads,
                                rise: symbol.rise && !second)   // ⬆ で上ルのは最初の手順（図1・図3）だけ。図2・図4 は下ル
                            Text("図\(fig.index)").font(.caption2).foregroundColor(.secondary)
                            TedoriCanvas(figure: fig, unit: unit)
                        }
                    }
                    let marks = tedoriMarks(symbol)
                    if !marks.isEmpty {
                        VStack(spacing: 2) {
                            Text("糸交換").font(.caption2).foregroundColor(.secondary)
                            TedoriExchangeCanvas(marks: marks, mirrored: mirrored,
                                                 threads: threads, unit: unit)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - 全段の手取り図（記号表の全体を手順書として並べる）

struct TedoriListView: View {
    @ObservedObject var vm: EditorViewModel
    var unit: CGFloat = 16

    private var threads: Int { vm.tama / 4 }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(vm.tedoriGroups) { g in
                VStack(alignment: .leading, spacing: 6) {
                    TedoriHalfView(title: "\(g.label)段 右半面 \(g.right)",
                                   cells: vm.cells.R[g.from], symbol: g.rightSymbol,
                                   mirrored: false, threads: threads, unit: unit)
                    TedoriHalfView(title: "\(g.label)段 左半面 \(g.left)",
                                   cells: vm.cells.L[g.from], symbol: g.leftSymbol,
                                   mirrored: true, threads: threads, unit: unit)
                }
                .padding(.vertical, 4)
                .background(vm.highlighted == g.from...g.to ? Color.red.opacity(0.10) : Color.clear)
                // 図をタップするとその段がグリッド上でハイライトされる
                .contentShape(Rectangle())
                .onTapGesture {
                    let range = g.from...g.to
                    vm.highlighted = (vm.highlighted == range) ? nil : range
                }
                Divider()
            }
        }
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
                let g = row < groups.count ? groups[row] : NotationGroup(from: row, to: row, left: "", right: "")
                VStack(alignment: .leading, spacing: 12) {
                    Text("手取り図").font(.headline)
                    TedoriHalfView(title: "\(row + 1)段 右半面 \(g.right)",
                                   cells: vm.cells.R[row], symbol: g.rightSymbol,
                                   mirrored: false, threads: threads, unit: unit)
                    TedoriHalfView(title: "\(row + 1)段 左半面 \(g.left)",
                                   cells: vm.cells.L[row], symbol: g.leftSymbol,
                                   mirrored: true, threads: threads, unit: unit)
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
}
