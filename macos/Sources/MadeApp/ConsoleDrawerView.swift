import SwiftUI
import MadeCore

public struct ConsoleDrawerView: View {
    var logs: [ConsoleLogEntry]
    var renderCount: Int
    var drawCalls: Int
    var lastReason: String
    var activeSnapKind: SnapKind?
    var viewportState: ViewportState
    var onClearLogs: () -> Void
    var onCollapse: () -> Void
    
    @State private var activeTab: ConsoleTab = .logs
    @State private var filterText: String = ""
    
    public init(
        logs: [ConsoleLogEntry],
        renderCount: Int,
        drawCalls: Int,
        lastReason: String,
        activeSnapKind: SnapKind?,
        viewportState: ViewportState,
        onClearLogs: @escaping () -> Void,
        onCollapse: @escaping () -> Void
    ) {
        self.logs = logs
        self.renderCount = renderCount
        self.drawCalls = drawCalls
        self.lastReason = lastReason
        self.activeSnapKind = activeSnapKind
        self.viewportState = viewportState
        self.onClearLogs = onClearLogs
        self.onCollapse = onCollapse
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                // Tab switcher
                HStack(spacing: 2) {
                    ForEach(ConsoleTab.allCases) { tab in
                        Button {
                            activeTab = tab
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tab.iconName)
                                Text(tab.rawValue)
                            }
                            .font(.system(size: 11, weight: activeTab == tab ? .semibold : .regular))
                            .foregroundColor(activeTab == tab ? .accentColor : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(activeTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // Clear button
                if activeTab == .logs {
                    Button(action: onClearLogs) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Console Logs")
                }
                
                // Filter field
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("Filter", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                }
                .frame(width: 90)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
                
                Divider().frame(height: 12)
                
                // Collapse button
                Button(action: onCollapse) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide Debug Console")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Body Content
            Group {
                switch activeTab {
                case .logs:
                    logsView
                case .engine:
                    engineStatusView
                case .telemetry:
                    telemetryView
                }
            }
            .frame(height: 140)
            .background(Color(NSColor.textBackgroundColor))
        }
    }
    
    // MARK: - Logs View
    
    private var logsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(filteredLogs) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(formatTimestamp(entry.timestamp))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Text("[\(entry.level.rawValue)]")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(entry.level.color)
                                .frame(width: 52, alignment: .leading)
                            
                            Text("[\(entry.subsystem)]")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Text(entry.message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .id(entry.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: logs.count) {
                if let last = logs.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Engine Status View
    
    private var engineStatusView: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CLI ENGINE & MCP SERVER")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                statusRow(label: "Protocol Mode", value: "JSON-RPC 2.0 / MCP (2024-11-05)")
                statusRow(label: "Stdio Server", value: CommandLine.arguments.contains("--mcp-stdio") ? "Running" : "Standby")
                statusRow(label: "Active CAD Tools", value: "8 registered tools")
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("CSG GEOMETRY PIPELINE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                statusRow(label: "CSG Engine", value: "Euclid CSG (Pure Swift)")
                statusRow(label: "Worker Concurrency", value: "KernelClient Actor (Thread-safe)")
                statusRow(label: "Debounce Window", value: "60 ms")
            }
            
            Spacer()
        }
        .padding(12)
    }
    
    // MARK: - Telemetry View
    
    private var telemetryView: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("METAL 3 RENDER PIPELINE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                statusRow(label: "Device State", value: viewportState == .ready ? "Metal 3 Ready" : "Unavailable")
                statusRow(label: "Buffer Storage", value: ".storageModeShared")
                statusRow(label: "Render Invalidation", value: lastReason)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("SYSTEM RESOURCE METRICS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                statusRow(label: "Render Count", value: "\(renderCount)")
                statusRow(label: "Draw Calls", value: "\(drawCalls)")
                statusRow(label: "Active Snapping", value: activeSnapKind?.rawValue ?? "None")
            }
            
            Spacer()
        }
        .padding(12)
    }
    
    private func statusRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
    
    private var filteredLogs: [ConsoleLogEntry] {
        if filterText.trimmingCharacters(in: .whitespaces).isEmpty {
            return logs
        }
        return logs.filter {
            $0.message.localizedCaseInsensitiveContains(filterText) ||
            $0.subsystem.localizedCaseInsensitiveContains(filterText) ||
            $0.level.rawValue.localizedCaseInsensitiveContains(filterText)
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
