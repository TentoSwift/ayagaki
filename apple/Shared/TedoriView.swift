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

/// 経路の一区間。円弧・楕円弧もすべて3次ベジェに落として持つ（Swift と Web で同じ形にするため）
enum TedoriSeg: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case curve(CGPoint, CGPoint, CGPoint)   // control1, control2, to
}

/// 経路を「直線・四分円・玉を回る半楕円」で接線連続に組み立てるペン
struct TedoriPen {
    /// 円弧を3次ベジェで表すときの制御点の伸ばし方（90度の弧）
    static let kappa: CGFloat = 0.5522847498307936

    private(set) var segs: [TedoriSeg] = []
    private(set) var cur: CGPoint = .zero

    mutating func move(_ p: CGPoint) { segs.append(.move(p)); cur = p }
    mutating func line(_ p: CGPoint) { segs.append(.line(p)); cur = p }
    mutating func curve(_ c1: CGPoint, _ c2: CGPoint, _ p: CGPoint) {
        segs.append(.curve(c1, c2, p)); cur = p
    }

    /// 四分円。今の点から向き u で入り、半径 r で向き v へ曲がる（u と v は直交する単位ベクトル）
    mutating func quarter(u: CGPoint, v: CGPoint, r: CGFloat) {
        let k = Self.kappa, p = cur
        let q = CGPoint(x: p.x + (u.x + v.x) * r, y: p.y + (u.y + v.y) * r)
        curve(CGPoint(x: p.x + u.x * k * r, y: p.y + u.y * k * r),
              CGPoint(x: q.x - v.x * k * r, y: q.y - v.y * k * r), q)
    }

    /// 玉を回るループ（半楕円）。t=0 が真上、t=π/2 が外端（side=+1 で右、-1 で左）、t=π が真下。
    /// t=0 の接線は水平（外向き）、t=π の接線も水平（内向き）なので、前後の四分円と接線が揃う
    mutating func loop(center c: CGPoint, a: CGFloat, b: CGFloat, side: CGFloat,
                       from t0: CGFloat, to t1: CGFloat) {
        let steps = max(1, Int(((t1 - t0) / (.pi / 2) - 1e-9).rounded(.up)))
        let dt = (t1 - t0) / CGFloat(steps)
        let al = 4.0 / 3.0 * tan(dt / 4)
        func pointAt(_ t: CGFloat) -> CGPoint {
            CGPoint(x: c.x + side * a * sin(t), y: c.y - b * cos(t))
        }
        func tangentAt(_ t: CGFloat) -> CGPoint {
            CGPoint(x: side * a * cos(t), y: b * sin(t))
        }
        for i in 0..<steps {
            let ta = t0 + dt * CGFloat(i), tb = ta + dt
            let pa = pointAt(ta), pb = pointAt(tb)
            let da = tangentAt(ta), db = tangentAt(tb)
            curve(CGPoint(x: pa.x + al * da.x, y: pa.y + al * da.y),
                  CGPoint(x: pb.x - al * db.x, y: pb.y - al * db.y), pb)
        }
    }
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
    /// ループ（玉を回る半楕円）が玉の中心から外へ張り出す量（写真 h_nami1 実測 0.60）
    var loopA: CGFloat { dotRadius + 0.34 }
    /// 素通りの縦線 ↔ ループ をつなぐ四分円の半径（＝縦線と帯の間隔）
    var turnR: CGFloat { xGap - xC }
    /// ループの縦の半径。turnR と足して 1 段になるので、ループの前後の段では
    /// 必ず素通りの位置（xGap）を真下向きで通る＝隣のループと接線連続でつながる
    var loopB: CGFloat { 1 - turnR }
    /// 図1 のフック（C の一番上の黒玉の左を小さく回る）の中心を下げる量
    let hookOffset: CGFloat = 0.30

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

    /// 動かす糸の経路。折れ線をならすのではなく、
    /// 「直線（素通り）→四分円→玉を回る半楕円→四分円→直線」を**接線連続**に組み立てる。
    /// ループの前後ちょうど 1 段の所で必ず (xGap, 段) を真下向きに通るので、
    /// 隣り合うループどうしは自然な S 字でつながり、素通りの段は縦一直線になる。
    func threadSegments(slots: [Bool]) -> [TedoriSeg] {
        var pen = TedoriPen()
        let a = loopA, b = loopB, rt = turnR
        let y1 = y(1)
        let down = CGPoint(x: 0, y: 1)
        let right = CGPoint(x: 1, y: 0)
        if second {
            // 図2: 尾は D の一番上の白玉の左から出て、S 字で C の一番上の黒玉を回る（写真 h_nami2）
            let tail = CGPoint(x: xD - dotRadius - 0.14, y: y1 + 0.06)
            let entry = CGPoint(x: xC, y: y1 - b)
            let h = (tail.x - entry.x) * 0.55
            pen.move(tail)
            pen.curve(CGPoint(x: tail.x - h, y: tail.y), CGPoint(x: entry.x + h, y: entry.y), entry)
            pen.loop(center: CGPoint(x: xC, y: y1), a: a, b: b, side: -1, from: 0, to: .pi)
        } else {
            // 図1: C の一番上の黒玉の左に小さくフックしてから間へ降りる（写真 h_nami1）
            let c = CGPoint(x: xC, y: y1 + hookOffset)
            let t0: CGFloat = 0.55
            pen.move(CGPoint(x: c.x - a * sin(t0), y: c.y - b * cos(t0)))
            pen.loop(center: c, a: a, b: b, side: -1, from: t0, to: .pi)
        }
        pen.quarter(u: right, v: down, r: rt)      // → 素通りの縦線へ

        for (i, k) in slotRows(count: slots.count).enumerated() {
            // 上 = その段の白玉（D）の右を回る／下 = 黒玉（C）の左を回る
            let s: CGFloat = slots[i] ? 1 : -1
            let cx = slots[i] ? xD : xC
            pen.line(CGPoint(x: xGap, y: y(k) - 1))          // 素通り（縦一直線）
            pen.quarter(u: down, v: CGPoint(x: s, y: 0), r: rt)
            pen.loop(center: CGPoint(x: cx, y: y(k)), a: a, b: b, side: s, from: 0, to: .pi)
            pen.quarter(u: CGPoint(x: -s, y: 0), v: down, r: rt)
        }
        // 最後の段を素通りしてから、下端の矢印へ大きく滑らかに曲がる（急な折れ角なし）
        pen.line(CGPoint(x: xGap, y: y(rows)))
        let ar = arrow
        let dx = ar.to.x - ar.from.x, dy = ar.to.y - ar.from.y
        let len = max(0.001, sqrt(dx * dx + dy * dy))
        let ux = dx / len, uy = dy / len
        let p0 = pen.cur, p1 = ar.from
        let h = max(0.001, sqrt(pow(p1.x - p0.x, 2) + pow(p1.y - p0.y, 2))) * 0.55
        pen.curve(CGPoint(x: p0.x, y: p0.y + h),
                  CGPoint(x: p1.x - ux * h, y: p1.y - uy * h), p1)
        return pen.segs
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
        // 動かす糸（円弧と S 字を接線連続でつないだ経路）
        var thread = Path()
        for seg in lay.threadSegments(slots: slots) {
            switch seg {
            case .move(let p): thread.move(to: pt(p, lay))
            case .line(let p): thread.addLine(to: pt(p, lay))
            case .curve(let c1, let c2, let p):
                thread.addCurve(to: pt(p, lay), control1: pt(c1, lay), control2: pt(c2, lay))
            }
        }
        ctx.stroke(thread, with: .color(.black),
                   style: StrokeStyle(lineWidth: max(1.4, unit * 0.12), lineCap: .round, lineJoin: .round))
        // 下端の交差: 動かした糸（黒・反対の対へ渡る）と、反対の対から渡ってくる相手の糸（灰・逆向き）。
        // ⬆ の段は動かした糸が相手の上を通る（上ル）＝相手の線を交差で途切れさせる。
        // ⬆ の無い段は下を通る（下ル）＝動かした糸を交差で途切れさせる（ユーザー確認 2026-09-09）
        let a = lay.arrow, p = lay.partnerArrow
        let from = pt(a.from, lay), to = pt(a.to, lay)
        let pFrom = pt(p.from, lay), pTo = pt(p.to, lay)
        let gap = unit * 0.30
        let gray = Color(white: 0.60)
        // ⬆（上ル）の図だけ相手の糸と交差・ラベルを描く。操作の無い図は書籍どおり矢印のみ（ユーザー確認 2026-09-10）
        if figure.rise {
            crossLine(ctx, pFrom, pTo, color: gray, width: max(1.0, unit * 0.06),
                      cut: true, gap: gap)
            arrowHead(ctx, pFrom, pTo, color: gray, length: unit * 0.50, halfWidth: unit * 0.22)
        }
        crossLine(ctx, from, to, color: .black, width: max(1.2, unit * 0.09),
                  cut: false, gap: gap)
        arrowHead(ctx, from, to, color: .black, length: unit * 0.70, halfWidth: unit * 0.30)
        if figure.rise {
            ctx.draw(Text("上ル").font(.system(size: unit * 0.58)).foregroundColor(.primary),
                     at: pt(lay.crossLabelPoint, lay))
        }
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
