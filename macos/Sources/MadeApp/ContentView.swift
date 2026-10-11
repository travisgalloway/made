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
    
    // Workspace Pane Visibility State (Xcode-style layout toggles)
    @State private var isNavigatorVisible: Bool = true
    @State private var isConsoleVisible: Bool = true
    @State private var isInspectorVisible: Bool = true
    
    // Viewport & Transform Gizmo State
    @State private var gizmoMode: GizmoMode = .select
    @State private var projectionMode: CameraProjection = .perspective
    @State private var currentPerspective: ViewportPerspective = .perspective
    
    // Simulation Execution State
    @State private var isSimulating: Bool = false
    
    // Debug & Console State
    @State private var consoleLogs: [ConsoleLogEntry] = [
        ConsoleLogEntry(level: .info, subsystem: "App", message: "made macOS workspace initialized"),
        ConsoleLogEntry(level: .kernel, subsystem: "Kernel", message: "Euclid CSG engine ready (60ms debounce)"),
        ConsoleLogEntry(level: .agent, subsystem: "Agent", message: "MCP JSON-RPC server ready with 8 tools")
    ]
    
    // Agent Subsystem
    @State private var toolRegistry: CADToolRegistry? = nil
    @State private var agentController: InAppAgentController? = nil
    
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
                    gizmoMode: $gizmoMode,
                    projectionMode: $projectionMode,
                    currentPerspective: $currentPerspective,
                    coordinator: $coordinator,
                    activeSnapKind: activeSnapKind,
                    onInvalidate: {
                        updateStats()
                    },
                    onSnapChanged: { result in
                        self.activeSnapKind = result?.kind
                        if let r = result {
                            log(.snap, subsystem: "Snapping", message: "Snapped to \(r.kind.rawValue) at target point")
                        }
                    },
                    onPerspectiveChanged: { persp in
                        guard let rend = viewportManager.renderer else { return }
                        rend.camera = Camera.preset(persp)
                        log(.info, subsystem: "Camera", message: "Changed perspective to \(persp.rawValue)")
                        invalidateViewport(reason: .camera)
                    },
                    onProjectionChanged: { proj in
                        guard let rend = viewportManager.renderer else { return }
                        rend.projectionMode = proj
                        log(.info, subsystem: "Camera", message: "Switched projection to \(proj.rawValue)")
                        invalidateViewport(reason: .camera)
                    }
                )
                .frame(minWidth: 400, minHeight: 300)
                
                // Bottom Collapsible Console & Telemetry Drawer
                if isConsoleVisible {
                    ConsoleDrawerView(
                        logs: consoleLogs,
                        renderCount: renderCount,
                        drawCalls: drawCalls,
                        lastReason: lastReason,
                        activeSnapKind: activeSnapKind,
                        viewportState: viewportManager.state,
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
                    agentController: agentController,
                    isMetalUnavailable: viewportManager.state.isUnavailable,
                    onTransformChanged: { id, newTransform in
                        document.setTransform(id: id, transform: newTransform)
                        if var mesh = viewportManager.renderer?.meshes[id] {
                            mesh.transform = newTransform
                            mesh.candidateMesh.transform = newTransform
                            viewportManager.renderer?.meshes[id] = mesh
                        }
                        log(.info, subsystem: "Transform", message: "Updated \(id.rawValue) position to \(newTransform.position)")
                        invalidateViewport(reason: .model)
                    },
                    onParamChanged: { id, key, value in
                        document.setParam(id: id, key: key, value: value)
                        log(.kernel, subsystem: "CSG", message: "Param changed for \(id.rawValue): \(key) = \(String(format: "%.1f", value))")
                        recomputeSolid(id: id)
                    },
                    onMaterialChanged: { id, newMat in
                        document.setMaterial(id: id, material: newMat)
                        log(.info, subsystem: "Material", message: "Updated material for \(id.rawValue)")
                    },
                    onSimulationChanged: { id, newSim in
                        document.setSimulation(id: id, simulation: newSim)
                        log(.info, subsystem: "Physics", message: "Updated physics for \(id.rawValue): mass = \(newSim.mass)kg")
                    },
                    onCopilotSubmit: { prompt in
                        log(.agent, subsystem: "Copilot", message: "Prompt: \(prompt)")
                        submitCopilotPrompt(prompt)
                    }
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
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
    
    // MARK: - Unified Window Toolbar (Xcode-style)
    
    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        // Leading: Primary Execution Controls (Run/Pause Simulation)
        ToolbarItemGroup(placement: .navigation) {
            Button {
                isSimulating.toggle()
                log(.info, subsystem: "Simulation", message: isSimulating ? "Simulation started" : "Simulation paused")
            } label: {
                Label(isSimulating ? "Pause" : "Run", systemImage: isSimulating ? "pause.fill" : "play.fill")
                    .foregroundColor(isSimulating ? .orange : .accentColor)
            }
            .help(isSimulating ? "Pause Simulation" : "Run Simulation")
            
            HStack(spacing: 4) {
                Circle()
                    .fill(isSimulating ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(isSimulating ? "Simulating" : "Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }
        
        // Center: Document Title & Perspective Quick Selector
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text("made — Untitled Scene.made")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        
        // Trailing: Viewport Perspective & Pane Layout Toggles
        ToolbarItemGroup(placement: .automatic) {
            // Viewport Perspective Picker Menu
            Menu {
                ForEach(ViewportPerspective.allCases) { persp in
                    Button(persp.rawValue) {
                        currentPerspective = persp
                        guard let rend = viewportManager.renderer else { return }
                        rend.camera = Camera.preset(persp)
                        log(.info, subsystem: "Camera", message: "Switched to \(persp.rawValue) perspective")
                        invalidateViewport(reason: .camera)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cube")
                    Text(currentPerspective.rawValue)
                }
            }
            .help("Viewport Perspective Presets")
            
            Divider()
            
            // Toggle Left Navigator
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isNavigatorVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundColor(isNavigatorVisible ? .accentColor : .secondary)
            }
            .help("Toggle Navigator Sidebar (Cmd+0)")
            
            // Toggle Bottom Console / Telemetry Drawer
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isConsoleVisible.toggle()
                }
            } label: {
                Image(systemName: "rectangle.bottomhalf.inset.filled")
                    .foregroundColor(isConsoleVisible ? .accentColor : .secondary)
            }
            .help("Toggle Debug Console & Telemetry (Cmd+Shift+Y)")
            
            // Toggle Right Inspector
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isInspectorVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundColor(isInspectorVisible ? .accentColor : .secondary)
            }
            .help("Toggle Inspector Panel (Opt+Cmd+0)")
        }
    }
    
    // MARK: - Actions & Engine Helpers
    
    private func submitCopilotPrompt(_ text: String) {
        Task {
            await agentController?.sendPrompt(text)
            await MainActor.run {
                for obj in document.objects {
                    recomputeSolid(id: obj.id)
                }
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
        self.agentController = InAppAgentController(toolRegistry: registry)
        
        for obj in document.objects {
            recomputeSolid(id: obj.id)
        }
        
        isKernelReady = true
        log(.info, subsystem: "Metal", message: "Metal 3 pipeline initialized successfully")
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
