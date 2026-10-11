import SwiftUI
import MadeCore

public struct InspectorPanelView: View {
    @Bindable var document: DocumentModel
    @Binding var selectedId: ObjectId
    var agentController: InAppAgentController?
    var isMetalUnavailable: Bool
    var onTransformChanged: (ObjectId, Transform) -> Void
    var onParamChanged: (ObjectId, String, Float) -> Void
    var onMaterialChanged: (ObjectId, MaterialAttributes) -> Void
    var onSimulationChanged: (ObjectId, SimulationParameters) -> Void
    var onCopilotSubmit: (String) -> Void
    
    @State private var activeTab: InspectorTab = .properties
    @State private var copilotInputText: String = ""
    
    public init(
        document: DocumentModel,
        selectedId: Binding<ObjectId>,
        agentController: InAppAgentController?,
        isMetalUnavailable: Bool,
        onTransformChanged: @escaping (ObjectId, Transform) -> Void,
        onParamChanged: @escaping (ObjectId, String, Float) -> Void,
        onMaterialChanged: @escaping (ObjectId, MaterialAttributes) -> Void,
        onSimulationChanged: @escaping (ObjectId, SimulationParameters) -> Void,
        onCopilotSubmit: @escaping (String) -> Void
    ) {
        self.document = document
        self._selectedId = selectedId
        self.agentController = agentController
        self.isMetalUnavailable = isMetalUnavailable
        self.onTransformChanged = onTransformChanged
        self.onParamChanged = onParamChanged
        self.onMaterialChanged = onMaterialChanged
        self.onSimulationChanged = onSimulationChanged
        self.onCopilotSubmit = onCopilotSubmit
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Inspector Header Tabs
            HStack(spacing: 4) {
                ForEach(InspectorTab.allCases) { tab in
                    Button {
                        activeTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.iconName)
                            Text(tab.rawValue)
                        }
                        .font(.system(size: 11, weight: activeTab == tab ? .semibold : .regular))
                        .foregroundColor(activeTab == tab ? .accentColor : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(activeTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .disabled(tab == .copilot && isMetalUnavailable)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Tab Content
            if activeTab == .properties || (activeTab == .copilot && isMetalUnavailable) {
                ScrollView {
                    propertiesContent
                        .padding(12)
                }
            } else if activeTab == .simulation {
                ScrollView {
                    simulationContent
                        .padding(12)
                }
            } else {
                copilotContent
            }
        }
        .frame(minWidth: 260, maxWidth: 340)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Properties Inspector
    
    private var propertiesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selected = document.objects.first(where: { $0.id == selectedId }) {
                // Section 1: Identity & Metadata
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("IDENTITY & TYPE")
                    
                    HStack {
                        Text("Name").foregroundColor(.secondary).font(.caption)
                        Spacer()
                        TextField("Name", text: Binding(
                            get: { selected.name },
                            set: { document.setName(id: selectedId, name: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 140)
                    }
                    
                    HStack {
                        Text("ID").foregroundColor(.secondary).font(.caption)
                        Spacer()
                        Text(selected.id.rawValue)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Kind").foregroundColor(.secondary).font(.caption)
                        Spacer()
                        Text(selected.def.kind.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Layer").foregroundColor(.secondary).font(.caption)
                        Spacer()
                        Text(selected.layer)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Section 2: Numeric Transform Coordinates
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("TRANSFORM COORDINATES")
                    
                    Text("Position (mm)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        coordField(label: "X", value: selected.transform.position.x) { newX in
                            var t = selected.transform
                            t.position.x = newX
                            onTransformChanged(selected.id, t)
                        }
                        coordField(label: "Y", value: selected.transform.position.y) { newY in
                            var t = selected.transform
                            t.position.y = newY
                            onTransformChanged(selected.id, t)
                        }
                        coordField(label: "Z", value: selected.transform.position.z) { newZ in
                            var t = selected.transform
                            t.position.z = newZ
                            onTransformChanged(selected.id, t)
                        }
                    }
                    
                    Text("Scale")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    HStack(spacing: 8) {
                        coordField(label: "X", value: selected.transform.scale.x) { newSx in
                            var t = selected.transform
                            t.scale.x = max(0.01, newSx)
                            onTransformChanged(selected.id, t)
                        }
                        coordField(label: "Y", value: selected.transform.scale.y) { newSy in
                            var t = selected.transform
                            t.scale.y = max(0.01, newSy)
                            onTransformChanged(selected.id, t)
                        }
                        coordField(label: "Z", value: selected.transform.scale.z) { newSz in
                            var t = selected.transform
                            t.scale.z = max(0.01, newSz)
                            onTransformChanged(selected.id, t)
                        }
                    }
                }
                
                Divider()
                
                // Section 3: Parametric Dimensions
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("GEOMETRIC DIMENSIONS")
                    
                    switch selected.def {
                    case .box(let params):
                        paramSlider(label: "Width (X)", value: params.width, range: DocumentLimits.boxWidth) { val in
                            onParamChanged(selectedId, "width", val)
                        }
                        paramSlider(label: "Depth (Y)", value: params.depth, range: DocumentLimits.boxDepth) { val in
                            onParamChanged(selectedId, "depth", val)
                        }
                        paramSlider(label: "Height (Z)", value: params.height, range: DocumentLimits.boxHeight) { val in
                            onParamChanged(selectedId, "height", val)
                        }
                    case .cylinder(let params):
                        paramSlider(label: "Radius", value: params.radius, range: DocumentLimits.cylinderRadius) { val in
                            onParamChanged(selectedId, "radius", val)
                        }
                        paramSlider(label: "Height (Z)", value: params.height, range: DocumentLimits.cylinderHeight) { val in
                            onParamChanged(selectedId, "height", val)
                        }
                    case .imported(let name):
                        Text("Imported Mesh: \(name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Section 4: Material Attributes
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("MATERIAL ATTRIBUTES")
                    
                    HStack {
                        Text("Roughness").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f", selected.material.roughness)).font(.caption).monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { selected.material.roughness },
                            set: {
                                var m = selected.material
                                m.roughness = $0
                                onMaterialChanged(selected.id, m)
                            }
                        ),
                        in: 0...1
                    )
                    
                    HStack {
                        Text("Opacity").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", selected.material.opacity * 100)).font(.caption).monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { selected.material.opacity },
                            set: {
                                var m = selected.material
                                m.opacity = $0
                                onMaterialChanged(selected.id, m)
                            }
                        ),
                        in: 0.1...1
                    )
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No Object Selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Select a solid in the Navigator or Viewport to inspect properties.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
    
    // MARK: - Simulation Inspector
    
    private var simulationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selected = document.objects.first(where: { $0.id == selectedId }) {
                sectionHeader("PHYSICS SIMULATION")
                
                // Body Type Picker
                HStack {
                    Text("Body Type").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { selected.simulation.bodyType },
                        set: {
                            var s = selected.simulation
                            s.bodyType = $0
                            onSimulationChanged(selected.id, s)
                        }
                    )) {
                        ForEach(SimulationBodyType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                
                // Mass
                HStack {
                    Text("Mass (kg)").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f kg", selected.simulation.mass)).font(.caption).monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { selected.simulation.mass },
                        set: {
                            var s = selected.simulation
                            s.mass = $0
                            onSimulationChanged(selected.id, s)
                        }
                    ),
                    in: 0.1...50
                )
                
                // Friction
                HStack {
                    Text("Friction").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", selected.simulation.friction)).font(.caption).monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { selected.simulation.friction },
                        set: {
                            var s = selected.simulation
                            s.friction = $0
                            onSimulationChanged(selected.id, s)
                        }
                    ),
                    in: 0...1
                )
                
                // Restitution (Bounciness)
                HStack {
                    Text("Restitution").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", selected.simulation.restitution)).font(.caption).monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { selected.simulation.restitution },
                        set: {
                            var s = selected.simulation
                            s.restitution = $0
                            onSimulationChanged(selected.id, s)
                        }
                    ),
                    in: 0...1
                )
                
                Divider()
                
                sectionHeader("SIMULATION PIPELINE")
                VStack(alignment: .leading, spacing: 6) {
                    pipelineRow(label: "Solver State", value: "Ready")
                    pipelineRow(label: "Update Frequency", value: "60 Hz (16.6 ms)")
                    pipelineRow(label: "Ground Plane Collision", value: "Active")
                }
            } else {
                Text("Select an object to configure physics.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Copilot Content
    
    private var copilotContent: some View {
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
                        submitCopilot()
                    }
                
                Button(action: submitCopilot) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(copilotInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
    }
    
    private func submitCopilot() {
        let text = copilotInputText
        copilotInputText = ""
        onCopilotSubmit(text)
    }
    
    // MARK: - View Helpers
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
    }
    
    private func coordField(label: String, value: Float, onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 12)
            TextField("", value: Binding(
                get: { Double(value) },
                set: { onChange(Float($0)) }
            ), format: .number.precision(.fractionLength(1)))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
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
    
    private func pipelineRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).foregroundColor(.primary)
        }
    }
}
