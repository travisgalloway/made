import SwiftUI
import MadeCore

@main
struct MadeApp: App {
    @State private var workspace = WorkspaceModel()

    init() {
        if CommandLine.arguments.contains("--mcp-stdio") {
            let doc = DocumentModel()
            let kernel = KernelClient.makeDefault()
            // The registry holds its provider weakly; the stdio task below keeps this one alive.
            let snapshot = HeadlessSnapshotProvider.make(document: doc, kernelClient: kernel)
            let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: snapshot)
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
                withExtendedLifetime(snapshot) {}
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
            CommandGroup(after: .newItem) {
                Button("Open Part Script…") { workspace.promptOpenPartFile() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Reload Part Scripts") { workspace.reloadAllParts() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
            EditMenuCommands(workspace: workspace)
            SolidMenuCommands(workspace: workspace)
            ViewNavigationCommands(workspace: workspace)
            ToolsMenuCommands(workspace: workspace)
            CommandGroup(after: .appInfo) {
                OpenSourceLicensesMenuButton()
            }
            CommandGroup(after: .help) {
                OpenSourceLicensesMenuButton()
            }
            #if DEBUG
            CommandMenu("Debug") {
                Button("Fail Next Recompute") { workspace.failNextRecompute() }
            }
            #endif
        }

        Window("Open Source Licenses", id: OpenSourceLicensesView.windowID) {
            OpenSourceLicensesView()
        }
        .defaultSize(width: 760, height: 520)

        Settings {
            SettingsView()
                .environment(workspace)
        }
    }
}

private struct OpenSourceLicensesMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Source Licenses…") {
            openWindow(id: OpenSourceLicensesView.windowID)
        }
    }
}

