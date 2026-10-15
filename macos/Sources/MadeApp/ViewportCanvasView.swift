import SwiftUI
import MadeCore

struct ViewportCanvasView: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            canvas
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
            .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: BarMetrics.height)
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
                    onResetView: { workspace.resetView() },
                    onCommitParam: { id, key, value in workspace.setParam(id, key, value) }
                )
            }
        case .initializing:
            ProgressView("Initializing Metal 4…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason):
            ContentUnavailableView("Metal Unavailable", systemImage: "exclamationmark.triangle", description: Text(reason.description))
        }
    }
}
