import SwiftUI
import MadeCore

struct MCPServerView: View {
    static let windowId = "mcp-server"

    @Environment(WorkspaceModel.self) private var workspace
    @State private var copied = false

    private var configSnippet: String {
        """
        {
          "mcpServers": {
            "made": {
              "command": "swift",
              "args": ["run", "--package-path", "\(FileManager.default.currentDirectoryPath)/macos", "MadeApp", "--mcp-stdio"]
            }
          }
        }
        """
    }

    var body: some View {
        let running = workspace.isMCPServerRunning
        let toolNames = workspace.toolRegistry?.tools.map(\.name) ?? []

        Form {
            Section {
                LabeledContent {
                    Button(running ? "Stop Server" : "Start Server",
                           systemImage: running ? "stop.fill" : "play.fill") {
                        workspace.toggleMCPServer()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(running ? .red : .accentColor)
                } label: {
                    Label {
                        Text("Model Context Protocol")
                        Text(running ? "Active on 127.0.0.1:\(String(workspace.mcpPort))" : "Offline")
                    } icon: {
                        Image(systemName: "sparkle").foregroundStyle(running ? .green : .secondary)
                    }
                }
            }

            Section {
                LabeledContent("Config File") {
                    Text("~/Library/Application Support/Claude/claude_desktop_config.json")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Text(configSnippet)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button(copied ? "Copied" : "Copy JSON", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configSnippet, forType: .string)
                    copied = true
                }
                .task(id: copied) {
                    guard copied else { return }
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } header: {
                Text("Claude Desktop")
            } footer: {
                Text("Connect Claude Desktop, Cursor, or a CLI agent to drive the CAD session over MCP.")
            }

            Section {
                LabeledContent("Address") {
                    Text(verbatim: "127.0.0.1:\(workspace.mcpPort)")
                        .monospaced()
                        .textSelection(.enabled)
                }
            } header: {
                Text("Local TCP")
            } footer: {
                Text("Send newline-delimited JSON-RPC 2.0 messages to this address.")
            }

            Section("Registered CAD Tools (\(toolNames.count))") {
                ForEach(toolNames, id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear { workspace.isMCPWindowOpen = true }
        .onDisappear { workspace.isMCPWindowOpen = false }
    }
}
