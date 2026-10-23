import SwiftUI
import MadeCore

final class MadeAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--ui-testing") {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

@main
struct MadeApp: App {
    @NSApplicationDelegateAdaptor(MadeAppDelegate.self) private var appDelegate
    @State private var workspace: WorkspaceModel

    @MainActor
    static func makeWorkspace(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WorkspaceModel {
        if arguments.contains("--ui-testing") {
            let suiteName = "com.made.app.uitesting"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)

            let recoveryURL: URL
            if let path = environment["MADE_RECOVERY_DIR"], !path.isEmpty {
                recoveryURL = URL(fileURLWithPath: path, isDirectory: true)
            } else {
                recoveryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("made-uitesting-\(UUID().uuidString)", isDirectory: true)
            }
            try? FileManager.default.createDirectory(at: recoveryURL, withIntermediateDirectories: true)

            return WorkspaceModel(defaults: defaults, recoveryStore: CrashRecoveryStore(recoveryDirectoryURL: recoveryURL))
        }

        return WorkspaceModel()
    }

    init() {
        _workspace = State(initialValue: Self.makeWorkspace())
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
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            InspectorCommands()
            FileMenuCommands(workspace: workspace)
            EditMenuCommands(workspace: workspace)
            SolidMenuCommands(workspace: workspace)
            AssemblyMenuCommands(workspace: workspace)
            SimulationMenuCommands(workspace: workspace)
            ViewNavigationCommands(workspace: workspace)
            ToolsMenuCommands(workspace: workspace)
            OpenSourceLicensesCommands()
            #if DEBUG
            CommandMenu("Debug") {
                Button("Fail Next Recompute") { workspace.failNextRecompute() }
            }
            #endif
        }

        Window("Material Library", id: MaterialLibraryView.windowID) {
            MaterialLibraryView()
                .environment(workspace)
        }
        .defaultSize(width: 840, height: 580)

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

private struct OpenSourceLicensesCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            OpenSourceLicensesMenuButton()
        }
        CommandGroup(after: .help) {
            OpenSourceLicensesMenuButton()
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
