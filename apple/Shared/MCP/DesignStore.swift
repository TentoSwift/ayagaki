#if os(macOS)
import CoreData
import Foundation

struct StoreError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// MCP ツールから Core Data のデザインを読み書きする。
/// すべての操作をコンテキストのキュー上（performAndWait）で実行するため、
/// viewContext（GUI・HTTP サーバ）でもバックグラウンドコンテキスト（stdio サーバ）でも安全に使える。
/// 変更後は externalChange 通知を送り、開いているエディタに反映させる。
final class DesignStore: @unchecked Sendable {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - 取得

    func list() throws -> [[String: Any]] {
        try context.performAndWait {
            context.refreshAllObjects()  // 他プロセスの変更を確実に読む
            let req = Design.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(req).map { summary(of: $0) }
        }
    }

    func get(id: String) throws -> [String: Any] {
        try context.performAndWait {
            let design = try find(id)
            let s = design.snapshot
            var dict = summary(of: design)
            dict["palette"] = s.palette
            dict["readDir"] = s.readDir ?? "center"
            dict["colsPerSide"] = BraidSpec.cols(forTama: s.tama)
            dict["cells"] = ["L": s.cells.L, "R": s.cells.R,
                             "C": s.cells.C ?? [Int](repeating: 0, count: s.rows * 2)]
            dict["notation"] = notationRows(s)
            return dict
        }
    }

    func notation(id: String) throws -> [String: Any] {
        try context.performAndWait {
            let s = try find(id).snapshot
            return ["rows": s.rows, "notation": notationRows(s)]
        }
    }

    /// PDF 書き出し用にスナップショットと表示名を取り出す
    func snapshotAndName(id: String) throws -> (snapshot: DesignSnapshot, name: String) {
        try context.performAndWait {
            let design = try find(id)
            return (design.snapshot, design.displayName)
        }
    }

    // MARK: - 作成・更新

    func create(name: String, tama: Int?, rows: Int?) throws -> [String: Any] {
        try context.performAndWait {
            let design = Design(context: context)
            design.apply(snapshot: DesignSnapshot(
                name: name,
                tama: tama ?? 60,
                rows: rows ?? BraidSpec.defaultRows,
                palette: BraidSpec.defaultPalette,
                cells: .empty(rows: rows ?? BraidSpec.defaultRows,
                              cols: BraidSpec.cols(forTama: tama ?? 60)),
                readDir: ReadDirection.center.rawValue))
            try saveAndNotify(design)
            return summary(of: design)
        }
    }

    func update(id: String, name: String?, tama: Int?, rows: Int?,
                readDir: String?, palette: [String]?) throws -> [String: Any] {
        try context.performAndWait {
            let design = try find(id)
            var s = design.snapshot
            if let name { s.name = name }
            if let tama {
                guard BraidSpec.tamaOptions.contains(tama) else {
                    throw StoreError("tama は 60 か 68 を指定してください")
                }
                s.tama = tama
            }
            if let rows {
                guard BraidSpec.rowRange.contains(rows) else {
                    throw StoreError("rows は \(BraidSpec.rowRange.lowerBound)〜\(BraidSpec.rowRange.upperBound) で指定してください")
                }
                s.rows = rows
            }
            if let readDir {
                guard ReadDirection(rawValue: readDir) != nil else {
                    throw StoreError("readDir は edge か center を指定してください")
                }
                s.readDir = readDir
            }
            if let palette {
                guard palette.count == 4 else { throw StoreError("palette は 4 色（#RRGGBB）の配列です") }
                s.palette = palette
            }
            design.apply(snapshot: s)
            try saveAndNotify(design)
            return summary(of: design)
        }
    }

    /// グリッド全体を置き換える。次元は rows × colsPerSide に一致している必要がある。
    /// cellsC は中央のジグザグ目（rows 個、省略可）。
    func setCells(id: String, cellsL: [[Int]], cellsR: [[Int]], cellsC: [Int]?) throws -> [String: Any] {
        try context.performAndWait {
            let design = try find(id)
            var s = design.snapshot
            let cols = BraidSpec.cols(forTama: s.tama)
            for (label, plane) in [("L", cellsL), ("R", cellsR)] {
                guard plane.count == s.rows, plane.allSatisfy({ $0.count == cols }) else {
                    throw StoreError("cells.\(label) の次元が不正です。\(s.rows)行 × \(cols)列（片面）で指定してください")
                }
                guard plane.allSatisfy({ $0.allSatisfy { (0...3).contains($0) } }) else {
                    throw StoreError("セル値は 0（地）〜 3（柄3）です")
                }
            }
            if let cellsC {
                guard cellsC.count == s.rows * 2 || cellsC.count == s.rows,
                      cellsC.allSatisfy({ (0...3).contains($0) }) else {
                    throw StoreError("cells.C は \(s.rows * 2) 個（各段2目: index 2r=右の上ル目, 2r+1=左の上ル目）・値 0〜3 で指定してください")
                }
            }
            s.cells = CellGrid(L: cellsL, R: cellsR,
                               C: cellsC ?? [Int](repeating: 0, count: s.rows * 2))
                .resized(rows: s.rows, cols: cols)  // 旧形式の C を展開
            design.apply(snapshot: s)
            try saveAndNotify(design)
            return ["ok": true, "notation": notationRows(s)]
        }
    }

    /// 矩形（段範囲 × 目範囲）を塗る。pos は綾書定規の目盛りと同じで中央=1 … 外端=colsPerSide。
    func paint(id: String, ops: [[String: Any]]) throws -> [String: Any] {
        try context.performAndWait {
            let design = try find(id)
            var s = design.snapshot
            let cols = BraidSpec.cols(forTama: s.tama)

            for (i, op) in ops.enumerated() {
                guard let sideStr = op["side"] as? String, ["L", "R", "both", "C"].contains(sideStr) else {
                    throw StoreError("ops[\(i)].side は L / R / both / C（中央のジグザグ目）を指定してください")
                }
                guard let color = op["color"] as? Int, (0...3).contains(color) else {
                    throw StoreError("ops[\(i)].color は 0（地）〜 3 を指定してください")
                }
                let rowFrom = op["rowFrom"] as? Int ?? 1
                let rowTo = op["rowTo"] as? Int ?? rowFrom
                let posFrom = op["posFrom"] as? Int ?? 1
                let posTo = op["posTo"] as? Int ?? posFrom
                guard rowFrom >= 1, rowTo <= s.rows, rowFrom <= rowTo else {
                    throw StoreError("ops[\(i)] の段範囲が不正です（1〜\(s.rows)）")
                }
                if sideStr == "C" {
                    // 中央の上ル目（各段2目）。pos: 1=右の目のみ、2=左の目のみ、省略=両方
                    let half = op["posFrom"] as? Int
                    for r in (rowFrom - 1)...(rowTo - 1) {
                        if half == nil || half == 1 { s.cells.set(side: .center, r: 2 * r, d: 0, to: color) }
                        if half == nil || half == 2 { s.cells.set(side: .center, r: 2 * r + 1, d: 0, to: color) }
                    }
                    continue
                }
                guard posFrom >= 1, posTo <= cols, posFrom <= posTo else {
                    throw StoreError("ops[\(i)] の目範囲が不正です（1〜\(cols)、1=中央）")
                }
                let sides: [BraidSide] = sideStr == "both" ? [.left, .right]
                    : (sideStr == "L" ? [.left] : [.right])
                for side in sides {
                    for r in (rowFrom - 1)...(rowTo - 1) {
                        for pos in posFrom...posTo {
                            s.cells.set(side: side, r: r, d: pos - 1, to: color)
                        }
                    }
                }
            }
            design.apply(snapshot: s)
            try saveAndNotify(design)
            return ["ok": true, "notation": notationRows(s)]
        }
    }

    func clearCells(id: String) throws -> [String: Any] {
        try context.performAndWait {
            let design = try find(id)
            var s = design.snapshot
            s.cells = .empty(rows: s.rows, cols: BraidSpec.cols(forTama: s.tama))
            design.apply(snapshot: s)
            try saveAndNotify(design)
            return ["ok": true]
        }
    }

    func delete(id: String) throws -> [String: Any] {
        try context.performAndWait {
            let design = try find(id)
            let name = design.displayName
            context.delete(design)
            try context.save()
            NotificationCenter.default.post(name: BraidSpec.externalChangeNotification, object: nil)
            return ["ok": true, "deleted": name]
        }
    }

    // MARK: - 内部（すべて performAndWait の中から呼ばれる）

    private func find(_ idString: String) throws -> Design {
        context.refreshAllObjects()  // 他プロセスの変更を確実に読む
        guard let uuid = UUID(uuidString: idString) else {
            throw StoreError("id は list_designs で取得した UUID を指定してください")
        }
        let req = Design.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        req.fetchLimit = 1
        guard let design = try context.fetch(req).first else {
            throw StoreError("id \(idString) のデザインが見つかりません")
        }
        return design
    }

    private func summary(of design: Design) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "id": design.id?.uuidString ?? "",
            "name": design.displayName,
            "tama": Int(design.tama),
            "rows": Int(design.rows),
            "colsPerSide": BraidSpec.cols(forTama: Int(design.tama)),
            "updatedAt": design.updatedAt.map { iso.string(from: $0) } ?? "",
        ]
    }

    private func notationRows(_ s: DesignSnapshot) -> [[String: Any]] {
        let dir = ReadDirection(rawValue: s.readDir ?? "") ?? .center
        return Notation.groups(cells: s.cells, dir: dir).map {
            ["rows": $0.label, "left": $0.left, "right": $0.right]
        }
    }

    private func saveAndNotify(_ design: Design) throws {
        try context.save()
        NotificationCenter.default.post(name: BraidSpec.externalChangeNotification,
                                        object: design.objectID)
    }
}
#endif
