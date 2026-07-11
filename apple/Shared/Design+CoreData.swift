import CoreData

@objc(Design)
public class Design: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var tama: Int16
    @NSManaged public var rows: Int16
    @NSManaged public var readDir: String?
    @NSManaged public var paletteJSON: String?
    @NSManaged public var cellsData: Data?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
}

extension Design {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Design> {
        NSFetchRequest<Design>(entityName: "Design")
    }

    var displayName: String {
        let n = name ?? ""
        return n.isEmpty ? "無題" : n
    }

    /// エンティティ → 値型スナップショット
    var snapshot: DesignSnapshot {
        let cols = BraidSpec.cols(forTama: Int(tama))
        let rowCount = rows > 0 ? Int(rows) : BraidSpec.defaultRows
        var cells = CellGrid.empty(rows: rowCount, cols: cols)
        if let data = cellsData, let decoded = try? JSONDecoder().decode(CellGrid.self, from: data) {
            cells = decoded.resized(rows: rowCount, cols: cols)
        }
        var palette = BraidSpec.defaultPalette
        if let pj = paletteJSON,
           let decoded = try? JSONDecoder().decode([String].self, from: Data(pj.utf8)),
           decoded.count == 4 {
            palette = decoded
        }
        return DesignSnapshot(name: name ?? "", tama: Int(tama),
                              rows: rowCount, palette: palette, cells: cells, readDir: readDir)
            .normalized()
    }

    /// 値型スナップショット → エンティティ
    func apply(snapshot: DesignSnapshot) {
        let s = snapshot.normalized()
        name = s.name
        tama = Int16(s.tama)
        rows = Int16(s.rows)
        readDir = s.readDir
        paletteJSON = (try? JSONEncoder().encode(s.palette)).flatMap { String(data: $0, encoding: .utf8) }
        cellsData = try? JSONEncoder().encode(s.cells)
        updatedAt = Date()
        if createdAt == nil { createdAt = Date() }
        if id == nil { id = UUID() }
    }
}
