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
    /// 玉数 → 片面の目数（書籍 4-10/4-11 の綾書定規の目盛り: 60玉=1〜13、68玉=1〜15）
    static func cols(forTama tama: Int) -> Int { tama == 68 ? 15 : 13 }
    static let tamaOptions = [60, 68]
    static let rowRange = 4...120
    static let defaultRows = 40
    static let defaultPalette = ["#DFE6C4", "#A2653A", "#3F5DA8", "#C8B23C"]
    static let paletteLabels = ["地", "柄1", "柄2", "柄3"]

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

    /// その段の記号に ⬆（中央で上ル）を付けるか。
    /// 中央の2列（d=0）に色が置かれた段は自動で ⬆、それ以外は手動指定（C）による
    func hasArrow(side: BraidSide, row: Int) -> Bool {
        let plane = side == .right ? R : L
        if row < plane.count, (plane[row].first ?? 0) > 0 { return true }
        guard let C else { return false }
        if C.count == L.count { return row < C.count && C[row] > 0 }  // 旧形式
        let j = side == .right ? 2 * row : 2 * row + 1
        return j < C.count && C[j] > 0
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
        s.tama = tama == 68 ? 68 : 60
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
    /// 丸数字（糸が元の段に戻った目数に付ける。書籍 4-13 の丸印）
    private static func circled(_ n: Int) -> String {
        if (1...20).contains(n), let scalar = UnicodeScalar(0x2460 + n - 1) {
            return String(Character(scalar))
        }
        return "(\(n))"
    }

    /// 綾の読みで使う「入れかえの目」＝1目おき（偶数目盛り d=1,3,5,…、60玉=6目／68玉=7目）
    private static func sampledSlots(_ rowCells: [Int], dir: ReadDirection) -> [Bool] {
        let sampled = stride(from: 1, to: rowCells.count, by: 2).map { rowCells[$0] > 0 }
        return dir == .edge ? sampled.reversed() : Array(sampled)
    }

    /// 綾名（ナミ／上n下m…）。書籍 4-15 の書式:
    /// ・中央から始まる単純な浮き（上n＋残り下）は「上n」と略記
    /// ・それ以外は全区間を書き、3区間以上では 1 を省く（「下上下4」形式）
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
        if runs.first?.flag == true && runs.count <= 2 {
            return "上\(runs[0].n)"
        }
        let omitOnes = runs.count >= 3
        return runs.map { run in
            let label = run.flag ? "上" : "下"
            return (omitOnes && run.n == 1) ? label : label + "\(run.n)"
        }.joined()
    }

    /// 丸数字の範囲（3個以下は並記、4個以上は ②〜⑩ 形式）
    private static func circledRange(_ from: Int, _ to: Int) -> String {
        guard to >= from else { return "" }
        if to - from + 1 <= 3 { return (from...to).map(circled).joined() }
        return circled(from) + "〜" + circled(to)
    }

    /// 糸交換の番号列（2.3.4.5.6 形式）
    private static func plainList(_ from: Int, _ to: Int) -> String {
        guard to >= from else { return "" }
        return (from...to).map(String.init).joined(separator: ".") + " "
    }

    /// 片面の全段の記号（糸交換リスト＋綾名）。書籍 4-15 の実例に合わせた規則:
    /// ・模様が M 段続いた直後の空段 → 「②〜(M+2)ナミ」（入れかえていた糸を一括で戻す）
    /// ・入れかえの目が一度に2目以上増える段 → 「2.3…M 」の糸交換を前置（飛びの変化）
    /// ・±1目の漸進変化は綾の手取りだけで賄うため数字なし
    static func sideTexts(_ plane: [[Int]], dir: ReadDirection, arrows: [Bool]? = nil) -> [String] {
        var texts: [String] = []
        var opRun = 0          // 連続する模様（非ナミ）段数
        var prevSlots: [Bool]?
        for (r, row) in plane.enumerated() {
            let slots = sampledSlots(row, dir: dir)
            var text: String
            if !slots.contains(true) {
                text = opRun > 0 ? circledRange(2, opRun + 2) + "ナミ" : "ナミ"
                opRun = 0
            } else {
                var prefix = ""
                if let prev = prevSlots, opRun >= 2 {
                    let added = zip(slots, prev).filter { $0.0 && !$0.1 }.count
                    if added >= 2 { prefix = plainList(2, opRun) }
                }
                text = prefix + ayaName(slots)
                opRun += 1
            }
            if arrows?[r] == true { text += "⬆" }  // 中央で上ル
            texts.append(text)
            prevSlots = slots
        }
        return texts
    }

    /// 全段を生成し、連続する同一手順の段をまとめる
    static func groups(cells: CellGrid, dir: ReadDirection) -> [NotationGroup] {
        let rows = cells.L.count
        let arrowsL = (0..<rows).map { cells.hasArrow(side: .left, row: $0) }
        let arrowsR = (0..<rows).map { cells.hasArrow(side: .right, row: $0) }
        let lefts = sideTexts(cells.L, dir: dir, arrows: arrowsL)
        let rights = sideTexts(cells.R, dir: dir, arrows: arrowsR)
        var out: [NotationGroup] = []
        for r in 0..<lefts.count {
            if let last = out.last, last.left == lefts[r], last.right == rights[r] {
                out[out.count - 1].to = r
            } else {
                out.append(NotationGroup(from: r, to: r, left: lefts[r], right: rights[r]))
            }
        }
        return out
    }
}
