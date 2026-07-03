#if os(macOS)
import SwiftUI
import CoreData
import Network

/// アプリ内蔵 MCP サーバの起動と状態管理（macOS のみ）
@MainActor
final class MCPServerController: ObservableObject {
    static let port: UInt16 = 53536

    @Published var statusText = "停止中"

    private var server: HTTPServer?
    private var handler: AyagakiMCPHandler?

    func start(context: NSManagedObjectContext) {
        guard server == nil else { return }
        let handler = AyagakiMCPHandler(store: DesignStore(context: context))
        self.handler = handler
        let server = HTTPServer(port: Self.port) { request in
            await handler.handle(request)
        }
        do {
            try server.start { state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.statusText = "127.0.0.1:\(Self.port)/mcp で待機中"
                    case .failed(let error):
                        self?.statusText = "起動失敗: \(error.localizedDescription)"
                    case .cancelled:
                        self?.statusText = "停止中"
                    default:
                        break
                    }
                }
            }
            self.server = server
        } catch {
            statusText = "起動失敗: \(error.localizedDescription)"
        }
    }

    func stop() {
        server?.stop()
        server = nil
        statusText = "停止中"
    }
}
#endif
