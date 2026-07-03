#if os(macOS)
import Foundation
import Network

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]  // キーは小文字
    var body: Data
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    static func json(_ status: Int = 200, object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: data)
    }

    static func empty(_ status: Int) -> HTTPResponse {
        HTTPResponse(status: status, headers: [:], body: Data())
    }

    static func text(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["Content-Type": "text/plain; charset=utf-8"],
                     body: Data(message.utf8))
    }
}

/// 127.0.0.1 のみで待ち受ける最小限の HTTP/1.1 サーバ（1接続1リクエスト、Connection: close）
final class HTTPServer: @unchecked Sendable {
    private let port: UInt16
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private let queue = DispatchQueue(label: "com.tento.ayagaki.http")
    private var listener: NWListener?

    init(port: UInt16, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.port = port
        self.handler = handler
    }

    func start(onStateChange: @escaping @Sendable (NWListener.State) -> Void) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HTTPServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "無効なポート番号: \(port)"])
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // ループバック以外からは接続できないようにする
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)

        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = onStateChange
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            if buffer.count > 4 << 20 {
                self.send(.text(413, "Payload Too Large"), on: connection)
                return
            }

            if let request = Self.parseRequest(buffer) {
                Task {
                    let response = await self.handler(request)
                    self.send(response, on: connection)
                }
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let statusText: [Int: String] = [
            200: "OK", 202: "Accepted", 400: "Bad Request", 404: "Not Found",
            405: "Method Not Allowed", 413: "Payload Too Large", 500: "Internal Server Error",
        ]
        var head = "HTTP/1.1 \(response.status) \(statusText[response.status] ?? "OK")\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// ヘッダ + Content-Length 分のボディが揃っていればリクエストを返す
    private static func parseRequest(_ buffer: Data) -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }

        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().components(separatedBy: " ")
        guard requestLine.count >= 2 else { return nil }
        let method = requestLine[0]
        let path = requestLine[1].components(separatedBy: "?")[0]

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= contentLength else { return nil }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
#endif
