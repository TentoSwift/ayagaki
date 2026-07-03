import SwiftUI

@main
enum AyagakiMain {
    static func main() {
        #if os(macOS)
        // `Ayagaki --mcp` で GUI を出さずに stdio MCP サーバとして動く
        if CommandLine.arguments.contains("--mcp") {
            StdioMCPServer.run()
        }
        #endif
        AyagakiApp.main()
    }
}
