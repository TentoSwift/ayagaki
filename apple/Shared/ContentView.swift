import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)])
    private var designs: FetchedResults<Design>

    @State private var selection: NSManagedObjectID?
    #if os(macOS)
    @EnvironmentObject private var mcpServer: MCPServerController
    #endif

    var body: some View {
        NavigationSplitView {
            List(designs, id: \.objectID, selection: $selection) { design in
                DesignRow(design: design)
                    .id(design.objectID)  // セル再利用で別デザインの内容が残らないよう明示
                    .contextMenu {
                        Button("削除", role: .destructive) { delete(design) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("削除", role: .destructive) { delete(design) }
                    }
            }
            .navigationTitle("綾書")
            .onAppear {
                // デバッグ用: 起動引数 --open-latest で最新のデザインを自動で開く（シミュレータでの表示確認用）
                if CommandLine.arguments.contains("--open-latest"), selection == nil {
                    selection = designs.first?.objectID
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                Label("MCP: \(mcpServer.statusText)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addDesign()
                    } label: {
                        Label("新規デザイン", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if designs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.3x3.topleft.filled")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("＋ で新しい綾書を作成")
                            .foregroundColor(.secondary)
                    }
                }
            }
        } detail: {
            if let sel = selection,
               let design = try? context.existingObject(with: sel) as? Design,
               !design.isDeleted {
                EditorView(design: design, context: context)
                    .id(sel)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "hand.point.left")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("デザインを選択するか、＋ で新規作成してください")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func addDesign() {
        let design = Design(context: context)
        design.apply(snapshot: DesignSnapshot(
            name: "", tama: 60, rows: BraidSpec.defaultRows,
            palette: BraidSpec.defaultPalette,
            cells: .empty(rows: BraidSpec.defaultRows, cols: BraidSpec.cols(forTama: 60))))
        try? context.save()
        selection = design.objectID
    }

    private func delete(_ design: Design) {
        if selection == design.objectID { selection = nil }
        context.delete(design)
        try? context.save()
    }
}

/// サイドバーの行。@ObservedObject でエンティティの変更（名前変更・外部更新）に追従する。
private struct DesignRow: View {
    @ObservedObject var design: Design

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(design.displayName)
                .font(.body)
            Text("\(Int(design.tama))玉・\(Int(design.rows))段" +
                 (design.updatedAt.map { "　" + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}
