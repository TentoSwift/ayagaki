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

    /// 1段・片面ぶんの記号（書籍 4-13 の形式）。
    /// 上n＝n目入れかえて浮かせる／下n＝n目そのまま。末尾の「下」は省略。
    /// 入れかえなしの段は「ナミ」。前の段で入れかえていた糸が元に戻る「下」の目数には丸を付ける。
    /// rowCells は d=0（中央）〜 N-1（外端）
    static func rowText(_ rowCells: [Int], previous: [Int]?, dir: ReadDirection) -> String {
        func ordered(_ cells: [Int]) -> [Bool] {
            switch dir {
            case .edge:   return cells.reversed().map { $0 > 0 }
            case .center: return cells.map { $0 > 0 }
            }
        }
        let flags = ordered(rowCells)
        let prevFlags = previous.map(ordered)

        var runs: [(flag: Bool, start: Int, n: Int)] = []
        for (i, f) in flags.enumerated() {
            if let last = runs.last, last.flag == f {
                runs[runs.count - 1].n += 1
            } else {
                runs.append((f, i, 1))
            }
        }
        if runs.count == 1 && runs[0].flag == false { return "ナミ" }
        // 末尾の「そのまま」区間は書かない
        if let last = runs.last, last.flag == false { runs.removeLast() }

        return runs.map { run in
            if run.flag { return "上\(run.n)" }
            // 前の段で入れかえていた糸が元に戻る場合は数字に丸
            let returned = prevFlags.map { prev in
                (run.start..<(run.start + run.n)).contains { prev[$0] }
            } ?? false
            return "下" + (returned ? circled(run.n) : "\(run.n)")
        }.joined()
    }

    /// 全段を生成し、連続する同一手順の段をまとめる
    static func groups(cells: CellGrid, dir: ReadDirection) -> [NotationGroup] {
        var out: [NotationGroup] = []
        for r in 0..<cells.L.count {
            let prevL = r > 0 ? cells.L[r - 1] : nil
            let prevR = r > 0 ? cells.R[r - 1] : nil
            let l = rowText(cells.L[r], previous: prevL, dir: dir)
            let rt = rowText(cells.R[r], previous: prevR, dir: dir)
            if let last = out.last, last.left == l, last.right == rt {
                out[out.count - 1].to = r
            } else {
                out.append(NotationGroup(from: r, to: r, left: l, right: rt))
            }
        }
        return out
    }
}
