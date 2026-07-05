import Foundation

// MARK: - 基本型

enum BraidSide: String, Codable {
    case left = "L"
    case right = "R"

    var opposite: BraidSide { self == .left ? .right : .left }
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

    static func empty(rows: Int, cols: Int) -> CellGrid {
        let plane = [[Int]](repeating: [Int](repeating: 0, count: cols), count: rows)
        return CellGrid(L: plane, R: plane)
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
        return out
    }

    func value(side: BraidSide, r: Int, d: Int) -> Int {
        side == .left ? L[r][d] : R[r][d]
    }

    mutating func set(side: BraidSide, r: Int, d: Int, to v: Int) {
        if side == .left { L[r][d] = v } else { R[r][d] = v }
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
    static func sideTexts(_ plane: [[Int]], dir: ReadDirection) -> [String] {
        var texts: [String] = []
        var opRun = 0          // 連続する模様（非ナミ）段数
        var prevSlots: [Bool]?
        for row in plane {
            let slots = sampledSlots(row, dir: dir)
            if !slots.contains(true) {
                texts.append(opRun > 0 ? circledRange(2, opRun + 2) + "ナミ" : "ナミ")
                opRun = 0
            } else {
                var prefix = ""
                if let prev = prevSlots, opRun >= 2 {
                    let added = zip(slots, prev).filter { $0.0 && !$0.1 }.count
                    if added >= 2 { prefix = plainList(2, opRun) }
                }
                texts.append(prefix + ayaName(slots))
                opRun += 1
            }
            prevSlots = slots
        }
        return texts
    }

    /// 全段を生成し、連続する同一手順の段をまとめる
    static func groups(cells: CellGrid, dir: ReadDirection) -> [NotationGroup] {
        let lefts = sideTexts(cells.L, dir: dir)
        let rights = sideTexts(cells.R, dir: dir)
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
