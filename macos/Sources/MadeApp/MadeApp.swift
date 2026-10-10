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
        WindowGroup("made - Native CAD") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New CAD Document") {
                    // New document
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Geometry") {
                Button("Add Box") {}
                Button("Add Cylinder") {}
                Divider()
                Button("Import STEP File...") {}
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}
