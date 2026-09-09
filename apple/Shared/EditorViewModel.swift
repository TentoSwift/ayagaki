import SwiftUI
import CoreData

@MainActor
final class EditorViewModel: ObservableObject {
    let design: Design
    private let context: NSManagedObjectContext

    @Published var tama: Int
    @Published var rowCount: Int
    @Published var cells: CellGrid
    @Published var palette: [String]
    @Published var currentColor: Int = 1
    @Published var symmetric: Bool = false
    @Published var highlighted: ClosedRange<Int>? = nil

    private var undoStack: [CellGrid] = []
    private var strokeActive = false
    private var saveTask: Task<Void, Never>?
    private var dirty = false

    var cols: Int { BraidSpec.cols(forTama: tama) }
    var canUndo: Bool { !undoStack.isEmpty }
    var notationGroups: [NotationGroup] { Notation.groups(cells: cells) }
    /// 手取り図の全段表示用（同じ記号が続く段はまとめる）
    var tedoriGroups: [NotationGroup] { Notation.tedoriGroups(cells: cells) }

    private var externalChangeObserver: NSObjectProtocol?

    init(design: Design, context: NSManagedObjectContext) {
        self.design = design
        self.context = context
        let s = design.snapshot
        tama = s.tama
        rowCount = s.rows
        cells = s.cells
        palette = s.palette

        // MCP サーバなど外部からの変更を画面に反映する
        let objectID = design.objectID
        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: BraidSpec.externalChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard note.object as? NSManagedObjectID == objectID else { return }
            Task { @MainActor in self?.reloadFromDesign() }
        }
    }

    deinit {
        if let externalChangeObserver {
            NotificationCenter.default.removeObserver(externalChangeObserver)
        }
    }

    private func reloadFromDesign() {
        guard !design.isDeleted, design.managedObjectContext != nil else { return }
        let s = design.snapshot
        tama = s.tama
        rowCount = s.rows
        cells = s.cells
        palette = s.palette
    }

    var snapshotValue: DesignSnapshot {
        DesignSnapshot(name: design.name ?? "", tama: tama, rows: rowCount,
                       palette: palette, cells: cells)
    }

    // MARK: 塗り

    func strokeChanged(at point: CGPoint, geometry: GridGeometry) {
        guard let hit = geometry.hitTest(point) else { return }
        if !strokeActive {
            strokeActive = true
            pushUndo()
        }
        paint(side: hit.side, r: hit.r, d: hit.d)
    }

    func strokeEnded() {
        guard strokeActive else { return }
        strokeActive = false
        scheduleSave()
    }

    func tap(at point: CGPoint, geometry: GridGeometry) {
        guard let hit = geometry.hitTest(point) else { return }
        pushUndo()
        paint(side: hit.side, r: hit.r, d: hit.d)
        scheduleSave()
    }

    private func paint(side: BraidSide, r: Int, d: Int) {
        if side == .center {
            // 中央の上ル目（r は通し番号 0..2*rows-1）。塗るとその段に ⬆ が付く
            guard r >= 0, r < rowCount * 2 else { return }
            if cells.value(side: .center, r: r, d: 0) != currentColor {
                cells.set(side: .center, r: r, d: 0, to: currentColor)
            }
            return
        }
        guard r >= 0, r < rowCount else { return }
        guard d >= 0, d < cols else { return }
        if cells.value(side: side, r: r, d: d) != currentColor {
            cells.set(side: side, r: r, d: d, to: currentColor)
            if d == 0 { cells.syncArrowFromCenterColor(side: side, row: r) }
        }
        if symmetric, cells.value(side: side.opposite, r: r, d: d) != currentColor {
            cells.set(side: side.opposite, r: r, d: d, to: currentColor)
            if d == 0 { cells.syncArrowFromCenterColor(side: side.opposite, row: r) }
        }
    }

    // MARK: 元に戻す・全消去

    private func pushUndo() {
        undoStack.append(cells)
        if undoStack.count > 100 { undoStack.removeFirst() }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        cells = prev.resized(rows: rowCount, cols: cols)
        scheduleSave()
    }

    func clearAll() {
        pushUndo()
        cells = .empty(rows: rowCount, cols: cols)
        scheduleSave()
    }

    // MARK: 設定変更

    func setTama(_ t: Int) {
        guard t != tama else { return }
        pushUndo()
        tama = t
        cells = cells.resized(rows: rowCount, cols: cols)
        scheduleSave()
    }

    func setRows(_ n: Int) {
        let v = min(BraidSpec.rowRange.upperBound, max(BraidSpec.rowRange.lowerBound, n))
        guard v != rowCount else { return }
        pushUndo()
        rowCount = v
        cells = cells.resized(rows: v, cols: cols)
        scheduleSave()
    }

    func setPaletteColor(_ hex: String, at index: Int) {
        guard palette.indices.contains(index) else { return }
        palette[index] = hex
        scheduleSave()
    }

    func rename(_ newName: String) {
        design.name = newName
        scheduleSave()
    }

    // MARK: 読み込み（JSON インポート）

    func applyImported(_ snapshot: DesignSnapshot) {
        pushUndo()
        let s = snapshot.normalized()
        tama = s.tama
        rowCount = s.rows
        palette = s.palette
        cells = s.cells
        if !s.name.isEmpty { design.name = s.name }
        scheduleSave()
    }

    // MARK: 保存（デバウンス）

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.performSave()
        }
    }

    func flushSave() {
        saveTask?.cancel()
        performSave()
    }

    private func performSave() {
        // 実際に編集されたときだけ保存する（開いただけで updatedAt を進めない）
        guard dirty, !design.isDeleted, design.managedObjectContext != nil else { return }
        design.apply(snapshot: snapshotValue)
        do {
            try context.save()
            dirty = false
        } catch {
            NSLog("Ayagaki: 保存に失敗: \(error.localizedDescription)")
        }
    }
}
