import SwiftUI
import MadeCore
import AppKit

public struct MCPServerPopoutView: View {
    var isRunning: Bool
    var port: UInt16
    var onToggleServer: () -> Void
    @State private var copiedClaudeConfig: Bool = false
    @State private var copiedStdioCmd: Bool = false
    
    public init(
        isRunning: Bool,
        port: UInt16 = 9820,
        onToggleServer: @escaping () -> Void
    ) {
        self.isRunning = isRunning
        self.port = port
        self.onToggleServer = onToggleServer
    }
    
    private var claudeConfigSnippet: String {
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
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Status and Title
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 16))
                    .foregroundColor(isRunning ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Context Protocol (MCP)")
                        .font(.system(size: 13, weight: .bold))
                    Text(isRunning ? "Server active on 127.0.0.1:\(port)" : "Server offline")
                        .font(.system(size: 11))
                        .foregroundColor(isRunning ? .green : .secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            .padding(.bottom, 2)
            
            // Server Start / Stop Button
            Button(action: onToggleServer) {
                HStack {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    Text(isRunning ? "Stop MCP Server" : "Start MCP Server")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? .red : .accentColor)
            
            Divider()
            
            // Connection Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("CONNECTING AN AI AGENT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                Text("You can connect Claude Desktop, Cursor, or CLI agents to control the Made 3D CAD canvas through MCP.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Option A: Claude Desktop Configuration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Claude Desktop Config")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Button(copiedClaudeConfig ? "Copied!" : "Copy JSON") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(claudeConfigSnippet, forType: .string)
                            copiedClaudeConfig = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedClaudeConfig = false
                            }
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                    }
                    
                    Text("~/Library/Application Support/Claude/claude_desktop_config.json")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(claudeConfigSnippet)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(5)
                    }
                }
                .padding(8)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                
                // Option B: TCP / Socket Mode
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local TCP Connection")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Send newline-delimited JSON-RPC 2.0 messages to:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("127.0.0.1:\(port)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                }
                .padding(8)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
                .cornerRadius(6)
            }
            
            Divider()
            
            // Available Tools List
            VStack(alignment: .leading, spacing: 4) {
                Text("REGISTERED CAD TOOLS (8)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                Text("cad_get_scene, cad_create_box, cad_create_cylinder, cad_set_param, cad_remove_solid, cad_boolean, cad_capture_snapshot")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
