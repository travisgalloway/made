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
                case .document:
                    DocumentSettingsInspectorView()
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
                        .disabled(selected.isLocked)
                    dimensionsSection(selected)
                        .disabled(selected.isLocked)
                    materialSection(selected)
                        .disabled(selected.isLocked)
                }
                .formStyle(.columns)
                .controlSize(.small)
                .padding()
            }
        } else if let sketch = workspace.selectedSketchFeature {
            ScrollView {
                Form {
                    sketchIdentitySection(sketch)
                    sketchEntitiesSection(sketch)
                    sketchConstraintsSection(sketch)
                    sketchRegionsSection(sketch)
                }
                .formStyle(.columns)
                .controlSize(.small)
                .padding()
            }
        } else if let datumPlane = workspace.selectedDatumPlaneFeature {
            ScrollView {
                Form {
                    datumPlaneIdentitySection(datumPlane)
                    datumPlaneParametersSection(datumPlane)
                }
                .formStyle(.columns)
                .controlSize(.small)
                .padding()
            }
        } else if let datumAxis = workspace.selectedDatumAxisFeature {
            ScrollView {
                Form {
                    datumAxisIdentitySection(datumAxis)
                    datumAxisParametersSection(datumAxis)
                }
                .formStyle(.columns)
                .controlSize(.small)
                .padding()
            }
        } else if let datumPoint = workspace.selectedDatumPointFeature {
            ScrollView {
                Form {
                    datumPointIdentitySection(datumPoint)
                    datumPointParametersSection(datumPoint)
                }
                .formStyle(.columns)
                .controlSize(.small)
                .padding()
            }
        } else if let ucs = workspace.selectedDatumCoordinateSystemFeature {
            ScrollView {
                Form {
                    datumCoordinateSystemIdentitySection(ucs)
                    datumCoordinateSystemParametersSection(ucs)
                }
                .formStyle(.columns)
                .controlSize(.small)
                .padding()
            }
        } else if workspace.document.objects.isEmpty && !hasAnySketches && !hasAnyDatums {
            ContentUnavailableView {
                Label("No Objects in Scene", systemImage: "cube.transparent")
            } description: {
                Text("Add a 3D solid primitive or open a part script to inspect and edit its properties.")
            } actions: {
                Menu("Add Solid", systemImage: "plus") {
                    Button("Box Solid", systemImage: "shippingbox") { workspace.addDefaultBox() }
                    Button("Cylinder Solid", systemImage: "cylinder") { workspace.addDefaultCylinder() }
                    Button("Sphere Solid", systemImage: "globe") { workspace.addDefaultSphere() }
                    Button("Cone Solid", systemImage: "cone.fill") { workspace.addDefaultCone() }
                    Button("Torus Solid", systemImage: "circle.circle") { workspace.addDefaultTorus() }
                    Button("Wedge Solid", systemImage: "triangle.fill") { workspace.addDefaultWedge() }
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

    private var hasAnySketches: Bool {
        workspace.document.features.contains {
            if case .sketch = $0.operation { return true }
            return false
        }
    }

    private var hasAnyDatums: Bool {
        workspace.document.features.contains {
            switch $0.operation {
            case .datumPlane, .datumAxis, .datumPoint, .datumCoordinateSystem:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Sections

    private func identitySection(_ obj: SceneObject) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { obj.name },
                set: { workspace.setName(id: obj.id, name: $0) }
            ))
            .disabled(obj.isLocked)
            Toggle("Visible in Viewport", isOn: Binding(
                get: { obj.isVisible },
                set: { workspace.setVisibility(obj.id, isVisible: $0) }
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
            LabeledContent("Position (\(workspace.document.settings.units.lengthUnit.symbol))") {
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
                paramField("Width (X)", params.width, DocumentLimits.boxWidth, id: obj.id, key: "width") { workspace.setParam(obj.id, "width", $0) }
                paramField("Depth (Y)", params.depth, DocumentLimits.boxDepth, id: obj.id, key: "depth") { workspace.setParam(obj.id, "depth", $0) }
                paramField("Height (Z)", params.height, DocumentLimits.boxHeight, id: obj.id, key: "height") { workspace.setParam(obj.id, "height", $0) }
            case .cylinder(let params):
                paramField("Radius", params.radius, DocumentLimits.cylinderRadius, id: obj.id, key: "radius") { workspace.setParam(obj.id, "radius", $0) }
                paramField("Height (Z)", params.height, DocumentLimits.cylinderHeight, id: obj.id, key: "height") { workspace.setParam(obj.id, "height", $0) }
            case .sphere(let params):
                paramField("Radius", params.radius, DocumentLimits.sphereRadius, id: obj.id, key: "radius") { workspace.setParam(obj.id, "radius", $0) }
            case .cone(let params):
                paramField("Bottom Radius", params.bottomRadius, DocumentLimits.coneBottomRadius, id: obj.id, key: "bottomRadius") { workspace.setParam(obj.id, "bottomRadius", $0) }
                paramField("Top Radius", params.topRadius, DocumentLimits.coneTopRadius, id: obj.id, key: "topRadius") { workspace.setParam(obj.id, "topRadius", $0) }
                paramField("Height (Z)", params.height, DocumentLimits.coneHeight, id: obj.id, key: "height") { workspace.setParam(obj.id, "height", $0) }
            case .torus(let params):
                paramField("Major Radius", params.majorRadius, DocumentLimits.torusMajorRadius, id: obj.id, key: "majorRadius") { workspace.setParam(obj.id, "majorRadius", $0) }
                paramField("Minor Radius", params.minorRadius, DocumentLimits.torusMinorRadius, id: obj.id, key: "minorRadius") { workspace.setParam(obj.id, "minorRadius", $0) }
            case .wedge(let params):
                paramField("Width (X)", params.width, DocumentLimits.wedgeWidth, id: obj.id, key: "width") { workspace.setParam(obj.id, "width", $0) }
                paramField("Depth (Y)", params.depth, DocumentLimits.wedgeDepth, id: obj.id, key: "depth") { workspace.setParam(obj.id, "depth", $0) }
                paramField("Height (Z)", params.height, DocumentLimits.wedgeHeight, id: obj.id, key: "height") { workspace.setParam(obj.id, "height", $0) }
                paramField("Top Width (X)", params.topWidth, DocumentLimits.wedgeTopWidth, id: obj.id, key: "topWidth") { workspace.setParam(obj.id, "topWidth", $0) }
            case .extrude(let params):
                paramField("Distance (Z)", Float(params.distance), DocumentLimits.extrudeDistance, id: obj.id, key: "distance") { workspace.setParam(obj.id, "distance", $0) }
                LabeledContent("Symmetric", value: params.isSymmetric ? "Yes" : "No")
                LabeledContent("Profile Points", value: "\(params.profile.points.count)")
                if let sketchId = params.sketchFeatureId, let sketch = workspace.document.feature(for: sketchId) {
                    LabeledContent("Source Sketch") {
                        Button(sketch.name) {
                            workspace.selectFeature(sketchId)
                        }
                        .buttonStyle(.link)
                    }
                }
            case .imported(let name, _, _):
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
            } else if let errorState = workspace.document.feature(for: obj.id)?.errorState {
                Label(errorState.message, systemImage: errorState.severity == .warning ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(errorState.severity == .warning ? .orange : .red)
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

    private func sketchIdentitySection(_ sketch: Feature) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { sketch.name },
                set: { newName in
                    var updated = sketch
                    updated.name = newName
                    workspace.document.updateFeature(updated)
                }
            ))
            if case .sketch(let data) = sketch.operation {
                LabeledContent("Plane", value: data.planeName ?? "XY Ground Plane")
                LabeledContent("Entities", value: "\(data.entities.count)")
            }
            Button {
                workspace.startExtrudeCommand(sketchFeatureId: sketch.id)
            } label: {
                Label("Extrude Sketch…", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } header: {
            sectionHeader("Sketch Identity", isFirst: true)
        }
    }

    private func datumPlaneIdentitySection(_ datumPlane: Feature) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { datumPlane.name },
                set: { newName in
                    var updated = datumPlane
                    updated.name = newName
                    workspace.document.updateFeature(updated)
                }
            ))
            if case .datumPlane(let data) = datumPlane.operation {
                LabeledContent("Mode", value: data.mode.rawValue.capitalized)
                if let cached = data.cachedPlane {
                    LabeledContent("Origin", value: String(format: "(%.1f, %.1f, %.1f)", cached.origin.x, cached.origin.y, cached.origin.z))
                    LabeledContent("Normal", value: String(format: "(%.2f, %.2f, %.2f)", cached.normal.x, cached.normal.y, cached.normal.z))
                }
            }
        } header: {
            sectionHeader("Datum Plane Identity", isFirst: true)
        }
    }

    private func datumPlaneParametersSection(_ datumPlane: Feature) -> some View {
        guard case .datumPlane(let data) = datumPlane.operation else { return AnyView(EmptyView()) }
        return AnyView(Section {
            LabeledContent("Mode", value: data.mode.rawValue.capitalized)
            switch data.mode {
            case .origin:
                LabeledContent("Preset", value: data.originPreset ?? "XY")
                LabeledContent("Offset", value: String(format: "%.1f mm", data.offsetDistance))
            case .offset:
                LabeledContent("Offset Distance", value: String(format: "%.1f mm", data.offsetDistance))
            case .atAngle:
                LabeledContent("Angle", value: String(format: "%.1f°", data.angleDegrees))
            case .threePoints:
                if let p1 = data.point1 {
                    LabeledContent("Point 1", value: String(format: "(%.1f, %.1f, %.1f)", p1.x, p1.y, p1.z))
                }
                if let p2 = data.point2 {
                    LabeledContent("Point 2", value: String(format: "(%.1f, %.1f, %.1f)", p2.x, p2.y, p2.z))
                }
                if let p3 = data.point3 {
                    LabeledContent("Point 3", value: String(format: "(%.1f, %.1f, %.1f)", p3.x, p3.y, p3.z))
                }
            case .normalToCurve:
                LabeledContent("Parameter t", value: String(format: "%.2f", data.curveParameter))
            case .midplane:
                LabeledContent("Type", value: data.point1 != nil ? "Between Points" : "Between Planes")
            case .tangent:
                LabeledContent("Type", value: "Curved Face Tangent")
            }
            Toggle("Flipped Normal", isOn: Binding(
                get: { data.isFlipped },
                set: { flipped in
                    var updatedData = data
                    updatedData.isFlipped = flipped
                    var updatedFeature = datumPlane
                    updatedFeature.operation = .datumPlane(updatedData)
                    _ = workspace.document.updateFeature(updatedFeature)
                    Task {
                        await KernelRegeneration.regenerateIncremental(from: datumPlane.id, in: workspace.document, client: workspace.kernelClient)
                    }
                }
            ))
        } header: {
            sectionHeader("Parameters")
        })
    }

    private func datumAxisIdentitySection(_ datumAxis: Feature) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { datumAxis.name },
                set: { newName in
                    var updated = datumAxis
                    updated.name = newName
                    workspace.document.updateFeature(updated)
                }
            ))
            if case .datumAxis(let data) = datumAxis.operation {
                LabeledContent("Mode", value: data.mode.rawValue.capitalized)
                if let cached = data.cachedAxis {
                    LabeledContent("Origin", value: String(format: "(%.1f, %.1f, %.1f)", cached.origin.x, cached.origin.y, cached.origin.z))
                    LabeledContent("Direction", value: String(format: "(%.2f, %.2f, %.2f)", cached.direction.x, cached.direction.y, cached.direction.z))
                }
            }
        } header: {
            sectionHeader("Datum Axis Identity", isFirst: true)
        }
    }

    private func datumAxisParametersSection(_ datumAxis: Feature) -> some View {
        guard case .datumAxis(let data) = datumAxis.operation else { return AnyView(EmptyView()) }
        return AnyView(Section {
            LabeledContent("Mode", value: data.mode.rawValue.capitalized)
            switch data.mode {
            case .preset:
                LabeledContent("Preset Axis", value: data.presetName ?? "Z")
            case .twoPoints:
                if let p1 = data.point1 {
                    LabeledContent("Point 1", value: String(format: "(%.1f, %.1f, %.1f)", p1.x, p1.y, p1.z))
                }
                if let p2 = data.point2 {
                    LabeledContent("Point 2", value: String(format: "(%.1f, %.1f, %.1f)", p2.x, p2.y, p2.z))
                }
            case .edge:
                LabeledContent("Source", value: "Referenced Edge / Line")
            case .cylinder:
                LabeledContent("Source", value: "Cylinder Axis")
            case .normalToPlane:
                LabeledContent("Source", value: "Plane Normal")
            }
            Toggle("Flipped Direction", isOn: Binding(
                get: { data.isFlipped },
                set: { flipped in
                    var updatedData = data
                    updatedData.isFlipped = flipped
                    var updatedFeature = datumAxis
                    updatedFeature.operation = .datumAxis(updatedData)
                    _ = workspace.document.updateFeature(updatedFeature)
                    Task {
                        await KernelRegeneration.regenerateIncremental(from: datumAxis.id, in: workspace.document, client: workspace.kernelClient)
                    }
                }
            ))
        } header: {
            sectionHeader("Parameters")
        })
    }

    private func datumPointIdentitySection(_ datumPoint: Feature) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { datumPoint.name },
                set: { newName in
                    var updated = datumPoint
                    updated.name = newName
                    workspace.document.updateFeature(updated)
                }
            ))
            if case .datumPoint(let data) = datumPoint.operation {
                LabeledContent("Mode", value: data.mode.rawValue.capitalized)
                if let cached = data.cachedPoint {
                    LabeledContent("Position", value: String(format: "(%.1f, %.1f, %.1f)", cached.position.x, cached.position.y, cached.position.z))
                }
            }
        } header: {
            sectionHeader("Datum Point Identity", isFirst: true)
        }
    }

    private func datumPointParametersSection(_ datumPoint: Feature) -> some View {
        guard case .datumPoint(let data) = datumPoint.operation else { return AnyView(EmptyView()) }
        return AnyView(Section {
            LabeledContent("Mode", value: data.mode.rawValue.capitalized)
            switch data.mode {
            case .coordinates:
                if let c = data.coordinates {
                    LabeledContent("Coordinates", value: String(format: "(%.1f, %.1f, %.1f)", c.x, c.y, c.z))
                }
            case .alongCurve:
                LabeledContent("Parameter t", value: String(format: "%.2f", data.curveParameter))
            case .onVertex:
                LabeledContent("Source", value: "Referenced Vertex")
            case .arcCenter:
                LabeledContent("Source", value: "Arc / Circle Center")
            case .midpoint:
                LabeledContent("Source", value: "Midpoint between References")
            case .intersection:
                LabeledContent("Source", value: "Line-Plane Intersection")
            }
        } header: {
            sectionHeader("Parameters")
        })
    }

    private func datumCoordinateSystemIdentitySection(_ ucs: Feature) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { ucs.name },
                set: { newName in
                    var updated = ucs
                    updated.name = newName
                    workspace.document.updateFeature(updated)
                }
            ))
            if case .datumCoordinateSystem(let data) = ucs.operation {
                LabeledContent("Mode", value: data.mode.rawValue.capitalized)
                if let cached = data.cachedCoordinateSystem {
                    LabeledContent("Origin", value: String(format: "(%.1f, %.1f, %.1f)", cached.origin.x, cached.origin.y, cached.origin.z))
                    LabeledContent("X Axis", value: String(format: "(%.2f, %.2f, %.2f)", cached.xAxis.x, cached.xAxis.y, cached.xAxis.z))
                    LabeledContent("Y Axis", value: String(format: "(%.2f, %.2f, %.2f)", cached.yAxis.x, cached.yAxis.y, cached.yAxis.z))
                    LabeledContent("Z Axis", value: String(format: "(%.2f, %.2f, %.2f)", cached.zAxis.x, cached.zAxis.y, cached.zAxis.z))
                }
            }
        } header: {
            sectionHeader("Coordinate System Identity", isFirst: true)
        }
    }

    private func datumCoordinateSystemParametersSection(_ ucs: Feature) -> some View {
        guard case .datumCoordinateSystem(let data) = ucs.operation else { return AnyView(EmptyView()) }
        return AnyView(Section {
            LabeledContent("Mode", value: data.mode.rawValue.capitalized)
            switch data.mode {
            case .originAndAxes:
                if let orig = data.origin {
                    LabeledContent("Origin", value: String(format: "(%.1f, %.1f, %.1f)", orig.x, orig.y, orig.z))
                }
            case .threePoints:
                if let p1 = data.point1 {
                    LabeledContent("Origin (P1)", value: String(format: "(%.1f, %.1f, %.1f)", p1.x, p1.y, p1.z))
                }
                if let p2 = data.point2 {
                    LabeledContent("+X Axis (P2)", value: String(format: "(%.1f, %.1f, %.1f)", p2.x, p2.y, p2.z))
                }
                if let p3 = data.point3 {
                    LabeledContent("+XY Plane (P3)", value: String(format: "(%.1f, %.1f, %.1f)", p3.x, p3.y, p3.z))
                }
            case .alignedWithPlane:
                LabeledContent("Alignment", value: "Aligned with Reference Plane")
            case .offsetFromParent:
                if let off = data.offsetDistance {
                    LabeledContent("Offset", value: String(format: "(%.1f, %.1f, %.1f) mm", off.x, off.y, off.z))
                }
                if let rot = data.rotationAngles {
                    LabeledContent("Euler Angles", value: String(format: "(%.1f°, %.1f°, %.1f°)", rot.x, rot.y, rot.z))
                }
            }
            if let cached = data.cachedCoordinateSystem {
                let m = cached.transformMatrix
                LabeledContent("Transform Matrix", value: String(format: "[%.2f %.2f %.2f | %.1f]\n[%.2f %.2f %.2f | %.1f]\n[%.2f %.2f %.2f | %.1f]", m.columns.0.x, m.columns.1.x, m.columns.2.x, m.columns.3.x, m.columns.0.y, m.columns.1.y, m.columns.2.y, m.columns.3.y, m.columns.0.z, m.columns.1.z, m.columns.2.z, m.columns.3.z))
            }
        } header: {
            sectionHeader("Parameters")
        })
    }

    private func sketchEntitiesSection(_ sketch: Feature) -> some View {
        guard case .sketch(let data) = sketch.operation else { return AnyView(EmptyView()) }
        let closureResult: Result<SketchProfile, Error> = Result {
            try SketchProfileBuilder.build(from: data.entities)
        }

        return AnyView(Section {
            switch closureResult {
            case .success(let profile):
                Label("Profile Closed (\(profile.points.count) vertices)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button("+ Line") {
                    let nextIdx = data.entities.count
                    let start = SIMD2<Double>(Double(nextIdx * 10), 0)
                    let end = SIMD2<Double>(Double((nextIdx + 1) * 10), 0)
                    let entity = SketchEntity.line(start: start, end: end)
                    workspace.addSketchEntity(to: sketch.id, entity: entity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+ Arc") {
                    let entity = SketchEntity.arc(
                        start: SIMD2<Double>(0, 0),
                        end: SIMD2<Double>(10, 10),
                        center: SIMD2<Double>(0, 10),
                        clockwise: false
                    )
                    workspace.addSketchEntity(to: sketch.id, entity: entity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+ Circle") {
                    let entity = SketchEntity.circle(center: .zero, radius: 25.0)
                    workspace.addSketchEntity(to: sketch.id, entity: entity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+ Rect") {
                    let offset = Double(data.entities.count * 5)
                    let p0 = SIMD2<Double>(offset, offset)
                    let p1 = SIMD2<Double>(offset + 40, offset)
                    let p2 = SIMD2<Double>(offset + 40, offset + 30)
                    let p3 = SIMD2<Double>(offset, offset + 30)
                    workspace.addSketchEntity(to: sketch.id, entity: .line(start: p0, end: p1))
                    workspace.addSketchEntity(to: sketch.id, entity: .line(start: p1, end: p2))
                    workspace.addSketchEntity(to: sketch.id, entity: .line(start: p2, end: p3))
                    workspace.addSketchEntity(to: sketch.id, entity: .line(start: p3, end: p0))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+ Project") {
                    _ = workspace.projectSelectedGeometry()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if data.entities.isEmpty {
                Text("No entities in sketch. Use the buttons above to add geometry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(data.entities) { entity in
                    sketchEntityRow(sketchId: sketch.id, entity: entity)
                }
            }
        } header: {
            sectionHeader("Entities & Profile")
        })
    }

    private func sketchEntityRow(sketchId: UUID, entity: SketchEntity) -> some View {
        let isSelected = workspace.selectedSketchEntity?.entity.id == entity.id
        let status = workspace.dofStatus(for: entity.id)
        let statusColor = ViewportStatusBar.dofColor(for: status)
        let bg = isSelected ? Color.accentColor.opacity(0.12) : (statusColor?.opacity(0.04) ?? Color.clear)
        let strokeColor = isSelected ? Color.accentColor : (statusColor?.opacity(0.35) ?? Color.clear)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entity.kind.capitalized)
                    .font(.caption.bold())
                entityDOFBadge(for: status)
                if entity.isConstruction {
                    Text("Construction")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .foregroundStyle(.secondary)
                        )
                        .foregroundStyle(.secondary)
                }
                if entity.isProjected {
                    Text("Projected")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.purple.opacity(0.2))
                        )
                        .foregroundStyle(.purple)
                }
                Spacer()
                Toggle(isOn: Binding(
                    get: { entity.isConstruction },
                    set: { newVal in
                        var e = entity
                        e.isConstruction = newVal
                        workspace.updateSketchEntity(in: sketchId, entity: e)
                    }
                )) {
                    Image(systemName: "line.diagonal")
                        .font(.caption2)
                }
                .toggleStyle(.button)
                .controlSize(.mini)
                .help("Toggle construction geometry (excluded from extrude profiles)")

                Button(role: .destructive) {
                    workspace.removeSketchEntity(from: sketchId, entityId: entity.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            switch entity.kind {
            case "line":
                if let start = entity.startPoint, let end = entity.endPoint {
                    HStack(spacing: 6) {
                        Text("Start:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(label: "SX", value: start.x, width: 44) {
                            var e = entity
                            e.startPoint = SIMD2<Double>($0, start.y)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        CommitNumberField(label: "SY", value: start.y, width: 44) {
                            var e = entity
                            e.startPoint = SIMD2<Double>(start.x, $0)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        Text("End:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(label: "EX", value: end.x, width: 44) {
                            var e = entity
                            e.endPoint = SIMD2<Double>($0, end.y)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        CommitNumberField(label: "EY", value: end.y, width: 44) {
                            var e = entity
                            e.endPoint = SIMD2<Double>(end.x, $0)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Length:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(label: "Length", value: entity.length ?? 0.0, width: 56, minimum: 0.0001) { newLen in
                            do {
                                try workspace.dimensionSketchLine(featureId: sketchId, entityId: entity.id, length: newLen)
                            } catch {
                                // Error handled by workspace
                            }
                        }
                        .id(entity.id)
                    }
                }
            case "circle":
                if let center = entity.centerPoint, let radius = entity.radius {
                    HStack(spacing: 6) {
                        Text("Center:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(label: "CX", value: center.x, width: 44) {
                            var e = entity
                            e.centerPoint = SIMD2<Double>($0, center.y)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        CommitNumberField(label: "CY", value: center.y, width: 44) {
                            var e = entity
                            e.centerPoint = SIMD2<Double>(center.x, $0)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        Text("Radius:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(label: "R", value: radius, width: 44) {
                            var e = entity
                            e.radius = $0
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                    }
                }
            case "arc":
                if let start = entity.startPoint, let end = entity.endPoint, let center = entity.centerPoint {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Start:").font(.caption2).foregroundStyle(.secondary)
                            CommitNumberField(label: "SX", value: start.x, width: 44) {
                                var e = entity
                                e.startPoint = SIMD2<Double>($0, start.y)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            CommitNumberField(label: "SY", value: start.y, width: 44) {
                                var e = entity
                                e.startPoint = SIMD2<Double>(start.x, $0)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            Text("End:").font(.caption2).foregroundStyle(.secondary)
                            CommitNumberField(label: "EX", value: end.x, width: 44) {
                                var e = entity
                                e.endPoint = SIMD2<Double>($0, end.y)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            CommitNumberField(label: "EY", value: end.y, width: 44) {
                                var e = entity
                                e.endPoint = SIMD2<Double>(end.x, $0)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                        }
                        HStack(spacing: 6) {
                            Text("Center:").font(.caption2).foregroundStyle(.secondary)
                            CommitNumberField(label: "CX", value: center.x, width: 44) {
                                var e = entity
                                e.centerPoint = SIMD2<Double>($0, center.y)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            CommitNumberField(label: "CY", value: center.y, width: 44) {
                                var e = entity
                                e.centerPoint = SIMD2<Double>(center.x, $0)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            Toggle("CW", isOn: Binding(
                                get: { entity.isClockwise },
                                set: {
                                    var e = entity
                                    e.isClockwise = $0
                                    workspace.updateSketchEntity(in: sketchId, entity: e)
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            default:
                EmptyView()
            }

            if isSelected {
                HStack(spacing: 4) {
                    Button("Trim") {
                        workspace.tool = .trim
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                    .help("Switch to Trim tool")

                    if entity.kind == "line" || entity.kind == "arc" {
                        Button("Extend Start") {
                            workspace.extendSelectedSketchEntity(targetEnd: .start)
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                        .help("Extend start endpoint to nearest intersection")

                        Button("Extend End") {
                            workspace.extendSelectedSketchEntity(targetEnd: .end)
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                        .help("Extend end endpoint to nearest intersection")
                    }

                    Button("Split") {
                        workspace.splitSelectedSketchEntityAtMidpoint()
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                    .help("Split entity into two segments")
                }
                .padding(.top, 2)
            }

            if entity.isConstruction {
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: 1)
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .padding(.vertical, 2)
            } else {
                Divider().padding(.vertical, 2)
            }
        }
        .padding(4)
        .background(bg)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(strokeColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.selectSketchEntity(featureId: sketchId, entityId: entity.id)
        }
    }

    @ViewBuilder
    private func entityDOFBadge(for status: SketchDOFStatus) -> some View {
        switch status {
        case .underConstrained(let dof):
            Text("\(dof) DOF")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .foregroundStyle(.blue)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                )
        case .fullyConstrained:
            Text("Constrained")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .foregroundStyle(.green)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.green.opacity(0.35), lineWidth: 1)
                )
        case .overConstrained:
            Text("Over-constrained")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .foregroundStyle(.red)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
        case .inactive:
            EmptyView()
        }
    }

    private func sketchConstraintsSection(_ sketch: Feature) -> some View {
        guard case .sketch(let data) = sketch.operation else { return AnyView(EmptyView()) }

        return AnyView(Section {
            if let overConstrainedMsg = workspace.overConstrainedMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(overConstrainedMsg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                .padding(6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            } else if case .overConstrained(let dof) = workspace.sketchDOFStatus {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Over-constrained sketch (\(dof) excess DOF). Delete conflicting constraints.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
            }

            if workspace.isLiveInferenceEnabled && !workspace.inferredConstraints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(workspace.inferredConstraints) { inferred in
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.blue)
                                .font(.caption2)
                            Text("Inferred: \(inferred.kind.rawValue.capitalized)")
                                .font(.caption2)
                            Spacer()
                            Button("Apply") {
                                workspace.applyInferredConstraint(inferred)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                    }
                }
                .padding(6)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(4)
            }

            Toggle("Infer Constraints Live", isOn: Binding(
                get: { workspace.isLiveInferenceEnabled },
                set: { _ in workspace.toggleLiveInference() }
            ))
            .font(.caption)

            HStack(spacing: 6) {
                Button("+ Parallel") {
                    workspace.applyConstraintToSelectedSketch(.parallel)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+ Perpendicular") {
                    workspace.applyConstraintToSelectedSketch(.perpendicular)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+ Tangent") {
                    workspace.applyConstraintToSelectedSketch(.tangent)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+ Concentric") {
                    workspace.applyConstraintToSelectedSketch(.concentric)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+ Symmetric") {
                    workspace.applyConstraintToSelectedSketch(.symmetric)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if data.constraints.isEmpty {
                Text("No constraints applied. Use buttons or live inference to constrain geometry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(data.constraints) { constraint in
                    sketchConstraintRow(sketchId: sketch.id, constraint: constraint)
                }
            }
        } header: {
            sectionHeader("Constraints")
        })
    }

    private func sketchConstraintRow(sketchId: UUID, constraint: SketchConstraint) -> some View {
        HStack {
            Image(systemName: constraintIcon(for: constraint.kind))
                .font(.caption)
                .foregroundStyle(.primary)

            Text(constraint.kind.rawValue.capitalized)
                .font(.caption.bold())

            Spacer()

            Button(role: .destructive) {
                workspace.removeSketchConstraint(from: sketchId, constraintId: constraint.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }

    private func constraintIcon(for kind: SketchConstraint.Kind) -> String {
        switch kind {
        case .parallel: return "equal"
        case .perpendicular: return "angle"
        case .tangent: return "circle.dotted"
        case .concentric: return "circle.circle"
        case .symmetric: return "arrow.left.and.right"
        case .coincident: return "point.topleft.down.to.point.bottomright.filled"
        case .horizontal: return "arrow.left.and.right.line"
        case .vertical: return "arrow.up.and.down.line"
        }
    }

    @ViewBuilder
    private func sketchRegionsSection(_ sketch: Feature) -> some View {
        if case .sketch = sketch.operation {
            let regions = workspace.detectedSketchRegions
            if !regions.isEmpty {
                Section("Regions (\(regions.count))") {
                ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Region \(index + 1)")
                                .fontWeight(workspace.selectedSketchRegionId == region.id ? .bold : .regular)
                            HStack(spacing: 6) {
                                Text(String(format: "Area: %.1f mm²", region.area))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                if !region.innerLoops.isEmpty {
                                    Text("(\(region.innerLoops.count) \(region.innerLoops.count == 1 ? "hole" : "holes"))")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                        Spacer()
                        Button("Extrude") {
                            workspace.selectSketchRegion(featureId: sketch.id, regionId: region.id)
                            Task { @MainActor in
                                _ = await workspace.extrudeSketch(
                                    sketchFeatureId: sketch.id,
                                    distance: 20.0,
                                    isSymmetric: false,
                                    regionId: region.id
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onHover { isHovered in
                        workspace.setHoveredSketchRegion(isHovered ? region.id : nil)
                    }
                    .onTapGesture {
                        workspace.selectSketchRegion(featureId: sketch.id, regionId: region.id)
                    }
                }
            }
        }
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

    /// A typed millimeter value with a slider and a 1-mm stepper; `setParam` clamps to the range (invariant 9).
    private func paramField(
        _ label: String,
        _ value: Float,
        _ range: ParamRange,
        id: ObjectId,
        key: String,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        let binding = Binding(get: { Double(value) }, set: { onChange(Float($0)) })
        let symbol = workspace.document.settings.units.lengthUnit.symbol
        let spoken = "\(value.formatted(.number.precision(.fractionLength(1)))) \(symbol)"
        return LabeledContent(label) {
            HStack(spacing: 4) {
                Slider(value: binding, in: Double(range.min)...Double(range.max), step: 1) {
                    Text(label)
                } onEditingChanged: { editing in
                    if editing {
                        workspace.beginInteractiveParamEdit(id, key)
                    } else {
                        workspace.endInteractiveParamEdit(id, key)
                    }
                }
                .accessibilityLabel(label)
                .accessibilityValue(spoken)

                CommitNumberField(label: label, value: Double(value), width: 52) { onChange(Float($0)) }
                    .accessibilityLabel(label)
                    .accessibilityValue(spoken)
                Text(symbol).foregroundStyle(.secondary)
                Stepper(label, value: binding, in: Double(range.min)...Double(range.max), step: 1)
                    .accessibilityLabel(label)
                    .accessibilityValue(spoken)
            }
            .labelsHidden()
        }
    }
}

struct DocumentSettingsInspectorView: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        ScrollView {
            Form {
                unitsSection
                tolerancesSection
                materialSection
            }
            .formStyle(.columns)
            .controlSize(.small)
            .padding()
        }
    }

    private var unitsSection: some View {
        Section {
            Picker("Length Unit", selection: Binding(
                get: { workspace.document.settings.units.lengthUnit },
                set: { newUnit in
                    var u = workspace.document.settings.units
                    u.lengthUnit = newUnit
                    workspace.setDocumentUnits(u)
                }
            )) {
                ForEach(LengthUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }

            Picker("Angular Unit", selection: Binding(
                get: { workspace.document.settings.units.angleUnit },
                set: { newUnit in
                    var u = workspace.document.settings.units
                    u.angleUnit = newUnit
                    workspace.setDocumentUnits(u)
                }
            )) {
                ForEach(AngleUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }

            Stepper("Decimal Places: \(workspace.document.settings.units.decimalPrecision)", value: Binding(
                get: { workspace.document.settings.units.decimalPrecision },
                set: { newPrecision in
                    var u = workspace.document.settings.units
                    u.decimalPrecision = newPrecision
                    workspace.setDocumentUnits(u)
                }
            ), in: UnitSettings.minDecimalPrecision...UnitSettings.maxDecimalPrecision)

            LabeledContent("Length Preview") {
                Text(workspace.document.settings.units.formatLength(100.0))
                    .fontWeight(.medium)
            }

            LabeledContent("Angle Preview") {
                Text(workspace.document.settings.units.formatAngle(45.0))
                    .fontWeight(.medium)
            }
        } header: {
            sectionHeader("Units", isFirst: true)
        }
    }

    private var tolerancesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Linear Tolerance (mm):")
                    Spacer()
                    TextField("Linear", value: Binding(
                        get: { workspace.document.settings.tolerances.linearTolerance },
                        set: { val in
                            var t = workspace.document.settings.tolerances
                            t.linearTolerance = val
                            workspace.setDocumentTolerances(t)
                        }
                    ), format: .number)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                }
                Text("Valid range: \(KernelTolerances.minLinearTolerance, specifier: "%.4f")...\(KernelTolerances.maxLinearTolerance, specifier: "%.1f") mm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Angular Tolerance (deg):")
                    Spacer()
                    TextField("Angular", value: Binding(
                        get: { workspace.document.settings.tolerances.angularTolerance },
                        set: { val in
                            var t = workspace.document.settings.tolerances
                            t.angularTolerance = val
                            workspace.setDocumentTolerances(t)
                        }
                    ), format: .number)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                }
                Text("Valid range: \(KernelTolerances.minAngularTolerance, specifier: "%.3f")...\(KernelTolerances.maxAngularTolerance, specifier: "%.1f")°")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Chordal Deflection (mm):")
                    Spacer()
                    TextField("Chordal", value: Binding(
                        get: { workspace.document.settings.tolerances.chordalTolerance },
                        set: { val in
                            var t = workspace.document.settings.tolerances
                            t.chordalTolerance = val
                            workspace.setDocumentTolerances(t)
                        }
                    ), format: .number)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                }
                Text("Tessellation limit: \(KernelTolerances.minChordalTolerance, specifier: "%.4f")...\(KernelTolerances.maxChordalTolerance, specifier: "%.1f") mm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Reset Tolerances to Defaults") {
                workspace.setDocumentTolerances(KernelTolerances.default)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } header: {
            sectionHeader("Tolerances")
        }
    }

    private var materialSection: some View {
        Section {
            ColorPicker("Default Color", selection: Binding(
                get: {
                    let c = workspace.document.settings.defaultMaterial.color
                    return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: Double(c.w))
                },
                set: { newColor in
                    let resolved = newColor.resolve(in: EnvironmentValues())
                    let simdColor = SIMD4<Float>(resolved.red, resolved.green, resolved.blue, 1.0)
                    workspace.setDocumentDefaultMaterial(MaterialAttributes(color: simdColor))
                }
            ), supportsOpacity: false)

            Button("Reset Material to Default") {
                workspace.setDocumentDefaultMaterial(MaterialAttributes())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } header: {
            sectionHeader("Default Material")
        }
    }

    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isFirst { Divider() }
            Text(title).font(.headline)
        }
        .padding(.top, 8)
    }
}
