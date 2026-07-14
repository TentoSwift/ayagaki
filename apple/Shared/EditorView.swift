import SwiftUI
import CoreData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct EditorView: View {
    @StateObject private var vm: EditorViewModel

    @State private var paintEnabled = true          // iOS: 塗る / スクロール切り替え
    @State private var showSettings = false
    @State private var showClearConfirm = false
    @State private var compactTab = 0               // 0=記号, 1=プレビュー

    @State private var exportingJSON = false
    @State private var importingJSON = false
    @State private var exportingPDF = false
    @State private var jsonDoc: JSONFile?
    @State private var pdfDoc: PDFFile?
    @State private var ioMessage: String?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif

    init(design: Design, context: NSManagedObjectContext) {
        _vm = StateObject(wrappedValue: EditorViewModel(design: design, context: context))
    }

    var body: some View {
        layout
            .navigationTitle(vm.design.displayName)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSettings) { settingsSheet }
            .confirmationDialog("すべてのマスを消去しますか？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("全消去", role: .destructive) { vm.clearAll() }
            }
            .fileExporter(isPresented: $exportingJSON,
                          document: jsonDoc ?? JSONFile(data: Data()),
                          contentType: .json,
                          defaultFilename: "ayagaki-\(vm.design.displayName)") { _ in }
            .fileExporter(isPresented: $exportingPDF,
                          document: pdfDoc ?? PDFFile(data: Data()),
                          contentType: .pdf,
                          defaultFilename: "ayagaki-\(vm.design.displayName)") { _ in }
            .fileImporter(isPresented: $importingJSON, allowedContentTypes: [.json]) { result in
                importJSON(result)
            }
            .alert("読み込みエラー", isPresented: Binding(get: { ioMessage != nil },
                                                    set: { if !$0 { ioMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(ioMessage ?? "")
            }
            .onDisappear { vm.flushSave() }
    }

    // MARK: レイアウト

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if hSize == .compact {
            compactLayout
        } else {
            wideLayout
        }
        #else
        wideLayout
        #endif
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                controlBar
                Divider()
                gridScroll
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("交換記号").font(.headline)
                    NotationView(vm: vm)
                    Text("仕上がりプレビュー（2リピート）").font(.headline).padding(.top, 8)
                    HStack { Spacer(); PreviewCanvasView(vm: vm); Spacer() }
                    legend
                }
                .padding(12)
            }
            .frame(width: 360)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            gridScroll
            Divider()
            Picker("", selection: $compactTab) {
                Text("交換記号").tag(0)
                Text("プレビュー").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Group {
                if compactTab == 0 {
                    ScrollView { NotationView(vm: vm).padding(.horizontal, 8) }
                } else {
                    ScrollView([.horizontal, .vertical]) { PreviewCanvasView(vm: vm).padding(8) }
                }
            }
            .frame(height: 230)
        }
    }

    private var gridScroll: some View {
        ScrollView([.horizontal, .vertical]) {
            GridCanvasView(vm: vm, paintEnabled: paintEnabled)
                .padding(8)
        }
        #if os(iOS)
        .background(Color(uiColor: .systemBackground))
        #endif
    }

    // MARK: 操作バー

    private var controlBar: some View {
        HStack(spacing: 12) {
            paletteBar
            Divider().frame(height: 28)
            ColorPicker("", selection: paletteColorBinding)
                .labelsHidden()
                .help("選択中の色を変更")
            Toggle(isOn: $vm.symmetric) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .toggleStyle(.button)
            .help("左右対称に塗る")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var paletteBar: some View {
        // 地の色に対して柄色は1つ（二枚安田組の制約。ユーザー確認 2026-07-07）
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { i in
                Button {
                    vm.currentColor = i
                } label: {
                    VStack(spacing: 2) {
                        Circle()
                            .fill(Color(hex: vm.palette[i]))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().strokeBorder(
                                    vm.currentColor == i ? Color.accentColor : Color.secondary.opacity(0.4),
                                    lineWidth: vm.currentColor == i ? 3 : 1)
                            )
                        Text(i == 0 ? "地" : BraidSpec.paletteLabels[i])
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var paletteColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: vm.palette[vm.currentColor]) },
            set: { vm.setPaletteColor($0.hexString, at: vm.currentColor) }
        )
    }

    private var legend: some View {
        Text("綾名：ナミ／上n＝上n下(6−n)の手取り ／ 先頭の数字：糸交換 ／ 丸数字：元の色に戻す ／ ⬆（中央で上ル）は中央の色から自動")
            .font(.caption2)
            .foregroundColor(.secondary)
    }

    // MARK: ツールバー

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            Button {
                paintEnabled.toggle()
            } label: {
                Image(systemName: paintEnabled ? "paintbrush.pointed.fill" : "hand.draw")
            }
            .help(paintEnabled ? "塗りモード（タップでスクロールモードへ）" : "スクロールモード（タップで塗りモードへ）")
            #endif

            Button {
                vm.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!vm.canUndo)
            .help("元に戻す")

            Menu {
                Button("JSON 書き出し（Web 版と互換）") {
                    if let data = try? JSONEncoder().encode(vm.snapshotValue) {
                        jsonDoc = JSONFile(data: data)
                        exportingJSON = true
                    }
                }
                Button("JSON 読み込み") { importingJSON = true }
                Divider()
                Button("PDF 手順書を書き出し") {
                    let snapshot = vm.snapshotValue
                    if let data = renderPDF(snapshot: snapshot,
                                            title: pdfTitle(for: snapshot, name: vm.design.displayName)) {
                        pdfDoc = PDFFile(data: data)
                        exportingPDF = true
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("書き出し / 読み込み")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("設定")
        }
    }

    // MARK: 設定シート

    private var settingsSheet: some View {
        SettingsForm(vm: vm, showClearConfirm: $showClearConfirm, dismiss: { showSettings = false })
    }

    // MARK: 読み込み

    private func importJSON(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(DesignSnapshot.self, from: data)
            vm.applyImported(snapshot)
        } catch {
            ioMessage = "このファイルは読み込めませんでした（Web 版・アプリ版の JSON 書き出しファイルを選んでください）"
        }
    }
}

// MARK: - 設定フォーム

private struct SettingsForm: View {
    @ObservedObject var vm: EditorViewModel
    @Binding var showClearConfirm: Bool
    var dismiss: () -> Void

    #if os(macOS)
    @EnvironmentObject private var mcpServer: MCPServerController
    @State private var tab = 0
    #endif

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("デザイン").tag(0)
                Text("MCP連携").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.top, .horizontal], 16)
            .padding(.bottom, 4)

            if tab == 0 {
                designForm
            } else {
                MCPSettingsView(statusText: mcpServer.statusText)
            }

            Divider()
            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 500)
        #else
        NavigationStack {
            designForm
                .navigationTitle("設定")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var designForm: some View {
        Form {
            Section("デザイン") {
                TextField("デザイン名", text: Binding(
                    get: { vm.design.name ?? "" },
                    set: { vm.rename($0) }))
                Picker("玉数", selection: Binding(get: { vm.tama }, set: { vm.setTama($0) })) {
                    ForEach(BraidSpec.tamaOptions, id: \.self) { t in
                        Text("\(t)玉（片面\(BraidSpec.cols(forTama: t))目）").tag(t)
                    }
                }
                Stepper("段数：\(vm.rowCount)",
                        value: Binding(get: { vm.rowCount }, set: { vm.setRows($0) }),
                        in: BraidSpec.rowRange)
            }
            Section {
                Button("全消去", role: .destructive) {
                    dismiss()
                    showClearConfirm = true
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

// MARK: - MCP 連携タブ（macOS のみ）

#if os(macOS)
private struct MCPSettingsView: View {
    var statusText: String
    @State private var copiedCommand: String?

    private var executablePath: String { Bundle.main.executablePath ?? "" }
    private var httpURL: String { "http://127.0.0.1:\(MCPServerController.port)/mcp" }

    var body: some View {
        Form {
            Section("内蔵 HTTP サーバ（アプリ起動中に接続）") {
                LabeledContent("状態", value: statusText)
                commandRow("Claude Code に登録",
                           "claude mcp add --transport http ayagaki \(httpURL)")
                commandRow("Codex に登録",
                           "codex mcp add ayagaki --url \(httpURL)")
            }
            Section("stdio サーバ（アプリ起動不要・クライアントが自動起動）") {
                commandRow("Claude Code に登録",
                           "claude mcp add ayagaki -- \"\(executablePath)\" --mcp")
                commandRow("Codex に登録",
                           "codex mcp add ayagaki -- \"\(executablePath)\" --mcp")
                Text("本体を --mcp 付きで起動すると画面を出さずに MCP サーバとして動きます。登録前にアプリを /Applications に置いておくと、パスが変わりません。どちらの方式でも変更は開いている画面に反映されます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func commandRow(_ label: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copiedCommand = command
                } label: {
                    Label(copiedCommand == command ? "コピー済み" : "コピー",
                          systemImage: copiedCommand == command ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
#endif
