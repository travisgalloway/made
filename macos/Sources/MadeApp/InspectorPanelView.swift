import SwiftUI
import MadeCore
import simd

struct InspectorPanelView: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        if let selected = workspace.selectedObject {
            Form {
                identitySection(selected)
                transformSection(selected)
                dimensionsSection(selected)
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No Object Selected",
                systemImage: "cursorarrow.slash",
                description: Text("Select a solid in the Navigator to inspect its properties.")
            )
        }
    }

    // MARK: - Sections

    private func identitySection(_ obj: SceneObject) -> some View {
        Section("Identity") {
            TextField("Name", text: Binding(
                get: { obj.name },
                set: { workspace.document.setName(id: obj.id, name: $0) }
            ))
            LabeledContent("ID") {
                Text(obj.id.rawValue).monospaced()
            }
            LabeledContent("Kind", value: obj.def.kind.capitalized)
        }
    }

    private func transformSection(_ obj: SceneObject) -> some View {
        Section("Transform") {
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
                    t.scale = simd_max(scale, SIMD3<Float>(repeating: 0.01))
                    workspace.setTransform(obj.id, t)
                }
            }
        }
    }

    @ViewBuilder
    private func dimensionsSection(_ obj: SceneObject) -> some View {
        Section("Dimensions") {
            switch obj.def {
            case .box(let params):
                paramSlider("Width (X)", params.width, DocumentLimits.boxWidth) { workspace.setParam(obj.id, "width", $0) }
                paramSlider("Depth (Y)", params.depth, DocumentLimits.boxDepth) { workspace.setParam(obj.id, "depth", $0) }
                paramSlider("Height (Z)", params.height, DocumentLimits.boxHeight) { workspace.setParam(obj.id, "height", $0) }
            case .cylinder(let params):
                paramSlider("Radius", params.radius, DocumentLimits.cylinderRadius) { workspace.setParam(obj.id, "radius", $0) }
                paramSlider("Height (Z)", params.height, DocumentLimits.cylinderHeight) { workspace.setParam(obj.id, "height", $0) }
            case .imported(let name):
                LabeledContent("Imported Mesh", value: name)
            }
            if let message = workspace.recomputeFailures.message(for: obj.id) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    // MARK: - Controls

    private func vectorFields(_ value: SIMD3<Float>, onChange: @escaping (SIMD3<Float>) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { axis in
                TextField(["X", "Y", "Z"][axis], value: Binding(
                    get: { Double(value[axis]) },
                    set: { newValue in
                        var v = value
                        v[axis] = Float(newValue)
                        onChange(v)
                    }
                ), format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
                .frame(minWidth: 48)
            }
        }
        .labelsHidden()
    }

    private func paramSlider(_ label: String, _ value: Float, _ range: ParamRange, onChange: @escaping (Float) -> Void) -> some View {
        LabeledContent {
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: range.min...range.max)
        } label: {
            Text(label)
            Text("\(value, format: .number.precision(.fractionLength(1))) mm")
        }
    }
}
