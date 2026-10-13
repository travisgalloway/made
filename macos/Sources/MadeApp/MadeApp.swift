import SwiftUI
import MadeCore

@main
struct MadeApp: App {
    @State private var workspace = WorkspaceModel()

    init() {
        if CommandLine.arguments.contains("--mcp-stdio") {
            let doc = DocumentModel()
            let kernel = KernelClient.makeDefault()
            let registry = CADToolRegistry(document: doc, kernelClient: kernel)
            let server = MCPServer(toolRegistry: registry)

            // A restarted kernel service holds no solids; rebuild this document's from its parameters.
            Task {
                for await restart in await kernel.restarts() {
                    await KernelRegeneration.regenerate(document: doc, client: kernel, excluding: restart.excludedSolid)
                }
            }

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
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            InspectorCommands()
            CommandGroup(after: .sidebar) {
                Button(workspace.isConsoleVisible ? "Hide Console" : "Show Console") { workspace.toggleConsole() }
                    .keyboardShortcut("y", modifiers: [.command, .shift])
            }
            #if DEBUG
            CommandMenu("Debug") {
                Button("Fail Next Recompute") { workspace.failNextRecompute() }
            }
            #endif
        }
    }
}
