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
    
    // Agent Subsystem
    @State private var selectedSidebarTab: Int = 0 // 0 = Inspector, 1 = Copilot
    @State private var toolRegistry: CADToolRegistry? = nil
    @State private var agentController: InAppAgentController? = nil
    @State private var copilotInputText: String = ""
    
    public init() {}
    
    public var body: some View {
        HSplitView {
            // 1. 3D Metal Viewport
            ZStack(alignment: .bottomLeading) {
                switch viewportManager.state {
                case .ready:
                    if let rend = viewportManager.renderer {
                        CADMetalViewRepresentable(document: document, renderer: rend) {
                            updateStats()
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    }
                case .initializing:
                    Color.black
                        .overlay(
                            Text("Initializing Metal 3...")
                                .foregroundColor(.gray)
                        )
                        .frame(minWidth: 400, minHeight: 300)
                case .unavailable(let reason):
                    Color.black
                        .overlay(
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("Metal unavailable")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(reason.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                        .frame(minWidth: 400, minHeight: 300)
                }
                
                // Status HUD (Observability surface mirroring made runtime state)
                HStack(spacing: 16) {
                    if viewportManager.state.isUnavailable {
                        Label("Metal unavailable", systemImage: "bolt.slash.fill")
                            .foregroundColor(.red)
                    } else {
                        Label("Metal 3", systemImage: "bolt.fill")
                            .foregroundColor(viewportManager.state == .ready ? .green : .yellow)
                    }
                    Divider().frame(height: 12)
                    Text("Render Count: \(renderCount)")
                        .monospacedDigit()
                    Divider().frame(height: 12)
                    Text("Draw Calls: \(drawCalls)")
                        .monospacedDigit()
                    Divider().frame(height: 12)
                    Text("Invalidate: \(lastReason)")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
            
            // 2. CAD Sidebar (Inspector & Agent Copilot)
            VStack(spacing: 0) {
                Picker("Sidebar View", selection: $selectedSidebarTab) {
                    Text("Inspector").tag(0)
                    Label("AI Copilot", systemImage: "sparkles")
                        .tag(1)
                        .disabled(viewportManager.state.isUnavailable)
                }
                .pickerStyle(.segmented)
                .padding(12)
                
                Divider()
                
                if selectedSidebarTab == 0 || viewportManager.state.isUnavailable {
                    inspectorView
                } else {
                    copilotView
                }
            }
            .frame(minWidth: 280, maxWidth: 360)
            .background(Color(NSColor.controlBackgroundColor))
            .onChange(of: selectedSidebarTab) { _, newValue in
                if viewportManager.state.isUnavailable && newValue == 1 {
                    selectedSidebarTab = 0
                }
            }
            .onChange(of: viewportManager.state) { _, newState in
                if newState.isUnavailable && selectedSidebarTab == 1 {
                    selectedSidebarTab = 0
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            setupMetal()
        }
    }
    
    // MARK: - Inspector View
    
    private var inspectorView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Active Solid", selection: $selectedId) {
                ForEach(document.objects) { obj in
                    Text(obj.id.rawValue).tag(obj.id)
                }
            }
            .pickerStyle(.menu)
            
            Divider()
            
            if let selected = document.objects.first(where: { $0.id == selectedId }) {
                switch selected.def {
                case .box(let params):
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Box Dimensions")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        paramSlider(label: "Width (X)", value: params.width, range: DocumentLimits.boxWidth) { val in
                            document.setParam(id: selectedId, key: "width", value: val)
                            recomputeSolid(id: selectedId)
                        }
                        
                        paramSlider(label: "Depth (Y)", value: params.depth, range: DocumentLimits.boxDepth) { val in
                            document.setParam(id: selectedId, key: "depth", value: val)
                            recomputeSolid(id: selectedId)
                        }
                        
                        paramSlider(label: "Height (Z)", value: params.height, range: DocumentLimits.boxHeight) { val in
                            document.setParam(id: selectedId, key: "height", value: val)
                            recomputeSolid(id: selectedId)
                        }
                    }
                    
                case .cylinder(let params):
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cylinder Dimensions")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        paramSlider(label: "Radius", value: params.radius, range: DocumentLimits.cylinderRadius) { val in
                            document.setParam(id: selectedId, key: "radius", value: val)
                            recomputeSolid(id: selectedId)
                        }
                        
                        paramSlider(label: "Height (Z)", value: params.height, range: DocumentLimits.cylinderHeight) { val in
                            document.setParam(id: selectedId, key: "height", value: val)
                            recomputeSolid(id: selectedId)
                        }
                    }
                    
                case .imported(let name):
                    Text("Imported Solid: \(name)")
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - Copilot View
    
    private var copilotView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let agent = agentController {
                            ForEach(agent.messages) { msg in
                                HStack {
                                    if msg.sender == "user" {
                                        Spacer()
                                        Text(msg.text)
                                            .padding(10)
                                            .background(Color.accentColor.opacity(0.85))
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    } else {
                                        VStack(alignment: .leading, spacing: 4) {
                                            if let tool = msg.toolExecuted {
                                                Label(tool, systemImage: "wrench.and.screwdriver")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(msg.text)
                                                .padding(10)
                                                .background(Color(NSColor.windowBackgroundColor))
                                                .cornerRadius(12)
                                        }
                                        Spacer()
                                    }
                                }
                                .id(msg.id)
                            }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: agentController?.messages.count) {
                    if let last = agentController?.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input bar
            HStack(spacing: 8) {
                TextField("Describe CAD change...", text: $copilotInputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitCopilotPrompt()
                    }
                
                Button(action: submitCopilotPrompt) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(copilotInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
    }
    
    private func submitCopilotPrompt() {
        let text = copilotInputText
        copilotInputText = ""
        Task {
            await agentController?.sendPrompt(text)
            // Recompute scene after agent modifications
            await MainActor.run {
                for obj in document.objects {
                    recomputeSolid(id: obj.id)
                }
            }
        }
    }
    
    private func paramSlider(label: String, value: Float, range: ParamRange, onChange: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f mm", value))
                    .font(.caption)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range.min...range.max
            )
        }
    }
    
    private func setupMetal() {
        let state = viewportManager.setup()
        if let rend = viewportManager.renderer {
            rend.onDeviceLost = { [weak viewportManager] in
                Task { @MainActor in
                    viewportManager?.handleDeviceLost()
                }
            }
        }
        
        // Initialize Agent Subsystem
        let registry = CADToolRegistry(
            document: document,
            kernelClient: kernelClient,
            snapshotProvider: viewportManager.renderer
        )
        self.toolRegistry = registry
        self.agentController = InAppAgentController(toolRegistry: registry)
        
        // Initial solid generation: kernel still runs even without a renderer
        for obj in document.objects {
            recomputeSolid(id: obj.id)
        }
        
        isKernelReady = true
        
        if state.isUnavailable && selectedSidebarTab == 1 {
            selectedSidebarTab = 0
        }
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
                    let color: SIMD4<Float> = (id == boxSolidId)
                        ? SIMD4<Float>(0.35, 0.65, 0.95, 1.0)
                        : SIMD4<Float>(0.95, 0.55, 0.35, 1.0)
                    
                    var offset: SIMD3<Float> = obj.transform.position
                    if offset == .zero {
                        offset = (id == boxSolidId) ? SIMD3<Float>(-25, 0, 0) : SIMD3<Float>(25, 0, 0)
                    }
                    
                    var transform = obj.transform
                    transform.position = offset
                    
                    if let mesh = rend.createMesh(from: payload, transform: transform, color: color) {
                        rend.meshes[id] = mesh
                        RenderInstrumentation.shared.recordInvalidation(reason: .model)
                        updateStats()
                    }
                }
            }
        }
    }
    
    private func updateStats() {
        self.renderCount = RenderInstrumentation.shared.renderCount
        self.drawCalls = RenderInstrumentation.shared.drawCalls
        self.lastReason = RenderInstrumentation.shared.lastReason?.rawValue ?? "idle"
    }
}
