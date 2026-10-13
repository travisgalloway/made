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
            switch workspace.inspectorTab {
            case .properties:
                properties
                    .frame(maxHeight: .infinity)
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
                }
                .formStyle(.columns)
                .controlSize(.small)
                .padding()
            }
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
                    t.scale = simd_max(scale, SIMD3<Float>(repeating: 0.01))
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
            }
            if let message = workspace.recomputeFailures.message(for: obj.id) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        } header: {
            sectionHeader("Dimensions")
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
