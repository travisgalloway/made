import SwiftUI
import MadeCore

@main
struct MadeApp: App {
    init() {
        if CommandLine.arguments.contains("--mcp-stdio") {
            let doc = DocumentModel()
            let kernel = KernelClient()
            let registry = CADToolRegistry(document: doc, kernelClient: kernel)
            let server = MCPServer(toolRegistry: registry)
            
            // Run headless MCP server over stdio
            Task {
                await server.runStdio()
                exit(0)
            }
        }
    }
    
    var body: some Scene {
        WindowGroup("made — Native CAD Workspace") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
