import SwiftUI
import MadeCore

struct ViewportCanvasView: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack(alignment: .bottomLeading) {
                canvas
                statusHUD
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                Label("Scene", systemImage: "cube")
                    .fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(workspace.selectedObject?.name ?? "No Selection")
            }
            .font(.caption)
            Spacer()
            Picker("Camera View", systemImage: "camera.viewfinder", selection: Binding(
                get: { workspace.perspective },
                set: { workspace.applyPerspective($0) }
            )) {
                ForEach(ViewportPerspective.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Camera View Perspective")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private var canvas: some View {
        @Bindable var workspace = workspace

        switch workspace.viewportManager.state {
        case .ready:
            if let renderer = workspace.viewportManager.renderer {
                CADMetalViewRepresentable(
                    document: workspace.document,
                    renderer: renderer,
                    tool: workspace.tool,
                    coordinator: $workspace.coordinator,
                    onInvalidate: { workspace.updateStats() },
                    onSnapChanged: { workspace.handleSnapChanged($0) },
                    onToolShortcut: { workspace.tool = $0 },
                    onResetView: { workspace.resetView() }
                )
            }
        case .initializing:
            ProgressView("Initializing Metal 4…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason):
            ContentUnavailableView("Metal Unavailable", systemImage: "exclamationmark.triangle", description: Text(reason.description))
        }
    }

    private var statusHUD: some View {
        let stats = workspace.renderStats
        let state = workspace.viewportManager.state
        return HStack(spacing: 12) {
            if state.isUnavailable {
                Label("Metal unavailable", systemImage: "bolt.slash.fill").foregroundStyle(.red)
            } else {
                Label("Metal 4", systemImage: "bolt.fill").foregroundStyle(state == .ready ? .green : .yellow)
            }
            Divider().frame(height: 12)
            Text("Render: \(stats.renderCount)")
            Divider().frame(height: 12)
            Text("Draw Calls: \(stats.drawCalls)")
            Divider().frame(height: 12)
            Text("Invalidate: \(stats.lastReason)").foregroundStyle(.secondary)
            Divider().frame(height: 12)
            Text("Tool: \(workspace.tool.title)")
            Divider().frame(height: 12)
            if let snap = workspace.activeSnapKind {
                Text("Snap: \(snap.rawValue)").foregroundStyle(color(for: snap))
            } else {
                Text("Snap: none").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(in: .capsule)
        .padding(10)
    }

    private func color(for kind: SnapKind) -> Color {
        switch kind {
        case .vertex: return .orange
        case .edge: return .cyan
        case .grid: return .green
        }
    }
}
