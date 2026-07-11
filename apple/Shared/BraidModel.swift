import Foundation

// MARK: - 基本型

enum BraidSide: String, Codable {
    case left = "L"
    case right = "R"
    case center = "C"   // 中央のジグザグ目（段ごとに1目、綾名には数えない）

    var opposite: BraidSide {
        switch self {
        case .left: return .right
        case .right: return .left
        case .center: return .center
        }
    }
}

enum ReadDirection: String, Codable, CaseIterable, Identifiable {
    case edge    // 端 → 中央
    case center  // 中央 → 端

    var id: String { rawValue }
    var label: String { self == .edge ? "端 → 中央" : "中央 → 端" }
}

enum BraidSpec {
    /// 玉数 → 片面の目数（書籍 4-10/4-11 の綾書定規の目盛り）。
    /// 60玉=13目 を基点に 8玉ごとに +2目（68=15, 76=17, 84=19, 92=21, 100=23）
    static func cols(forTama tama: Int) -> Int {
        let t = tamaOptions.contains(tama) ? tama : 60
        return 13 + (t - 60) / 4
    }
    static let tamaOptions = [60, 68, 76, 84, 92, 100]
    static let rowRange = 4...120
    static let defaultRows = 40
    static let defaultPalette = ["#DFE6C4", "#A2653A", "#3F5DA8", "#C8B23C"]
    /// 地の色に対して柄色は1つ（UI は先頭2色のみ。配列は保存データ互換のため4色のまま）
    static let paletteLabels = ["地", "柄", "柄2", "柄3"]

    /// MCP サーバなど外部からデザインが変更されたときの通知（object = NSManagedObjectID?）
    static let externalChangeNotification = Notification.Name("com.tento.ayagaki.externalChange")
}

// MARK: - セルグリッド（Web 版 JSON と互換）

struct CellGrid: Codable, Equatable {
    var L: [[Int]]
    var R: [[Int]]
    /// 中央のジグザグ目（各段に2目: index 2r=右半面の段r+1の上ル目、2r+1=左半面の段r+1の上ル目）。
    /// 塗るとその段の記号に ⬆（中央で上ル）が付く。古いデータには無い／段数ぶんの旧形式もある
    var C: [Int]?

    static func empty(rows: Int, cols: Int) -> CellGrid {
        let plane = [[Int]](repeating: [Int](repeating: 0, count: cols), count: rows)
        return CellGrid(L: plane, R: plane, C: [Int](repeating: 0, count: rows * 2))
    }

    /// サイズ変更（既存の塗りは可能な範囲で保持）
    func resized(rows: Int, cols: Int) -> CellGrid {
        var out = CellGrid.empty(rows: rows, cols: cols)
        for r in 0..<min(rows, L.count) {
            for d in 0..<min(cols, L[r].count) { out.L[r][d] = L[r][d] }
        }
        for r in 0..<min(rows, R.count) {
            for d in 0..<min(cols, R[r].count) { out.R[r][d] = R[r][d] }
        }
        if let C {
            if C.count == L.count {
                // 旧形式（段ごとに1目）→ 両方の目に展開
                for r in 0..<min(rows, C.count) {
                    out.C![2 * r] = C[r]
                    out.C![2 * r + 1] = C[r]
                }
            } else {
                for j in 0..<min(rows * 2, C.count) { out.C![j] = C[j] }
            }
        }
        return out
    }

    /// side == .center のとき r は中央目の通し番号 j（0..2*rows-1）
    func value(side: BraidSide, r: Int, d: Int) -> Int {
        switch side {
        case .left: return L[r][d]
        case .right: return R[r][d]
        case .center:
            guard let C, r < C.count else { return 0 }
            return C[r]
        }
    }

    mutating func set(side: BraidSide, r: Int, d: Int, to v: Int) {
        switch side {
        case .left: L[r][d] = v
        case .right: R[r][d] = v
        case .center:
            if C == nil || C!.count != L.count * 2 { C = resized(rows: L.count, cols: L.first?.count ?? 0).C }
            if r < C!.count { C![r] = v }
        }
    }

    /// その段の記号に ⬆（中央で上ル）を付けるか（C が唯一の情報源。
    /// 中央の2列 d=0 への塗り/消しが自動で C を書き込み、タップでも上書きできる）
    func hasArrow(side: BraidSide, row: Int) -> Bool {
        guard let C else { return false }
        if C.count == L.count { return row < C.count && C[row] > 0 }  // 旧形式
        let j = side == .right ? 2 * row : 2 * row + 1
        return j < C.count && C[j] > 0
    }

    /// 中央の2列（d=0）への塗りに応じて ⬆ フラグを書き込む。
    /// 左の中央列の色 → 右半面の ⬆（中央の目＝反対側から来て上ル糸のため）
    mutating func syncArrowFromCenterColor(side: BraidSide, row: Int) {
        guard side != .center else { return }
        let value = value(side: side, r: row, d: 0) > 0 ? 1 : 0
        // 反対側の半面の ⬆。左半面は中央の色の1段前に出る（ユーザー確認 2026-07-07）
        let j = side == .left ? 2 * row : 2 * (row - 1) + 1
        if j >= 0 { set(side: .center, r: j, d: 0, to: value) }
    }
}

// MARK: - デザインのスナップショット（Web 版のエクスポート JSON と同一スキーマ）

struct DesignSnapshot: Codable {
    var v: Int = 1
    var name: String
    var tama: Int
    var rows: Int
    var palette: [String]
    var cells: CellGrid
    var readDir: String?

    /// 値を仕様範囲に正規化して返す
    func normalized() -> DesignSnapshot {
        var s = self
        s.tama = BraidSpec.tamaOptions.contains(tama) ? tama : 60
        s.rows = min(BraidSpec.rowRange.upperBound, max(BraidSpec.rowRange.lowerBound, rows))
        if s.palette.count != 4 { s.palette = BraidSpec.defaultPalette }
        s.cells = cells.resized(rows: s.rows, cols: BraidSpec.cols(forTama: s.tama))
        return s
    }
}

// MARK: - 交換記号の生成

struct NotationGroup: Identifiable, Equatable {
    var from: Int
    var to: Int
    var left: String
    var right: String

    var id: Int { from }
    var label: String { from == to ? "\(from + 1)" : "\(from + 1)〜\(to + 1)" }
}

enum Notation {
    /// 丸数字（糸が元の段に戻った目数に付ける。書籍 4-13 の丸印）。
    /// ①〜⑳（U+2460）＋㉑〜㉟（U+3251）で 100玉（片面23目）まで対応
    private static func circled(_ n: Int) -> String {
        if (1...20).contains(n), let scalar = UnicodeScalar(0x2460 + n - 1) {
            return String(Character(scalar))
        }
        if (21...35).contains(n), let scalar = UnicodeScalar(0x3251 + n - 21) {
            return String(Character(scalar))
        }
        return "(\(n))"
    }

    /// 綾の読みで使う「入れかえの目」＝1目おき（偶数目盛り d=1,3,5,…、60玉=6目／68玉=7目）。
    /// 偶数列（縦に進む列）は綾名には入れない（糸交換のみ）
    private static func sampledSlots(_ rowCells: [Int], dir: ReadDirection) -> [Bool] {
        let sampled = stride(from: 1, to: rowCells.count, by: 2).map { rowCells[$0] > 0 }
        return dir == .edge ? sampled.reversed() : Array(sampled)
    }

    /// 綾名（ナミ／上a下b…）。全区間を数字付きで略さず書く（1も書く。合計は常に6）
    private static func ayaName(_ slots: [Bool]) -> String {
        guard slots.contains(true) else { return "ナミ" }
        var runs: [(flag: Bool, n: Int)] = []
        for f in slots {
            if let last = runs.last, last.flag == f {
                runs[runs.count - 1].n += 1
            } else {
                runs.append((f, 1))
            }
        }
        return runs.map { ($0.flag ? "上" : "下") + "\($0.n)" }.joined()
    }

    /// 丸数字の範囲（3個以下は並記、4個以上は ②〜⑩ 形式）
    private static func circledRange(_ from: Int, _ to: Int) -> String {
        guard to >= from else { return "" }
        if to - from + 1 <= 3 { return (from...to).map(circled).joined() }
        return circled(from) + "〜" + circled(to)
    }

    /// 丸数字の列（昇順前提。連続なら範囲形式、不連続は並記）
    private static func circledList(_ nums: [Int]) -> String {
        guard let first = nums.first, let last = nums.last else { return "" }
        if nums.count == last - first + 1 { return circledRange(first, last) }
        return nums.map(circled).joined()
    }

    /// 糸交換の番号列（昇順前提）。全体が連続で6個以上なら「2〜11.」に範囲圧縮（書籍 4-16）、
    /// それ以外は「3.5.7.」の並記。末尾のピリオドが綾名との区切り
    private static func plainNumbers(_ nums: [Int]) -> String {
        guard let first = nums.first, let last = nums.last else { return "" }
        if nums.count >= 6 && nums.count == last - first + 1 { return "\(first)〜\(last)." }
        return nums.map(String.init).joined(separator: ".") + "."
    }

    /// 糸交換（数字）と戻し（丸数字）を1つの数列にする（手書きの綾書の書式）。
    /// 数値順に並べ、通常数字の後にだけ「.」。同種のみなら従来の範囲圧縮を使う
    private static func numberList(circled circledNums: Set<Int>, plain plainNums: Set<Int>,
                                   beforeNami: Bool) -> String {
        if circledNums.isEmpty && plainNums.isEmpty { return "" }
        if plainNums.isEmpty {
            let s = circledList(circledNums.sorted())
            return beforeNami ? s : s + "."
        }
        if circledNums.isEmpty { return plainNumbers(plainNums.sorted()) }
        let all = (circledNums.map { ($0, true) } + plainNums.map { ($0, false) })
            .sorted { $0.0 == $1.0 ? $0.1 && !$1.1 : $0.0 < $1.0 }
        var out = ""
        for (n, isCircled) in all { out += isCircled ? circled(n) : "\(n)." }
        if !out.hasSuffix(".") && !beforeNami { out += "." }
        return out
    }

    /// 片面の全段の記号（糸交換リスト＋綾名）。書籍 4-15 の実例に合わせた規則:
    /// ・上の操作（綾の手取りで目を上げる）には戻しを付けない。戻しが要るのは糸交換のみ
    /// ・斜めに進んだ縞は、一番先の目の色が終わる段に、その場所の番号（d+1）で糸交換を書く（戻し不要）
    /// ・飛びの糸交換は+2の番号で、模様の終わりの1段先で戻す（2.3 → ④⑤）
    /// ・戻しの丸数字は終わった段の直後ではなく、ひとつ段を飛ばした先に表示する
    /// ・中央の糸交換（⬆）は、それぞれの段の2段先に③で戻す（毎回同じ番号）
    /// ・偶数列（縦に進む列 d=2,4,…）は糸交換のみ: 色のある段に番号 d+1 を書き、2段先に+2の丸数字で戻す
    /// ・手取りの⬆のみ（中央の色なし）のブロックは書籍 4-15 の一括の戻し「②〜(M+2)ナミ」
    /// ・入れかえの目が一度に2目以上増える段 → 「2.3.」等の糸交換を前置（6個以上は「2〜M.」に圧縮）
    /// ・数字・丸数字と綾名の区切りはピリオド（ナミの前は区切りなし。書籍 4-16）
    /// ・±1目の漸進変化は綾の手取りだけで賄うため数字なし
    static func sideTexts(_ plane: [[Int]], dir: ReadDirection, arrows: [Bool]? = nil,
                          centerRise: [Bool]? = nil, oppositeRise: [Bool]? = nil) -> [String] {
        let rows = plane.count
        var texts: [String] = []
        var opRun = 0          // 連続する入れかえ段数（中央で上がる段も含む）
        var prevSlots: [Bool]?
        var blockPairs = Set<Int>()  // ブロック内の飛びの糸交換で戻す番号（交換番号+2）
        var hadCenter = false        // ブロックが中央の色による上ルを含むか
        var hadArrow = false         // ブロックが手取りの⬆を含むか
        var sched = [Set<Int>](repeating: [], count: rows)  // 各段で戻す対（先の段に予約）
        // 糸交換の連なりの追跡: 中央（d=0）または発火した偶数列の糸交換から45度
        // （±1目、1段おきの2段2目も含む）で続いてきた色は carried。
        // carried の偶数列は糸交換を書かない。綾（奇数列）から続いただけの偶数列は糸交換が要る
        let cols0 = plane.first?.count ?? 0
        var carried = [[Bool]](repeating: [Bool](repeating: false, count: cols0), count: rows)
        var fired = [[Bool]](repeating: [Bool](repeating: false, count: cols0), count: rows)
        for r0 in 0..<rows {
            for d0 in 0..<cols0 where plane[r0][d0] > 0 {
                func fromChain(_ rr: Int, _ dd: Int) -> Bool {
                    guard rr >= 0, dd >= 0, dd < cols0, plane[rr][dd] > 0 else { return false }
                    return carried[rr][dd] || dd == 0 || (dd % 2 == 0 && fired[rr][dd])
                }
                // 連なりは外向き（1目外 or 1段おきの2目外）のみ。内向きの斜めは続きにしない
                carried[r0][d0] = fromChain(r0-1, d0-1) || fromChain(r0-2, d0-2)
                if d0 >= 2 && d0 % 2 == 0 && !carried[r0][d0] { fired[r0][d0] = true }
            }
        }
        // 斜めに進んだ縞（入れかえの目を1目ずつ外へ移る色）の糸交換:
        // 一番先の目の色が終わる段に、その場所の番号（d+1）を書く。戻しは不要
        var tipNums = [Set<Int>](repeating: [], count: rows)
        let cols = plane.first?.count ?? 0
        for d in stride(from: 1, to: cols, by: 2) {
            // 内側（d-2、d=1 は中央の上ル）に色があるか
            func innerAt(_ r: Int) -> Bool {
                guard r >= 0, r < rows else { return false }
                return d >= 3 ? plane[r][d-2] > 0 : centerRise?[r] == true
            }
            var runStart: Int? = nil
            for r in 0...rows {
                let colored = r < rows && plane[r][d] > 0
                if colored && runStart == nil { runStart = r }
                if !colored, let a = runStart {
                    let b = r - 1
                    // 縞が内側から移ってきたか（直前の段か、1段おきの塗りなら2段前）
                    let fromInner = innerAt(a - 1) || innerAt(a - 2)
                    // 外側（d+2）へまだ続くか（1段おきの塗りも考慮して b+2 まで見る）
                    let toOuter = d + 2 < cols &&
                        (b...min(b + 2, rows - 1)).contains { plane[$0][d+2] > 0 }
                    // 内側が縞の始まる前から終端まで塗られたままなら、広がる模様（4-15型）なので出さない
                    let widening = innerAt(a - 1) && innerAt(b)
                    // 糸を変える操作（偶数列の糸交換）から45度で続いてきた色なら、
                    // 地色に戻る所までの間に糸交換を書かない（戻しが受け持つ）
                    var fromExchange = false
                    var rr = a, dd = d
                    while true {
                        if rr - 1 >= 0 && dd - 1 >= 0 && plane[rr-1][dd-1] > 0 { rr -= 1; dd -= 1 }
                        else if rr - 2 >= 0 && dd - 2 >= 0 && plane[rr-2][dd-2] > 0 { rr -= 2; dd -= 2 }
                        else { break }
                        if dd == 0 { fromExchange = true; break }  // 中央の糸交換が起点
                        if dd % 2 == 0 && fired[rr][dd] { fromExchange = true; break }  // 途中の糸交換が起点
                    }
                    if fromInner && !toOuter && !widening && !fromExchange {
                        tipNums[b].insert(min(d + 1, cols))
                    }
                    runStart = nil
                }
            }
        }
        for (r, row) in plane.enumerated() {
            let slots = sampledSlots(row, dir: dir)
            let cap = row.count
            let risesAtCenter = centerRise?[r] == true  // 中央の色による上ル
            // 45度に色を辿る（1段1目外。1段おきの塗りは2段2目でも続きとみなす）。
            // 歩調は一貫させる: 1段1目で進んできた連なりは2段2目へ乗り換えない（逆も同じ）。
            // 終端の段と、色の数（ステップ数）を返す
            func trace45(fromRow r0: Int, col d0: Int) -> (row: Int, col: Int, steps: Int) {
                var pr = r0, pd = d0, n = 0, pace = 0  // pace: 0=未定, 1, 2
                while true {
                    if pace != 2, pr + 1 < rows, pd + 1 < cap, plane[pr + 1][pd + 1] > 0 {
                        pr += 1; pd += 1; pace = 1
                    } else if pace != 1, pr + 2 < rows, pd + 2 < cap, plane[pr + 2][pd + 2] > 0 {
                        pr += 2; pd += 2; pace = 2
                    } else { break }
                    n += 1
                }
                return (pr, pd, n)
            }
            // 戻しは、45度の終端から先の「次の偶数列（交換できる目）」の段に、その位置の番号で行う:
            // 終端が偶数列なら2段先に+3、奇数列なら1段先に+2。
            // 一番端の列では糸交換ができない（端で折り返す）ため、着地が端の列以遠なら戻し不要
            func scheduleReturn(_ end: (row: Int, col: Int, steps: Int)) {
                let step = end.col % 2 == 0 ? 2 : 1
                let rCol = end.col + step
                guard rCol < cap - 1, end.row + step < rows else { return }
                sched[end.row + step].insert(min(rCol + 1, cap))
            }
            // 矢印（中央上ル）の後の戻しは反対の面で行う（中央単独=③、d2で終われば⑤）
            if oppositeRise?[r] == true {
                scheduleReturn(trace45(fromRow: r, col: 0))
            }
            // 偶数列（縦に進む列）は糸交換のみ: 番号は中央=1からの通し（d+1）。
            // 交換した対は45度（1段ごとに1目外）で進み、色が地色になる所で元に戻す
            // （最後に色が続いた位置の2段先・番号+3。交換の2段先より先になることがある）。
            // 番号は片面の目数（60玉=13、68玉=15）が上限。
            // 45度で続いてきた色（前段の±1目、または1段おきなら2段前の2目内側。中央含む）は
            // 色が変わるところではないので交換しない
            var exchNums = tipNums[r]  // 斜めの縞の一番先の糸交換（戻しなし）
            for d in stride(from: 2, to: row.count, by: 2) where row[d] > 0 {
                if !fired[r][d] { continue }  // 糸交換の連なりの続き（carried）は書かない
                exchNums.insert(min(d + 1, cap))
                scheduleReturn(trace45(fromRow: r, col: d))
            }
            var aya: String
            var isBridge = false
            if !slots.contains(true) {
                aya = "ナミ"
                if risesAtCenter {
                    // 中央だけで上がる段: 数には入れず、続き扱い（書籍 4-15 のナミ⬆段は②〜nに入らない）
                    isBridge = true
                    hadCenter = true
                } else {
                    let pairs: Set<Int>
                    if opRun > 0 && hadArrow && !hadCenter {
                        // 手取りの⬆のみのブロック: 書籍 4-15 の一括の戻し（数字は片面の目数が上限）
                        pairs = Set(2...min(opRun + 2, cap))
                    } else {
                        // 上の操作には戻し不要。飛びの糸交換の分だけ戻す
                        pairs = opRun > 0 ? blockPairs : []
                    }
                    if r + 1 < rows { sched[r + 1].formUnion(pairs) }
                    opRun = 0
                    blockPairs.removeAll()
                    hadCenter = false
                    hadArrow = false
                }
            } else {
                if let prev = prevSlots, opRun >= 2 {
                    // 斜めに色が続く（前段の±1目から移ってきた）目は交換に数えない。
                    // 色が変わるところ（斜めから繋がらない新しい目）だけ糸交換
                    let added = slots.indices.filter { i in
                        slots[i] && !prev[i]
                            && !(i > 0 && prev[i - 1])
                            && !(i + 1 < prev.count && prev[i + 1])
                    }.count
                    if added >= 2 {
                        exchNums.formUnion(2...min(opRun, cap))
                        // 飛びで交換した対は番号+2で戻す（糸交換の2 → ④。片面の目数が上限）
                        blockPairs.formUnion((2...min(opRun, cap)).map { min($0 + 2, cap) })
                    }
                }
                aya = ayaName(slots)
                opRun += 1
                if arrows?[r] == true { hadArrow = true }
                if risesAtCenter { hadCenter = true }
            }
            if arrows?[r] == true { aya += "⬆" }  // 中央で上ル
            // 糸交換と戻しは1つの数列にまとめて前置（数値順。手書きの綾書の書式）
            let nums = numberList(circled: sched[r], plain: exchNums,
                                  beforeNami: aya.hasPrefix("ナミ"))
            texts.append(nums + aya)
            if !isBridge { prevSlots = slots }
        }
        return texts
    }

    /// 全段を生成する（段は省略せず1段ずつ）
    static func groups(cells: CellGrid, dir: ReadDirection) -> [NotationGroup] {
        let rows = cells.L.count
        let arrowsL = (0..<rows).map { cells.hasArrow(side: .left, row: $0) }
        let arrowsR = (0..<rows).map { cells.hasArrow(side: .right, row: $0) }
        // 中央で上がる糸の色は反対側の中央列（d=0）に置かれる。
        // 記号の法則は左右同一（⬆の表示位置だけ左が1段前 = C の自動書き込みで対応）
        let riseL = (0..<rows).map { cells.R[$0].first ?? 0 > 0 }
        let riseR = (0..<rows).map { cells.L[$0].first ?? 0 > 0 }
        let lefts = sideTexts(cells.L, dir: dir, arrows: arrowsL, centerRise: riseL, oppositeRise: riseR)
        let rights = sideTexts(cells.R, dir: dir, arrows: arrowsR, centerRise: riseR, oppositeRise: riseL)
        return (0..<lefts.count).map {
            NotationGroup(from: $0, to: $0, left: lefts[$0], right: rights[$0])
        }
    }
}
