import Foundation
import CoreGraphics
import CoreText

/// 手順書 PDF（タイトル + 綾書グリッド + 交換記号表）を CoreGraphics で描く。
/// SwiftUI に依存しないため、GUI のない stdio MCP プロセスでも動作する。
struct PDFSheetRenderer {
    let snapshot: DesignSnapshot
    let title: String

    private let margin: CGFloat = 24
    private let cell: CGFloat = 9          // 菱形の半径
    private let notationColWidths: (rows: CGFloat, half: CGFloat) = (48, 158)
    private let notationRowHeight: CGFloat = 14

    func render() -> Data? {
        let cols = BraidSpec.cols(forTama: snapshot.tama)
        let geo = GridGeometry(cols: cols, rows: snapshot.rows, cell: cell)
        let groups = Notation.groups(
            cells: snapshot.cells,
            dir: ReadDirection(rawValue: snapshot.readDir ?? "") ?? .center)

        let titleH: CGFloat = 34
        let notationW = notationColWidths.rows + 2 * notationColWidths.half
        let notationH = CGFloat(groups.count + 1) * notationRowHeight + 26  // ヘッダ + 凡例
        let width = margin + geo.size.width + 20 + notationW + margin
        let height = margin + titleH + max(geo.size.height, notationH) + margin

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        ctx.beginPDFPage(nil)
        // 上から下へ描けるよう座標を反転
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)

        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(box)

        drawText(title, at: CGPoint(x: margin, y: margin + 16), size: 15, bold: true,
                 color: gray(0.15), ctx: ctx)

        drawGrid(geo: geo, origin: CGPoint(x: margin, y: margin + titleH), ctx: ctx)
        drawNotation(groups: groups,
                     origin: CGPoint(x: margin + geo.size.width + 20, y: margin + titleH),
                     ctx: ctx)

        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    // MARK: グリッド

    private func drawGrid(geo: GridGeometry, origin: CGPoint, ctx: CGContext) {
        let colors = snapshot.palette.map { cgColor(hex: $0) }
        let line = gray(0.55)

        for r in 0..<geo.rows {
            for side in [BraidSide.left, .right] {
                for d in 0..<geo.cols {
                    let c = geo.center(side: side, r: r, d: d)
                    let p = CGPoint(x: origin.x + c.x, y: origin.y + c.y)
                    let v = snapshot.cells.value(side: side, r: r, d: d)
                    diamond(at: p, ctx: ctx)
                    ctx.setFillColor(colors[min(max(v, 0), colors.count - 1)])
                    ctx.fillPath()
                    diamond(at: p, ctx: ctx)
                    ctx.setStrokeColor(line)
                    ctx.setLineWidth(0.4)
                    ctx.strokePath()
                }
            }
            // 段番号（両端）
            let yOuter = origin.y + geo.center(side: .left, r: r, d: geo.cols - 1).y
            drawText("\(r + 1)", at: CGPoint(x: origin.x + geo.margin + geo.numW - 6, y: yOuter + 2.5),
                     size: 7, bold: false, color: gray(0.45), ctx: ctx, alignRight: true)
            drawText("\(r + 1)", at: CGPoint(x: origin.x + geo.size.width - geo.margin - geo.numW + 6, y: yOuter + 2.5),
                     size: 7, bold: false, color: gray(0.45), ctx: ctx)
        }

        // 中央の上ル目（向きが一目ずつ交互のマス）とジグザグ線
        for j in 0..<(geo.rows * 2) {
            let corners = geo.centerBarCorners(j).map {
                CGPoint(x: origin.x + $0.x, y: origin.y + $0.y)
            }
            let v = snapshot.cells.value(side: .center, r: j, d: 0)
            ctx.beginPath()
            ctx.addLines(between: corners)
            ctx.closePath()
            ctx.setFillColor(colors[min(max(v, 0), colors.count - 1)])
            ctx.fillPath()
            ctx.beginPath()
            ctx.addLines(between: corners)
            ctx.closePath()
            ctx.setStrokeColor(line)
            ctx.setLineWidth(0.4)
            ctx.strokePath()
        }
        ctx.setStrokeColor(gray(0.45))
        ctx.setLineWidth(0.8)
        ctx.move(to: CGPoint(x: origin.x + geo.cx, y: origin.y + geo.y0))
        for j in 0..<(geo.rows * 2) {
            let p = geo.center(side: .center, r: j, d: 0)
            let outerX = j % 2 == 0 ? p.x - geo.cell / 2 : p.x + geo.cell / 2
            ctx.addLine(to: CGPoint(x: origin.x + outerX, y: origin.y + p.y))
        }
        ctx.addLine(to: CGPoint(x: origin.x + geo.cx,
                                y: origin.y + geo.y0 + CGFloat(geo.rows * 2) * geo.cell))
        ctx.strokePath()
    }

    private func diamond(at p: CGPoint, ctx: CGContext) {
        ctx.beginPath()
        ctx.move(to: CGPoint(x: p.x, y: p.y - cell))
        ctx.addLine(to: CGPoint(x: p.x + cell, y: p.y))
        ctx.addLine(to: CGPoint(x: p.x, y: p.y + cell))
        ctx.addLine(to: CGPoint(x: p.x - cell, y: p.y))
        ctx.closePath()
    }

    // MARK: 記号表

    private func drawNotation(groups: [NotationGroup], origin: CGPoint, ctx: CGContext) {
        let (rowsW, halfW) = notationColWidths
        var y = origin.y + 11

        for (label, offset) in [("段", 0.0), ("左半面", rowsW), ("右半面", rowsW + halfW)] {
            drawText(label, at: CGPoint(x: origin.x + CGFloat(offset), y: y),
                     size: 8.5, bold: true, color: gray(0.4), ctx: ctx)
        }
        y += 4
        hline(at: y, from: origin.x, width: rowsW + 2 * halfW, ctx: ctx)

        for g in groups {
            y += notationRowHeight
            drawText(g.label, at: CGPoint(x: origin.x, y: y - 3.5),
                     size: 8.5, bold: true, color: gray(0.3), ctx: ctx)
            drawText(g.left, at: CGPoint(x: origin.x + rowsW, y: y - 3.5),
                     size: 8.5, bold: false, color: gray(0.15), ctx: ctx)
            drawText(g.right, at: CGPoint(x: origin.x + rowsW + halfW, y: y - 3.5),
                     size: 8.5, bold: false, color: gray(0.15), ctx: ctx)
            hline(at: y, from: origin.x, width: rowsW + 2 * halfW, ctx: ctx)
        }

        drawText("綾名：ナミ／上n＝上n下(6−n)の手取り ／ 先頭の数字：糸交換（上下段の糸を入れかえる位置）／ 丸数字：入れかえて元の色に戻す",
                 at: CGPoint(x: origin.x, y: y + 16), size: 7, bold: false,
                 color: gray(0.45), ctx: ctx)
    }

    private func hline(at y: CGFloat, from x: CGFloat, width: CGFloat, ctx: CGContext) {
        ctx.setStrokeColor(gray(0.85))
        ctx.setLineWidth(0.4)
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + width, y: y))
        ctx.strokePath()
    }

    // MARK: テキスト・色

    /// 反転済み（上から下）座標系でベースライン位置にテキストを描く
    private func drawText(_ string: String, at p: CGPoint, size: CGFloat, bold: Bool,
                          color: CGColor, ctx: CGContext, alignRight: Bool = false) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes))
        var x = p.x
        if alignRight {
            x -= CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        ctx.saveGState()
        ctx.translateBy(x: x, y: p.y)
        ctx.scaleBy(x: 1, y: -1)   // テキストだけ元の向きに戻す
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func cgColor(hex: String) -> CGColor {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private func gray(_ w: CGFloat) -> CGColor {
        CGColor(srgbRed: w, green: w, blue: w, alpha: 1)
    }
}
