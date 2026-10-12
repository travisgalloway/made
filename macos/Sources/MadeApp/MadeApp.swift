import SwiftUI
import MadeCore

@main
struct MadeApp: App {
    @State private var workspace = WorkspaceModel()

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
        WindowGroup {
            ContentView()
                .environment(workspace)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
            InspectorCommands()
            #if DEBUG
            CommandMenu("Debug") {
                Button("Fail Next Recompute") { workspace.failNextRecompute() }
            }
            #endif
        }

        Window("Model Context Protocol", id: MCPServerView.windowId) {
            MCPServerView()
                .environment(workspace)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultPosition(.center)
    }
}
