#if os(macOS)
import Foundation

/// MCP (Model Context Protocol) の Streamable HTTP トランスポートを処理する。
/// POST /mcp に JSON-RPC 2.0 メッセージが届く。レスポンスは application/json で返す。
final class AyagakiMCPHandler: @unchecked Sendable {
    static let serverName = "ayagaki"
    static let serverVersion = "1.0.0"
    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let store: DesignStore

    init(store: DesignStore) {
        self.store = store
    }

    // MARK: - HTTP 入口

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.path == "/mcp" || request.path == "/" else {
            return .text(404, "Not Found. MCP endpoint is /mcp")
        }
        switch request.method {
        case "POST":
            return await handlePost(request)
        case "GET":
            return .text(405, "Method Not Allowed")
        case "DELETE":
            return .empty(200)
        default:
            return .text(405, "Method Not Allowed")
        }
    }

    private func handlePost(_ request: HTTPRequest) async -> HTTPResponse {
        let parsed = try? JSONSerialization.jsonObject(with: request.body)
        if let message = parsed as? [String: Any] {
            if let response = await process(message) {
                return .json(200, object: response)
            }
            return .empty(202)
        }
        if let batch = parsed as? [[String: Any]] {
            var responses: [[String: Any]] = []
            for message in batch {
                if let response = await process(message) {
                    responses.append(response)
                }
            }
            return responses.isEmpty ? .empty(202) : .json(200, object: responses)
        }
        return .json(400, object: Self.errorResponse(id: NSNull(), code: -32700, message: "Parse error"))
    }

    // MARK: - JSON-RPC

    private func process(_ message: [String: Any]) async -> [String: Any]? {
        guard let method = message["method"] as? String else { return nil }
        let id = message["id"]
        if id == nil || id is NSNull { return nil }  // 通知
        let params = message["params"] as? [String: Any] ?? [:]

        do {
            let result = try await dispatch(method: method, params: params)
            return ["jsonrpc": "2.0", "id": id!, "result": result]
        } catch let error as MCPError {
            return Self.errorResponse(id: id!, code: error.code, message: error.message)
        } catch {
            return Self.errorResponse(id: id!, code: -32603, message: error.localizedDescription)
        }
    }

    private static func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    struct MCPError: Error {
        var code: Int
        var message: String
        static func methodNotFound(_ method: String) -> MCPError {
            MCPError(code: -32601, message: "Method not found: \(method)")
        }
        static func invalidParams(_ detail: String) -> MCPError {
            MCPError(code: -32602, message: "Invalid params: \(detail)")
        }
    }

    private func dispatch(method: String, params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let version = Self.supportedProtocolVersions.contains(requested)
                ? requested : Self.supportedProtocolVersions[0]
            return [
                "protocolVersion": version,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": Self.serverName, "version": Self.serverVersion],
                "instructions": """
                組紐（二枚安田組）の綾書デザインを読み書きするサーバです。
                グリッド構造: 左右 2 半面 × rows 段 × 片面 colsPerSide 目（60玉=15目、68玉=17目）。
                セル値: 0=地（ナミ）、1〜3=柄色。paint の pos は 1=外端 … colsPerSide=中央。
                同じ段のセルは実際の組紐では斜めのラインになります。模様の設計は paint（矩形塗り）か set_cells（全置換）で行い、
                get_notation で組むときの交換記号（ナミn=n目そのまま／上n=n目交換して浮かせる）を取得できます。
                """,
            ]
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": Self.toolDefinitions]
        case "tools/call":
            guard let name = params["name"] as? String else {
                throw MCPError.invalidParams("name がありません")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return await callTool(name: name, arguments: arguments)
        default:
            throw MCPError.methodNotFound(method)
        }
    }

    // MARK: - ツール実行

    private func callTool(name: String, arguments: [String: Any]) async -> [String: Any] {
        do {
            let result = try await invokeTool(name: name, arguments: arguments)
            let text = Self.prettyJSON(result)
            return ["content": [["type": "text", "text": text]], "isError": false]
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ["content": [["type": "text", "text": "エラー: \(message)"]], "isError": true]
        }
    }

    private func invokeTool(name: String, arguments: [String: Any]) async throws -> Any {
        switch name {
        case "list_designs":
            return try await store.list()

        case "get_design":
            return try await store.get(id: try requiredID(arguments))

        case "get_notation":
            return try await store.notation(id: try requiredID(arguments))

        case "create_design":
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                throw MCPError.invalidParams("name は必須です")
            }
            return try await store.create(
                name: name,
                tama: arguments["tama"] as? Int,
                rows: arguments["rows"] as? Int)

        case "update_design":
            return try await store.update(
                id: try requiredID(arguments),
                name: arguments["name"] as? String,
                tama: arguments["tama"] as? Int,
                rows: arguments["rows"] as? Int,
                readDir: arguments["readDir"] as? String,
                palette: arguments["palette"] as? [String])

        case "paint":
            guard let ops = arguments["ops"] as? [[String: Any]], !ops.isEmpty else {
                throw MCPError.invalidParams("ops は必須です")
            }
            return try await store.paint(id: try requiredID(arguments), ops: ops)

        case "set_cells":
            guard let cells = arguments["cells"] as? [String: Any],
                  let l = intPlane(cells["L"]), let r = intPlane(cells["R"]) else {
                throw MCPError.invalidParams("cells は {L: [[Int]], R: [[Int]]} 形式で指定してください")
            }
            return try await store.setCells(id: try requiredID(arguments), cellsL: l, cellsR: r)

        case "clear_cells":
            return try await store.clearCells(id: try requiredID(arguments))

        case "delete_design":
            return try await store.delete(id: try requiredID(arguments))

        default:
            throw MCPError.methodNotFound("tool: \(name)")
        }
    }

    private func requiredID(_ arguments: [String: Any]) throws -> String {
        guard let id = arguments["id"] as? String, !id.isEmpty else {
            throw MCPError.invalidParams("id は必須です")
        }
        return id
    }

    private func intPlane(_ value: Any?) -> [[Int]]? {
        guard let rows = value as? [[Any]] else { return nil }
        var out: [[Int]] = []
        for row in rows {
            var r: [Int] = []
            for v in row {
                if let n = v as? Int { r.append(n) }
                else if let n = v as? NSNumber { r.append(n.intValue) }
                else { return nil }
            }
            out.append(r)
        }
        return out
    }

    private static func prettyJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return text
    }

    // MARK: - ツール定義

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "list_designs",
            "description": "綾書デザインの一覧を取得する。各デザインの id・名前・玉数・段数・片面の目数・更新日時を返す。",
            "inputSchema": ["type": "object", "properties": [String: Any](), "required": [String]()],
        ],
        [
            "name": "get_design",
            "description": "デザインの全情報を取得する。cells は {L, R} の 2 半面 × 段 × 目の 2 次元配列（0=地、1〜3=柄色）。目の並びは index 0 が中央寄り、最後が外端。notation（交換記号）も含む。",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "list_designs で取得したデザイン ID"]],
                "required": ["id"],
            ],
        ],
        [
            "name": "create_design",
            "description": "新しい綾書デザインを作成する。作成後 paint か set_cells で模様を描く。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "デザイン名（必須）"],
                    "tama": ["type": "integer", "description": "玉数: 60（片面15目）か 68（片面17目）。省略時 60"],
                    "rows": ["type": "integer", "description": "段数 4〜120。省略時 40"],
                ],
                "required": ["name"],
            ],
        ],
        [
            "name": "update_design",
            "description": "デザインの設定を変更する。指定したフィールドだけが変わる。玉数・段数を変えても塗りは可能な範囲で保持される。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "デザイン ID（必須）"],
                    "name": ["type": "string", "description": "新しい名前"],
                    "tama": ["type": "integer", "description": "玉数: 60 か 68"],
                    "rows": ["type": "integer", "description": "段数 4〜120"],
                    "readDir": ["type": "string", "description": "交換記号の読み方向: edge（端→中央）か center（中央→端）"],
                    "palette": ["type": "array", "items": ["type": "string"],
                                "description": "4 色の #RRGGBB 配列。[0]=地色、[1..3]=柄色"],
                ],
                "required": ["id"],
            ],
        ],
        [
            "name": "paint",
            "description": "矩形範囲を塗って模様を描く。複数の op をまとめて適用できる。段 row は 1 始まり（上から）、目 pos は 1=外端 … colsPerSide=中央。color 0 で消去。同じ段の連続する目は、実際の組紐では 45° の斜めラインになる点に注意。適用後の交換記号を返す。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "デザイン ID（必須）"],
                    "ops": [
                        "type": "array",
                        "description": "塗り操作の配列。順に適用される",
                        "items": [
                            "type": "object",
                            "properties": [
                                "side": ["type": "string", "enum": ["L", "R", "both"], "description": "左半面 / 右半面 / 両方"],
                                "rowFrom": ["type": "integer", "description": "開始段（1 始まり）"],
                                "rowTo": ["type": "integer", "description": "終了段（省略時 rowFrom と同じ）"],
                                "posFrom": ["type": "integer", "description": "開始目（1=外端）"],
                                "posTo": ["type": "integer", "description": "終了目（省略時 posFrom と同じ）"],
                                "color": ["type": "integer", "description": "0=地（消去）、1〜3=柄色"],
                            ],
                            "required": ["side", "rowFrom", "posFrom", "color"],
                        ],
                    ],
                ],
                "required": ["id", "ops"],
            ],
        ],
        [
            "name": "set_cells",
            "description": "グリッド全体を一括で置き換える。cells.L / cells.R は 段数 × 片面目数 の 2 次元配列（値 0〜3、index 0 が中央寄り・最後が外端）。細かい模様を一度に描くときに使う。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "デザイン ID（必須）"],
                    "cells": [
                        "type": "object",
                        "properties": [
                            "L": ["type": "array", "items": ["type": "array", "items": ["type": "integer"]]],
                            "R": ["type": "array", "items": ["type": "array", "items": ["type": "integer"]]],
                        ],
                        "required": ["L", "R"],
                    ],
                ],
                "required": ["id", "cells"],
            ],
        ],
        [
            "name": "get_notation",
            "description": "デザインの交換記号（組むときの手順）を取得する。段ごとに左右半面の記号を返し、同じ手順が続く段はまとめられる。ナミn=n目そのまま組む、上n=色糸をn目交換して表に浮かせる。",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "デザイン ID（必須）"]],
                "required": ["id"],
            ],
        ],
        [
            "name": "clear_cells",
            "description": "デザインの塗りをすべて消去する（設定は残る）。",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "デザイン ID（必須）"]],
                "required": ["id"],
            ],
        ],
        [
            "name": "delete_design",
            "description": "デザインを削除する。元に戻せないので注意。",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "デザイン ID（必須）"]],
                "required": ["id"],
            ],
        ],
    ]
}
#endif
