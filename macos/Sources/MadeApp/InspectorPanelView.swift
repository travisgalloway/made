import SwiftUI
import MadeCore
import simd

struct InspectorPanelView: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace

        VStack(spacing: 0) {
            PaneTabBar(label: "Inspector", selection: $workspace.inspectorTab, fillsWidth: true)
            Divider()
            if workspace.commandPanelPlacement == .inspector, let session = workspace.activeCommand {
                ScrollView {
                    CommandPanelView(session: session)
                }
                .frame(maxHeight: .infinity)
            } else {
                switch workspace.inspectorTab {
                case .properties:
                    properties
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var properties: some View {
        if let selected = workspace.selectedObject {
            ScrollView {
                Form {
                    identitySection(selected)
                    transformSection(selected)
                    dimensionsSection(selected)
                    materialSection(selected)
                }
                .disabled(selected.isLocked)
                .formStyle(.columns)
                .controlSize(.small)
                .padding()
            }
        } else if workspace.document.objects.isEmpty {
            ContentUnavailableView {
                Label("No Objects in Scene", systemImage: "cube.transparent")
            } description: {
                Text("Add a 3D solid primitive or open a part script to inspect and edit its properties.")
            } actions: {
                HStack(spacing: 8) {
                    Button("Add Box", systemImage: "shippingbox") {
                        workspace.addDefaultBox()
                    }
                    Button("Add Cylinder", systemImage: "cylinder") {
                        workspace.addDefaultCylinder()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            ContentUnavailableView(
                "No Object Selected",
                systemImage: "cursorarrow.slash",
                description: Text("Select a solid in the viewport or Navigator to inspect its properties.")
            )
        }
    }

    // MARK: - Sections

    private func identitySection(_ obj: SceneObject) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { obj.name },
                set: { workspace.document.setName(id: obj.id, name: $0) }
            ))
            LabeledContent("ID") {
                Text(obj.id.rawValue).monospaced().textSelection(.enabled)
            }
            LabeledContent("Kind", value: obj.def.kind.capitalized)
        } header: {
            sectionHeader("Identity", isFirst: true)
        }
    }

    private func transformSection(_ obj: SceneObject) -> some View {
        Section {
            LabeledContent("Position (mm)") {
                vectorFields(obj.transform.position) { position in
                    var t = obj.transform
                    t.position = position
                    workspace.setTransform(obj.id, t)
                }
            }
            LabeledContent("Scale") {
                vectorFields(obj.transform.scale) { scale in
                    var t = obj.transform
                    t.scale = simd_max(scale, SIMD3<Float>(repeating: DocumentLimits.scaleFloor))
                    workspace.setTransform(obj.id, t)
                }
            }
        } header: {
            sectionHeader("Transform")
        }
    }

    @ViewBuilder
    private func dimensionsSection(_ obj: SceneObject) -> some View {
        Section {
            switch obj.def {
            case .box(let params):
                paramField("Width (X)", params.width, DocumentLimits.boxWidth) { workspace.setParam(obj.id, "width", $0) }
                paramField("Depth (Y)", params.depth, DocumentLimits.boxDepth) { workspace.setParam(obj.id, "depth", $0) }
                paramField("Height (Z)", params.height, DocumentLimits.boxHeight) { workspace.setParam(obj.id, "height", $0) }
            case .cylinder(let params):
                paramField("Radius", params.radius, DocumentLimits.cylinderRadius) { workspace.setParam(obj.id, "radius", $0) }
                paramField("Height (Z)", params.height, DocumentLimits.cylinderHeight) { workspace.setParam(obj.id, "height", $0) }
            case .imported(let name):
                LabeledContent("Imported Mesh", value: name)
            case .boolean(let op, let solidA, let solidB):
                LabeledContent("Boolean", value: "\(op.rawValue)(\(solidA.rawValue), \(solidB.rawValue))")
            case .part(let url, _):
                LabeledContent("Source File") {
                    Text(url.lastPathComponent)
                        .monospaced()
                        .textSelection(.enabled)
                        .help(url.path)
                }
                LabeledContent("Live Reload") {
                    Button("Reload Now") {
                        workspace.reloadPart(obj.id)
                    }
                }
            }
            if let message = workspace.recomputeFailures.message(for: obj.id) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        } header: {
            sectionHeader("Dimensions")
        }
    }

    private func materialSection(_ obj: SceneObject) -> some View {
        Section {
            ColorPicker("Color", selection: Binding(
                get: {
                    let c = obj.material.color
                    return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: Double(c.w))
                },
                set: { newColor in
                    let resolved = newColor.resolve(in: EnvironmentValues())
                    let simdColor = SIMD4<Float>(resolved.red, resolved.green, resolved.blue, 1.0)
                    workspace.setMaterial(obj.id, MaterialAttributes(color: simdColor))
                }
            ), supportsOpacity: false)
        } header: {
            sectionHeader("Material")
        }
    }

    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isFirst { Divider() }
            Text(title).font(.headline)
        }
        .padding(.top, 8)
    }

    // MARK: - Controls

    /// Three axis fields with X/Y/Z captions beneath, so Position and Scale lay out identically.
    private func vectorFields(_ value: SIMD3<Float>, onChange: @escaping (SIMD3<Float>) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { axis in
                let name = ["X", "Y", "Z"][axis]
                VStack(spacing: 2) {
                    CommitNumberField(label: name, value: Double(value[axis])) { newValue in
                        var v = value
                        v[axis] = Float(newValue)
                        onChange(v)
                    }
                    .accessibilityLabel(name)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .labelsHidden()
    }

    /// A typed millimeter value with a 1-mm stepper; `setParam` clamps to the range (invariant 9).
    private func paramField(_ label: String, _ value: Float, _ range: ParamRange, onChange: @escaping (Float) -> Void) -> some View {
        let binding = Binding(get: { Double(value) }, set: { onChange(Float($0)) })
        let spoken = "\(value.formatted(.number.precision(.fractionLength(1)))) millimeters"
        return LabeledContent(label) {
            HStack(spacing: 4) {
                CommitNumberField(label: label, value: Double(value), width: 64) { onChange(Float($0)) }
                    .accessibilityLabel(label)
                    .accessibilityValue(spoken)
                Text("mm").foregroundStyle(.secondary)
                Stepper(label, value: binding, in: Double(range.min)...Double(range.max), step: 1)
                    .accessibilityLabel(label)
                    .accessibilityValue(spoken)
            }
            .labelsHidden()
        }
    }
}
