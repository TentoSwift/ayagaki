import SwiftUI

struct AyagakiApp: App {
    private let persistence = PersistenceController.shared
    #if os(macOS)
    @StateObject private var mcpServer = MCPServerController()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                #if os(macOS)
                .environmentObject(mcpServer)
                .onAppear { mcpServer.start(context: persistence.container.viewContext) }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1150, height: 780)
        #endif
    }
}
