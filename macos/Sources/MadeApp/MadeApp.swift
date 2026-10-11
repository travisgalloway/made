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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New CAD Document") {
                    // New document
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Geometry") {
                Button("Add Box Solid") {}
                Button("Add Cylinder Solid") {}
                Divider()
                Button("Import STEP File...") {}
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("Toggle Navigator") {}
                    .keyboardShortcut("0", modifiers: .command)
                Button("Toggle Debug Console") {}
                    .keyboardShortcut("y", modifiers: [.command, .shift])
                Button("Toggle Inspector") {}
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Divider()
                Button("Perspective View") {}
                    .keyboardShortcut("1", modifiers: .command)
                Button("Top View") {}
                    .keyboardShortcut("2", modifiers: .command)
                Button("Front View") {}
                    .keyboardShortcut("3", modifiers: .command)
                Button("Right View") {}
                    .keyboardShortcut("4", modifiers: .command)
                Button("Isometric View") {}
                    .keyboardShortcut("5", modifiers: .command)
            }
            CommandMenu("Simulation") {
                Button("Run / Pause Simulation") {}
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
