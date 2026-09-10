import SwiftUI
import UniformTypeIdentifiers

// MARK: - 書き出し用 FileDocument

struct JSONFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - PDF 手順書（CoreGraphics 直描き — GUI のない stdio MCP プロセスでも動く）

func pdfTitle(for snapshot: DesignSnapshot, name: String) -> String {
    let base = "綾書 — \(snapshot.tama)玉\(snapshot.braid.label)"
    return (name.isEmpty || name == "無題") ? base : base + "「\(name)」"
}

func renderPDF(snapshot: DesignSnapshot, title: String) -> Data? {
    PDFSheetRenderer(snapshot: snapshot, title: title).render()
}
