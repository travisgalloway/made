import SwiftUI
import MadeCore

struct ContentView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var workspace = workspace

        NavigationSplitView(columnVisibility: $workspace.columnVisibility) {
            NavigatorSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                ViewportCanvasView()
                if workspace.isConsoleVisible {
                    Divider()
                    ConsoleDrawerView()
                }
            }
            .frame(minWidth: 400, minHeight: 300)
        }
        .inspector(isPresented: $workspace.isInspectorPresented) {
            InspectorPanelView()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 340)
        }
        .toolbar { workspaceToolbar }
        .onAppear { workspace.setUp() }
        .onChange(of: workspace.document.objects) { old, new in
            workspace.syncMeshes(removedFrom: old, to: new)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        @Bindable var workspace = workspace

        ToolbarItem(placement: .navigation) {
            Text("Untitled Project")
                .font(.headline)
                .padding(.horizontal, 4)
        }

        ToolbarSpacer(.flexible)

        ToolbarItem(placement: .automatic) {
            Picker("Viewport Tool", selection: $workspace.tool) {
                ForEach(ViewportTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Viewport tool: Select (V), Orbit (O), Pan (P), Zoom (Z). Option-drag orbits and middle-drag pans under every tool.")
        }

        ToolbarItem(placement: .automatic) {
            ControlGroup("View", systemImage: "camera") {
                Button("Zoom In", systemImage: "plus.magnifyingglass") { workspace.zoomStep(zoomIn: true) }
                    .help("Zoom In (=)")
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { workspace.zoomStep(zoomIn: false) }
                    .help("Zoom Out (-)")
                Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") { workspace.fitToScene() }
                    .help("Zoom to Fit (F)")
                Button("Reset View", systemImage: "house") { workspace.resetView() }
                    .help("Reset View (H)")
            }
            .disabled(workspace.coordinator == nil)
        }

        ToolbarItem(placement: .automatic) {
            Button {
                if workspace.isMCPWindowOpen {
                    dismissWindow(id: MCPServerView.windowId)
                } else {
                    openWindow(id: MCPServerView.windowId)
                }
            } label: {
                Label("MCP", systemImage: "sparkle")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(workspace.isMCPServerRunning ? .green : .secondary)
            }
            .help("Model Context Protocol (MCP) Server")
        }

        ToolbarItem(placement: .automatic) {
            ControlGroup("Panes", systemImage: "rectangle.3.group") {
                Toggle(isOn: Binding(
                    get: { workspace.isNavigatorVisible },
                    set: { workspace.columnVisibility = $0 ? .all : .detailOnly }
                )) {
                    Label("Navigator", systemImage: "sidebar.left")
                }
                .help("Toggle Navigator Sidebar")
                Toggle(isOn: $workspace.isConsoleVisible.animation(.easeInOut(duration: 0.15))) {
                    Label("Console", systemImage: "rectangle.bottomhalf.inset.filled")
                }
                .help("Toggle Debug Console")
                Toggle(isOn: $workspace.isInspectorPresented) {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle Inspector Panel")
            }
            .toggleStyle(.button)
        }
    }
}
