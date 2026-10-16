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
                Text(workspace.document.objects.isEmpty ? "Empty Scene" : (workspace.selectedObject?.name ?? "No Selection"))
            }
            .font(.callout)
            Spacer()
            if workspace.viewportManager.state == .ready {
                Picker("Display Mode", selection: Binding(
                    get: { workspace.displayMode },
                    set: { workspace.setDisplayMode($0) }
                )) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                Picker("Projection", selection: Binding(
                    get: { workspace.projectionMode },
                    set: { workspace.setProjectionMode($0) }
                )) {
                    ForEach(CameraProjection.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 170)
            }
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
                ZStack(alignment: .topTrailing) {
                    ZStack(alignment: .topLeading) {
                        CADMetalViewRepresentable(
                            document: workspace.document,
                            renderer: renderer,
                            selectedId: workspace.selectedId,
                            selectedSubElement: workspace.document.selectedSubElement,
                            tool: workspace.tool,
                            selectionFilter: workspace.selectionFilter,
                            showsGrid: workspace.showsGrid,
                            showsAxes: workspace.showsAxes,
                            showsGizmo: workspace.showsGizmo,
                            showsEdges: workspace.showsEdges,
                            displayMode: workspace.displayMode,
                            navigationPreset: workspace.navigationPreset,
                            coordinator: $workspace.coordinator,
                            isCommandActive: workspace.activeCommand != nil,
                            onCancelCommand: { workspace.cancelActiveCommand() },
                            onCommitCommand: { workspace.commitActiveCommand() },
                            onSelectObjectForCommand: { id in workspace.selectObjectForActiveCommand(id) },
                            onInvalidate: { workspace.updateStats() },
                            onSnapChanged: { workspace.handleSnapChanged($0) },
                            onToolShortcut: { workspace.tool = $0 },
                            onResetView: { workspace.resetView() },
                            onCommitParam: { id, key, value in workspace.setParam(id, key, value) },
                            onDoubleTapFace: { solidId, faceId in workspace.snapCameraToFace(solidId: solidId, faceId: faceId) },
                            onCancelAnimation: { workspace.cancelCameraAnimation() }
                        )

                        if workspace.document.objects.isEmpty {
                            EmptySceneGuidanceOverlayView()
                        }

                        if workspace.commandPanelPlacement == .floatingHUD, let session = workspace.activeCommand {
                            CommandHUDOverlayView(session: session)
                        }
                    }

                    ViewCubeOverlayView()
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                }
            }
        case .initializing:
            ProgressView("Initializing Metal 4…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason):
            ContentUnavailableView("Metal Unavailable", systemImage: "exclamationmark.triangle", description: Text(reason.description))
        }
    }
}
