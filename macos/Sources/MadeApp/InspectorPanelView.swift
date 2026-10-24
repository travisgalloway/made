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

    static func displayVolume(_ valueInCubicMillimeters: Double, unit: LengthUnit) -> Double {
        let factor = unit.fromMillimeters(1.0)
        return valueInCubicMillimeters * (factor * factor * factor)
    }

    static func volumeAccessibilityValue(_ displayValue: Double, unit: LengthUnit) -> String {
        "\(displayValue.formatted(.number.precision(.fractionLength(1...3)))) \(unit.symbol)³"
    }

    static func displayMass(_ valueInKilograms: Double) -> (value: Double, unitSymbol: String) {
        if abs(valueInKilograms) < 0.1 && abs(valueInKilograms) > 0 {
            return (valueInKilograms * 1000.0, "g")
        } else {
            return (valueInKilograms, "kg")
        }
    }

    static func commitMass(_ displayValue: Double, unitSymbol: String) -> Double {
        if unitSymbol.lowercased() == "g" {
            return displayValue / 1000.0
        } else {
            return displayValue
        }
    }

    static func commitLengthDouble(_ displayValue: Double, unit: LengthUnit) -> Double {
        unit.toMillimeters(displayValue)
    }

    static func massAccessibilityValue(_ valueInKilograms: Double) -> String {
        let (val, sym) = displayMass(valueInKilograms)
        return "\(val.formatted(.number.precision(.fractionLength(1...3)))) \(sym)"
    }
}

struct InspectorPanelView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.openWindow) private var openWindow
    @State private var massPropertiesCoordSystem: MassPropertiesCoordinateSystem = .centroid

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
                if let selectedBOM = workspace.selectedDrawingBOMTable {
                    DrawingBOMTableInspectorView(table: selectedBOM)
                } else if let selectedAnnotation = workspace.selectedDrawingAnnotation {
                    DrawingAnnotationInspectorView(annotation: selectedAnnotation)
                } else if let selectedView = workspace.selectedDrawingView, let activeSheet = workspace.document.activeSheet {
                    DrawingViewInspectorView(view: selectedView, sheet: activeSheet)
                } else if let activeSheet = workspace.document.activeSheet {
                    DrawingSheetInspectorView(sheet: activeSheet)
                } else {
                    ContentUnavailableView("No Drawing Sheet", systemImage: "doc.text")
                }
            }
        } else if workspace.document.selection.count > 1 {
            multiSelectionView
        } else if let fixture = workspace.selectedSimulationFixture, let study = workspace.selectedSimulationStudy {
            ScrollView {
                InspectorSimulationFixtureView(study: study, fixture: fixture)
            }
        } else if let load = workspace.selectedSimulationLoad, let study = workspace.selectedSimulationStudy {
            ScrollView {
                InspectorSimulationLoadView(study: study, load: load)
            }
        } else if workspace.isSimulationMeshSelected, let study = workspace.selectedSimulationStudy {
            ScrollView {
                InspectorSimulationMeshView(study: study)
            }
        } else if workspace.isSimulationResultsSelected, let study = workspace.selectedSimulationStudy {
            ScrollView {
                InspectorSimulationResultsView(study: study)
            }
        } else if let study = workspace.selectedSimulationStudy {
            ScrollView {
                InspectorSimulationStudyView(study: study)
            }
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
                    massPropertiesSection(selected)
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
            if let materialName = obj.material.materialName, !materialName.isEmpty {
                LabeledContent("Material", value: materialName)
                    .accessibilityIdentifier("inspector-body-material-name")
            }

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

            Button {
                openWindow(id: MaterialLibraryView.windowID)
            } label: {
                Label("Browse Material Library…", systemImage: "books.vertical")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("browse-material-library-button")
        } header: {
            sectionHeader("Material")
        }
    }

    @ViewBuilder
    private func massPropertiesSection(_ obj: SceneObject) -> some View {
        InspectorMassPropertiesSection(
            solidId: obj.id,
            metadata: obj.metadata,
            isLocked: obj.isLocked
        )
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
            massPropertiesSection
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

    private var massPropertiesSection: some View {
        InspectorMassPropertiesSection(
            solidId: component.solidId,
            metadata: component.metadata,
            isLocked: component.isLocked
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

/// Inspector section for mass properties calculations and purchased part mass overrides (BL-MAT-04, BL-MAT-05, #257, #258).
struct InspectorMassPropertiesSection: View {
    @Environment(WorkspaceModel.self) private var workspace
    let solidId: SolidId
    let metadata: [String: String]
    var isLocked: Bool = false

    @State private var coordSystem: MassPropertiesCoordinateSystem = .centroid

    private var massOverride: MassOverride {
        MassOverride(metadata: metadata)
    }

    var body: some View {
        Section {
            Picker("Coordinates", selection: $coordSystem) {
                ForEach(MassPropertiesCoordinateSystem.allCases) { sys in
                    Text(sys.displayName).tag(sys)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("inspector-mass-properties-coordinate-system")

            Toggle("Purchased Part Override", isOn: Binding(
                get: { massOverride.isPurchased },
                set: { workspace.setPurchasedOverride(id: solidId, isPurchased: $0) }
            ))
            .disabled(isLocked)
            .accessibilityIdentifier("inspector-mass-override-toggle")

            if massOverride.isPurchased {
                let lengthUnit = workspace.document.settings.units.lengthUnit

                LabeledContent("Override Mass (kg)") {
                    TextField("Mass", text: Binding(
                        get: {
                            if let m = massOverride.overrideMass {
                                return String(m)
                            }
                            return ""
                        },
                        set: { newText in
                            let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            if trimmed.isEmpty {
                                workspace.setOverrideMass(id: solidId, massKg: nil)
                            } else if trimmed.hasSuffix("kg"), let val = Double(trimmed.dropLast(2).trimmingCharacters(in: .whitespaces)), val > 0, val.isFinite {
                                workspace.setOverrideMass(id: solidId, massKg: val)
                            } else if trimmed.hasSuffix("g"), let val = Double(trimmed.dropLast(1).trimmingCharacters(in: .whitespaces)), val > 0, val.isFinite {
                                workspace.setOverrideMass(id: solidId, massKg: val / 1000.0)
                            } else if let val = Double(trimmed), val > 0, val.isFinite {
                                workspace.setOverrideMass(id: solidId, massKg: val)
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .disabled(isLocked)
                    .accessibilityIdentifier("inspector-override-mass-input")
                }

                let currentCom = massOverride.overrideCenterOfMass
                LabeledContent("Override Center of Mass (\(lengthUnit.symbol))") {
                    HStack(spacing: 4) {
                        TextField("X", text: Binding(
                            get: {
                                if let xMm = currentCom?.x {
                                    let disp = InspectorUnitConversion.displayLength(xMm, unit: lengthUnit)
                                    return String(disp)
                                }
                                return ""
                            },
                            set: { updateCom(axis: 0, text: $0, currentCom: currentCom, unit: lengthUnit) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .disabled(isLocked)
                        .accessibilityIdentifier("inspector-override-com-x")

                        TextField("Y", text: Binding(
                            get: {
                                if let yMm = currentCom?.y {
                                    let disp = InspectorUnitConversion.displayLength(yMm, unit: lengthUnit)
                                    return String(disp)
                                }
                                return ""
                            },
                            set: { updateCom(axis: 1, text: $0, currentCom: currentCom, unit: lengthUnit) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .disabled(isLocked)
                        .accessibilityIdentifier("inspector-override-com-y")

                        TextField("Z", text: Binding(
                            get: {
                                if let zMm = currentCom?.z {
                                    let disp = InspectorUnitConversion.displayLength(zMm, unit: lengthUnit)
                                    return String(disp)
                                }
                                return ""
                            },
                            set: { updateCom(axis: 2, text: $0, currentCom: currentCom, unit: lengthUnit) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .disabled(isLocked)
                        .accessibilityIdentifier("inspector-override-com-z")
                    }
                }

                Button("Clear Overrides") {
                    workspace.clearMassOverrides(id: solidId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLocked)
                .accessibilityIdentifier("inspector-clear-mass-overrides-button")
            }

            if let props = workspace.massProperties(for: solidId, coordinateSystem: coordSystem) {
                let units = workspace.document.settings.units
                let (matName, density) = MassPropertiesCalculator.resolveMaterialDensity(for: solidId, in: workspace.document, userMaterials: workspace.userMaterials)
                let densityStr = "\(matName ?? "Standard"): \(String(format: "%.1f", density)) kg/m³"
                LabeledContent("Material & Density") {
                    Text(densityStr)
                        .accessibilityIdentifier("inspector-mass-density")
                        .monospaced()
                        .textSelection(.enabled)
                }

                let massStr = units.formatMass(props.mass)
                LabeledContent("Mass") {
                    HStack(spacing: 4) {
                        Text(massStr)
                            .accessibilityIdentifier("inspector-mass-value")
                            .monospaced()
                            .textSelection(.enabled)
                        if props.isMassOverridden {
                            Text("(Overridden)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("inspector-mass-override-badge")
                        }
                    }
                }

                let volStr = units.formatVolume(props.volume)
                LabeledContent("Volume") {
                    Text(volStr)
                        .accessibilityIdentifier("inspector-volume-value")
                        .monospaced()
                        .textSelection(.enabled)
                }

                let areaStr = units.formatArea(props.surfaceArea)
                LabeledContent("Surface Area") {
                    Text(areaStr)
                        .accessibilityIdentifier("inspector-surface-area-value")
                        .monospaced()
                        .textSelection(.enabled)
                }

                let cmX = units.formatLength(props.centerOfMass.x)
                let cmY = units.formatLength(props.centerOfMass.y)
                let cmZ = units.formatLength(props.centerOfMass.z)
                let cmStr = "(\(cmX), \(cmY), \(cmZ))"
                LabeledContent("Center of Mass") {
                    HStack(spacing: 4) {
                        Text(cmStr)
                            .accessibilityIdentifier("inspector-center-of-mass")
                            .monospaced()
                            .textSelection(.enabled)
                        if props.isCenterOfMassOverridden {
                            Text("(Overridden)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("inspector-center-of-mass-override-badge")
                        }
                    }
                }

                let ixxStr = String(format: "%.2e", props.inertiaTensor.ixx)
                let iyyStr = String(format: "%.2e", props.inertiaTensor.iyy)
                let izzStr = String(format: "%.2e", props.inertiaTensor.izz)
                let inertiaStr = "\(ixxStr), \(iyyStr), \(izzStr) kg·mm²"
                LabeledContent("Moments of Inertia") {
                    Text(inertiaStr)
                        .accessibilityIdentifier("inspector-moments-of-inertia")
                        .monospaced()
                        .textSelection(.enabled)
                }

                let i1Str = String(format: "%.2e", props.principalMoments.i1)
                let i2Str = String(format: "%.2e", props.principalMoments.i2)
                let i3Str = String(format: "%.2e", props.principalMoments.i3)
                let principalStr = "\(i1Str), \(i2Str), \(i3Str) kg·mm²"
                LabeledContent("Principal Moments") {
                    Text(principalStr)
                        .accessibilityIdentifier("inspector-principal-moments")
                        .monospaced()
                        .textSelection(.enabled)
                }

                Button {
                    let report = props.formattedReport(units: units)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                } label: {
                    Label("Copy Mass Properties", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("inspector-copy-mass-properties-button")
            } else {
                LabeledContent("Mass Properties") {
                    Text("Unavailable")
                        .accessibilityIdentifier("inspector-no-mass-properties")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Mass Properties")
        }
    }

    private func updateCom(axis: Int, text: String, currentCom: SIMD3<Double>?, unit: LengthUnit) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var com = currentCom ?? SIMD3<Double>(0, 0, 0)
        if trimmed.isEmpty {
            com[axis] = 0.0
            if currentCom == nil { return }
        } else if let val = Double(trimmed), val.isFinite {
            com[axis] = InspectorUnitConversion.commitLengthDouble(val, unit: unit)
        } else {
            return
        }
        workspace.setOverrideCenterOfMass(id: solidId, centerOfMassLocal: com)
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
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

// MARK: - Simulation Study Inspectors (BL-SIM-01, #157)

/// Inspector view for a simulation study root node.
struct InspectorSimulationStudyView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy

    var body: some View {
        let isActive = workspace.document.activeStudyId == study.id

        Form {
            Section {
                TextField("Name", text: Binding(
                    get: { study.name },
                    set: { newName in
                        workspace.renameSimulationStudy(id: study.id, name: newName)
                    }
                ))
                .accessibilityIdentifier("inspector-simulation-study-name")

                Picker("Study Type", selection: Binding(
                    get: { study.studyType },
                    set: { newType in
                        var copy = study
                        copy.studyType = newType
                        workspace.updateSimulationStudy(copy)
                    }
                )) {
                    ForEach(SimulationStudyType.allCases) { type in
                        Label(type.displayName, systemImage: type.systemImageName).tag(type)
                    }
                }
                .accessibilityIdentifier("inspector-simulation-study-type")

                Toggle("Active Study", isOn: Binding(
                    get: { isActive },
                    set: { active in
                        workspace.setActiveSimulationStudy(id: active ? study.id : nil)
                    }
                ))
                .accessibilityIdentifier("inspector-simulation-study-active-toggle")

                Picker("Coordinate System", selection: Binding(
                    get: { study.coordinateSystemId },
                    set: { newId in
                        var copy = study
                        copy.coordinateSystemId = newId
                        workspace.updateSimulationStudy(copy)
                    }
                )) {
                    Text("Global (World)").tag(UUID?.none)
                    ForEach(workspace.document.activeCoordinateSystems()) { ucs in
                        Text(ucs.name).tag(UUID?.some(ucs.id))
                    }
                }
                .accessibilityIdentifier("inspector-simulation-study-ucs-picker")
            } header: {
                sectionHeader("Study Identity", isFirst: true)
            }

            Section {
                LabeledContent("Target Geometry") {
                    Text(study.targets.isEmpty ? "All visible bodies" : "\(study.targets.count) target(s)")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Materials") {
                    Text("\(study.materials.count) assignment(s)")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Fixtures") {
                    Text("\(study.fixtures.count) constraint(s)")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Loads") {
                    Text("\(study.loads.count) load(s)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                sectionHeader("Model Scope")
            }

            Section {
                Picker("Solver Engine", selection: Binding(
                    get: { study.solver.engine },
                    set: { newEngine in
                        var copy = study.solver
                        copy.engine = newEngine
                        workspace.updateSimulationSolverConfiguration(studyId: study.id, solver: copy)
                    }
                )) {
                    ForEach(SimulationSolverEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }

                TextField("Max Iterations", value: Binding(
                    get: { study.solver.maxIterations },
                    set: { newIter in
                        var copy = study.solver
                        copy.maxIterations = max(1, newIter)
                        workspace.updateSimulationSolverConfiguration(studyId: study.id, solver: copy)
                    }
                ), format: .number)

                TextField("Tolerance", value: Binding(
                    get: { study.solver.convergenceTolerance },
                    set: { newTol in
                        var copy = study.solver
                        copy.convergenceTolerance = max(1e-12, newTol)
                        workspace.updateSimulationSolverConfiguration(studyId: study.id, solver: copy)
                    }
                ), format: .number)

                if study.studyType == .linearBuckling {
                    TextField("Buckling Modes", value: Binding(
                        get: { study.solver.bucklingModesCount },
                        set: { newCount in
                            var copy = study.solver
                            copy.bucklingModesCount = max(1, newCount)
                            workspace.updateSimulationSolverConfiguration(studyId: study.id, solver: copy)
                        }
                    ), format: .number)
                    .accessibilityIdentifier("inspector-study-solver-buckling-modes")
                }
            } header: {
                sectionHeader("Solver Configuration")
            }

            Section {
                let isRunning = workspace.isStudyRunning(study.id)
                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Solving…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            workspace.cancelSimulationStudy(id: study.id)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("inspector-simulation-cancel-study-button")
                    }
                } else {
                    Button {
                        workspace.runSimulationStudy(id: study.id)
                    } label: {
                        Label("Run Study", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("inspector-simulation-run-study-button")
                }
            } header: {
                sectionHeader("Solve")
            }

            Section {
                Button("Delete Study", role: .destructive) {
                    workspace.removeSimulationStudy(id: study.id)
                }
                .accessibilityIdentifier("inspector-simulation-delete-study-button")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
    }

    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isFirst { Divider() }
            Text(title).font(.headline)
        }
        .padding(.top, 8)
    }
}

/// Inspector view for a boundary fixture constraint.
struct InspectorSimulationFixtureView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy
    let fixture: SimulationFixture

    var body: some View {
        let studyUCSName: String? = {
            guard let ucsId = study.coordinateSystemId else { return nil }
            return workspace.document.activeCoordinateSystems().first(where: { $0.id == ucsId })?.name
        }()
        let lengthUnit = workspace.document.settings.units.lengthUnit

        return Form {
            Section {
                TextField("Name", text: Binding(
                    get: { fixture.name },
                    set: { newName in
                        var copy = fixture
                        copy.name = newName
                        workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                    }
                ))
                .accessibilityIdentifier("inspector-simulation-fixture-name")

                Picker("Constraint Type", selection: Binding(
                    get: { fixture.kind },
                    set: { newKind in
                        var copy = fixture
                        copy.kind = newKind
                        workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                    }
                )) {
                    ForEach(SimulationFixtureKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImageName).tag(kind)
                    }
                }
                .accessibilityIdentifier("inspector-simulation-fixture-type")
            } header: {
                sectionHeader("Fixture Identity", isFirst: true)
            }

            Section {
                Picker("Coordinate System", selection: Binding(
                    get: { fixture.coordinateSystemId },
                    set: { newId in
                        var copy = fixture
                        copy.coordinateSystemId = newId
                        workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                    }
                )) {
                    Text("Default (\(studyUCSName ?? "Global"))").tag(UUID?.none)
                    ForEach(workspace.document.activeCoordinateSystems()) { ucs in
                        Text(ucs.name).tag(UUID?.some(ucs.id))
                    }
                }
                .accessibilityIdentifier("inspector-simulation-fixture-ucs-picker")

                switch fixture.kind {
                case .fixed, .pinned:
                    Text("Constrains all translational degrees of freedom (Ux = Uy = Uz = 0).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                case .rollerSlider:
                    Toggle("Restrain X (Ux = 0)", isOn: Binding(
                        get: { fixture.isRestrainedX },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedX = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    Toggle("Restrain Y (Uy = 0)", isOn: Binding(
                        get: { fixture.isRestrainedY },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedY = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    Toggle("Restrain Z (Uz = 0)", isOn: Binding(
                        get: { fixture.isRestrainedZ },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedZ = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))

                case .symmetry:
                    Toggle("Restrain Normal X (Ux = 0)", isOn: Binding(
                        get: { fixture.isRestrainedX },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedX = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    .accessibilityIdentifier("inspector-simulation-fixture-symmetry-x")

                    Toggle("Restrain Normal Y (Uy = 0)", isOn: Binding(
                        get: { fixture.isRestrainedY },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedY = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    .accessibilityIdentifier("inspector-simulation-fixture-symmetry-y")

                    Toggle("Restrain Normal Z (Uz = 0)", isOn: Binding(
                        get: { fixture.isRestrainedZ },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedZ = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    .accessibilityIdentifier("inspector-simulation-fixture-symmetry-z")

                case .prescribedDisplacement:
                    Toggle("Restrain X", isOn: Binding(
                        get: { fixture.isRestrainedX },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedX = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    Toggle("Restrain Y", isOn: Binding(
                        get: { fixture.isRestrainedY },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedY = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    Toggle("Restrain Z", isOn: Binding(
                        get: { fixture.isRestrainedZ },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedZ = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))

                    LabeledContent("Prescribed X (\(lengthUnit.symbol))") {
                        TextField("X", value: Binding(
                            get: { SimulationUnitConversion.displayLength(fixture.prescribedDisplacement.x, unit: lengthUnit) },
                            set: { val in
                                var copy = fixture
                                copy.prescribedDisplacement.x = SimulationUnitConversion.commitLength(val, unit: lengthUnit)
                                workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                            }
                        ), format: .number)
                        .accessibilityIdentifier("inspector-simulation-fixture-prescribed-x")
                    }
                    LabeledContent("Prescribed Y (\(lengthUnit.symbol))") {
                        TextField("Y", value: Binding(
                            get: { SimulationUnitConversion.displayLength(fixture.prescribedDisplacement.y, unit: lengthUnit) },
                            set: { val in
                                var copy = fixture
                                copy.prescribedDisplacement.y = SimulationUnitConversion.commitLength(val, unit: lengthUnit)
                                workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                            }
                        ), format: .number)
                        .accessibilityIdentifier("inspector-simulation-fixture-prescribed-y")
                    }
                    LabeledContent("Prescribed Z (\(lengthUnit.symbol))") {
                        TextField("Z", value: Binding(
                            get: { SimulationUnitConversion.displayLength(fixture.prescribedDisplacement.z, unit: lengthUnit) },
                            set: { val in
                                var copy = fixture
                                copy.prescribedDisplacement.z = SimulationUnitConversion.commitLength(val, unit: lengthUnit)
                                workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                            }
                        ), format: .number)
                        .accessibilityIdentifier("inspector-simulation-fixture-prescribed-z")
                    }

                case .elasticSupport:
                    let stiffnessSymbol = SimulationUnitConversion.stiffnessUnitSymbol(unit: lengthUnit)
                    Toggle("Spring Foundation X", isOn: Binding(
                        get: { fixture.isRestrainedX },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedX = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    if fixture.isRestrainedX {
                        LabeledContent("Stiffness X (\(stiffnessSymbol))") {
                            TextField("Kx", value: Binding(
                                get: { SimulationUnitConversion.displayStiffness(fixture.elasticStiffness.x, unit: lengthUnit) },
                                set: { val in
                                    var copy = fixture
                                    copy.elasticStiffness.x = max(0, SimulationUnitConversion.commitStiffness(val, unit: lengthUnit))
                                    workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                                }
                            ), format: .number)
                            .accessibilityIdentifier("inspector-simulation-fixture-stiffness-x")
                        }
                    }

                    Toggle("Spring Foundation Y", isOn: Binding(
                        get: { fixture.isRestrainedY },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedY = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    if fixture.isRestrainedY {
                        LabeledContent("Stiffness Y (\(stiffnessSymbol))") {
                            TextField("Ky", value: Binding(
                                get: { SimulationUnitConversion.displayStiffness(fixture.elasticStiffness.y, unit: lengthUnit) },
                                set: { val in
                                    var copy = fixture
                                    copy.elasticStiffness.y = max(0, SimulationUnitConversion.commitStiffness(val, unit: lengthUnit))
                                    workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                                }
                            ), format: .number)
                            .accessibilityIdentifier("inspector-simulation-fixture-stiffness-y")
                        }
                    }

                    Toggle("Spring Foundation Z", isOn: Binding(
                        get: { fixture.isRestrainedZ },
                        set: { val in
                            var copy = fixture
                            copy.isRestrainedZ = val
                            workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                        }
                    ))
                    if fixture.isRestrainedZ {
                        LabeledContent("Stiffness Z (\(stiffnessSymbol))") {
                            TextField("Kz", value: Binding(
                                get: { SimulationUnitConversion.displayStiffness(fixture.elasticStiffness.z, unit: lengthUnit) },
                                set: { val in
                                    var copy = fixture
                                    copy.elasticStiffness.z = max(0, SimulationUnitConversion.commitStiffness(val, unit: lengthUnit))
                                    workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                                }
                            ), format: .number)
                            .accessibilityIdentifier("inspector-simulation-fixture-stiffness-z")
                        }
                    }
                }
            } header: {
                sectionHeader("Kinematic Restraints")
            }

            Section {
                if fixture.targetReferences.isEmpty && fixture.groupNames.isEmpty {
                    LabeledContent("Targets") {
                        Text("All boundary surfaces")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(fixture.targetReferences) { ref in
                        HStack {
                            Label(ref.targetName.isEmpty ? "Target Entity" : ref.targetName, systemImage: "target")
                            Spacer()
                            Button {
                                workspace.removeTargetReferenceFromFixture(studyId: study.id, fixtureId: fixture.id, referenceId: ref.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("inspector-simulation-fixture-remove-target-\(ref.id)")
                        }
                    }
                    ForEach(fixture.groupNames, id: \.self) { gName in
                        HStack {
                            Label(gName, systemImage: "folder")
                            Spacer()
                            Button {
                                var copy = fixture
                                copy.groupNames.removeAll { $0 == gName }
                                workspace.updateSimulationFixture(studyId: study.id, fixture: copy)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button {
                    workspace.assignSelectedSubElementToFixture(studyId: study.id, fixtureId: fixture.id)
                } label: {
                    Label("Assign Active Selection", systemImage: "plus.circle")
                }
                .disabled(workspace.document.selectedSubElement == nil)
                .accessibilityIdentifier("inspector-simulation-assign-selection-button")

                Button("Delete Fixture", role: .destructive) {
                    workspace.removeSimulationFixture(studyId: study.id, fixtureId: fixture.id)
                }
                .accessibilityIdentifier("inspector-simulation-delete-fixture-button")
            } header: {
                sectionHeader("Targets & Actions")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
    }

    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isFirst { Divider() }
            Text(title).font(.headline)
        }
        .padding(.top, 8)
    }
}

/// Inspector view for a mechanical or thermal load.
struct InspectorSimulationLoadView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy
    let load: SimulationLoad

    var body: some View {
        let studyUCSName: String? = {
            guard let ucsId = study.coordinateSystemId else { return nil }
            return workspace.document.activeCoordinateSystems().first(where: { $0.id == ucsId })?.name
        }()
        let lengthUnit = workspace.document.settings.units.lengthUnit
        let unitSymbol = SimulationUnitConversion.loadUnitSymbol(kind: load.kind, unit: lengthUnit)

        return Form {
            Section {
                TextField("Name", text: Binding(
                    get: { load.name },
                    set: { newName in
                        var copy = load
                        copy.name = newName
                        workspace.updateSimulationLoad(studyId: study.id, load: copy)
                    }
                ))
                .accessibilityIdentifier("inspector-simulation-load-name")

                Picker("Load Type", selection: Binding(
                    get: { load.kind },
                    set: { newKind in
                        var copy = load
                        copy.kind = newKind
                        workspace.updateSimulationLoad(studyId: study.id, load: copy)
                    }
                )) {
                    ForEach(SimulationLoadKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImageName).tag(kind)
                    }
                }
                .accessibilityIdentifier("inspector-simulation-load-type")
            } header: {
                sectionHeader("Load Identity", isFirst: true)
            }

            Section {
                Picker("Coordinate System", selection: Binding(
                    get: { load.coordinateSystemId },
                    set: { newId in
                        var copy = load
                        copy.coordinateSystemId = newId
                        workspace.updateSimulationLoad(studyId: study.id, load: copy)
                    }
                )) {
                    Text("Default (\(studyUCSName ?? "Global"))").tag(UUID?.none)
                    ForEach(workspace.document.activeCoordinateSystems()) { ucs in
                        Text(ucs.name).tag(UUID?.some(ucs.id))
                    }
                }
                .accessibilityIdentifier("inspector-simulation-load-ucs-picker")

                LabeledContent("Magnitude (\(unitSymbol))") {
                    TextField("Magnitude", value: Binding(
                        get: { SimulationUnitConversion.displayLoadMagnitude(load.magnitude, kind: load.kind, unit: lengthUnit) },
                        set: { val in
                            var copy = load
                            copy.magnitude = SimulationUnitConversion.commitLoadMagnitude(val, kind: load.kind, unit: lengthUnit)
                            workspace.updateSimulationLoad(studyId: study.id, load: copy)
                        }
                    ), format: .number)
                    .accessibilityIdentifier("inspector-simulation-load-magnitude")
                }

                if load.kind == .force {
                    Picker("Force Distribution", selection: Binding(
                        get: { load.forceDistribution },
                        set: { newDist in
                            var copy = load
                            copy.forceDistribution = newDist
                            workspace.updateSimulationLoad(studyId: study.id, load: copy)
                        }
                    )) {
                        ForEach(SimulationForceDistribution.allCases) { dist in
                            Text(dist.displayName).tag(dist)
                        }
                    }
                    .accessibilityIdentifier("inspector-simulation-load-distribution")
                }

                if load.kind == .convection {
                    LabeledContent("Ambient Temperature (\(SimulationUnitConversion.temperatureUnitSymbol(unit: lengthUnit)))") {
                        TextField("Ambient Temperature", value: Binding(
                            get: { SimulationUnitConversion.displayTemperature(load.ambientTemperature ?? 20.0, unit: lengthUnit) },
                            set: { val in
                                var copy = load
                                copy.ambientTemperature = SimulationUnitConversion.commitTemperature(val, unit: lengthUnit)
                                workspace.updateSimulationLoad(studyId: study.id, load: copy)
                            }
                        ), format: .number)
                        .accessibilityIdentifier("inspector-simulation-load-ambient-temperature")
                    }
                }

                if load.kind == .thermalLoad || load.kind == .temperature {
                    LabeledContent("Reference Temperature (\(SimulationUnitConversion.temperatureUnitSymbol(unit: lengthUnit)))") {
                        TextField("Reference Temperature", value: Binding(
                            get: { SimulationUnitConversion.displayTemperature(load.referenceTemperature ?? 20.0, unit: lengthUnit) },
                            set: { val in
                                var copy = load
                                copy.referenceTemperature = SimulationUnitConversion.commitTemperature(val, unit: lengthUnit)
                                workspace.updateSimulationLoad(studyId: study.id, load: copy)
                            }
                        ), format: .number)
                        .accessibilityIdentifier("inspector-simulation-load-reference-temperature")
                    }
                }

                let hasDirection = load.kind == .force || load.kind == .gravity || load.kind == .moment || load.kind == .remoteLoad || load.kind == .bearing || load.kind == .centrifugal
                if hasDirection {
                    LabeledContent("Direction (X, Y, Z)") {
                        HStack(spacing: 4) {
                            TextField("X", value: Binding(
                                get: { load.direction.x },
                                set: { val in
                                    var copy = load
                                    copy.direction.x = val
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                            TextField("Y", value: Binding(
                                get: { load.direction.y },
                                set: { val in
                                    var copy = load
                                    copy.direction.y = val
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                            TextField("Z", value: Binding(
                                get: { load.direction.z },
                                set: { val in
                                    var copy = load
                                    copy.direction.z = val
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                        }
                    }
                }

                if load.kind == .remoteLoad {
                    LabeledContent("Remote Point (X, Y, Z)") {
                        HStack(spacing: 4) {
                            TextField("X", value: Binding(
                                get: { load.remotePoint?.x ?? 0.0 },
                                set: { val in
                                    var copy = load
                                    var pt = copy.remotePoint ?? .zero
                                    pt.x = val
                                    copy.remotePoint = pt
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                            TextField("Y", value: Binding(
                                get: { load.remotePoint?.y ?? 0.0 },
                                set: { val in
                                    var copy = load
                                    var pt = copy.remotePoint ?? .zero
                                    pt.y = val
                                    copy.remotePoint = pt
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                            TextField("Z", value: Binding(
                                get: { load.remotePoint?.z ?? 0.0 },
                                set: { val in
                                    var copy = load
                                    var pt = copy.remotePoint ?? .zero
                                    pt.z = val
                                    copy.remotePoint = pt
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                        }
                        .accessibilityIdentifier("inspector-simulation-load-remote-point")
                    }
                }

                if load.kind == .centrifugal {
                    LabeledContent("Axis Origin (X, Y, Z)") {
                        HStack(spacing: 4) {
                            TextField("X", value: Binding(
                                get: { load.axisOrigin?.x ?? 0.0 },
                                set: { val in
                                    var copy = load
                                    var pt = copy.axisOrigin ?? .zero
                                    pt.x = val
                                    copy.axisOrigin = pt
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                            TextField("Y", value: Binding(
                                get: { load.axisOrigin?.y ?? 0.0 },
                                set: { val in
                                    var copy = load
                                    var pt = copy.axisOrigin ?? .zero
                                    pt.y = val
                                    copy.axisOrigin = pt
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                            TextField("Z", value: Binding(
                                get: { load.axisOrigin?.z ?? 0.0 },
                                set: { val in
                                    var copy = load
                                    var pt = copy.axisOrigin ?? .zero
                                    pt.z = val
                                    copy.axisOrigin = pt
                                    workspace.updateSimulationLoad(studyId: study.id, load: copy)
                                }
                            ), format: .number)
                        }
                        .accessibilityIdentifier("inspector-simulation-load-axis-origin")
                    }
                }
            } header: {
                sectionHeader("Load Magnitude & Vector")
            }

            Section {
                if load.targetReferences.isEmpty && load.groupNames.isEmpty {
                    LabeledContent("Targets") {
                        Text((load.kind == .gravity || load.kind == .centrifugal || load.kind == .thermalLoad) ? "All volume elements" : "All boundary surfaces")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(load.targetReferences) { ref in
                        HStack {
                            Label(ref.targetName.isEmpty ? "Target Entity" : ref.targetName, systemImage: "target")
                            Spacer()
                            Button {
                                workspace.removeTargetReferenceFromLoad(studyId: study.id, loadId: load.id, referenceId: ref.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("inspector-simulation-load-remove-target-\(ref.id)")
                        }
                    }
                    ForEach(load.groupNames, id: \.self) { gName in
                        HStack {
                            Label(gName, systemImage: "folder")
                            Spacer()
                            Button {
                                var copy = load
                                copy.groupNames.removeAll { $0 == gName }
                                workspace.updateSimulationLoad(studyId: study.id, load: copy)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button {
                    workspace.assignSelectedSubElementToLoad(studyId: study.id, loadId: load.id)
                } label: {
                    Label("Assign Active Selection", systemImage: "plus.circle")
                }
                .disabled(workspace.document.selectedSubElement == nil)
                .accessibilityIdentifier("inspector-simulation-assign-selection-button")

                Button("Delete Load", role: .destructive) {
                    workspace.removeSimulationLoad(studyId: study.id, loadId: load.id)
                }
                .accessibilityIdentifier("inspector-simulation-delete-load-button")
            } header: {
                sectionHeader("Targets & Actions")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
    }

    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isFirst { Divider() }
            Text(title).font(.headline)
        }
        .padding(.top, 8)
    }
}

/// Inspector view for finite element volume mesh parameters.
struct InspectorSimulationMeshView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy

    var body: some View {
        Form {
            Section {
                let isMeshing = workspace.isStudyMeshing(study.id)
                if isMeshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating Mesh…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            workspace.cancelSimulationMesh(studyId: study.id)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("inspector-simulation-mesh-cancel-button")
                    }
                } else {
                    Button {
                        workspace.generateSimulationMesh(studyId: study.id)
                    } label: {
                        Label("Generate Mesh", systemImage: "cube.transparent")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("inspector-simulation-mesh-generate-button")
                }

                if let error = study.results.errorMessage, !error.isEmpty, study.results.status == .failed {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                sectionHeader("Mesh Generation", isFirst: true)
            }

            Section {
                Picker("Element Order", selection: Binding(
                    get: { study.mesh.elementOrder },
                    set: { newOrder in
                        var copy = study.mesh
                        copy.elementOrder = newOrder
                        workspace.updateSimulationMeshSpecification(studyId: study.id, mesh: copy)
                    }
                )) {
                    ForEach(MeshElementOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .accessibilityIdentifier("inspector-simulation-mesh-order")

                LabeledContent("Target Element Size (mm)") {
                    TextField("Target Size", value: Binding(
                        get: { study.mesh.targetElementSize },
                        set: { val in
                            var copy = study.mesh
                            copy.targetElementSize = max(0.1, val)
                            if copy.minElementSize > copy.targetElementSize {
                                copy.minElementSize = copy.targetElementSize
                            }
                            workspace.updateSimulationMeshSpecification(studyId: study.id, mesh: copy)
                        }
                    ), format: .number)
                    .accessibilityIdentifier("inspector-simulation-mesh-target-size")
                }

                LabeledContent("Min Element Size (mm)") {
                    TextField("Min Size", value: Binding(
                        get: { study.mesh.minElementSize },
                        set: { val in
                            var copy = study.mesh
                            copy.minElementSize = max(0.01, min(val, copy.targetElementSize))
                            workspace.updateSimulationMeshSpecification(studyId: study.id, mesh: copy)
                        }
                    ), format: .number)
                    .accessibilityIdentifier("inspector-simulation-mesh-min-size")
                }

                LabeledContent("Growth Rate") {
                    TextField("Growth Rate", value: Binding(
                        get: { study.mesh.growthRate },
                        set: { val in
                            var copy = study.mesh
                            copy.growthRate = max(1.0, val)
                            workspace.updateSimulationMeshSpecification(studyId: study.id, mesh: copy)
                        }
                    ), format: .number)
                    .accessibilityIdentifier("inspector-simulation-mesh-growth-rate")
                }

                Toggle("Curvature Refinement", isOn: Binding(
                    get: { study.mesh.curvatureRefinement },
                    set: { enabled in
                        var copy = study.mesh
                        copy.curvatureRefinement = enabled
                        workspace.updateSimulationMeshSpecification(studyId: study.id, mesh: copy)
                    }
                ))
                .accessibilityIdentifier("inspector-simulation-mesh-curvature-refinement")

                if study.mesh.curvatureRefinement {
                    LabeledContent("Elements Per Circle") {
                        TextField("Elements Per Circle", value: Binding(
                            get: { study.mesh.curvatureElementsPerCircle },
                            set: { val in
                                var copy = study.mesh
                                copy.curvatureElementsPerCircle = max(3.0, val)
                                workspace.updateSimulationMeshSpecification(studyId: study.id, mesh: copy)
                            }
                        ), format: .number)
                        .accessibilityIdentifier("inspector-simulation-mesh-curvature-elements-per-circle")
                    }
                }
            } header: {
                sectionHeader("Volume Meshing Specification")
            }

            Section {
                Button {
                    workspace.addMeshRefinementRegion(studyId: study.id)
                } label: {
                    Label("Add Refinement Region", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("inspector-simulation-mesh-add-refinement-button")

                if study.mesh.refinementRegions.isEmpty {
                    Text("No local refinement regions defined.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(study.mesh.refinementRegions) { region in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Region Name", text: Binding(
                                    get: { region.name },
                                    set: { newName in
                                        var copy = region
                                        copy.name = newName
                                        workspace.updateMeshRefinementRegion(studyId: study.id, region: copy)
                                    }
                                ))
                                .accessibilityIdentifier("inspector-simulation-mesh-region-name-\(region.id)")

                                Spacer()

                                Button {
                                    workspace.removeMeshRefinementRegion(studyId: study.id, regionId: region.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("inspector-simulation-mesh-delete-region-\(region.id)")
                            }

                            LabeledContent("Target Size (mm)") {
                                TextField("Size", value: Binding(
                                    get: { region.targetElementSize },
                                    set: { newSize in
                                        var copy = region
                                        copy.targetElementSize = max(0.0001, newSize)
                                        workspace.updateMeshRefinementRegion(studyId: study.id, region: copy)
                                    }
                                ), format: .number)
                                .accessibilityIdentifier("inspector-simulation-mesh-region-size-\(region.id)")
                            }

                            if region.targetReferences.isEmpty {
                                Text("No targets assigned")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(region.targetReferences) { ref in
                                    HStack {
                                        Label(ref.targetName.isEmpty ? "Target Entity" : ref.targetName, systemImage: "target")
                                        Spacer()
                                        Button {
                                            workspace.removeTargetFromRefinementRegion(studyId: study.id, regionId: region.id, referenceId: ref.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityIdentifier("inspector-simulation-mesh-remove-region-target-\(ref.id)")
                                    }
                                }
                            }

                            Button {
                                workspace.assignActiveSelectionToRefinementRegion(studyId: study.id, regionId: region.id)
                            } label: {
                                Label("Assign Active Selection", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(workspace.document.selectedSubElement == nil && workspace.selectedBody == nil)
                            .accessibilityIdentifier("inspector-simulation-mesh-assign-region-target-\(region.id)")
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                sectionHeader("Local Refinement")
            }

            Section {
                Toggle("Show Mesh", isOn: Binding(
                    get: { study.meshDisplay.isVisible },
                    set: { val in
                        var copy = study.meshDisplay
                        copy.isVisible = val
                        workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                    }
                ))
                .accessibilityIdentifier("inspector-simulation-mesh-display-visibility-toggle")

                if study.meshDisplay.isVisible {
                    Toggle("Show Edges", isOn: Binding(
                        get: { study.meshDisplay.showEdges },
                        set: { val in
                            var copy = study.meshDisplay
                            copy.showEdges = val
                            workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                        }
                    ))
                    .accessibilityIdentifier("inspector-simulation-mesh-display-edges-toggle")

                    Toggle("Show Faces", isOn: Binding(
                        get: { study.meshDisplay.showFaces },
                        set: { val in
                            var copy = study.meshDisplay
                            copy.showFaces = val
                            workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                        }
                    ))
                    .accessibilityIdentifier("inspector-simulation-mesh-display-faces-toggle")

                    LabeledContent("Element Shrink") {
                        Slider(value: Binding(
                            get: { study.meshDisplay.elementShrink },
                            set: { val in
                                var copy = study.meshDisplay
                                copy.elementShrink = val
                                workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                            }
                        ), in: 0.0...0.9, step: 0.05)
                        .accessibilityIdentifier("inspector-simulation-mesh-display-shrink-slider")
                    }

                    Toggle("Slice Mesh", isOn: Binding(
                        get: { study.meshDisplay.isSliceEnabled },
                        set: { val in
                            var copy = study.meshDisplay
                            copy.isSliceEnabled = val
                            workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                        }
                    ))
                    .accessibilityIdentifier("inspector-simulation-mesh-display-slice-toggle")

                    if study.meshDisplay.isSliceEnabled {
                        Picker("Slice Axis", selection: Binding(
                            get: { study.meshDisplay.sliceAxis },
                            set: { val in
                                var copy = study.meshDisplay
                                copy.sliceAxis = val
                                workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                            }
                        )) {
                            ForEach(MeshSliceAxis.allCases) { axis in
                                Text(axis.displayName).tag(axis)
                            }
                        }
                        .accessibilityIdentifier("inspector-simulation-mesh-display-slice-axis-picker")

                        LabeledContent("Slice Position") {
                            Slider(value: Binding(
                                get: { study.meshDisplay.slicePosition },
                                set: { val in
                                    var copy = study.meshDisplay
                                    copy.slicePosition = val
                                    workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                                }
                            ), in: 0.0...1.0)
                            .accessibilityIdentifier("inspector-simulation-mesh-display-slice-position-slider")
                        }

                        Toggle("Invert Slice Direction", isOn: Binding(
                            get: { study.meshDisplay.isSliceInverted },
                            set: { val in
                                var copy = study.meshDisplay
                                copy.isSliceInverted = val
                                workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                            }
                        ))
                        .accessibilityIdentifier("inspector-simulation-mesh-display-slice-invert-toggle")
                    }

                    Toggle("Hide CAD Solid Body", isOn: Binding(
                        get: { study.meshDisplay.hideSolidBody },
                        set: { val in
                            var copy = study.meshDisplay
                            copy.hideSolidBody = val
                            workspace.updateSimulationMeshDisplaySettings(studyId: study.id, settings: copy)
                        }
                    ))
                    .accessibilityIdentifier("inspector-simulation-mesh-display-hide-solid-toggle")
                }
            } header: {
                sectionHeader("Mesh Display")
            }

            if study.results.meshStatistics.elementCount > 0 {
                Section {
                    LabeledContent("Total Nodes") {
                        Text("\(study.results.meshStatistics.nodeCount)")
                            .accessibilityIdentifier("inspector-simulation-mesh-node-count")
                    }
                    LabeledContent("Total Elements") {
                        Text("\(study.results.meshStatistics.elementCount)")
                            .accessibilityIdentifier("inspector-simulation-mesh-element-count")
                    }
                    LabeledContent("Polynomial Order") {
                        Text(study.mesh.elementOrder.displayName)
                    }
                    LabeledContent("Avg Quality") {
                        Text(String(format: "%.3f", study.results.meshStatistics.avgElementQuality))
                    }
                    LabeledContent("Min Quality") {
                        Text(String(format: "%.3f", study.results.meshStatistics.minElementQuality))
                    }
                    if let duration = study.results.runtimeDuration, duration > 0 {
                        LabeledContent("Duration") {
                            Text(String(format: "%.2f s", duration))
                        }
                    }
                } header: {
                    sectionHeader("Mesh Statistics")
                }

                let qualityReport = study.results.meshStatistics.qualityReport
                    ?? workspace.cachedStudyMeshes[study.id]?.statistics.qualityReport
                    ?? (workspace.cachedStudyMeshes[study.id].map { MeshQualityCalculator.evaluate(mesh: $0) })
                    ?? MeshQualityReport()

                Section {
                    Picker("Metric", selection: Binding(
                        get: { workspace.selectedMeshQualityMetric },
                        set: { workspace.selectMeshQualityMetric($0) }
                    )) {
                        ForEach(MeshQualityMetricKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("inspector-simulation-mesh-quality-picker")

                    let summary = qualityReport.summary(for: workspace.selectedMeshQualityMetric)

                    LabeledContent("Min") {
                        Text(String(format: "%.3f", summary.minValue))
                            .accessibilityIdentifier("inspector-simulation-mesh-quality-min")
                    }
                    LabeledContent("Max") {
                        Text(String(format: "%.3f", summary.maxValue))
                            .accessibilityIdentifier("inspector-simulation-mesh-quality-max")
                    }
                    LabeledContent("Avg") {
                        Text(String(format: "%.3f", summary.averageValue))
                            .accessibilityIdentifier("inspector-simulation-mesh-quality-avg")
                    }
                    LabeledContent("Failing") {
                        Text("\(summary.failingCount) (\(String(format: "%.1f", summary.failingPercentage))%)")
                            .accessibilityIdentifier("inspector-simulation-mesh-quality-failing-count")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Distribution")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let maxBinCount = max(1, summary.histogramBins.map(\.count).max() ?? 1)
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(summary.histogramBins) { bin in
                                let height = max(4.0, (CGFloat(bin.count) / CGFloat(maxBinCount)) * 40.0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(bin.isFailing ? Color.red : Color.accentColor)
                                    .frame(height: height)
                                    .help("[\(String(format: "%.2f", bin.rangeMin)), \(String(format: "%.2f", bin.rangeMax))]: \(bin.count) elements\(bin.isFailing ? " (Failing)" : "")")
                            }
                        }
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityIdentifier("inspector-simulation-mesh-quality-histogram")
                    }

                    HStack(spacing: 8) {
                        Button {
                            workspace.highlightFailingElements(studyId: study.id, metric: workspace.selectedMeshQualityMetric)
                        } label: {
                            Label("Highlight Failing", systemImage: "exclamationmark.triangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("inspector-simulation-mesh-quality-highlight-button")

                        Button {
                            workspace.clearMeshHighlight()
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(workspace.highlightedMeshElementIds.isEmpty)
                        .accessibilityIdentifier("inspector-simulation-mesh-quality-clear-button")
                    }
                } header: {
                    sectionHeader("Mesh Quality")
                }
            }

            if !study.results.meshSets.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(study.results.meshSets) { set in
                            HStack {
                                Text(set.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                if let subType = set.subelementType {
                                    Text(subType.rawValue.capitalized)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                } else {
                                    Text("Body")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                Text("\(set.nodeIds.count) nodes, \(set.elementIds.count) elements")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("inspector-simulation-mesh-sets-table")
                } header: {
                    sectionHeader("Mesh Sets")
                }
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
    }

    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isFirst { Divider() }
            Text(title).font(.headline)
        }
        .padding(.top, 8)
    }
}

/// Inspector view for simulation execution results and statistics.
struct InspectorSimulationResultsView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy
    @State private var selectedCoordinateSystemId: UUID? = nil
    @State private var selectedModeNumber: Int = 1

    var body: some View {
        Form {
            Section {
                let isRunning = workspace.isStudyRunning(study.id)

                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                        Text("Solving…")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: study.results.status.systemImageName)
                            .foregroundStyle(study.results.status == .completed ? Color.green : (study.results.status == .failed ? Color.red : Color.secondary))
                        Text(study.results.status.displayName)
                            .font(.headline)
                    }
                    Spacer()
                }
                .accessibilityIdentifier("inspector-simulation-results-status")

                if let duration = study.results.runtimeDuration {
                    LabeledContent("Execution Time") {
                        Text(String(format: "%.2f s", duration))
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = study.results.errorMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityIdentifier("inspector-simulation-results-error")
                }

                if isRunning {
                    Button("Cancel Solve") {
                        workspace.cancelSimulationStudy(id: study.id)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("inspector-simulation-results-cancel-button")
                } else {
                    Button {
                        workspace.runSimulationStudy(id: study.id)
                    } label: {
                        Label("Run Study", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("inspector-simulation-results-run-button")
                }
            } header: {
                sectionHeader("Execution Status", isFirst: true)
            }

            Section {
                LabeledContent("Mesh Nodes") {
                    Text("\(study.results.meshStatistics.nodeCount)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Tetrahedral Elements") {
                    Text("\(study.results.meshStatistics.elementCount)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Min Element Quality") {
                    Text(String(format: "%.3f", study.results.meshStatistics.minElementQuality))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Avg Element Quality") {
                    Text(String(format: "%.3f", study.results.meshStatistics.avgElementQuality))
                        .foregroundStyle(.secondary)
                }
            } header: {
                sectionHeader("Discretization Statistics")
            }

            if let modes = study.results.bucklingModes, !modes.isEmpty {
                Section {
                    Picker("Buckling Mode", selection: Binding(
                        get: { selectedModeNumber },
                        set: { newMode in
                            selectedModeNumber = newMode
                            workspace.selectBucklingMode(studyId: study.id, modeNumber: newMode)
                        }
                    )) {
                        ForEach(modes) { mode in
                            Text("Mode \(mode.modeNumber): λ = \(String(format: "%.4g", mode.loadFactor))").tag(mode.modeNumber)
                        }
                    }
                    .accessibilityIdentifier("inspector-simulation-buckling-modes-picker")

                    ForEach(modes) { mode in
                        LabeledContent("Mode \(mode.modeNumber)") {
                            HStack {
                                Text("λ = \(String(format: "%.4g", mode.loadFactor))")
                                    .foregroundStyle(.secondary)
                                if selectedModeNumber == mode.modeNumber {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader("Buckling Modes")
                }
                .accessibilityIdentifier("inspector-simulation-buckling-modes-table")
            }

            if !study.results.extrema.isEmpty {
                Section {
                    Picker("Results Coordinate System", selection: $selectedCoordinateSystemId) {
                        Text("Global (World)").tag(UUID?.none)
                        ForEach(workspace.document.activeCoordinateSystems()) { ucs in
                            Text(ucs.name).tag(UUID?.some(ucs.id))
                        }
                    }
                    .accessibilityIdentifier("inspector-simulation-results-ucs-picker")

                    let lengthUnit = workspace.document.settings.units.lengthUnit
                    let ucsGeom = selectedCoordinateSystemId.flatMap { workspace.document.coordinateSystemGeometry(id: $0) }
                    let displayedExtrema = SimulationUnitConversion.displayExtrema(
                        study.results.extrema,
                        coordinateSystem: ucsGeom,
                        lengthUnit: lengthUnit
                    )

                    ForEach(displayedExtrema) { ext in
                        LabeledContent(ext.fieldName) {
                            Text("\(String(format: "%.3g", ext.minValue)) … \(String(format: "%.3g", ext.maxValue)) \(ext.unitSymbol)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    sectionHeader("Result Extrema")
                }
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
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
            let customKeys = metadata.keys.filter { !CustomPropertyKey.standardKeys.contains($0) && !CustomPropertyKey.massOverrideKeys.contains($0) }.sorted()
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
    @Environment(\.openWindow) private var openWindow
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
            if let materialName = workspace.document.settings.defaultMaterial.materialName, !materialName.isEmpty {
                LabeledContent("Material", value: materialName)
                    .accessibilityIdentifier("inspector-default-material-name")
            }

            ColorPicker("Default Color", selection: Binding(
                get: {
                    let c = workspace.document.settings.defaultMaterial.color
                    return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: Double(c.w))
                },
                set: { newColor in
                    let resolved = newColor.resolve(in: EnvironmentValues())
                    let simdColor = SIMD4<Float>(resolved.red, resolved.green, resolved.blue, 1.0)
                    var current = workspace.document.settings.defaultMaterial
                    current.color = simdColor
                    workspace.setDocumentDefaultMaterial(current)
                }
            ), supportsOpacity: false)

            Button {
                openWindow(id: MaterialLibraryView.windowID)
            } label: {
                Label("Browse Material Library…", systemImage: "books.vertical")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("browse-document-material-library-button")

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

                Picker("Projection Standard", selection: Binding(
                    get: { sheet.projectionAngle },
                    set: { newAngle in
                        var copy = sheet
                        copy.projectionAngle = newAngle
                        _ = workspace.updateSheet(copy)
                    }
                )) {
                    ForEach(DrawingProjectionAngle.allCases, id: \.self) { angle in
                        Text(angle.displayName).tag(angle)
                    }
                }
                .accessibilityIdentifier("inspector-sheet-projection-picker")
            }

            Section("Drafting Standards") {
                Picker("Standard", selection: Binding(
                    get: { sheet.draftingStandards.standard },
                    set: { newStandard in
                        var copy = sheet
                        switch newStandard {
                        case .iso:
                            copy.draftingStandards = .iso
                        case .ansi:
                            copy.draftingStandards = .ansi
                        case .custom:
                            copy.draftingStandards.standard = .custom
                        }
                        _ = workspace.updateSheet(copy)
                    }
                )) {
                    ForEach(DrawingStandard.allCases, id: \.self) { standard in
                        Text(standard.displayName).tag(standard)
                    }
                }
                .accessibilityIdentifier("inspector-sheet-drafting-standard-picker")

                HStack {
                    Button("Apply ISO Defaults") {
                        var copy = sheet
                        copy.draftingStandards = .iso
                        _ = workspace.updateSheet(copy)
                    }
                    .accessibilityIdentifier("inspector-sheet-apply-iso-defaults-button")

                    Button("Apply ANSI Defaults") {
                        var copy = sheet
                        copy.draftingStandards = .ansi
                        _ = workspace.updateSheet(copy)
                    }
                    .accessibilityIdentifier("inspector-sheet-apply-ansi-defaults-button")
                }

                DisclosureGroup("Arrow Defaults") {
                    Picker("Style", selection: Binding(
                        get: { sheet.draftingStandards.arrows.style },
                        set: { newStyle in
                            var copy = sheet
                            copy.draftingStandards.arrows.style = newStyle
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    )) {
                        ForEach(ArrowheadStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .accessibilityIdentifier("inspector-sheet-arrow-style-picker")

                    TextField("Length (mm)", value: Binding(
                        get: { sheet.draftingStandards.arrows.lengthMM },
                        set: { newLen in
                            var copy = sheet
                            copy.draftingStandards.arrows.lengthMM = newLen
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inspector-sheet-arrow-length-field")

                    TextField("Width (mm)", value: Binding(
                        get: { sheet.draftingStandards.arrows.widthMM },
                        set: { newWidth in
                            var copy = sheet
                            copy.draftingStandards.arrows.widthMM = newWidth
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inspector-sheet-arrow-width-field")
                }

                DisclosureGroup("Text Defaults") {
                    Picker("Placement", selection: Binding(
                        get: { sheet.draftingStandards.text.placement },
                        set: { newPlace in
                            var copy = sheet
                            copy.draftingStandards.text.placement = newPlace
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    )) {
                        ForEach(DimensionTextPlacement.allCases, id: \.self) { place in
                            Text(place.displayName).tag(place)
                        }
                    }
                    .accessibilityIdentifier("inspector-sheet-text-placement-picker")

                    Picker("Decimal Separator", selection: Binding(
                        get: { sheet.draftingStandards.text.decimalSeparator },
                        set: { newSep in
                            var copy = sheet
                            copy.draftingStandards.text.decimalSeparator = newSep
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    )) {
                        ForEach(DecimalSeparator.allCases, id: \.self) { sep in
                            Text(sep.displayName).tag(sep)
                        }
                    }
                    .accessibilityIdentifier("inspector-sheet-decimal-separator-picker")

                    Picker("Trailing Zeros", selection: Binding(
                        get: { sheet.draftingStandards.text.trailingZeros },
                        set: { newTZ in
                            var copy = sheet
                            copy.draftingStandards.text.trailingZeros = newTZ
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    )) {
                        ForEach(TrailingZeroDisplay.allCases, id: \.self) { tz in
                            Text(tz.displayName).tag(tz)
                        }
                    }
                    .accessibilityIdentifier("inspector-sheet-trailing-zeros-picker")

                    TextField("Text Height (mm)", value: Binding(
                        get: { sheet.draftingStandards.text.textHeightMM },
                        set: { newH in
                            var copy = sheet
                            copy.draftingStandards.text.textHeightMM = newH
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inspector-sheet-text-height-field")
                }

                DisclosureGroup("Tolerance Defaults") {
                    Picker("Default Type", selection: Binding(
                        get: { sheet.draftingStandards.tolerances.defaultType },
                        set: { newType in
                            var copy = sheet
                            copy.draftingStandards.tolerances.defaultType = newType
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    )) {
                        ForEach(DraftingToleranceType.allCases, id: \.self) { tolType in
                            Text(tolType.displayName).tag(tolType)
                        }
                    }
                    .accessibilityIdentifier("inspector-sheet-tolerance-default-type-picker")

                    TextField("Linear Tolerance (mm)", value: Binding(
                        get: { sheet.draftingStandards.tolerances.linearToleranceMM },
                        set: { newTol in
                            var copy = sheet
                            copy.draftingStandards.tolerances.linearToleranceMM = newTol
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inspector-sheet-linear-tolerance-field")

                    TextField("Angular Tolerance (°)", value: Binding(
                        get: { sheet.draftingStandards.tolerances.angularToleranceDeg },
                        set: { newAng in
                            var copy = sheet
                            copy.draftingStandards.tolerances.angularToleranceDeg = newAng
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inspector-sheet-angular-tolerance-field")

                    Stepper("Default Precision: \(sheet.draftingStandards.tolerances.precision)", value: Binding(
                        get: { sheet.draftingStandards.tolerances.precision },
                        set: { newPrec in
                            var copy = sheet
                            copy.draftingStandards.tolerances.precision = newPrec
                            copy.draftingStandards.standard = .custom
                            _ = workspace.updateSheet(copy)
                        }
                    ), in: 0...6)
                    .accessibilityIdentifier("inspector-sheet-tolerance-precision-stepper")
                }
            }

            Section("Views (\(sheet.views.count))") {
                Menu("Add Base View…") {
                    Button("Front") { _ = workspace.addBaseView(standardView: .front) }
                    Button("Top") { _ = workspace.addBaseView(standardView: .top) }
                    Button("Right") { _ = workspace.addBaseView(standardView: .right) }
                    Button("Back") { _ = workspace.addBaseView(standardView: .back) }
                    Button("Bottom") { _ = workspace.addBaseView(standardView: .bottom) }
                    Button("Left") { _ = workspace.addBaseView(standardView: .left) }
                    Divider()
                    Button("Isometric") { _ = workspace.addBaseView(standardView: .isometric) }
                }
                .accessibilityIdentifier("inspector-sheet-add-base-view-menu")

                ForEach(sheet.views) { v in
                    HStack {
                        Image(systemName: "rectangle.inset.filled")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                        Text(v.name)
                            .font(.caption)
                        Spacer()
                        Text(v.standardView.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("[\(v.scale.displayString)]")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        workspace.selectDrawingView(v.id)
                    }
                }
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

/// Inspector view for configuring placed drawing views (BL-DRW-03, #210).
struct DrawingViewInspectorView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let view: DrawingView
    let sheet: DrawingSheet

    var body: some View {
        Form {
            Section("View Setup") {
                LabeledContent("Kind") {
                    Text(view.kind.displayName)
                        .fontWeight(.medium)
                }
                .accessibilityIdentifier("inspector-view-kind-label")

                TextField("Name", text: Binding(
                    get: { view.name },
                    set: { newName in
                        var updated = view
                        updated.name = newName
                        _ = workspace.updateDrawingView(updated)
                    }
                ))
                .accessibilityIdentifier("inspector-view-name-field")

                Picker("Orientation", selection: Binding(
                    get: { view.standardView },
                    set: { newStdView in
                        var updated = view
                        updated.standardView = newStdView
                        _ = workspace.updateDrawingView(updated)
                        workspace.recomputeDrawingViewHLR(viewId: view.id)
                    }
                )) {
                    ForEach(HLRStandardView.allCases, id: \.self) { stdView in
                        Text(stdView.rawValue.capitalized).tag(stdView)
                    }
                }
                .accessibilityIdentifier("inspector-view-orientation-picker")

                Picker("Display Style", selection: Binding(
                    get: { view.displayStyle },
                    set: { newStyle in
                        var updated = view
                        updated.displayStyle = newStyle
                        _ = workspace.updateDrawingView(updated)
                        workspace.recomputeDrawingViewHLR(viewId: view.id)
                    }
                )) {
                    ForEach(DrawingDisplayStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .accessibilityIdentifier("inspector-view-display-style-picker")

                Picker("Scale", selection: Binding(
                    get: {
                        if DrawingViewScale.standardScales.contains(view.scale) {
                            return view.scale.displayString
                        }
                        return "custom"
                    },
                    set: { selectedStr in
                        var updated = view
                        if selectedStr != "custom", let parsed = DrawingViewScale.parse(selectedStr) {
                            updated.scale = parsed
                            _ = workspace.updateDrawingView(updated)
                        }
                    }
                )) {
                    ForEach(DrawingViewScale.standardScales, id: \.displayString) { scale in
                        Text(scale.displayString).tag(scale.displayString)
                    }
                    Text("Custom…").tag("custom")
                }
                .accessibilityIdentifier("inspector-view-scale-picker")

                if !DrawingViewScale.standardScales.contains(view.scale) {
                    HStack {
                        TextField("Numerator", value: Binding(
                            get: { view.scale.numerator },
                            set: { newNum in
                                var updated = view
                                updated.scale = DrawingViewScale(numerator: newNum, denominator: view.scale.denominator)
                                _ = workspace.updateDrawingView(updated)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)

                        Text(":")

                        TextField("Denominator", value: Binding(
                            get: { view.scale.denominator },
                            set: { newDen in
                                var updated = view
                                updated.scale = DrawingViewScale(numerator: view.scale.numerator, denominator: newDen)
                                _ = workspace.updateDrawingView(updated)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if view.kind == .section || view.sectionDefinition != nil {
                Section("Section Properties") {
                    TextField("Label", text: Binding(
                        get: { view.sectionDefinition?.label ?? "A" },
                        set: { newLabel in
                            var updated = view
                            var sec = updated.sectionDefinition ?? SectionLineDefinition()
                            sec.label = newLabel
                            updated.sectionDefinition = sec
                            _ = workspace.updateDrawingView(updated)
                        }
                    ))

                    Picker("Hatch Style", selection: Binding(
                        get: { view.hatchPattern?.style ?? .ansi31 },
                        set: { newStyle in
                            var updated = view
                            var pat = updated.hatchPattern ?? HatchPatternDefinition()
                            pat.style = newStyle
                            updated.hatchPattern = pat
                            _ = workspace.updateDrawingView(updated)
                            workspace.recomputeDrawingViewHLR(viewId: view.id)
                        }
                    )) {
                        ForEach(HatchPatternStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    TextField("Hatch Angle (°)", value: Binding(
                        get: { view.hatchPattern?.angleDegrees ?? 45.0 },
                        set: { newAngle in
                            var updated = view
                            var pat = updated.hatchPattern ?? HatchPatternDefinition()
                            pat.angleDegrees = newAngle
                            updated.hatchPattern = pat
                            _ = workspace.updateDrawingView(updated)
                            workspace.recomputeDrawingViewHLR(viewId: view.id)
                        }
                    ), format: .number)

                    TextField("Hatch Spacing (mm)", value: Binding(
                        get: { view.hatchPattern?.spacingMM ?? 3.0 },
                        set: { newSpacing in
                            var updated = view
                            var pat = updated.hatchPattern ?? HatchPatternDefinition()
                            pat.spacingMM = max(0.5, newSpacing)
                            updated.hatchPattern = pat
                            _ = workspace.updateDrawingView(updated)
                            workspace.recomputeDrawingViewHLR(viewId: view.id)
                        }
                    ), format: .number)
                }
            }

            if view.kind == .detail || view.detailDefinition != nil {
                Section("Detail Properties") {
                    TextField("Label", text: Binding(
                        get: { view.detailDefinition?.label ?? "B" },
                        set: { newLabel in
                            var updated = view
                            var det = updated.detailDefinition ?? DetailCircleDefinition()
                            det.label = newLabel
                            updated.detailDefinition = det
                            _ = workspace.updateDrawingView(updated)
                        }
                    ))

                    TextField("Radius (mm)", value: Binding(
                        get: { view.detailDefinition?.radiusMM ?? 15.0 },
                        set: { newRadius in
                            var updated = view
                            var det = updated.detailDefinition ?? DetailCircleDefinition()
                            det.radiusMM = max(1.0, newRadius)
                            updated.detailDefinition = det
                            _ = workspace.updateDrawingView(updated)
                            workspace.recomputeDrawingViewHLR(viewId: view.id)
                        }
                    ), format: .number)
                }
            }

            if view.kind == .auxiliary || view.auxiliaryDefinition != nil {
                Section("Auxiliary Properties") {
                    TextField("Label", text: Binding(
                        get: { view.auxiliaryDefinition?.label ?? "C" },
                        set: { newLabel in
                            var updated = view
                            var aux = updated.auxiliaryDefinition ?? AuxiliaryViewDefinition()
                            aux.label = newLabel
                            updated.auxiliaryDefinition = aux
                            _ = workspace.updateDrawingView(updated)
                        }
                    ))

                    TextField("Projection Angle (°)", value: Binding(
                        get: { view.auxiliaryDefinition?.angleDegrees ?? 45.0 },
                        set: { newAngle in
                            var updated = view
                            var aux = updated.auxiliaryDefinition ?? AuxiliaryViewDefinition()
                            aux.angleDegrees = newAngle
                            let derived = DrawingAuxiliaryDerivation.deriveDirection(
                                from: updated.effectiveViewDirection,
                                angleDegrees: newAngle
                            )
                            aux.customDirection = derived
                            updated.auxiliaryDefinition = aux
                            updated.customViewDirection = derived
                            _ = workspace.updateDrawingView(updated)
                            workspace.recomputeDrawingViewHLR(viewId: view.id)
                        }
                    ), format: .number)
                }
            }

            if view.kind == .broken || view.breakDefinition != nil {
                Section("Break View Properties") {
                    Picker("Orientation", selection: Binding(
                        get: { view.breakDefinition?.orientation ?? .horizontal },
                        set: { newOrient in
                            var updated = view
                            var brk = updated.breakDefinition ?? BreakViewDefinition()
                            brk.orientation = newOrient
                            updated.breakDefinition = brk
                            _ = workspace.updateDrawingView(updated)
                            workspace.recomputeDrawingViewHLR(viewId: view.id)
                        }
                    )) {
                        ForEach(BreakOrientation.allCases, id: \.self) { orient in
                            Text(orient.displayName).tag(orient)
                        }
                    }

                    Picker("Line Style", selection: Binding(
                        get: { view.breakDefinition?.style ?? .zigzag },
                        set: { newStyle in
                            var updated = view
                            var brk = updated.breakDefinition ?? BreakViewDefinition()
                            brk.style = newStyle
                            updated.breakDefinition = brk
                            _ = workspace.updateDrawingView(updated)
                            workspace.recomputeDrawingViewHLR(viewId: view.id)
                        }
                    )) {
                        ForEach(BreakLineStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    HStack {
                        TextField("Start (mm)", value: Binding(
                            get: { view.breakDefinition?.startMM ?? -10.0 },
                            set: { newStart in
                                var updated = view
                                var brk = updated.breakDefinition ?? BreakViewDefinition()
                                brk.startMM = newStart
                                updated.breakDefinition = brk
                                _ = workspace.updateDrawingView(updated)
                                workspace.recomputeDrawingViewHLR(viewId: view.id)
                            }
                        ), format: .number)

                        TextField("End (mm)", value: Binding(
                            get: { view.breakDefinition?.endMM ?? 10.0 },
                            set: { newEnd in
                                var updated = view
                                var brk = updated.breakDefinition ?? BreakViewDefinition()
                                brk.endMM = newEnd
                                updated.breakDefinition = brk
                                _ = workspace.updateDrawingView(updated)
                                workspace.recomputeDrawingViewHLR(viewId: view.id)
                            }
                        ), format: .number)
                    }

                    TextField("Gap (mm)", value: Binding(
                        get: { view.breakDefinition?.gapMM ?? 5.0 },
                        set: { newGap in
                            var updated = view
                            var brk = updated.breakDefinition ?? BreakViewDefinition()
                            brk.gapMM = max(1.0, newGap)
                            updated.breakDefinition = brk
                            _ = workspace.updateDrawingView(updated)
                            workspace.recomputeDrawingViewHLR(viewId: view.id)
                        }
                    ), format: .number)
                }
            }

            Section("Position (mm)") {
                HStack {
                    TextField("X", value: Binding(
                        get: { view.positionMM.x },
                        set: { newX in
                            let targetX = max(10.0, min(sheet.dimensionsMM.width - 10.0, newX))
                            _ = workspace.repositionDrawingView(id: view.id, positionMM: SIMD2(targetX, view.positionMM.y))
                        }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)

                    TextField("Y", value: Binding(
                        get: { view.positionMM.y },
                        set: { newY in
                            let targetY = max(10.0, min(sheet.dimensionsMM.height - 10.0, newY))
                            _ = workspace.repositionDrawingView(id: view.id, positionMM: SIMD2(view.positionMM.x, targetY))
                        }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                }
            }

            Section("Projected & Derived Views") {
                VStack(spacing: 6) {
                    HStack {
                        Button("Right") {
                            _ = workspace.addProjectedView(parentViewId: view.id, direction: .right)
                        }
                        Button("Left") {
                            _ = workspace.addProjectedView(parentViewId: view.id, direction: .left)
                        }
                        Button("Above") {
                            _ = workspace.addProjectedView(parentViewId: view.id, direction: .above)
                        }
                        Button("Below") {
                            _ = workspace.addProjectedView(parentViewId: view.id, direction: .below)
                        }
                    }
                    Button("Isometric Projection") {
                        _ = workspace.addProjectedView(parentViewId: view.id, direction: .isometricTopRight)
                    }

                    Divider()

                    HStack {
                        Button("Section View") {
                            _ = workspace.addSectionView(parentViewId: view.id)
                        }
                        Button("Detail View") {
                            _ = workspace.addDetailView(parentViewId: view.id)
                        }
                    }
                    HStack {
                        Button("Auxiliary View") {
                            _ = workspace.addAuxiliaryView(parentViewId: view.id)
                        }
                        Button("Broken View") {
                            _ = workspace.addBrokenView(parentViewId: view.id)
                        }
                    }
                }
            }

            Section("Annotations & Dimensions") {
                VStack(spacing: 6) {
                    HStack {
                        Button("Linear") {
                            _ = workspace.addLinearDimension(viewId: view.id, start: SIMD2(-20.0, 0.0), end: SIMD2(20.0, 0.0))
                        }
                        Button("Angular") {
                            _ = workspace.addAngularDimension(viewId: view.id, vertex: SIMD2(0.0, 0.0), start: SIMD2(20.0, 0.0), end: SIMD2(0.0, 20.0))
                        }
                        Button("Radial") {
                            _ = workspace.addRadialDimension(viewId: view.id, center: SIMD2(0.0, 0.0), arcPoint: SIMD2(15.0, 0.0))
                        }
                    }
                    HStack {
                        Button("Center Mark") {
                            _ = workspace.addCenterMark(viewId: view.id, center: SIMD2(0.0, 0.0))
                        }
                        Button("Hole Callout") {
                            let holeParam = workspace.document.features.compactMap { feat -> HoleParams? in
                                if case .hole(let data) = feat.operation { return data }
                                return nil
                            }.first
                            if let holeParam {
                                _ = workspace.addHoleCalloutFromHoleWizard(viewId: view.id, anchor: SIMD2(10.0, 0.0), elbow: SIMD2(25.0, 15.0), holeParams: holeParam)
                            } else {
                                _ = workspace.addHoleCallout(viewId: view.id, anchor: SIMD2(10.0, 0.0), elbow: SIMD2(25.0, 15.0), holeData: HoleCalloutAnnotationData(anchorPointMM: SIMD2(10.0, 0.0), elbowPointMM: SIMD2(25.0, 15.0)))
                            }
                        }
                    }
                }
            }

            Section {
                Button("Delete View", role: .destructive) {
                    _ = workspace.removeDrawingView(id: view.id)
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier("inspector-view-delete-button")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
        .accessibilityIdentifier("drawing-view-inspector-view")
    }
}

/// Inspector panel view for inspecting and modifying drawing annotations and dimensions (BL-DRW-05).
struct DrawingAnnotationInspectorView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let annotation: DrawingAnnotation

    var body: some View {
        Form {
            if annotation.isDangling {
                Section {
                    Label("Annotation reference is dangling. Referenced feature or view was removed or suppressed.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section("Annotation Details") {
                LabeledContent("Kind") {
                    Text(annotation.kind.displayName)
                        .fontWeight(.medium)
                }
                .accessibilityIdentifier("inspector-annotation-kind-label")

                TextField("Name", text: Binding(
                    get: { annotation.name },
                    set: { newName in
                        var updated = annotation
                        updated.name = newName
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                .accessibilityIdentifier("inspector-annotation-name-field")

                if let viewId = annotation.viewId,
                   let view = workspace.document.activeSheet?.views.first(where: { $0.id == viewId }) {
                    LabeledContent("Attached View") {
                        Text(view.name)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("Attachment") {
                        Text("Sheet-Level")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Visible", isOn: Binding(
                    get: { annotation.isVisible },
                    set: { newVis in
                        var updated = annotation
                        updated.isVisible = newVis
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
            }

            measurementSection

            toleranceSection

            holeSpecificationSection

            balloonSpecificationSection

            Section {
                Button("Delete Annotation", role: .destructive) {
                    _ = workspace.removeDrawingAnnotation(id: annotation.id)
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier("inspector-annotation-delete-button")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
        .accessibilityIdentifier("drawing-annotation-inspector-view")
    }

    @ViewBuilder
    private var measurementSection: some View {
        switch annotation.data {
        case .linear(let data):
            Section("Measurement & Text") {
                LabeledContent("Measured Value") {
                    Text(String(format: "%.2f mm", data.measuredValue))
                }
                TextField("Text Override", text: Binding(
                    get: { data.textOverride ?? "" },
                    set: { newOverride in
                        var updated = annotation
                        var d = data
                        d.textOverride = newOverride.isEmpty ? nil : newOverride
                        updated.data = .linear(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                Stepper("Precision: \(data.precision)", value: Binding(
                    get: { data.precision },
                    set: { newPrec in
                        var updated = annotation
                        var d = data
                        d.precision = max(0, min(6, newPrec))
                        updated.data = .linear(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ), in: 0...6)
                TextField("Prefix", text: Binding(
                    get: { data.prefix },
                    set: { newPrefix in
                        var updated = annotation
                        var d = data
                        d.prefix = newPrefix
                        updated.data = .linear(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                TextField("Suffix", text: Binding(
                    get: { data.suffix },
                    set: { newSuffix in
                        var updated = annotation
                        var d = data
                        d.suffix = newSuffix
                        updated.data = .linear(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
            }

        case .angular(let data):
            Section("Measurement & Text") {
                LabeledContent("Measured Angle") {
                    Text(String(format: "%.1f°", data.measuredDegrees))
                }
                TextField("Text Override", text: Binding(
                    get: { data.textOverride ?? "" },
                    set: { newOverride in
                        var updated = annotation
                        var d = data
                        d.textOverride = newOverride.isEmpty ? nil : newOverride
                        updated.data = .angular(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                Stepper("Precision: \(data.precision)", value: Binding(
                    get: { data.precision },
                    set: { newPrec in
                        var updated = annotation
                        var d = data
                        d.precision = max(0, min(4, newPrec))
                        updated.data = .angular(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ), in: 0...4)
            }

        case .radial(let data):
            Section("Measurement & Text") {
                LabeledContent(data.isDiameter ? "Measured Diameter" : "Measured Radius") {
                    Text(String(format: "%.2f mm", data.measuredValue))
                }
                Toggle("Is Diameter", isOn: Binding(
                    get: { data.isDiameter },
                    set: { newIsDia in
                        var updated = annotation
                        var d = data
                        d.isDiameter = newIsDia
                        updated.data = .radial(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                TextField("Text Override", text: Binding(
                    get: { data.textOverride ?? "" },
                    set: { newOverride in
                        var updated = annotation
                        var d = data
                        d.textOverride = newOverride.isEmpty ? nil : newOverride
                        updated.data = .radial(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
            }

        case .ordinate(let data):
            Section("Measurement & Text") {
                LabeledContent("Offset from Datum") {
                    Text(String(format: "%.2f mm", data.measuredValue))
                }
                TextField("Text Override", text: Binding(
                    get: { data.textOverride ?? "" },
                    set: { newOverride in
                        var updated = annotation
                        var d = data
                        d.textOverride = newOverride.isEmpty ? nil : newOverride
                        updated.data = .ordinate(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
            }

        case .note(let data):
            Section("Note Properties") {
                TextField("Text", text: Binding(
                    get: { data.text },
                    set: { newText in
                        var updated = annotation
                        var d = data
                        d.text = newText
                        updated.data = .note(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                Toggle("Bold", isOn: Binding(
                    get: { data.isBold },
                    set: { newBold in
                        var updated = annotation
                        var d = data
                        d.isBold = newBold
                        updated.data = .note(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                Toggle("Border Frame", isOn: Binding(
                    get: { data.hasBorder },
                    set: { newBorder in
                        var updated = annotation
                        var d = data
                        d.hasBorder = newBorder
                        updated.data = .note(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
            }

        case .leader(let data):
            Section("Leader Properties") {
                TextField("Text", text: Binding(
                    get: { data.text },
                    set: { newText in
                        var updated = annotation
                        var d = data
                        d.text = newText
                        updated.data = .leader(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var holeSpecificationSection: some View {
        if case .holeCallout(let data) = annotation.data {
            Section("Hole Specifications") {
                LabeledContent("Hole Type") {
                    Text(data.holeType.rawValue.capitalized)
                }
                LabeledContent("Standard") {
                    Text(data.standard.rawValue.uppercased())
                }
                if let size = data.sizeDesignation {
                    LabeledContent("Size") {
                        Text(size)
                    }
                }
                TextField("Diameter (mm)", value: Binding(
                    get: { data.diameter },
                    set: { newDia in
                        var updated = annotation
                        var d = data
                        d.diameter = max(0.1, newDia)
                        updated.data = .holeCallout(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ), format: .number)
                if !data.isThrough {
                    TextField("Depth (mm)", value: Binding(
                        get: { data.depth },
                        set: { newDepth in
                            var updated = annotation
                            var d = data
                            d.depth = max(0.1, newDepth)
                            updated.data = .holeCallout(d)
                            _ = workspace.updateDrawingAnnotation(updated)
                        }
                    ), format: .number)
                }
                Toggle("Through Hole", isOn: Binding(
                    get: { data.isThrough },
                    set: { newThrough in
                        var updated = annotation
                        var d = data
                        d.isThrough = newThrough
                        updated.data = .holeCallout(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                Stepper("Hole Count: \(data.holeCount)", value: Binding(
                    get: { data.holeCount },
                    set: { newCount in
                        var updated = annotation
                        var d = data
                        d.holeCount = max(1, newCount)
                        updated.data = .holeCallout(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ), in: 1...99)
                TextField("Text Override", text: Binding(
                    get: { data.textOverride ?? "" },
                    set: { newOverride in
                        var updated = annotation
                        var d = data
                        d.textOverride = newOverride.isEmpty ? nil : newOverride
                        updated.data = .holeCallout(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Callout Preview:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(data.formattedCalloutText)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }

    @ViewBuilder
    private var balloonSpecificationSection: some View {
        if case .balloon(let data) = annotation.data {
            Section("Balloon Callout") {
                Picker("Shape", selection: Binding(
                    get: { data.shape },
                    set: { newShape in
                        var updated = annotation
                        var d = data
                        d.shape = newShape
                        updated.data = .balloon(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                )) {
                    ForEach(BalloonShape.allCases, id: \.self) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                .accessibilityIdentifier("inspector-balloon-shape-picker")

                TextField("Item Number", text: Binding(
                    get: { data.itemNumber },
                    set: { newNum in
                        var updated = annotation
                        var d = data
                        d.itemNumber = newNum
                        updated.data = .balloon(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))
                .accessibilityIdentifier("inspector-balloon-item-number-field")

                Stepper("Quantity: \(data.quantity)", value: Binding(
                    get: { data.quantity },
                    set: { newQty in
                        var updated = annotation
                        var d = data
                        d.quantity = max(1, newQty)
                        updated.data = .balloon(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ), in: 1...999)

                Toggle("Show Quantity", isOn: Binding(
                    get: { data.showQuantity },
                    set: { showQty in
                        var updated = annotation
                        var d = data
                        d.showQuantity = showQty
                        updated.data = .balloon(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))

                TextField("Text Override", text: Binding(
                    get: { data.textOverride ?? "" },
                    set: { newText in
                        var updated = annotation
                        var d = data
                        d.textOverride = newText.isEmpty ? nil : newText
                        updated.data = .balloon(d)
                        _ = workspace.updateDrawingAnnotation(updated)
                    }
                ))

                if !workspace.document.componentInstances.isEmpty {
                    Picker("Linked Component", selection: Binding(
                        get: { data.componentInstanceId },
                        set: { newCompId in
                            var updated = annotation
                            var d = data
                            d.componentInstanceId = newCompId
                            if let compId = newCompId,
                               let comp = workspace.document.componentInstances.first(where: { $0.id == compId }) {
                                d.componentName = comp.name
                            }
                            updated.data = .balloon(d)
                            _ = workspace.updateDrawingAnnotation(updated)
                        }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(workspace.document.componentInstances) { comp in
                            Text(comp.name).tag(UUID?.some(comp.id))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var toleranceSection: some View {
        if let currentTolerance = extractTolerance() {
            Section("Tolerance") {
                let activeSheet = workspace.document.activeSheet
                let activeStandards = activeSheet?.draftingStandards ?? .iso

                Picker("Type", selection: Binding(
                    get: { currentTolerance.type },
                    set: { newType in
                        var tol = currentTolerance
                        tol.type = newType
                        if newType == .symmetrical && tol.upperValue == 0 {
                            tol.upperValue = activeStandards.tolerances.linearToleranceMM
                            tol.lowerValue = -activeStandards.tolerances.linearToleranceMM
                        } else if newType == .deviation && tol.upperValue == 0 && tol.lowerValue == 0 {
                            tol.upperValue = activeStandards.tolerances.upperDeviationMM
                            tol.lowerValue = activeStandards.tolerances.lowerDeviationMM
                        }
                        updateTolerance(tol)
                    }
                )) {
                    ForEach(DraftingToleranceType.allCases, id: \.self) { tType in
                        Text(tType.displayName).tag(tType)
                    }
                }
                .accessibilityIdentifier("inspector-annotation-tolerance-type-picker")

                if currentTolerance.type == .symmetrical {
                    TextField("Tolerance (±)", value: Binding(
                        get: { abs(currentTolerance.upperValue) },
                        set: { newVal in
                            var tol = currentTolerance
                            tol.upperValue = abs(newVal)
                            tol.lowerValue = -abs(newVal)
                            updateTolerance(tol)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inspector-annotation-tolerance-symmetrical-field")
                } else if currentTolerance.type == .deviation || currentTolerance.type == .limits {
                    HStack {
                        TextField("Upper (+)", value: Binding(
                            get: { currentTolerance.upperValue },
                            set: { newVal in
                                var tol = currentTolerance
                                tol.upperValue = newVal
                                updateTolerance(tol)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("inspector-annotation-tolerance-upper-field")

                        TextField("Lower (-)", value: Binding(
                            get: { currentTolerance.lowerValue },
                            set: { newVal in
                                var tol = currentTolerance
                                tol.lowerValue = newVal
                                updateTolerance(tol)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("inspector-annotation-tolerance-lower-field")
                    }
                }

                if currentTolerance.type != .none {
                    Stepper("Precision Override: \(currentTolerance.precision.map { String($0) } ?? "Default")", value: Binding(
                        get: { currentTolerance.precision ?? 2 },
                        set: { newPrec in
                            var tol = currentTolerance
                            tol.precision = max(0, min(6, newPrec))
                            updateTolerance(tol)
                        }
                    ), in: 0...6)
                    .accessibilityIdentifier("inspector-annotation-tolerance-precision-stepper")
                }

                LabeledContent("Preview") {
                    Text(previewText(using: activeStandards))
                        .fontWeight(.medium)
                }
                .accessibilityIdentifier("inspector-annotation-tolerance-preview-label")
            }
        }
    }

    private func extractTolerance() -> DimensionTolerance? {
        switch annotation.data {
        case .linear(let d):
            return d.tolerance ?? DimensionTolerance(type: .none)
        case .angular(let d):
            return d.tolerance ?? DimensionTolerance(type: .none)
        case .radial(let d):
            return d.tolerance ?? DimensionTolerance(type: .none)
        case .ordinate(let d):
            return d.tolerance ?? DimensionTolerance(type: .none)
        case .baseline(let d):
            return d.tolerance ?? DimensionTolerance(type: .none)
        default:
            return nil
        }
    }

    private func updateTolerance(_ tolerance: DimensionTolerance) {
        var updated = annotation
        switch annotation.data {
        case .linear(var d):
            d.tolerance = tolerance.type == .none && tolerance.precision == nil ? nil : tolerance
            updated.data = .linear(d)
        case .angular(var d):
            d.tolerance = tolerance.type == .none && tolerance.precision == nil ? nil : tolerance
            updated.data = .angular(d)
        case .radial(var d):
            d.tolerance = tolerance.type == .none && tolerance.precision == nil ? nil : tolerance
            updated.data = .radial(d)
        case .ordinate(var d):
            d.tolerance = tolerance.type == .none && tolerance.precision == nil ? nil : tolerance
            updated.data = .ordinate(d)
        case .baseline(var d):
            d.tolerance = tolerance.type == .none && tolerance.precision == nil ? nil : tolerance
            updated.data = .baseline(d)
        default:
            return
        }
        _ = workspace.updateDrawingAnnotation(updated)
    }

    private func previewText(using standards: DraftingStandardSettings) -> String {
        switch annotation.data {
        case .linear(let d):
            return d.formattedText(using: standards)
        case .angular(let d):
            return d.formattedText(using: standards)
        case .radial(let d):
            return d.formattedText(using: standards)
        case .ordinate(let d):
            return d.formattedText(using: standards)
        case .baseline(let d):
            return d.formattedText(forTargetIndex: 0, using: standards)
        default:
            return ""
        }
    }
}

/// Inspector panel view for configuring a Bill of Materials table placed on a drawing sheet (BL-DRW-08, #215).
struct DrawingBOMTableInspectorView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let table: DrawingBOMTable

    var body: some View {
        Form {
            Section("Table Details") {
                TextField("Title", text: Binding(
                    get: { table.title },
                    set: { newTitle in
                        var updated = table
                        updated.title = newTitle
                        _ = workspace.updateBOMTable(updated)
                    }
                ))
                .accessibilityIdentifier("inspector-bom-table-title-field")

                Toggle("Show Title", isOn: Binding(
                    get: { table.showTitle },
                    set: { newShow in
                        var updated = table
                        updated.showTitle = newShow
                        _ = workspace.updateBOMTable(updated)
                    }
                ))

                Picker("Structure", selection: Binding(
                    get: { table.structure },
                    set: { newStruct in
                        var updated = table
                        updated.structure = newStruct
                        _ = workspace.updateBOMTable(updated)
                    }
                )) {
                    ForEach(BOMStructure.allCases, id: \.self) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .accessibilityIdentifier("inspector-bom-table-structure-picker")

                Stepper("Row Height: \(Int(table.rowHeightMM)) mm", value: Binding(
                    get: { Int(table.rowHeightMM) },
                    set: { newHeight in
                        var updated = table
                        updated.rowHeightMM = max(4.0, Double(newHeight))
                        _ = workspace.updateBOMTable(updated)
                    }
                ), in: 4...25)

                Stepper("Font Size: \(Int(table.fontSizePt)) pt", value: Binding(
                    get: { Int(table.fontSizePt) },
                    set: { newSize in
                        var updated = table
                        updated.fontSizePt = max(6.0, Double(newSize))
                        _ = workspace.updateBOMTable(updated)
                    }
                ), in: 6...18)
            }

            Section("Columns") {
                ForEach(DrawingBOMColumn.allCases) { col in
                    let isEnabled = table.columns.contains(col)
                    Toggle(col.displayName, isOn: Binding(
                        get: { isEnabled },
                        set: { enable in
                            var updated = table
                            if enable && !updated.columns.contains(col) {
                                updated.columns.append(col)
                            } else if !enable && updated.columns.contains(col) {
                                updated.columns.removeAll(where: { $0 == col })
                                if updated.columns.isEmpty {
                                    updated.columns = [.itemNumber]
                                }
                            }
                            _ = workspace.updateBOMTable(updated)
                        }
                    ))
                }
            }

            Section {
                Button("Delete BOM Table", role: .destructive) {
                    _ = workspace.removeBOMTable(id: table.id)
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier("inspector-bom-table-delete-button")
            }
        }
        .formStyle(.columns)
        .controlSize(.small)
        .padding()
        .accessibilityIdentifier("drawing-bom-table-inspector-view")
    }
}


