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

// MARK: - PDF 手順書

/// 印刷用レイアウト（タイトル + グリッド + 記号表）
struct PrintSheetView: View {
    @ObservedObject var vm: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("綾書 — \(vm.tama)玉二枚安田組\(vm.design.displayName == "無題" ? "" : "「\(vm.design.displayName)」")")
                .font(.title3.weight(.bold))
            HStack(alignment: .top, spacing: 24) {
                GridCanvasView(vm: vm, interactive: false, cellRadius: 9)
                VStack(alignment: .leading, spacing: 12) {
                    Text("交換記号").font(.headline)
                    NotationView(vm: vm, interactive: false)
                        .frame(width: 300)
                    Text("ナミn：n目そのまま組む ／ 上n：色糸をn目交換して表に浮かせる")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

@MainActor
func renderPDF(vm: EditorViewModel) -> Data? {
    let renderer = ImageRenderer(content: PrintSheetView(vm: vm))
    renderer.scale = 2

    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }

    var succeeded = false
    renderer.render { size, renderFn in
        var box = CGRect(origin: .zero, size: size)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
        ctx.beginPDFPage(nil)
        renderFn(ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        succeeded = true
    }
    return succeeded ? data as Data : nil
}
