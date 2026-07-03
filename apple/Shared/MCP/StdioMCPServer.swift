#if os(macOS)
import CoreData
import Foundation

/// stdio トランスポートの MCP サーバ。
/// `Ayagaki --mcp` で起動され、stdin から改行区切りの JSON-RPC を読み、stdout に応答を書く。
/// GUI と同じ Core Data ストアを共有する（クロスプロセスの反映は Persistent History 経由）。
enum StdioMCPServer {
    static func run() -> Never {
        let persistence = PersistenceController.shared
        let handler = AyagakiMCPHandler(store: DesignStore(context: persistence.container.viewContext))
        let stdout = FileHandle.standardOutput

        let thread = Thread {
            while let line = readLine(strippingNewline: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                let semaphore = DispatchSemaphore(value: 0)
                var output: Data?
                Task {
                    output = await handler.handleLine(Data(trimmed.utf8))
                    semaphore.signal()
                }
                semaphore.wait()

                if var output {
                    output.append(0x0A)  // newline-delimited JSON
                    stdout.write(output)
                }
            }
            // stdin が閉じられたら終了（クライアントの切断）
            exit(0)
        }
        thread.name = "mcp-stdio-reader"
        thread.start()

        // MainActor（Core Data の viewContext）の仕事を処理し続ける
        dispatchMain()
    }
}
#endif
