import SwiftUI
import MetalKit
import MadeCore

public struct ContentView: View {
    @State private var document = DocumentModel()
    @State private var selectedId: ObjectId = boxSolidId
    @State private var viewportManager = ViewportStateManager()
    @State private var kernelClient = KernelClient()
    @State private var renderCount: Int = 0
    @State private var drawCalls: Int = 0
    @State private var lastReason: String = "init"
    @State private var isKernelReady: Bool = false
    @State private var coordinator: CADMetalViewRepresentable.Coordinator? = nil
    @State private var activeSnapKind: SnapKind? = nil
    
    // Workspace Pane Visibility State (layout toggles)
    @State private var isNavigatorVisible: Bool = true
    @State private var isConsoleVisible: Bool = false
    @State private var isInspectorVisible: Bool = true
    
    // Camera Viewport Perspective State
    @State private var currentPerspective: ViewportPerspective = .perspective
    
    // Debug & Execution Console Logs
    @State private var consoleLogs: [ConsoleLogEntry] = [
        ConsoleLogEntry(level: .info, subsystem: "App", message: "made macOS workspace initialized")
    ]
    
    // MCP Subsystem
    @State private var toolRegistry: CADToolRegistry? = nil
    @State private var mcpServer: MCPServer? = nil
    @State private var isMCPServerRunning: Bool = false
    @State private var showMCPPopout: Bool = false
    
    public init() {}
    
    public var body: some View {
        HSplitView {
            // 1. Left Navigation Sidebar
            if isNavigatorVisible {
                NavigatorSidebarView(
                    document: document,
                    selectedId: $selectedId,
                    onAddObject: { def in
                        let newId = document.addObject(def: def)
                        selectedId = newId
                        log(.info, subsystem: "Scene", message: "Added object \(newId.rawValue)")
                        recomputeSolid(id: newId)
                    },
                    onToggleVisibility: { id in
                        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
                        let newVis = !obj.isVisible
                        document.setVisibility(id: id, isVisible: newVis)
                        if newVis {
                            viewportManager.renderer?.hiddenSolidIds.remove(id)
                        } else {
                            viewportManager.renderer?.hiddenSolidIds.insert(id)
                        }
                        log(.info, subsystem: "Scene", message: "\(newVis ? "Showed" : "Hid") object \(id.rawValue)")
                        invalidateViewport(reason: .model)
                    },
                    onToggleLock: { id in
                        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
                        let newLock = !obj.isLocked
                        document.setLocked(id: id, isLocked: newLock)
                        log(.info, subsystem: "Scene", message: "\(newLock ? "Locked" : "Unlocked") object \(id.rawValue)")
                    },
                    onDeleteObject: { id in
                        document.removeObject(id: id)
                        viewportManager.renderer?.meshes.removeValue(forKey: id)
                        if selectedId == id {
                            selectedId = document.objects.first?.id ?? ObjectId("none")
                        }
                        log(.info, subsystem: "Scene", message: "Removed object \(id.rawValue)")
                        invalidateViewport(reason: .model)
                    }
                )
            }
            
            // 2. Central Workspace (3D Viewport & Bottom Debug Console)
            VSplitView {
                // Primary CAD Viewport
                ViewportCanvasView(
                    document: document,
                    renderer: viewportManager.renderer,
                    viewportState: viewportManager.state,
                    selectedId: $selectedId,
                    coordinator: $coordinator,
                    activeSnapKind: activeSnapKind,
                    currentPerspective: currentPerspective,
                    renderCount: renderCount,
                    drawCalls: drawCalls,
                    lastReason: lastReason,
                    onInvalidate: {
                        updateStats()
                    },
                    onSnapChanged: { result in
                        self.activeSnapKind = result?.kind
                        if let r = result {
                            log(.snap, subsystem: "Snapping", message: "Snapped to \(r.kind.rawValue)")
                        }
                    },
                    onPerspectiveChanged: { persp in
                        currentPerspective = persp
                        guard let rend = viewportManager.renderer else { return }
                        rend.camera = Camera.preset(persp)
                        log(.info, subsystem: "Camera", message: "Switched to \(persp.rawValue) perspective")
                        invalidateViewport(reason: .camera)
                    }
                )
                .frame(minWidth: 400, minHeight: 300)
                
                // Bottom Collapsible Console Drawer
                if isConsoleVisible {
                    ConsoleDrawerView(
                        logs: consoleLogs,
                        onClearLogs: {
                            consoleLogs.removeAll()
                        },
                        onCollapse: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isConsoleVisible = false
                            }
                        }
                    )
                }
            }
            
            // 3. Right Inspector Panel
            if isInspectorVisible {
                InspectorPanelView(
                    document: document,
                    selectedId: $selectedId,
                    onTransformChanged: { id, newTransform in
                        document.setTransform(id: id, transform: newTransform)
                        if var mesh = viewportManager.renderer?.meshes[id] {
                            mesh.transform = newTransform
                            mesh.candidateMesh.transform = newTransform
                            viewportManager.renderer?.meshes[id] = mesh
                        }
                        invalidateViewport(reason: .model)
                    },
                    onParamChanged: { id, key, value in
                        document.setParam(id: id, key: key, value: value)
                        log(.kernel, subsystem: "CSG", message: "Updated \(id.rawValue) \(key) to \(String(format: "%.1f", value))")
                        recomputeSolid(id: id)
                    }
                )
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .navigationTitle("")
        .toolbar {
            workspaceToolbar
        }
        .onAppear {
            setupMetal()
        }
        .onChange(of: document.objects) { oldObjects, newObjects in
            let newIds = Set(newObjects.map(\.id))
            for old in oldObjects {
                if !newIds.contains(old.id) {
                    viewportManager.renderer?.meshes.removeValue(forKey: old.id)
                    invalidateViewport(reason: .model)
                }
            }
        }
    }
    
    // MARK: - Workspace Toolbar
    
    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        // Center Area: Only the name of the project/folder
        ToolbarItem(placement: .principal) {
            Text("Untitled Project")
                .font(.system(size: 12, weight: .medium))
        }
        
        // Right Edge: MCP and Pane Toggles (Justified to the right edge)
        ToolbarItemGroup(placement: .primaryAction) {
            // MCP Server Control (AI diamond icon: ✧ sparkle, toggles green when running)
            Button {
                showMCPPopout.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12))
                        .foregroundColor(isMCPServerRunning ? .green : .secondary)
                    Text("MCP")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .popover(isPresented: $showMCPPopout, arrowEdge: .bottom) {
                MCPServerPopoutView(
                    isRunning: isMCPServerRunning,
                    port: mcpServer?.port ?? 9820,
                    onToggleServer: toggleMCPServer
                )
            }
            .help("Model Context Protocol (MCP) Server")
            
            // Window Pane Toggles Group
            ControlGroup {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isNavigatorVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(isNavigatorVisible ? .accentColor : .secondary)
                }
                .help("Toggle Navigator Sidebar")
                
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isConsoleVisible.toggle()
                    }
                } label: {
                    Image(systemName: "rectangle.bottomhalf.inset.filled")
                        .foregroundColor(isConsoleVisible ? .accentColor : .secondary)
                }
                .help("Toggle Debug Console")
                
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isInspectorVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(isInspectorVisible ? .accentColor : .secondary)
                }
                .help("Toggle Inspector Panel")
            }
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func toggleMCPServer() {
        guard let server = mcpServer else { return }
        if isMCPServerRunning {
            server.stop()
            isMCPServerRunning = false
            log(.info, subsystem: "MCP", message: "Stopped MCP server")
        } else {
            do {
                try server.start(port: 9820)
                isMCPServerRunning = true
                log(.info, subsystem: "MCP", message: "Started MCP server on port 9820")
            } catch {
                log(.error, subsystem: "MCP", message: "Failed to start MCP server: \(error.localizedDescription)")
            }
        }
    }
    
    private func log(_ level: ConsoleLogLevel, subsystem: String, message: String) {
        let entry = ConsoleLogEntry(level: level, subsystem: subsystem, message: message)
        consoleLogs.append(entry)
        if consoleLogs.count > 200 {
            consoleLogs.removeFirst(50)
        }
    }
    
    private func setupMetal() {
        _ = viewportManager.setup()
        if let rend = viewportManager.renderer {
            rend.onDeviceLost = { [weak viewportManager] in
                Task { @MainActor in
                    viewportManager?.handleDeviceLost()
                }
            }
        }
        
        let registry = CADToolRegistry(
            document: document,
            kernelClient: kernelClient,
            snapshotProvider: viewportManager.renderer
        )
        self.toolRegistry = registry
        let server = MCPServer(toolRegistry: registry)
        server.onStateChange = { @Sendable running in
            Task { @MainActor in
                self.isMCPServerRunning = running
            }
        }
        self.mcpServer = server
        
        for obj in document.objects {
            recomputeSolid(id: obj.id)
        }
        
        isKernelReady = true
        log(.info, subsystem: "Metal", message: "Metal 3 pipeline initialized")
    }
    
    private func recomputeSolid(id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        
        Task {
            let request: KernelRequest
            switch obj.def {
            case .box(let params):
                request = .makeBox(jobId: JobId("job-\(UUID().uuidString)"), solidId: id, params: params)
            case .cylinder(let params):
                request = .makeCylinder(jobId: JobId("job-\(UUID().uuidString)"), solidId: id, params: params)
            case .imported:
                return
            }
            
            let result = await kernelClient.request(request)
            if case .success(_, let payload) = result {
                await MainActor.run {
                    guard let rend = self.viewportManager.renderer else { return }
                    let color: SIMD4<Float> = obj.material.color
                    
                    var offset: SIMD3<Float> = obj.transform.position
                    if offset == .zero {
                        offset = (id == boxSolidId) ? SIMD3<Float>(-25, 0, 0) : SIMD3<Float>(25, 0, 0)
                    }
                    
                    var transform = obj.transform
                    transform.position = offset
                    
                    if let mesh = rend.createMesh(from: payload, solidId: id, transform: transform, color: color) {
                        rend.meshes[id] = mesh
                        if !obj.isVisible {
                            rend.hiddenSolidIds.insert(id)
                        }
                        invalidateViewport(reason: .model)
                    }
                }
            }
        }
    }
    
    private func invalidateViewport(reason: InvalidateReason) {
        if let coord = coordinator {
            coord.invalidate(reason: reason)
        } else {
            RenderInstrumentation.shared.recordInvalidation(reason: reason)
            updateStats()
        }
    }
    
    private func updateStats() {
        self.renderCount = RenderInstrumentation.shared.renderCount
        self.drawCalls = RenderInstrumentation.shared.drawCalls
        self.lastReason = RenderInstrumentation.shared.lastReason?.rawValue ?? "idle"
    }
}
