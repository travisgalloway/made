import SwiftUI
import MadeCore

struct ConsoleDrawerView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(filteredLogs) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.timestamp, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3)))
                            .foregroundStyle(.secondary)
                        Text(entry.level.rawValue)
                            .bold()
                            .foregroundStyle(entry.level.color)
                            .frame(width: 52, alignment: .leading)
                        Text(entry.subsystem)
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                    }
                    .font(.caption.monospaced())
                    .listRowSeparator(.hidden)
                    .id(entry.id)
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 16)
                .overlay {
                    if workspace.logs.isEmpty {
                        ContentUnavailableView(
                            "No Logs",
                            systemImage: "terminal",
                            description: Text("Diagnostics and kernel events will appear here.")
                        )
                    } else if filteredLogs.isEmpty {
                        ContentUnavailableView.search(text: filterText)
                    }
                }
                .onChange(of: workspace.logs.count) {
                    if let last = workspace.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            Divider()

            HStack(spacing: 8) {
                telemetrySection
                Spacer()
                BarFilterField(text: $filterText)
                    .frame(width: 220)
                Button("Clear Console", systemImage: "trash") { workspace.clearLogs() }
                    .help("Clear Console")
            }
            .barControl()
            .padding(.horizontal, 10)
            .frame(height: BarMetrics.height)
            .background(.bar)
        }
        .onAppear {
            workspace.updateStats()
        }
    }

    private var telemetrySection: some View {
        HStack(spacing: 8) {
            Text("Render: \(workspace.renderStats.renderCount)")
            telemetrySeparator
            Text("Draw Calls: \(workspace.renderStats.drawCalls)")
            telemetrySeparator
            Text("Invalidate: \(workspace.renderStats.lastReason)")
            telemetrySeparator
            Text("Dispatched: \(workspace.kernelStats.dispatched)")
            telemetrySeparator
            Text("Conflated: \(workspace.kernelStats.conflated)")
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private var telemetrySeparator: some View {
        Divider().frame(height: 12)
    }

    private var filteredLogs: [ConsoleLogEntry] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return workspace.logs }
        return workspace.logs.filter {
            $0.message.localizedCaseInsensitiveContains(query)
                || $0.subsystem.localizedCaseInsensitiveContains(query)
                || $0.level.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
}
