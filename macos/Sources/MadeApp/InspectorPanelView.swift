import SwiftUI
import MadeCore

public struct InspectorPanelView: View {
    @Bindable var document: DocumentModel
    @Binding var selectedId: ObjectId
    var onTransformChanged: (ObjectId, Transform) -> Void
    var onParamChanged: (ObjectId, String, Float) -> Void
    
    public init(
        document: DocumentModel,
        selectedId: Binding<ObjectId>,
        onTransformChanged: @escaping (ObjectId, Transform) -> Void,
        onParamChanged: @escaping (ObjectId, String, Float) -> Void
    ) {
        self.document = document
        self._selectedId = selectedId
        self.onTransformChanged = onTransformChanged
        self.onParamChanged = onParamChanged
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Inspector")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Properties Content
            ScrollView {
                propertiesContent
                    .padding(12)
            }
        }
        .frame(minWidth: 240, maxWidth: 320)
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
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No Object Selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Select a solid in the Navigator to inspect properties.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
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
}
