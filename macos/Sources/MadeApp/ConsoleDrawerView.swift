import SwiftUI
import MadeCore

struct ConsoleDrawerView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Console", systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 140)
                Button("Clear Console Logs", systemImage: "trash") { workspace.clearLogs() }
                    .help("Clear Console Logs")
                Button("Hide Debug Console", systemImage: "chevron.down") {
                    withAnimation(.easeInOut(duration: 0.15)) { workspace.isConsoleVisible = false }
                }
                .help("Hide Debug Console")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.bar)

            Divider()

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
                    if filteredLogs.isEmpty {
                        ContentUnavailableView("No Logs", systemImage: "terminal")
                    }
                }
                .onChange(of: workspace.logs.count) {
                    if let last = workspace.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .frame(height: 130)
        }
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
