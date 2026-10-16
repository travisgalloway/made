import SwiftUI
import MadeCore

/// Viewport telemetry and the console toggle, laid out as Xcode's editor status bar.
struct ViewportStatusBar: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        let stats = workspace.renderStats
        let state = workspace.viewportManager.state

        HStack(spacing: 10) {
            Group {
                if state.isUnavailable {
                    Label("Metal unavailable", systemImage: "bolt.slash.fill")
                        .foregroundStyle(.red)
                } else {
                    Label("Metal 4", systemImage: "bolt.fill")
                        .foregroundStyle(state == .ready ? .green : .yellow)
                }
            }
            .labelStyle(.titleAndIcon)
            separator
            Text("Render: \(stats.renderCount)")
            separator
            Text("Draw Calls: \(stats.drawCalls)")
            separator
            Text("Invalidate: \(stats.lastReason)")
            separator
            Text("Tool: \(workspace.tool.title)")
            separator
            if let snap = workspace.activeSnapKind {
                Text("Snap: \(snap.rawValue)").foregroundStyle(color(for: snap))
            } else {
                Text("Snap: none")
            }
            separator
            Text("Units: \(workspace.document.settings.units.lengthUnit.symbol)")
                .accessibilityIdentifier("status-units")
            separator
            sketchDOFView
                .accessibilityIdentifier("status-dof")
            separator
            Text("Selected: \(workspace.document.selection.count)")
                .accessibilityIdentifier("status-selection")
            separator
            Text("Regen: \(workspace.formattedRegenerationDuration)")
                .accessibilityIdentifier("status-regen")
            Spacer()
            Button(workspace.consoleToggleTitle,
                   systemImage: "rectangle.bottomthird.inset.filled") {
                workspace.toggleConsole()
            }
            .foregroundStyle(workspace.isConsoleVisible ? Color.accentColor : Color.secondary)
            .help(workspace.consoleToggleHelp)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .barControl()
        .padding(.horizontal, 10)
        .frame(height: BarMetrics.height)
        .background(.bar)
    }

    private var separator: some View {
        Divider().frame(height: 16)
    }

    private func color(for kind: SnapKind) -> Color {
        switch kind {
        case .vertex: return .orange
        case .edge: return .cyan
        case .grid: return .green
        }
    }

    static func dofColor(for status: SketchDOFStatus) -> Color? {
        switch status {
        case .inactive:
            return nil
        case .underConstrained:
            return .blue
        case .fullyConstrained:
            return .green
        case .overConstrained:
            return .red
        }
    }

    @ViewBuilder
    var sketchDOFView: some View {
        if let color = Self.dofColor(for: workspace.sketchDOFStatus) {
            Text(workspace.sketchDOFStatus.statusText)
                .foregroundStyle(color)
        } else {
            Text(workspace.sketchDOFStatus.statusText)
        }
    }
}
