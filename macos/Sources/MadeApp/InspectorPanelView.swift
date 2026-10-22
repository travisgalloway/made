import SwiftUI
import MadeCore
import simd

enum InspectorUnitConversion {
    static func displayLength(_ valueInMillimeters: Double, unit: LengthUnit) -> Double {
        unit.fromMillimeters(valueInMillimeters)
    }

    static func commitLength(_ displayValue: Double, unit: LengthUnit) -> Float {
        Float(unit.toMillimeters(displayValue))
    }

    static func lengthAccessibilityValue(_ displayValue: Double, unit: LengthUnit) -> String {
        "\(displayValue.formatted(.number.precision(.fractionLength(1)))) \(unit.symbol)"
    }

    static func displayAngle(_ valueInDegrees: Double, unit: AngleUnit) -> Double {
        unit.fromDegrees(valueInDegrees)
    }

    static func commitAngle(_ displayValue: Double, unit: AngleUnit) -> Double {
        unit.toDegrees(displayValue)
    }

    static func angleAccessibilityValue(_ displayValue: Double, unit: AngleUnit) -> String {
        "\(displayValue.formatted(.number.precision(.fractionLength(1)))) \(unit.symbol)"
    }
}

struct InspectorPanelView: View {
    @Environment(WorkspaceModel.self) private var workspace

    nonisolated static let deleteConstraintAccessibilityLabel = InspectorSketchConstraintRow.deleteConstraintAccessibilityLabel
    nonisolated static let deleteConstraintHelpText = InspectorSketchConstraintRow.deleteConstraintHelpText

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
        if workspace.document.documentType == .drawing {
            ScrollView {
                if let activeSheet = workspace.document.activeSheet {
                    DrawingSheetInspectorView(sheet: activeSheet)
                } else {
                    ContentUnavailableView("No Drawing Sheet", systemImage: "doc.text")
                }
            }
        } else if workspace.document.selection.count > 1 {
            multiSelectionView
        } else if let view = workspace.selectedExplodedView {
            ScrollView {
                InspectorExplodedView(view: view)
            }
        } else if let constraint = workspace.selectedAssemblyConstraint {
            ScrollView {
                InspectorAssemblyConstraintView(constraint: constraint)
            }
        } else if let component = selectedComponentInstance {
            ScrollView {
                InspectorComponentInstanceView(component: component)
            }
        } else if let selected = workspace.selectedObject {
            ScrollView {
                Form {
                    identitySection(selected)
                    partPropertiesSection(selected)
                    transformSection(selected)
                        .disabled(selected.isLocked)
                    dimensionsSection(selected)
                        .disabled(selected.isLocked)
                    boundingBoxSection(selected)
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

    private var selectedComponentInstance: ComponentInstance? {
        guard let selectedId = workspace.selectedId else { return nil }
        return workspace.document.findComponentInstance(solidId: selectedId)
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

    private var multiSelectionView: some View {
        ScrollView {
            Form {
                Section("Multiple Selection") {
                    LabeledContent("Selected", value: "\(workspace.document.selection.count) objects")
                    ForEach(workspace.document.selectedBodies) { body in
                        LabeledContent("Solid", value: body.name)
                    }
                }
            }
            .formStyle(.columns)
            .controlSize(.small)
            .padding()
            .accessibilityIdentifier("inspector-multi-selection")
        }
    }

    // MARK: - Sections

    private func identitySection(_ obj: SceneObject) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { obj.name },
                set: { workspace.setBodyName(id: obj.id, name: $0) }
            ))
            .disabled(obj.isLocked)
            Toggle("Visible in Viewport", isOn: Binding(
                get: { obj.isVisible },
                set: { workspace.setBodyVisibility(id: obj.id, isVisible: $0) }
            ))
            LabeledContent("ID") {
                Text(obj.id.rawValue)
                    .accessibilityIdentifier("inspector-selected-object")
                    .monospaced()
                    .textSelection(.enabled)
            }
            LabeledContent("Kind", value: obj.def.kind.capitalized)
        } header: {
            sectionHeader("Identity", isFirst: true)
        }
    }

    private func partPropertiesSection(_ obj: SceneObject) -> some View {
        MetadataPropertiesView(
            metadata: obj.metadata,
            idPrefix: "inspector-part",
            isLocked: obj.isLocked,
            onSetProperty: { key, val in
                workspace.setBodyProperty(id: obj.id, key: key, value: val)
            }
        )
    }

    private func transformSection(_ obj: SceneObject) -> some View {
        Section {
            let lengthUnit = workspace.document.settings.units.lengthUnit
            LabeledContent("Position (\(lengthUnit.symbol))") {
                vectorFields(obj.transform.position, unit: lengthUnit) { position in
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
            case .revolve(let params):
                LabeledContent("Mode", value: params.mode.rawValue.capitalized)
                if params.mode != .full {
                    paramField("Angle", Float(params.angle), DocumentLimits.revolveAngle, id: obj.id, key: "angle") { workspace.setParam(obj.id, "angle", $0) }
                }
                if params.mode == .twoDirection {
                    paramField("Angle 2", Float(params.angle2), DocumentLimits.revolveAngle, id: obj.id, key: "angle2") { workspace.setParam(obj.id, "angle2", $0) }
                }
                LabeledContent("Profile Points", value: "\(params.profile.points.count)")
                if let sketchId = params.sketchFeatureId, let sketch = workspace.document.feature(for: sketchId) {
                    LabeledContent("Source Sketch") {
                        Button(sketch.name) {
                            workspace.selectFeature(sketchId)
                        }
                        .buttonStyle(.link)
                    }
                }
            case .chamfer(let params):
                LabeledContent("Mode", value: params.mode.label)
                paramField("Distance", Float(params.distance), DocumentLimits.chamferDistance, id: obj.id, key: "distance") { workspace.setParam(obj.id, "distance", $0) }
                if params.mode == .twoDistances {
                    paramField("Distance 2", Float(params.distance2), DocumentLimits.chamferDistance, id: obj.id, key: "distance2") { workspace.setParam(obj.id, "distance2", $0) }
                }
                if params.mode == .distanceAngle {
                    paramField("Angle", Float(params.angle), DocumentLimits.chamferAngle, id: obj.id, key: "angle") { workspace.setParam(obj.id, "angle", $0) }
                }
                LabeledContent("Edges count", value: "\(params.edgeReferences.count)")
            case .shell(let params):
                paramField("Thickness", Float(params.thickness), DocumentLimits.shellThickness, id: obj.id, key: "thickness") { workspace.setParam(obj.id, "thickness", $0) }
                LabeledContent("Removed Faces", value: "\(params.removedFaceReferences.count)")
                if !params.perFaceOverrides.isEmpty {
                    LabeledContent("Overrides", value: "\(params.perFaceOverrides.count)")
                }
            case .hole(let params):
                LabeledContent("Type", value: params.holeType.displayName)
                LabeledContent("Standard", value: params.standard.displayName)
                if let size = params.sizeDesignation {
                    LabeledContent("Size", value: size)
                }
                paramField("Diameter", Float(params.diameter), DocumentLimits.holeDiameter, id: obj.id, key: "diameter") { workspace.setParam(obj.id, "diameter", $0) }
                if params.isThrough {
                    LabeledContent("Termination", value: "Through All")
                } else {
                    paramField("Depth", Float(params.depth), DocumentLimits.holeDepth, id: obj.id, key: "depth") { workspace.setParam(obj.id, "depth", $0) }
                }
                if params.holeType == .counterbore {
                    paramField("C'Bore Dia", Float(params.counterboreDiameter), DocumentLimits.holeDiameter, id: obj.id, key: "counterboreDiameter") { workspace.setParam(obj.id, "counterboreDiameter", $0) }
                    paramField("C'Bore Depth", Float(params.counterboreDepth), DocumentLimits.holeDepth, id: obj.id, key: "counterboreDepth") { workspace.setParam(obj.id, "counterboreDepth", $0) }
                } else if params.holeType == .countersink {
                    paramField("C'Sink Dia", Float(params.countersinkDiameter), DocumentLimits.holeDiameter, id: obj.id, key: "countersinkDiameter") { workspace.setParam(obj.id, "countersinkDiameter", $0) }
                    paramField("C'Sink Angle", Float(params.countersinkAngle), DocumentLimits.countersinkAngle, id: obj.id, key: "countersinkAngle") { workspace.setParam(obj.id, "countersinkAngle", $0) }
                }
                if let thread = params.threadMetadata {
                    LabeledContent("Thread", value: "\(thread.designation) (pitch: \(thread.pitch.formatted(.number.precision(.fractionLength(2))))mm)")
                    if !thread.threadClass.isEmpty {
                        LabeledContent("Class", value: thread.threadClass)
                    }
                }
            case .pattern(let params):
                LabeledContent("Pattern Type", value: params.patternType == .linear ? "Linear" : "Circular")
                paramField("Count", Float(params.count), DocumentLimits.patternCount, id: obj.id, key: "count") { workspace.setParam(obj.id, "count", $0) }
                if params.patternType == .linear {
                    paramField("Spacing", Float(params.linearSpacing), DocumentLimits.patternSpacing, id: obj.id, key: "spacing") { workspace.setParam(obj.id, "spacing", $0) }
                    LabeledContent("Direction", value: params.isSymmetric ? "Symmetric" : "Standard")
                } else {
                    paramField("Angle", Float(params.totalAngle), DocumentLimits.patternAngle, id: obj.id, key: "totalAngle") { workspace.setParam(obj.id, "totalAngle", $0) }
                    LabeledContent("Span", value: params.isFullCircle ? "Full 360°" : "Partial Arc")
                }
                if !params.skippedIndices.isEmpty {
                    LabeledContent("Skipped", value: params.skippedIndices.map(String.init).joined(separator: ", "))
                }
            case .mirror(let params):
                LabeledContent("Mirror Plane", value: mirrorPlaneDescription(for: params))
                LabeledContent("Keep Original", value: params.keepOriginal ? "Yes" : "No")
                LabeledContent("Target Type", value: params.targetType.rawValue.capitalized)
            case .imported(let name, let sourceURL, _, let isLinked, let lastModifiedDate, _):
                let isDirectoryPackage = sourceURL?.pathExtension.lowercased() == "made"
                let kindDescription = isLinked ? (isDirectoryPackage ? "Linked .made" : "Linked STEP") : "Embedded Asset"
                LabeledContent("Reference", value: kindDescription)
                LabeledContent("Imported Mesh", value: name.isEmpty ? "Imported mesh" : name)

                if isLinked {
                    let status = workspace.linkStatus(for: obj.id)
                    LabeledContent("Status") {
                        HStack(spacing: 4) {
                            switch status {
                            case .upToDate:
                                Text("Up to Date")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            case .outOfDate:
                                Text("Out of Date")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.orange))
                            case .missingFile:
                                Text("Missing")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                    }

                    if let sourceURL {
                        LabeledContent("External Path") {
                            Text(sourceURL.lastPathComponent)
                                .font(.caption2)
                                .monospaced()
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(sourceURL.path)
                        }
                    }

                    if let lastModifiedDate {
                        LabeledContent("Last Modified") {
                            Text(lastModifiedDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Button("Update Link") {
                            Task {
                                _ = await workspace.updateLinkedReference(obj.id)
                            }
                        }
                        .disabled(status == .missingFile)

                        Button("Embed in Document") {
                            workspace.embedLinkedReference(obj.id)
                        }
                    }
                    .controlSize(.small)
                } else {
                    Button("Link to External File…") {
                        workspace.promptRelinkReference(obj.id)
                    }
                    .controlSize(.small)
                }
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

    private func mirrorPlaneDescription(for params: MirrorParams) -> String {
        if let ref = params.planeReference {
            switch ref.target {
            case .feature(let featId):
                return workspace.document.feature(for: featId)?.name ?? "Datum Plane"
            case .face(let topRef):
                return topRef.historyPath.last?.label ?? "Planar Face"
            default:
                return "Reference"
            }
        } else {
            let n = params.planeNormal
            if abs(n.x) > 0.9 {
                return "YZ Plane"
            } else if abs(n.y) > 0.9 {
                return "XZ Plane"
            } else if abs(n.z) > 0.9 {
                return "XY Plane"
            } else {
                return "Custom Plane"
            }
        }
    }

    @ViewBuilder
    private func boundingBoxSection(_ obj: SceneObject) -> some View {
        Section {
            if let boxes = workspace.boundingBoxes(for: obj.id) {
                let unit = workspace.document.settings.units.lengthUnit
                let aabbSize = boxes.axisAligned.size
                let aabbX = InspectorUnitConversion.displayLength(aabbSize.x, unit: unit)
                let aabbY = InspectorUnitConversion.displayLength(aabbSize.y, unit: unit)
                let aabbZ = InspectorUnitConversion.displayLength(aabbSize.z, unit: unit)
                let aabbStr = "\(aabbX.formatted(.number.precision(.fractionLength(1)))) × \(aabbY.formatted(.number.precision(.fractionLength(1)))) × \(aabbZ.formatted(.number.precision(.fractionLength(1)))) \(unit.symbol)"

                let obbDims = boxes.oriented.sortedDimensions
                let obb0 = InspectorUnitConversion.displayLength(obbDims.x, unit: unit)
                let obb1 = InspectorUnitConversion.displayLength(obbDims.y, unit: unit)
                let obb2 = InspectorUnitConversion.displayLength(obbDims.z, unit: unit)
                let obbStr = "\(obb0.formatted(.number.precision(.fractionLength(1)))) × \(obb1.formatted(.number.precision(.fractionLength(1)))) × \(obb2.formatted(.number.precision(.fractionLength(1)))) \(unit.symbol)"

                LabeledContent("Axis-Aligned (X, Y, Z)") {
                    Text(aabbStr)
                        .accessibilityIdentifier("inspector-aabb-size")
                        .monospaced()
                        .textSelection(.enabled)
                }
                LabeledContent("Oriented (Optimal)") {
                    Text(obbStr)
                        .accessibilityIdentifier("inspector-obb-size")
                        .monospaced()
                        .textSelection(.enabled)
                }
            } else {
                LabeledContent("Bounding Box") {
                    Text("None")
                        .accessibilityIdentifier("inspector-no-bounding-box")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Bounding Box")
        }
    }

    private func materialSection(_ obj: SceneObject) -> some View {
        Section {
            ColorPicker("Body Color", selection: Binding(
                get: {
                    let c = obj.material.color
                    return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: Double(c.w))
                },
                set: { newColor in
                    let resolved = newColor.resolve(in: EnvironmentValues())
                    let simdColor = SIMD4<Float>(resolved.red, resolved.green, resolved.blue, 1.0)
                    workspace.setBodyColor(id: obj.id, color: simdColor)
                }
            ), supportsOpacity: false)
            .accessibilityIdentifier("inspector-body-color-picker")
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
                LabeledContent("Offset", value: workspace.document.settings.units.formatLength(data.offsetDistance))
            case .offset:
                LabeledContent("Offset Distance", value: workspace.document.settings.units.formatLength(data.offsetDistance))
            case .atAngle:
                let angleUnit = workspace.document.settings.units.angleUnit
                let displayAngle = InspectorUnitConversion.displayAngle(data.angleDegrees, unit: angleUnit)
                let spoken = InspectorUnitConversion.angleAccessibilityValue(displayAngle, unit: angleUnit)
                LabeledContent("Angle") {
                    HStack(spacing: 4) {
                        CommitNumberField(
                            label: "Angle",
                            value: displayAngle,
                            width: 52,
                            step: angleUnit.defaultStep,
                            parameterResolver: { name in
                                workspace.document.parameter(named: name)?.value
                            },
                            evaluator: { expr in
                                let res = try workspace.document.evaluateExpression(expr)
                                return InspectorUnitConversion.displayAngle(res.value, unit: angleUnit)
                            }
                        ) { newAngle in
                            var updatedData = data
                            updatedData.angleDegrees = InspectorUnitConversion.commitAngle(newAngle, unit: angleUnit)
                            var updatedFeature = datumPlane
                            updatedFeature.operation = .datumPlane(updatedData)
                            _ = workspace.document.updateFeature(updatedFeature)
                            Task {
                                await KernelRegeneration.regenerateIncremental(from: datumPlane.id, in: workspace.document, client: workspace.kernelClient)
                            }
                        }
                        .accessibilityLabel("Angle")
                        .accessibilityValue(spoken)
                        Text(angleUnit.symbol).foregroundStyle(.secondary)
                    }
                }
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
                    let units = workspace.document.settings.units
                    let x = units.formatLength(Double(off.x), includeSymbol: false)
                    let y = units.formatLength(Double(off.y), includeSymbol: false)
                    let z = units.formatLength(Double(off.z), includeSymbol: false)
                    LabeledContent("Offset", value: "(\(x), \(y), \(z)) \(units.lengthUnit.symbol)")
                }
                if let rot = data.rotationAngles {
                    let units = workspace.document.settings.units
                    let x = units.formatAngle(Double(rot.x), includeSymbol: false)
                    let y = units.formatAngle(Double(rot.y), includeSymbol: false)
                    let z = units.formatAngle(Double(rot.z), includeSymbol: false)
                    LabeledContent("Euler Angles", value: "(\(x), \(y), \(z)) \(units.angleUnit.symbol)")
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

                Menu("+ Rect") {
                    Button("Corner Rectangle") {
                        let offset = Double(data.entities.count * 5)
                        let p0 = SIMD2<Double>(offset, offset)
                        let p1 = SIMD2<Double>(offset + 40, offset + 30)
                        _ = try? workspace.addCornerRectangle(to: sketch.id, corner1: p0, corner2: p1)
                    }
                    Button("Center Rectangle") {
                        let offset = Double(data.entities.count * 5)
                        let center = SIMD2<Double>(offset + 20, offset + 15)
                        let corner = SIMD2<Double>(offset + 40, offset + 30)
                        _ = try? workspace.addCenterRectangle(to: sketch.id, center: center, corner: corner)
                    }
                    Button("Three-Point Rectangle") {
                        let offset = Double(data.entities.count * 5)
                        let p0 = SIMD2<Double>(offset, offset)
                        let p1 = SIMD2<Double>(offset + 40, offset)
                        let p2 = SIMD2<Double>(offset + 40, offset + 30)
                        _ = try? workspace.addThreePointRectangle(to: sketch.id, point1: p0, point2: p1, point3: p2)
                    }
                }
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
                    InspectorSketchEntityRow(sketchId: sketch.id, entity: entity)
                }
            }
        } header: {
            sectionHeader("Entities & Profile")
        })
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

            if let redundantMsg = workspace.redundantConstraintsMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(redundantMsg)
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
                    InspectorSketchConstraintRow(sketchId: sketch.id, constraint: constraint)
                }
            }
        } header: {
            sectionHeader("Constraints")
        })
    }

    private func sketchConstraintRow(sketchId: UUID, constraint: SketchConstraint) -> some View {
        InspectorSketchConstraintRow(sketchId: sketchId, constraint: constraint)
    }

    private func constraintIcon(for kind: SketchConstraint.Kind) -> String {
        InspectorSketchConstraintRow.constraintIcon(for: kind)
    }

    @ViewBuilder
    private func sketchRegionsSection(_ sketch: Feature) -> some View {
        if case .sketch = sketch.operation {
            let regions = workspace.detectedSketchRegions
            if !regions.isEmpty {
                Section("Regions (\(regions.count))") {
                    ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                        InspectorSketchRegionRow(sketchId: sketch.id, regionNumber: index + 1, region: region)
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
    private func vectorFields(
        _ value: SIMD3<Float>,
        unit: LengthUnit? = nil,
        onChange: @escaping (SIMD3<Float>) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { axis in
                let name = ["X", "Y", "Z"][axis]
                let rawValue = Double(value[axis])
                let displayValue = unit.map { InspectorUnitConversion.displayLength(rawValue, unit: $0) } ?? rawValue
                let spoken = unit.map { InspectorUnitConversion.lengthAccessibilityValue(displayValue, unit: $0) }
                    ?? "\(displayValue.formatted(.number.precision(.fractionLength(1))))"
                VStack(spacing: 2) {
                    CommitNumberField(
                        label: name,
                        value: displayValue,
                        step: unit?.defaultStep ?? 1.0,
                        parameterResolver: { paramName in
                            workspace.document.parameter(named: paramName)?.value
                        },
                        evaluator: { expr in
                            let res = try workspace.document.evaluateExpression(expr)
                            return unit.map { InspectorUnitConversion.displayLength(res.value, unit: $0) } ?? res.value
                        }
                    ) { newValue in
                        var v = value
                        v[axis] = unit.map { InspectorUnitConversion.commitLength(newValue, unit: $0) } ?? Float(newValue)
                        onChange(v)
                    }
                    .accessibilityLabel(name)
                    .accessibilityValue(spoken)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .labelsHidden()
    }

    /// A typed length value with a slider and a unit-stepped stepper; `setParam` clamps to the range (invariant 9).
    private func paramField(
        _ label: String,
        _ value: Float,
        _ range: ParamRange,
        id: ObjectId,
        key: String,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        let lengthUnit = workspace.document.settings.units.lengthUnit
        let displayValue = InspectorUnitConversion.displayLength(Double(value), unit: lengthUnit)
        let displayMin = InspectorUnitConversion.displayLength(Double(range.min), unit: lengthUnit)
        let displayMax = InspectorUnitConversion.displayLength(Double(range.max), unit: lengthUnit)
        let symbol = lengthUnit.symbol
        let spoken = InspectorUnitConversion.lengthAccessibilityValue(displayValue, unit: lengthUnit)
        let currentExpr = workspace.document.feature(for: id)?.inputExpressions[key]?.formula
        let binding = Binding(
            get: { displayValue },
            set: { onChange(InspectorUnitConversion.commitLength($0, unit: lengthUnit)) }
        )
        return LabeledContent(label) {
            HStack(spacing: 4) {
                Slider(value: binding, in: displayMin...displayMax) {
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

                CommitNumberField(
                    label: label,
                    value: displayValue,
                    width: 52,
                    range: displayMin...displayMax,
                    step: lengthUnit.defaultStep,
                    expression: currentExpr,
                    parameterResolver: { name in
                        workspace.document.parameter(named: name)?.value
                    },
                    evaluator: { expr in
                        let res = try workspace.document.evaluateExpression(expr)
                        return InspectorUnitConversion.displayLength(res.value, unit: lengthUnit)
                    },
                    commitExpression: { userVal, expr in
                        let committed = Float(InspectorUnitConversion.commitLength(userVal, unit: lengthUnit))
                        workspace.setParam(id, key, committed, expression: expr)
                    }
                )
                .accessibilityLabel(label)
                .accessibilityValue(spoken)
                Text(symbol).foregroundStyle(.secondary)
                Stepper(label, value: binding, in: displayMin...displayMax, step: lengthUnit.defaultStep)
                    .accessibilityLabel(label)
                    .accessibilityValue(spoken)
            }
            .labelsHidden()
        }
    }
}

/// Inspector panel for a selected assembly component instance.
struct InspectorComponentInstanceView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let component: ComponentInstance

    var body: some View {
        Form {
            identitySection
            componentPropertiesSection
            if component.isSubassembly {
                subassemblySection
            }
            if component.patternId != nil || workspace.document.componentPatterns.contains(where: { $0.sourceInstanceId == component.id }) {
                patternSection
            }
            if component.mirrorId != nil || workspace.document.componentMirrors.contains(where: { $0.sourceInstanceId == component.id }) {
                mirrorSection
            }
            referenceSection
            transformSection
                .disabled(component.isLocked || component.isGrounded)
            degreesOfFreedomSection
            matesAndJointsSection
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
    }

    private var subassemblySection: some View {
        Section {
            Picker("Behavior", selection: Binding(
                get: { component.subassemblyBehavior },
                set: { workspace.setSubassemblyBehavior(id: component.id, behavior: $0) }
            )) {
                Text("Rigid").tag(SubassemblyBehavior.rigid)
                Text("Flexible").tag(SubassemblyBehavior.flexible)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("inspector-subassembly-behavior-picker")

            LabeledContent("Child Components", value: "\(component.childInstances.count)")
                .accessibilityIdentifier("inspector-subassembly-child-count")

            LabeledContent("Internal Constraints", value: "\(component.childConstraints.count)")
                .accessibilityIdentifier("inspector-subassembly-constraint-count")
        } header: {
            sectionHeader("Subassembly Configuration")
        }
    }

    @ViewBuilder
    private var patternSection: some View {
        let activePattern = component.patternId.flatMap { patId in
            workspace.document.componentPatterns.first(where: { $0.id == patId })
        } ?? workspace.document.componentPatterns.first(where: { $0.sourceInstanceId == component.id })

        if let pattern = activePattern {
            Section {
                LabeledContent("Pattern Name", value: pattern.name)
                LabeledContent("Type", value: pattern.params.patternType.rawValue.capitalized)
                LabeledContent("Count", value: "\(pattern.params.count)")
                if pattern.params.patternType == .linear {
                    let lengthUnit = workspace.document.settings.units.lengthUnit
                    LabeledContent("Spacing", value: "\(pattern.params.linearSpacing) \(lengthUnit.symbol)")
                    LabeledContent("Symmetric", value: pattern.params.isSymmetric ? "Yes" : "No")
                } else if pattern.params.patternType == .circular {
                    let angleUnit = workspace.document.settings.units.angleUnit
                    LabeledContent("Total Angle", value: "\(pattern.params.totalAngle) \(angleUnit.symbol)")
                    LabeledContent("Full Circle", value: pattern.params.isFullCircle ? "Yes" : "No")
                } else if pattern.params.patternType == .featureDriven {
                    if let fId = pattern.params.featurePatternId,
                       let feat = workspace.document.features.first(where: { $0.id == fId }) {
                        LabeledContent("Driver Feature", value: feat.name)
                    }
                }
                if let src = workspace.document.findComponentInstance(id: pattern.sourceInstanceId) {
                    LabeledContent("Source Component", value: src.name)
                }
                LabeledContent("Replicas", value: "\(pattern.replicaInstanceIds.count)")
                Button("Remove Pattern", role: .destructive) {
                    _ = workspace.removeComponentPattern(id: pattern.id)
                }
            } header: {
                sectionHeader("Component Pattern")
            }
        }
    }

    @ViewBuilder
    private var mirrorSection: some View {
        let activeMirror = component.mirrorId.flatMap { mirId in
            workspace.document.componentMirrors.first(where: { $0.id == mirId })
        } ?? workspace.document.componentMirrors.first(where: { $0.sourceInstanceId == component.id })

        if let mirror = activeMirror {
            Section {
                LabeledContent("Mirror Name", value: mirror.name)
                LabeledContent("Mode", value: mirror.params.mirrorMode == .symmetricReorient ? "Symmetric Reorient" : "Opposite Hand")
                LabeledContent("Plane Normal", value: String(format: "(%.2f, %.2f, %.2f)", mirror.params.planeNormal.x, mirror.params.planeNormal.y, mirror.params.planeNormal.z))
                if let src = workspace.document.findComponentInstance(id: mirror.sourceInstanceId) {
                    LabeledContent("Source Component", value: src.name)
                }
                Button("Remove Mirror", role: .destructive) {
                    _ = workspace.removeComponentMirror(id: mirror.id)
                }
            } header: {
                sectionHeader("Component Mirror")
            }
        }
    }

    private var identitySection: some View {
        Section {
            TextField("Name", text: Binding(
                get: { component.name },
                set: { workspace.setComponentInstanceName(id: component.id, name: $0) }
            ))
            .disabled(component.isLocked)

            Toggle("Visible in Viewport", isOn: Binding(
                get: { component.isVisible },
                set: { workspace.setBodyVisibility(id: component.solidId, isVisible: $0) }
            ))

            Toggle("Locked", isOn: Binding(
                get: { component.isLocked },
                set: { workspace.setBodyLocked(id: component.solidId, isLocked: $0) }
            ))

            Toggle("Grounded", isOn: Binding(
                get: { component.isGrounded },
                set: { workspace.setComponentInstanceGrounded(id: component.id, isGrounded: $0) }
            ))
            .help("Anchors component coordinate frame to assembly origin")

            LabeledContent("ID") {
                Text(component.solidId.rawValue)
                    .accessibilityIdentifier("inspector-selected-component")
                    .monospaced()
                    .textSelection(.enabled)
            }
        } header: {
            sectionHeader("Component Identity", isFirst: true)
        }
    }

    private var componentPropertiesSection: some View {
        MetadataPropertiesView(
            metadata: component.metadata,
            idPrefix: "inspector-component",
            isLocked: component.isLocked,
            onSetProperty: { key, val in
                workspace.setComponentProperty(id: component.id, key: key, value: val)
            }
        )
    }

    private var referenceSection: some View {
        Section {
            switch component.reference {
            case .internalPart(let name, let bodyId):
                LabeledContent("Source", value: "Internal Part")
                LabeledContent("Part Name", value: name)
                if let bodyId {
                    LabeledContent("Body ID", value: bodyId.rawValue)
                }
            case .externalDocument(let url, let partName):
                LabeledContent("Source", value: "External Document")
                LabeledContent("File", value: url.lastPathComponent)
                LabeledContent("Path") {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let partName {
                    LabeledContent("Part", value: partName)
                }
            case .subassembly(let name):
                LabeledContent("Source", value: "Subassembly")
                LabeledContent("Subassembly Name", value: name)
            }
        } header: {
            sectionHeader("Reference")
        }
    }

    private var transformSection: some View {
        Section {
            let lengthUnit = workspace.document.settings.units.lengthUnit
            let angleUnit = workspace.document.settings.units.angleUnit

            LabeledContent("Position (\(lengthUnit.symbol))") {
                vectorFields(component.transform.position, unit: lengthUnit) { newPos in
                    var t = component.transform
                    t.position = newPos
                    workspace.updateComponentInstanceTransform(id: component.id, transform: t)
                }
            }

            LabeledContent("Rotation (\(angleUnit.symbol))") {
                rotationFields(component.transform.rotation.eulerAnglesDegrees) { newEuler in
                    var t = component.transform
                    t.rotation = simd_quatf.fromEulerAngles(degrees: newEuler)
                    workspace.updateComponentInstanceTransform(id: component.id, transform: t)
                }
            }

            LabeledContent("Scale") {
                vectorFields(component.transform.scale) { newScale in
                    var t = component.transform
                    t.scale = simd_max(newScale, SIMD3<Float>(repeating: DocumentLimits.scaleFloor))
                    workspace.updateComponentInstanceTransform(id: component.id, transform: t)
                }
            }
        } header: {
            sectionHeader("3D Transform")
        }
    }

    private func vectorFields(
        _ value: SIMD3<Float>,
        unit: LengthUnit? = nil,
        onChange: @escaping (SIMD3<Float>) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { axis in
                let name = ["X", "Y", "Z"][axis]
                let rawValue = Double(value[axis])
                let displayValue = unit.map { InspectorUnitConversion.displayLength(rawValue, unit: $0) } ?? rawValue
                let spoken = unit.map { InspectorUnitConversion.lengthAccessibilityValue(displayValue, unit: $0) }
                    ?? "\(displayValue.formatted(.number.precision(.fractionLength(1))))"
                VStack(spacing: 2) {
                    CommitNumberField(
                        label: name,
                        value: displayValue,
                        step: unit?.defaultStep ?? 1.0,
                        parameterResolver: { paramName in
                            workspace.document.parameter(named: paramName)?.value
                        },
                        evaluator: { expr in
                            let res = try workspace.document.evaluateExpression(expr)
                            return unit.map { InspectorUnitConversion.displayLength(res.value, unit: $0) } ?? res.value
                        }
                    ) { newValue in
                        var v = value
                        v[axis] = unit.map { InspectorUnitConversion.commitLength(newValue, unit: $0) } ?? Float(newValue)
                        onChange(v)
                    }
                    .accessibilityLabel(name)
                    .accessibilityValue(spoken)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .labelsHidden()
    }

    private func rotationFields(
        _ eulerDegrees: SIMD3<Float>,
        onChange: @escaping (SIMD3<Float>) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { axis in
                let name = ["X", "Y", "Z"][axis]
                let rawValue = Double(eulerDegrees[axis])
                let angleUnit = workspace.document.settings.units.angleUnit
                let displayValue = InspectorUnitConversion.displayAngle(rawValue, unit: angleUnit)
                let spoken = InspectorUnitConversion.angleAccessibilityValue(displayValue, unit: angleUnit)
                VStack(spacing: 2) {
                    CommitNumberField(
                        label: name,
                        value: displayValue,
                        step: angleUnit == .radians ? 0.1 : 1.0,
                        parameterResolver: { paramName in
                            workspace.document.parameter(named: paramName)?.value
                        },
                        evaluator: { expr in
                            let res = try workspace.document.evaluateExpression(expr)
                            return InspectorUnitConversion.displayAngle(res.value, unit: angleUnit)
                        }
                    ) { newValue in
                        var v = eulerDegrees
                        v[axis] = Float(InspectorUnitConversion.commitAngle(newValue, unit: angleUnit))
                        onChange(v)
                    }
                    .accessibilityLabel("Rotation \(name)")
                    .accessibilityValue(spoken)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .labelsHidden()
    }

    private var degreesOfFreedomSection: some View {
        Section {
            let dof = workspace.remainingAssemblyDOF(for: component.id)
            LabeledContent("Remaining DOF") {
                HStack(spacing: 4) {
                    Text("\(dof)").bold()
                    Text(component.isGrounded ? "(Grounded)" : (dof == 0 ? "(Fully Constrained)" : "(Under-constrained)"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("inspector-component-dof-label")
            }
        } header: {
            sectionHeader("Degrees of Freedom")
        }
    }

    private var matesAndJointsSection: some View {
        Section {
            matesAndJointsList
        } header: {
            sectionHeader("Mates & Joints")
        }
    }

    @ViewBuilder
    private var matesAndJointsList: some View {
        let attached = workspace.document.assemblyConstraints.filter {
            $0.firstFeature.componentInstanceId == component.id ||
            $0.secondFeature.componentInstanceId == component.id
        }
        if attached.isEmpty {
            Text("No mates or joints attached")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(attached) { mate in
                attachedMateRow(mate)
            }
        }
    }

    @ViewBuilder
    private func attachedMateRow(_ mate: AssemblyConstraint) -> some View {
        Button {
            workspace.selectAssemblyConstraint(mate.id)
        } label: {
            HStack {
                Image(systemName: mate.kind.systemImageName)
                    .foregroundStyle(mate.isSuppressed ? Color.secondary : (mate.kind.isJoint ? Color.purple : Color.blue))
                Text(mate.name)
                Spacer()
                Text(mate.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isFirst { Divider() }
            Text(title).font(.headline)
        }
        .padding(.top, 8)
    }
}

/// Inspector panel view for inspecting and editing an assembly constraint or joint (BL-ASM-04, #165).
struct InspectorAssemblyConstraintView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let constraint: AssemblyConstraint

    var body: some View {
        let isConflicting = workspace.isAssemblyConstraintConflicting(constraint.id)
        let isRedundant = workspace.isAssemblyConstraintRedundant(constraint.id)

        Form {
            if isConflicting {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("This mate conflicts with other constraints and cannot be satisfied.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("inspector-constraint-conflict-alert")
                } header: {
                    sectionHeader("Diagnostics", isFirst: true)
                }
            } else if isRedundant {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("This mate is redundant and duplicates existing constraints.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .accessibilityIdentifier("inspector-constraint-redundant-alert")
                } header: {
                    sectionHeader("Diagnostics", isFirst: true)
                }
            }

            Section {
                TextField("Name", text: Binding(
                    get: { constraint.name },
                    set: { newName in
                        var copy = constraint
                        copy.name = newName
                        workspace.updateAssemblyConstraint(copy)
                    }
                ))
                .accessibilityIdentifier("inspector-constraint-name-field")

                Picker("Kind", selection: Binding(
                    get: { constraint.kind },
                    set: { newKind in
                        var copy = constraint
                        copy.kind = newKind
                        workspace.updateAssemblyConstraint(copy)
                    }
                )) {
                    Section("Mates") {
                        ForEach(AssemblyConstraintKind.allCases.filter { !$0.isJoint }, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.systemImageName).tag(kind)
                        }
                    }
                    Section("Joints") {
                        ForEach(AssemblyConstraintKind.allCases.filter { $0.isJoint }, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.systemImageName).tag(kind)
                        }
                    }
                }
                .accessibilityIdentifier("inspector-constraint-kind-picker")

                Toggle("Suppressed", isOn: Binding(
                    get: { constraint.isSuppressed },
                    set: { _ in
                        workspace.toggleAssemblyConstraintSuppressed(id: constraint.id)
                    }
                ))
                .accessibilityIdentifier("inspector-constraint-suppressed-toggle")
            } header: {
                sectionHeader("Constraint Identity", isFirst: !(isConflicting || isRedundant))
            }

            if constraint.kind == .distance || constraint.kind == .angle || constraint.kind == .tangent || constraint.kind == .planar {
                Section {
                    let isAngle = constraint.kind == .angle
                    let unitLabel = isAngle ? "rad" : "mm"
                    LabeledContent(isAngle ? "Angle" : "Offset") {
                        HStack(spacing: 4) {
                            TextField(
                                isAngle ? "Angle" : "Offset",
                                value: Binding(
                                    get: { constraint.value ?? 0.0 },
                                    set: { newValue in
                                        var copy = constraint
                                        copy.value = newValue
                                        workspace.updateAssemblyConstraint(copy)
                                    }
                                ),
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .accessibilityIdentifier("inspector-constraint-value-field")
                            Text(unitLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    sectionHeader("Parameters")
                }
            }

            Section {
                featureSummaryRow(title: "First Feature", feature: constraint.firstFeature)
                featureSummaryRow(title: "Second Feature", feature: constraint.secondFeature)
            } header: {
                sectionHeader("Features")
            }

            Section {
                if let result = workspace.lastAssemblySolverResult {
                    LabeledContent("Last Solve") {
                        Text(result.status.summaryText)
                            .font(.caption)
                            .foregroundStyle(result.status.isOverConstrained ? .red : (result.status.isRedundant ? .orange : .secondary))
                            .accessibilityIdentifier("inspector-assembly-solve-status-label")
                    }
                    LabeledContent("Total DOF") {
                        Text("\(result.totalDOF)")
                            .font(.caption)
                            .bold()
                            .accessibilityIdentifier("inspector-assembly-total-dof-label")
                    }
                }

                Button("Solve Assembly", systemImage: "arrow.triangle.2.circlepath") {
                    _ = workspace.solveAssemblyConstraints()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("inspector-solve-assembly-button")

                Button("Delete Constraint", role: .destructive) {
                    workspace.removeAssemblyConstraint(id: constraint.id)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("inspector-delete-constraint-button")
            } header: {
                sectionHeader("Actions")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
    }

    @ViewBuilder
    private func featureSummaryRow(title: String, feature: AssemblyFeature) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let instId = feature.componentInstanceId,
               let comp = workspace.document.componentInstances.first(where: { $0.id == instId }) {
                Text(comp.name)
                    .font(.body)
            } else {
                Text("Ground (World Frame)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Text("Origin: (\(String(format: "%.1f", feature.localOrigin.x)), \(String(format: "%.1f", feature.localOrigin.y)), \(String(format: "%.1f", feature.localOrigin.z)))")
                .font(.caption2)
                .foregroundStyle(.secondary)
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

/// Inspector panel view for inspecting and editing an exploded view and its steps (BL-ASM-12).
struct InspectorExplodedView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let view: ExplodedView

    var body: some View {
        let isActive = workspace.activeExplodedViewId == view.id && !view.isCollapsed
        let lengthUnit = workspace.document.settings.units.lengthUnit

        Form {
            Section {
                TextField("Name", text: Binding(
                    get: { view.name },
                    set: { newName in
                        workspace.renameExplodedView(id: view.id, name: newName)
                    }
                ))
                .accessibilityIdentifier("inspector-exploded-view-name-field")

                Toggle("Active (Exploded)", isOn: Binding(
                    get: { isActive },
                    set: { _ in
                        workspace.toggleExplodedView(id: view.id)
                    }
                ))
                .accessibilityIdentifier("inspector-exploded-view-active-toggle")

                Toggle("Collapsed", isOn: Binding(
                    get: { view.isCollapsed },
                    set: { _ in
                        workspace.toggleExplodedViewCollapsed(id: view.id)
                    }
                ))
                .accessibilityIdentifier("inspector-exploded-view-collapsed-toggle")
            } header: {
                sectionHeader("Exploded View Identity", isFirst: true)
            }

            Section {
                if let selectedStep = workspace.selectedExplodeStep {
                    stepConfigurationSection(selectedStep, lengthUnit: lengthUnit)
                } else if let firstStep = view.steps.first {
                    stepConfigurationSection(firstStep, lengthUnit: lengthUnit)
                } else {
                    Text("No steps added yet. Add a step to begin exploding components.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    _ = workspace.addExplodeStep(viewId: view.id)
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .accessibilityIdentifier("inspector-add-step-button")
            } header: {
                sectionHeader("Step Configuration")
            }

            if view.steps.count > 1 {
                Section {
                    ForEach(view.steps) { step in
                        let isSelectedStep = (workspace.selectedExplodeStepId == step.id) || (workspace.selectedExplodeStepId == nil && view.steps.first?.id == step.id)
                        let displayDist = InspectorUnitConversion.displayLength(Double(step.distance), unit: lengthUnit)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.name)
                                    .font(.body)
                                    .bold(isSelectedStep)
                                Text("\(step.targetInstanceIds.count) parts, \(displayDist.formatted(.number.precision(.fractionLength(1)))) \(lengthUnit.symbol)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelectedStep {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            workspace.selectExplodeStep(viewId: view.id, stepId: step.id)
                        }
                    }
                } header: {
                    sectionHeader("All Steps (\(view.steps.count))")
                }
            }

            Section {
                Button(role: .destructive) {
                    workspace.removeExplodedView(id: view.id)
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Exploded View")
                        Spacer()
                    }
                }
                .accessibilityIdentifier("inspector-delete-exploded-view-button")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
    }

    @ViewBuilder
    private func stepConfigurationSection(_ step: ExplodeStep, lengthUnit: LengthUnit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Step Name", text: Binding(
                get: { step.name },
                set: { newName in
                    var copy = step
                    copy.name = newName
                    workspace.updateExplodeStep(viewId: view.id, step: copy)
                }
            ))
            .accessibilityIdentifier("inspector-explode-step-name-field")

            let displayDist = InspectorUnitConversion.displayLength(Double(step.distance), unit: lengthUnit)
            LabeledContent("Distance (\(lengthUnit.symbol))") {
                HStack(spacing: 4) {
                    TextField(
                        "Distance",
                        value: Binding(
                            get: { displayDist },
                            set: { userVal in
                                var copy = step
                                copy.distance = Float(InspectorUnitConversion.commitLength(userVal, unit: lengthUnit))
                                workspace.updateExplodeStep(viewId: view.id, step: copy)
                            }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .accessibilityIdentifier("inspector-explode-step-distance-field")
                    Text(lengthUnit.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Direction (X, Y, Z)") {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { axis in
                        let name = ["X", "Y", "Z"][axis]
                        TextField(
                            name,
                            value: Binding(
                                get: { Double(step.direction[axis]) },
                                set: { newAxisVal in
                                    var copy = step
                                    copy.direction[axis] = Float(newAxisVal)
                                    workspace.updateExplodeStep(viewId: view.id, step: copy)
                                }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    }
                }
            }

            Toggle("Show Trail", isOn: Binding(
                get: { step.hasTrail },
                set: { hasTrail in
                    var copy = step
                    copy.hasTrail = hasTrail
                    workspace.updateExplodeStep(viewId: view.id, step: copy)
                }
            ))
            .accessibilityIdentifier("inspector-explode-step-trail-toggle")

            let allComps = workspace.document.allComponentInstances
            if !allComps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Components (\(step.targetInstanceIds.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(allComps) { comp in
                        let isTarget = step.targetInstanceIds.contains(comp.id)
                        Toggle(comp.name, isOn: Binding(
                            get: { isTarget },
                            set: { shouldTarget in
                                var copy = step
                                if shouldTarget {
                                    if !copy.targetInstanceIds.contains(comp.id) {
                                        copy.targetInstanceIds.append(comp.id)
                                    }
                                } else {
                                    copy.targetInstanceIds.removeAll(where: { $0 == comp.id })
                                }
                                workspace.updateExplodeStep(viewId: view.id, step: copy)
                            }
                        ))
                    }
                }
            }

            Button("Delete Step", role: .destructive) {
                workspace.removeExplodeStep(viewId: view.id, stepId: step.id)
            }
            .accessibilityIdentifier("inspector-delete-step-button")
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

/// Reusable inspector view for standard and custom key/value metadata properties (BL-FND-14, #172).
struct MetadataPropertiesView: View {
    let metadata: [String: String]
    var idPrefix: String = "inspector-doc"
    var isLocked: Bool = false
    var onSetProperty: (String, String?) -> Void

    @State private var newKey: String = ""
    @State private var newValue: String = ""

    var body: some View {
        Section {
            TextField("Part Number", text: Binding(
                get: { metadata[CustomPropertyKey.partNumber] ?? "" },
                set: { onSetProperty(CustomPropertyKey.partNumber, $0) }
            ))
            .disabled(isLocked)
            .accessibilityIdentifier("\(idPrefix)-part-number")

            TextField("Description", text: Binding(
                get: { metadata[CustomPropertyKey.description] ?? "" },
                set: { onSetProperty(CustomPropertyKey.description, $0) }
            ))
            .disabled(isLocked)
            .accessibilityIdentifier("\(idPrefix)-description")

            TextField("Revision", text: Binding(
                get: { metadata[CustomPropertyKey.revision] ?? "" },
                set: { onSetProperty(CustomPropertyKey.revision, $0) }
            ))
            .disabled(isLocked)
            .accessibilityIdentifier("\(idPrefix)-revision")

            TextField("Vendor", text: Binding(
                get: { metadata[CustomPropertyKey.vendor] ?? "" },
                set: { onSetProperty(CustomPropertyKey.vendor, $0) }
            ))
            .disabled(isLocked)
            .accessibilityIdentifier("\(idPrefix)-vendor")
        } header: {
            sectionHeader("Standard Properties")
        }

        Section {
            let customKeys = metadata.keys.filter { !CustomPropertyKey.standardKeys.contains($0) }.sorted()
            if customKeys.isEmpty {
                Text("No custom properties defined.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(customKeys, id: \.self) { key in
                    HStack(spacing: 6) {
                        Text(key)
                            .accessibilityIdentifier("\(idPrefix)-custom-key-\(key)")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                            .lineLimit(1)
                        TextField("Value", text: Binding(
                            get: { metadata[key] ?? "" },
                            set: { onSetProperty(key, $0) }
                        ))
                        .disabled(isLocked)
                        .accessibilityIdentifier("\(idPrefix)-custom-val-\(key)")
                        Button(role: .destructive) {
                            onSetProperty(key, nil)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLocked)
                        .accessibilityIdentifier("\(idPrefix)-custom-delete-\(key)")
                    }
                }
            }

            if !isLocked {
                HStack(spacing: 6) {
                    TextField("Key", text: $newKey)
                        .accessibilityIdentifier("\(idPrefix)-new-key")
                        .onSubmit(commitNewProperty)
                    TextField("Value", text: $newValue)
                        .accessibilityIdentifier("\(idPrefix)-new-val")
                        .onSubmit(commitNewProperty)
                    Button {
                        commitNewProperty()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("\(idPrefix)-add-property")
                }
            }
        } header: {
            sectionHeader("Custom Properties")
        }
    }

    private func commitNewProperty() {
        let trimmedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        onSetProperty(trimmedKey, newValue)
        newKey = ""
        newValue = ""
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(title).font(.headline)
        }
        .padding(.top, 8)
    }
}

struct DocumentSettingsInspectorView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var parameterError: String? = nil
    @State private var showingErrorAlert = false

    var body: some View {
        ScrollView {
            Form {
                documentTypeSection
                documentPropertiesSection
                parametersSection
                unitsSection
                tolerancesSection
                materialSection
            }
            .formStyle(.columns)
            .controlSize(.small)
            .padding()
        }
        .alert("Parameter Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(parameterError ?? "")
        }
    }

    private var documentTypeSection: some View {
        Section {
            LabeledContent("Type", value: workspace.document.documentType.displayName)
            if workspace.document.documentType == .assembly {
                LabeledContent("Components", value: "\(workspace.document.componentInstances.count)")
            }
        } header: {
            sectionHeader("Document Type", isFirst: true)
        }
    }

    private var documentPropertiesSection: some View {
        MetadataPropertiesView(
            metadata: workspace.document.metadata,
            idPrefix: "inspector-doc",
            isLocked: false,
            onSetProperty: { key, val in
                workspace.setDocumentProperty(key: key, value: val)
            }
        )
    }

    private var parametersSection: some View {
        Section {
            if workspace.document.parameters.isEmpty {
                Text("No document parameters defined.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Spacer().frame(width: 12)
                        Text("Name").font(.caption).bold().frame(width: 70, alignment: .leading)
                        Text("Value").font(.caption).bold().frame(width: 55, alignment: .trailing)
                        Text("Unit").font(.caption).bold().frame(width: 36, alignment: .leading)
                        Text("Comment").font(.caption).bold().frame(maxWidth: .infinity, alignment: .leading)
                        Spacer().frame(width: 24)
                    }
                    Divider()
                    ForEach(workspace.document.parameters) { param in
                        DocumentParameterRowView(
                            param: param,
                            onError: { error in
                                parameterError = error.localizedDescription
                                showingErrorAlert = true
                            }
                        )
                    }
                }
            }

            Button {
                addDefaultParameter()
            } label: {
                Label("Add Parameter", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } header: {
            sectionHeader("Parameters", isFirst: false)
        }
    }

    private func addDefaultParameter() {
        let existing = workspace.document.parameters.map(\.name)
        var candidate = "param_1"
        var counter = 1
        while existing.contains(candidate) {
            counter += 1
            candidate = "param_\(counter)"
        }
        let newParam = DocumentParameter(name: candidate, value: 10.0, unit: "mm", comment: "")
        do {
            try workspace.addParameter(newParam)
        } catch {
            parameterError = error.localizedDescription
            showingErrorAlert = true
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
            sectionHeader("Units", isFirst: false)
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

struct DocumentParameterRowView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let param: DocumentParameter
    let onError: (Error) -> Void

    @State private var isExpanded: Bool = false
    @State private var nameDraft: String = ""
    @State private var unitDraft: String = ""
    @State private var commentDraft: String = ""
    @State private var minDraft: String = ""
    @State private var maxDraft: String = ""
    @State private var stepDraft: String = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, unit, comment, min, max, step
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse range settings" : "Expand range settings")

                TextField("Name", text: $nameDraft)
                    .focused($focusedField, equals: .name)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitName)

                CommitNumberField(
                    label: "Value",
                    value: param.value,
                    width: 55,
                    minimum: param.min,
                    maximum: param.max,
                    step: param.step ?? 1.0,
                    expression: param.expression,
                    parameterResolver: { name in
                        workspace.document.parameters.first(where: { $0.name == name })?.value
                    },
                    evaluator: { expr in
                        try workspace.document.evaluateExpression(expr).value
                    },
                    commitExpression: { val, expr in
                        do {
                            try workspace.updateParameter(id: param.id, value: val, expression: expr)
                        } catch {
                            onError(error)
                        }
                    }
                )

                TextField("Unit", text: $unitDraft)
                    .focused($focusedField, equals: .unit)
                    .frame(width: 36)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitUnit)

                TextField("Comment", text: $commentDraft)
                    .focused($focusedField, equals: .comment)
                    .frame(maxWidth: .infinity)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitComment)

                Button(role: .destructive) {
                    do {
                        try workspace.deleteParameter(id: param.id)
                    } catch {
                        onError(error)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(param.name)")
            }

            if isExpanded {
                HStack(spacing: 8) {
                    Text("Range:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text("Min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("None", text: $minDraft)
                            .focused($focusedField, equals: .min)
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(commitMin)
                    }

                    HStack(spacing: 4) {
                        Text("Max")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("None", text: $maxDraft)
                            .focused($focusedField, equals: .max)
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(commitMax)
                    }

                    HStack(spacing: 4) {
                        Text("Step")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("1.0", text: $stepDraft)
                            .focused($focusedField, equals: .step)
                            .frame(width: 44)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(commitStep)
                    }

                    Spacer()
                }
                .padding(.leading, 18)
            }

            if param.isOutOfRange, let errorMsg = param.rangeErrorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(errorMsg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.leading, 18)
            }
        }
        .onChange(of: focusedField) { oldField, _ in
            switch oldField {
            case .name: commitName()
            case .unit: commitUnit()
            case .comment: commitComment()
            case .min: commitMin()
            case .max: commitMax()
            case .step: commitStep()
            case nil: break
            }
        }
        .onAppear {
            syncFromParam()
        }
        .onChange(of: param) { _, _ in
            syncFromParam()
        }
    }

    private func syncFromParam() {
        nameDraft = param.name
        unitDraft = param.unit
        commentDraft = param.comment
        minDraft = param.min.map { String(format: "%.1f", $0) } ?? ""
        maxDraft = param.max.map { String(format: "%.1f", $0) } ?? ""
        stepDraft = param.step.map { String(format: "%.1f", $0) } ?? ""
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard trimmed != param.name else { return }
        do {
            try workspace.renameParameter(id: param.id, newName: trimmed)
        } catch {
            nameDraft = param.name
            onError(error)
        }
    }

    private func commitUnit() {
        let trimmed = unitDraft.trimmingCharacters(in: .whitespaces)
        guard trimmed != param.unit else { return }
        do {
            try workspace.updateParameter(id: param.id, unit: trimmed)
        } catch {
            unitDraft = param.unit
            onError(error)
        }
    }

    private func commitComment() {
        let trimmed = commentDraft.trimmingCharacters(in: .whitespaces)
        guard trimmed != param.comment else { return }
        do {
            try workspace.updateParameter(id: param.id, comment: trimmed)
        } catch {
            commentDraft = param.comment
            onError(error)
        }
    }

    private func commitMin() {
        let trimmed = minDraft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard param.min != nil else { return }
            do {
                try workspace.updateParameter(id: param.id, min: .some(nil))
            } catch {
                syncFromParam()
                onError(error)
            }
        } else if let num = Double(trimmed) {
            guard num != param.min else { return }
            do {
                try workspace.updateParameter(id: param.id, min: num)
            } catch {
                syncFromParam()
                onError(error)
            }
        } else {
            syncFromParam()
            onError(CommitFieldError.invalidNumber(trimmed))
        }
    }

    private func commitMax() {
        let trimmed = maxDraft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard param.max != nil else { return }
            do {
                try workspace.updateParameter(id: param.id, max: .some(nil))
            } catch {
                syncFromParam()
                onError(error)
            }
        } else if let num = Double(trimmed) {
            guard num != param.max else { return }
            do {
                try workspace.updateParameter(id: param.id, max: num)
            } catch {
                syncFromParam()
                onError(error)
            }
        } else {
            syncFromParam()
            onError(CommitFieldError.invalidNumber(trimmed))
        }
    }

    private func commitStep() {
        let trimmed = stepDraft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard param.step != nil else { return }
            do {
                try workspace.updateParameter(id: param.id, step: .some(nil))
            } catch {
                syncFromParam()
                onError(error)
            }
        } else if let num = Double(trimmed) {
            guard num != param.step else { return }
            do {
                try workspace.updateParameter(id: param.id, step: num)
            } catch {
                syncFromParam()
                onError(error)
            }
        } else {
            syncFromParam()
            onError(CommitFieldError.invalidNumber(trimmed))
        }
    }
}

struct InspectorSketchEntityRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let sketchId: UUID
    let entity: SketchEntity

    init(sketchId: UUID, entity: SketchEntity) {
        self.sketchId = sketchId
        self.entity = entity
    }

    nonisolated static let defaultAccessibilityTraits: AccessibilityTraits = .isButton
    nonisolated static let deleteEntityAccessibilityLabel = "Delete Entity"
    nonisolated static let deleteEntityHelpText = "Delete Entity"

    nonisolated static func accessibilityTraits(isSelected: Bool = false) -> AccessibilityTraits {
        isSelected ? [defaultAccessibilityTraits, .isSelected] : defaultAccessibilityTraits
    }

    nonisolated static func accessibilityLabel(
        kind: String,
        status: SketchDOFStatus,
        isConstruction: Bool = false,
        isProjected: Bool = false
    ) -> String {
        var label = "\(kind.capitalized), \(status.statusText)"
        if isConstruction {
            label += ", Construction"
        }
        if isProjected {
            label += ", Projected"
        }
        return label
    }

    var body: some View {
        let isSelected = workspace.selectedSketchEntity?.entity.id == entity.id
        let status = workspace.dofStatus(for: entity.id)
        let statusColor = ViewportStatusBar.dofColor(for: status)
        let bg = isSelected ? Color.accentColor.opacity(0.12) : (statusColor?.opacity(0.04) ?? Color.clear)
        let strokeColor = isSelected ? Color.accentColor : (statusColor?.opacity(0.35) ?? Color.clear)

        VStack(alignment: .leading, spacing: 4) {
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
                .accessibilityLabel(Self.deleteEntityAccessibilityLabel)
                .help(Self.deleteEntityHelpText)
            }

            let sketchParamResolver: (String) -> Double? = { name in
                workspace.document.parameter(named: name)?.value
            }
            let sketchEvaluator: (String) throws -> Double = { expr in
                try workspace.document.evaluateExpression(expr).value
            }

            switch entity.kind {
            case "line":
                if let start = entity.startPoint, let end = entity.endPoint {
                    HStack(spacing: 6) {
                        Text("Start:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(
                            label: "SX",
                            value: start.x,
                            width: 44,
                            step: 1.0,
                            parameterResolver: sketchParamResolver,
                            evaluator: sketchEvaluator
                        ) {
                            var e = entity
                            e.startPoint = SIMD2<Double>($0, start.y)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        CommitNumberField(
                            label: "SY",
                            value: start.y,
                            width: 44,
                            step: 1.0,
                            parameterResolver: sketchParamResolver,
                            evaluator: sketchEvaluator
                        ) {
                            var e = entity
                            e.startPoint = SIMD2<Double>(start.x, $0)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        Text("End:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(
                            label: "EX",
                            value: end.x,
                            width: 44,
                            step: 1.0,
                            parameterResolver: sketchParamResolver,
                            evaluator: sketchEvaluator
                        ) {
                            var e = entity
                            e.endPoint = SIMD2<Double>($0, end.y)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        CommitNumberField(
                            label: "EY",
                            value: end.y,
                            width: 44,
                            step: 1.0,
                            parameterResolver: sketchParamResolver,
                            evaluator: sketchEvaluator
                        ) {
                            var e = entity
                            e.endPoint = SIMD2<Double>(end.x, $0)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Length:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(
                            label: "Length",
                            value: entity.length ?? 0.0,
                            width: 56,
                            minimum: 0.0001,
                            step: 1.0,
                            parameterResolver: sketchParamResolver,
                            evaluator: sketchEvaluator
                        ) { newLen in
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
                        CommitNumberField(
                            label: "CX",
                            value: center.x,
                            width: 44,
                            step: 1.0,
                            parameterResolver: sketchParamResolver,
                            evaluator: sketchEvaluator
                        ) {
                            var e = entity
                            e.centerPoint = SIMD2<Double>($0, center.y)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        CommitNumberField(
                            label: "CY",
                            value: center.y,
                            width: 44,
                            step: 1.0,
                            parameterResolver: sketchParamResolver,
                            evaluator: sketchEvaluator
                        ) {
                            var e = entity
                            e.centerPoint = SIMD2<Double>(center.x, $0)
                            workspace.updateSketchEntity(in: sketchId, entity: e)
                        }
                        Text("Radius:").font(.caption2).foregroundStyle(.secondary)
                        CommitNumberField(
                            label: "R",
                            value: radius,
                            width: 44,
                            step: 1.0,
                            parameterResolver: sketchParamResolver,
                            evaluator: sketchEvaluator
                        ) {
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
                            CommitNumberField(
                                label: "SX",
                                value: start.x,
                                width: 44,
                                step: 1.0,
                                parameterResolver: sketchParamResolver,
                                evaluator: sketchEvaluator
                            ) {
                                var e = entity
                                e.startPoint = SIMD2<Double>($0, start.y)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            CommitNumberField(
                                label: "SY",
                                value: start.y,
                                width: 44,
                                step: 1.0,
                                parameterResolver: sketchParamResolver,
                                evaluator: sketchEvaluator
                            ) {
                                var e = entity
                                e.startPoint = SIMD2<Double>(start.x, $0)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            Text("End:").font(.caption2).foregroundStyle(.secondary)
                            CommitNumberField(
                                label: "EX",
                                value: end.x,
                                width: 44,
                                step: 1.0,
                                parameterResolver: sketchParamResolver,
                                evaluator: sketchEvaluator
                            ) {
                                var e = entity
                                e.endPoint = SIMD2<Double>($0, end.y)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            CommitNumberField(
                                label: "EY",
                                value: end.y,
                                width: 44,
                                step: 1.0,
                                parameterResolver: sketchParamResolver,
                                evaluator: sketchEvaluator
                            ) {
                                var e = entity
                                e.endPoint = SIMD2<Double>(end.x, $0)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                        }
                        HStack(spacing: 6) {
                            Text("Center:").font(.caption2).foregroundStyle(.secondary)
                            CommitNumberField(
                                label: "CX",
                                value: center.x,
                                width: 44,
                                step: 1.0,
                                parameterResolver: sketchParamResolver,
                                evaluator: sketchEvaluator
                            ) {
                                var e = entity
                                e.centerPoint = SIMD2<Double>($0, center.y)
                                workspace.updateSketchEntity(in: sketchId, entity: e)
                            }
                            CommitNumberField(
                                label: "CY",
                                value: center.y,
                                width: 44,
                                step: 1.0,
                                parameterResolver: sketchParamResolver,
                                evaluator: sketchEvaluator
                            ) {
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
        .focusable()
        .onKeyPress(.return) {
            workspace.selectSketchEntity(featureId: sketchId, entityId: entity.id)
            return .handled
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(Self.accessibilityTraits(isSelected: isSelected))
        .accessibilityLabel(Self.accessibilityLabel(
            kind: entity.kind,
            status: status,
            isConstruction: entity.isConstruction,
            isProjected: entity.isProjected
        ))
        .accessibilityAction {
            workspace.selectSketchEntity(featureId: sketchId, entityId: entity.id)
        }
        .accessibilityAction(named: "Toggle Construction") {
            var e = entity
            e.isConstruction.toggle()
            workspace.updateSketchEntity(in: sketchId, entity: e)
        }
        .accessibilityAction(named: "Delete") {
            workspace.removeSketchEntity(from: sketchId, entityId: entity.id)
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
}

struct InspectorSketchConstraintRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let sketchId: UUID
    let constraint: SketchConstraint

    init(sketchId: UUID, constraint: SketchConstraint) {
        self.sketchId = sketchId
        self.constraint = constraint
    }

    nonisolated static let deleteConstraintAccessibilityLabel = "Delete Constraint"
    nonisolated static let deleteConstraintHelpText = "Delete Constraint"

    nonisolated static func constraintIcon(for kind: SketchConstraint.Kind) -> String {
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

    var body: some View {
        let isConflicting = workspace.conflictingConstraintIds.contains(constraint.id)
        let isRedundant = workspace.redundantConstraintIds.contains(constraint.id)

        let labelColor: Color = {
            if constraint.isDriven {
                return .secondary
            } else if isConflicting {
                return .red
            } else if isRedundant {
                return .orange
            } else {
                return .primary
            }
        }()

        let rowBackground: Color = {
            if isConflicting {
                return Color.red.opacity(0.1)
            } else if isRedundant {
                return Color.orange.opacity(0.08)
            } else {
                return Color.clear
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: Self.constraintIcon(for: constraint.kind))
                .font(.caption)
                .foregroundStyle(labelColor)

            Text(constraint.kind.rawValue.capitalized)
                .font(.caption.bold())
                .foregroundStyle(labelColor)

            if constraint.isDriven {
                Text("Driven")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
            } else if isConflicting {
                Text("Conflict")
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
            } else if isRedundant {
                Text("Redundant")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(.orange)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                    )
            }

            Spacer()

            Button {
                workspace.toggleSketchConstraintDriven(in: sketchId, constraintId: constraint.id)
            } label: {
                Text(constraint.isDriven ? "Make Driving" : "Make Driven")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button(role: .destructive) {
                workspace.removeSketchConstraint(from: sketchId, constraintId: constraint.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityLabel(Self.deleteConstraintAccessibilityLabel)
            .help(Self.deleteConstraintHelpText)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(rowBackground)
        )
        .contextMenu {
            Button(constraint.isDriven ? "Convert to Driving" : "Convert to Driven") {
                workspace.toggleSketchConstraintDriven(in: sketchId, constraintId: constraint.id)
            }
            Button("Delete Constraint", role: .destructive) {
                workspace.removeSketchConstraint(from: sketchId, constraintId: constraint.id)
            }
        }
    }
}

struct InspectorSketchRegionRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let sketchId: UUID
    let regionNumber: Int
    let region: SketchRegion

    init(sketchId: UUID, regionNumber: Int, region: SketchRegion) {
        self.sketchId = sketchId
        self.regionNumber = regionNumber
        self.region = region
    }

    nonisolated static let defaultAccessibilityTraits: AccessibilityTraits = .isButton

    nonisolated static func accessibilityTraits(isSelected: Bool = false) -> AccessibilityTraits {
        isSelected ? [defaultAccessibilityTraits, .isSelected] : defaultAccessibilityTraits
    }

    nonisolated static func accessibilityLabel(regionNumber: Int, area: Float, holeCount: Int = 0) -> String {
        let areaText = String(format: "Area: %.1f mm²", area)
        if holeCount > 0 {
            let holeText = holeCount == 1 ? "1 hole" : "\(holeCount) holes"
            return "Region \(regionNumber), \(areaText), \(holeText)"
        } else {
            return "Region \(regionNumber), \(areaText)"
        }
    }

    var body: some View {
        let isSelected = workspace.selectedSketchRegionId == region.id
        let bg = isSelected ? Color.accentColor.opacity(0.12) : Color.clear
        let strokeColor = isSelected ? Color.accentColor.opacity(0.4) : Color.clear

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Region \(regionNumber)")
                    .fontWeight(isSelected ? .bold : .regular)
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
                workspace.selectSketchRegion(featureId: sketchId, regionId: region.id)
                Task { @MainActor in
                    _ = await workspace.extrudeSketch(
                        sketchFeatureId: sketchId,
                        distance: 20.0,
                        isSymmetric: false,
                        regionId: region.id
                    )
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(bg)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(strokeColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered in
            workspace.setHoveredSketchRegion(isHovered ? region.id : nil)
        }
        .onTapGesture {
            workspace.selectSketchRegion(featureId: sketchId, regionId: region.id)
        }
        .focusable()
        .onKeyPress(.return) {
            workspace.selectSketchRegion(featureId: sketchId, regionId: region.id)
            return .handled
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(Self.accessibilityTraits(isSelected: isSelected))
        .accessibilityLabel(Self.accessibilityLabel(
            regionNumber: regionNumber,
            area: region.area,
            holeCount: region.innerLoops.count
        ))
        .accessibilityAction {
            workspace.selectSketchRegion(featureId: sketchId, regionId: region.id)
        }
        .accessibilityAction(named: "Extrude") {
            workspace.selectSketchRegion(featureId: sketchId, regionId: region.id)
            Task { @MainActor in
                _ = await workspace.extrudeSketch(
                    sketchFeatureId: sketchId,
                    distance: 20.0,
                    isSymmetric: false,
                    regionId: region.id
                )
            }
        }
    }
}

/// Inspector view for drawing sheet setup and title block properties (BL-DRW-01, #208).
struct DrawingSheetInspectorView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let sheet: DrawingSheet

    var body: some View {
        Form {
            Section("Sheet Setup") {
                TextField("Sheet Name", text: Binding(
                    get: { sheet.name },
                    set: { newName in
                        var copy = sheet
                        copy.name = newName
                        _ = workspace.updateSheet(copy)
                    }
                ))
                .accessibilityIdentifier("inspector-sheet-name-field")

                Picker("Size", selection: Binding(
                    get: {
                        if case .custom = sheet.size {
                            return "custom"
                        }
                        return sheet.size.displayName
                    },
                    set: { selectedKey in
                        var copy = sheet
                        if selectedKey == "custom" {
                            copy.size = .custom(width: 420, height: 297)
                        } else if let matching = DrawingSheetSize.standardSizes.first(where: { $0.displayName == selectedKey }) {
                            copy.size = matching
                        }
                        _ = workspace.updateSheet(copy)
                    }
                )) {
                    ForEach(DrawingSheetSize.standardSizes, id: \.displayName) { standardSize in
                        Text(standardSize.displayName).tag(standardSize.displayName)
                    }
                    Text("Custom…").tag("custom")
                }
                .accessibilityIdentifier("inspector-sheet-size-picker")

                if case .custom(let w, let h) = sheet.size {
                    HStack {
                        TextField("Width (mm)", value: Binding(
                            get: { w },
                            set: { newW in
                                var copy = sheet
                                copy.size = .custom(width: newW, height: h)
                                _ = workspace.updateSheet(copy)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)

                        TextField("Height (mm)", value: Binding(
                            get: { h },
                            set: { newH in
                                var copy = sheet
                                copy.size = .custom(width: w, height: newH)
                                _ = workspace.updateSheet(copy)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                    }
                }

                Picker("Orientation", selection: Binding(
                    get: { sheet.orientation },
                    set: { newOrientation in
                        var copy = sheet
                        copy.orientation = newOrientation
                        _ = workspace.updateSheet(copy)
                    }
                )) {
                    ForEach(DrawingSheetOrientation.allCases, id: \.self) { orient in
                        Text(orient.displayName).tag(orient)
                    }
                }
                .accessibilityIdentifier("inspector-sheet-orientation-picker")

                TextField("Scale", text: Binding(
                    get: { sheet.scale },
                    set: { newScale in
                        var copy = sheet
                        copy.scale = newScale
                        _ = workspace.updateSheet(copy)
                    }
                ))
                .accessibilityIdentifier("inspector-sheet-scale-field")

                Picker("Title Block", selection: Binding(
                    get: { sheet.titleBlockTemplate },
                    set: { newTemplate in
                        var copy = sheet
                        copy.titleBlockTemplate = newTemplate
                        _ = workspace.updateSheet(copy)
                    }
                )) {
                    ForEach(TitleBlockTemplate.allCases, id: \.self) { template in
                        Text(template.displayName).tag(template)
                    }
                }
                .accessibilityIdentifier("inspector-sheet-template-picker")
            }

            Section("Title Block Properties") {
                let metadata = workspace.document.metadata

                TextField("Title", text: Binding(
                    get: { metadata[CustomPropertyKey.description] ?? metadata["title"] ?? "" },
                    set: {
                        workspace.setDocumentProperty(key: CustomPropertyKey.description, value: $0)
                        workspace.setDocumentProperty(key: "title", value: $0)
                    }
                ))
                .accessibilityIdentifier("inspector-title-block-title-field")

                TextField("Part Number", text: Binding(
                    get: { metadata[CustomPropertyKey.partNumber] ?? "" },
                    set: { workspace.setDocumentProperty(key: CustomPropertyKey.partNumber, value: $0) }
                ))
                .accessibilityIdentifier("inspector-title-block-part-number-field")

                TextField("Revision", text: Binding(
                    get: { metadata[CustomPropertyKey.revision] ?? "" },
                    set: { workspace.setDocumentProperty(key: CustomPropertyKey.revision, value: $0) }
                ))
                .accessibilityIdentifier("inspector-title-block-revision-field")

                TextField("Vendor / Company", text: Binding(
                    get: { metadata[CustomPropertyKey.vendor] ?? "" },
                    set: { workspace.setDocumentProperty(key: CustomPropertyKey.vendor, value: $0) }
                ))
                .accessibilityIdentifier("inspector-title-block-vendor-field")

                TextField("Author", text: Binding(
                    get: { metadata["author"] ?? "" },
                    set: { workspace.setDocumentProperty(key: "author", value: $0) }
                ))
                .accessibilityIdentifier("inspector-title-block-author-field")

                TextField("Date", text: Binding(
                    get: { metadata["date"] ?? "" },
                    set: { workspace.setDocumentProperty(key: "date", value: $0) }
                ))
                .accessibilityIdentifier("inspector-title-block-date-field")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
        .accessibilityIdentifier("drawing-sheet-inspector-view")
    }
}


