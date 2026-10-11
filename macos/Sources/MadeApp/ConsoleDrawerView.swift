import SwiftUI
import MadeCore

public struct ConsoleDrawerView: View {
    var logs: [ConsoleLogEntry]
    var onClearLogs: () -> Void
    var onCollapse: () -> Void
    
    @State private var filterText: String = ""
    
    public init(
        logs: [ConsoleLogEntry],
        onClearLogs: @escaping () -> Void,
        onCollapse: @escaping () -> Void
    ) {
        self.logs = logs
        self.onClearLogs = onClearLogs
        self.onCollapse = onCollapse
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Console")
                        .font(.system(size: 11, weight: .semibold))
                }
                
                Spacer()
                
                // Clear button
                Button(action: onClearLogs) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Console Logs")
                
                // Filter field
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("Filter", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                }
                .frame(width: 100)
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
            
            // Logs Content
            logsView
                .frame(height: 130)
                .background(Color(NSColor.textBackgroundColor))
        }
    }
    
    // MARK: - Logs View
    
    private var logsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if filteredLogs.isEmpty {
                        Text("No logs recorded")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(10)
                    } else {
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
