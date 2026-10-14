import SwiftUI
import MadeCore

/// MCP server controls, shown in a popover anchored to the toolbar's sparkles button.
struct MCPServerPopover: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var copied = false

    private static let configPath = "~/Library/Application Support/Claude/claude_desktop_config.json"

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
        let error = workspace.mcpServerError
        let toolNames = workspace.toolRegistry?.tools.map(\.name) ?? []
        let address = "127.0.0.1:\(workspace.mcpPort)"

        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { running },
                    set: { if $0 != running { workspace.toggleMCPServer() } }
                )) {
                    Label {
                        Text("MCP Server")
                        if running {
                            Text("Listening on \(address)")
                        } else if let error {
                            Text("Off — \(error)")
                                .foregroundStyle(.red)
                        } else {
                            Text("Off")
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(running ? Color.green : Color.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section {
                LabeledContent("Address") {
                    Text(verbatim: address)
                        .monospaced()
                        .textSelection(.enabled)
                }
                LabeledContent("Claude Desktop Config") {
                    Button(copied ? "Copied" : "Copy JSON", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(configSnippet, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Copy the JSON for \(Self.configPath)")
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
            }

            Section {
                DisclosureGroup("Registered Tools (\(toolNames.count))") {
                    ForEach(toolNames, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .scrollDisabled(true)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}
