import SwiftUI
import MadeCore

struct ContentView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var isMCPPopoverPresented = false

    var body: some View {
        @Bindable var workspace = workspace

        NavigationSplitView(columnVisibility: $workspace.columnVisibility) {
            NavigatorSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VSplitView {
                VStack(spacing: 0) {
                    ViewportCanvasView()
                    Divider()
                    ViewportStatusBar()
                }
                .frame(minHeight: 300)
                if workspace.isConsoleVisible {
                    ConsoleDrawerView()
                        .frame(minHeight: 80, idealHeight: 160)
                }
            }
            // A .frame(minWidth:) here loops AppKit's constraint pass beside the inspector and crashes windows under 1300 pt (#457).
            .navigationSplitViewColumnWidth(min: 400, ideal: 800)
            .toolbar { workspaceToolbar }
        }
        .inspector(isPresented: $workspace.isInspectorPresented) {
            InspectorPanelView()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 340)
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem {
                        inspectorToggle
                    }
                }
        }
        .navigationTitle(workspace.documentTitle)
        .onAppear {
            workspace.setUp()
            workspace.syncWindowState()
        }
        .onChange(of: workspace.isDocumentModified) { _, _ in
            workspace.syncWindowState()
        }
        .onChange(of: workspace.currentDocumentURL) { _, _ in
            workspace.syncWindowState()
        }
        .onChange(of: workspace.document.objects) { old, new in
            workspace.syncMeshes(removedFrom: old, to: new)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        @Bindable var workspace = workspace

        ToolbarItem(placement: .principal) {
            Picker("Viewport Tool", selection: $workspace.tool) {
                ForEach(ViewportTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Viewport tool: Select (V), Orbit (O), Pan (P), Zoom (Z). Option-drag orbits and middle-drag pans under every tool.")
        }

        ToolbarItemGroup {
            Picker("View Angle", systemImage: "camera.viewfinder", selection: Binding(
                get: { workspace.perspective },
                set: { workspace.applyPerspective($0) }
            )) {
                ForEach(ViewportPerspective.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .help("View Angle")
            Button("Zoom In", systemImage: "plus.magnifyingglass") { workspace.zoomStep(zoomIn: true) }
                .help("Zoom In (=)")
                .disabled(workspace.coordinator == nil)
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { workspace.zoomStep(zoomIn: false) }
                .help("Zoom Out (-)")
                .disabled(workspace.coordinator == nil)
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") { workspace.fitToScene() }
                .help("Zoom to Fit (F)")
                .disabled(workspace.coordinator == nil)
            Button("Reset View", systemImage: "house") { workspace.resetView() }
                .help("Reset View (H)")
                .disabled(workspace.coordinator == nil)
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup {
            Button {
                isMCPPopoverPresented.toggle()
            } label: {
                Label("MCP Server", systemImage: "sparkles")
                    .foregroundStyle(workspace.isMCPServerRunning ? Color.green : Color.primary)
            }
            .help(workspace.isMCPServerRunning ? "MCP Server: running" : "MCP Server: off")
            .popover(isPresented: $isMCPPopoverPresented, arrowEdge: .bottom) {
                MCPServerPopover()
            }
        }
    }

    private var inspectorToggle: some View {
        Button(workspace.isInspectorPresented ? "Hide Inspector" : "Show Inspector",
               systemImage: "sidebar.right") {
            workspace.isInspectorPresented.toggle()
        }
        .help(workspace.isInspectorPresented ? "Hide Inspector (⌃⌘I)" : "Show Inspector (⌃⌘I)")
    }
}
