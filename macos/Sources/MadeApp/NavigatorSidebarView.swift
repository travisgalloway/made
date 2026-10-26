import SwiftUI
import MadeCore

struct NavigatorSidebarView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var filterText = ""
    @State private var renamingTarget: (id: ObjectId, name: String)? = nil
    @State private var renamingText = ""

    var body: some View {
        @Bindable var workspace = workspace

        VStack(spacing: 0) {
            if workspace.document.isRolledBack {
                rollbackBanner
            }

            ScrollViewReader { proxy in
                List(selection: $workspace.selectedIds) {
                    switch workspace.navigatorTab {
                    case .scene:
                        sceneSections
                    case .construction:
                        constructionSections
                    case .simulation:
                        simulationSections
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    emptyStateOverlay
                }
                .contextMenu(forSelectionType: ObjectId.self) { ids in
                    if let id = ids.first, let body = workspace.document.body(for: id) {
                        Button("Edit Feature…") { workspace.startEditFeature(for: id) }
                            .disabled(body.isLocked)
                        Divider()
                        let obj = workspace.document.objects.first(where: { $0.id == id })
                        if let obj, case .part = obj.def {
                            Button("Convert to Features") {
                                Task {
                                    _ = try? await workspace.convertPartToFeatures(id: id)
                                }
                            }
                            Button("Reload Part") { workspace.reloadPart(id) }
                            Divider()
                        }
                        if let obj, case .imported(_, _, _, let isLinked, _, _) = obj.def, isLinked {
                            Button("Update Link") {
                                Task {
                                    _ = await workspace.updateLinkedReference(id)
                                }
                            }
                            Button("Relink…") {
                                workspace.promptRelinkReference(id)
                            }
                            Divider()
                        }
                        Button("Roll Back to Here") { workspace.rollBack(to: id) }
                        Button("Roll Back Before") { workspace.rollBack(before: id) }
                        Divider()
                        Button("Rename…") {
                            renamingText = body.name
                            renamingTarget = (id: id, name: body.name)
                        }
                        .disabled(body.isLocked)
                        Button(body.isVisible ? "Hide" : "Show") { workspace.toggleBodyVisibility(id) }
                        Button(body.isLocked ? "Unlock" : "Lock") { workspace.toggleBodyLocked(id) }
                        if let feat = workspace.document.feature(for: id) {
                            Button(feat.isSuppressed ? "Unsuppress" : "Suppress") {
                                workspace.toggleFeatureSuppressed(feat.id)
                            }
                            .disabled(feat.isLocked)
                        }
                        Divider()
                        Button("Delete", role: .destructive) { workspace.requestDeleteObject(id) }
                            .disabled(body.isLocked)
                    }
                } primaryAction: { ids in
                    if let id = ids.first {
                        workspace.startEditFeature(for: id)
                    }
                }
                .alert(
                    "Rename “\(renamingTarget?.name ?? "Body")”",
                    isPresented: Binding(
                        get: { renamingTarget != nil },
                        set: { if !$0 { renamingTarget = nil } }
                    )
                ) {
                    TextField("Name", text: $renamingText)
                    Button("Rename") {
                        if let target = renamingTarget {
                            workspace.setBodyName(id: target.id, name: renamingText)
                            renamingTarget = nil
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        renamingTarget = nil
                    }
                }
                .confirmationDialog(
                    "Delete “\(workspace.objectPendingDeletion?.name ?? "Solid")”?",
                    isPresented: Binding(
                        get: { workspace.pendingDeleteId != nil },
                        set: { if !$0 { workspace.cancelDeleteObject() } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        workspace.confirmDeleteObject()
                    }
                    Button("Cancel", role: .cancel) {
                        workspace.cancelDeleteObject()
                    }
                } message: {
                    Text("Are you sure you want to delete “\(workspace.objectPendingDeletion?.name ?? "this solid")”? This action cannot be undone.")
                }
                .confirmationDialog(
                    "Delete “\(workspace.featurePendingDeletion?.name ?? "Feature")”?",
                    isPresented: Binding(
                        get: { workspace.pendingDeleteFeatureId != nil },
                        set: { if !$0 { workspace.cancelDeleteFeature() } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        workspace.confirmDeleteFeature()
                    }
                    Button("Cancel", role: .cancel) {
                        workspace.cancelDeleteFeature()
                    }
                } message: {
                    Text("Are you sure you want to delete “\(workspace.featurePendingDeletion?.name ?? "this feature")”? Any downstream features depending on it will show reference errors.")
                }
                .onChange(of: workspace.selectedId) { _, newId in
                    if let newId {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(newId, anchor: nil)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                PaneTabBar(label: "Navigator", selection: $workspace.navigatorTab, fillsWidth: true)
                Divider()
            }
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    @ViewBuilder
    private var sceneSections: some View {
        if workspace.document.documentType == .drawing || !workspace.document.sheets.isEmpty {
            Section {
                ForEach(workspace.document.sheets) { sheet in
                    NavigatorSheetRow(sheet: sheet)
                }
            } header: {
                HStack {
                    Text("Sheets")
                    Spacer()
                    Button {
                        _ = workspace.addSheet()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 16, height: 16)
                    .help("Add Sheet")
                    .accessibilityIdentifier("navigator-add-sheet-button")
                }
            }
        }

        if workspace.document.documentType == .assembly || !workspace.document.componentInstances.isEmpty {
            Section {
                ForEach(filteredComponents) { component in
                    NavigatorComponentRow(component: component)
                        .tag(component.solidId)
                        .id(component.solidId)
                }
            } header: {
                HStack {
                    Text("Components")
                    Spacer()
                    Menu {
                        Button("Insert from File…") {
                            workspace.promptInsertComponentFromFile()
                        }
                        Button("Insert from Document…") {
                            workspace.promptInsertComponentFromDocument()
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 16, height: 16)
                }
            }
        }

        if workspace.document.documentType == .assembly || !workspace.document.assemblyConstraints.isEmpty {
            Section {
                if let result = workspace.lastAssemblySolverResult {
                    switch result.status {
                    case .overConstrained(let conflicting):
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            Text("Over-constrained (\(conflicting.count) conflicting)").font(.caption2).foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .accessibilityIdentifier("navigator-assembly-overconstrained-banner")
                    case .redundant(let redundant):
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            Text("Redundant mates (\(redundant.count))").font(.caption2).foregroundStyle(.orange)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .accessibilityIdentifier("navigator-assembly-redundant-banner")
                    case .failedToConverge:
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            Text("Solve failed").font(.caption2).foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .accessibilityIdentifier("navigator-assembly-failed-banner")
                    case .converged:
                        EmptyView()
                    }
                }
                ForEach(filteredConstraints) { constraint in
                    NavigatorConstraintRow(constraint: constraint)
                }
            } header: {
                HStack {
                    Text("Mates & Joints")
                    Spacer()
                    Button {
                        _ = workspace.solveAssemblyConstraints()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 16, height: 16)
                    .help("Solve Assembly")
                    .disabled(workspace.document.assemblyConstraints.isEmpty)
                }
            }
        }

        if workspace.document.documentType == .assembly || !workspace.document.explodedViews.isEmpty {
            Section {
                ForEach(workspace.document.explodedViews) { view in
                    NavigatorExplodedViewRow(view: view)
                }
            } header: {
                HStack {
                    Text("Exploded Views")
                    Spacer()
                    Button {
                        _ = workspace.createExplodedView()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 16, height: 16)
                    .help("New Exploded View")
                    .accessibilityIdentifier("navigator-add-exploded-view-button")
                }
            }
        }

        if (workspace.document.documentType != .assembly && workspace.document.documentType != .drawing) || !filteredBodies.isEmpty {
            Section("Bodies") {
                ForEach(filteredBodies) { body in
                    NavigatorRow(body: body)
                        .tag(body.id)
                        .id(body.id)
                }
            }
        }

        if !suppressedSolidFeatures.isEmpty {
            Section("Suppressed Features") {
                ForEach(suppressedSolidFeatures) { feat in
                    NavigatorSuppressedFeatureRow(feature: feat)
                }
            }
        }
    }

    @ViewBuilder
    private var constructionSections: some View {
        Section {
            ForEach(filteredSketchFeatures) { sketch in
                NavigatorSketchRow(feature: sketch)
            }
        } header: {
            HStack {
                Text("Sketches")
                Spacer()
                Button {
                    workspace.startNewSketchCommand()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .frame(width: 16, height: 16)
                .help("New Ground Sketch")
                .accessibilityIdentifier("navigator-add-sketch-button")
            }
        }

        Section {
            ForEach(filteredDatumPlaneFeatures) { datum in
                NavigatorDatumPlaneRow(feature: datum)
            }
        } header: {
            HStack {
                Text("Datum Planes")
                Spacer()
                Button {
                    workspace.startDatumPlaneCommand()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .frame(width: 16, height: 16)
                .help("New Datum Plane")
                .accessibilityIdentifier("navigator-add-datum-plane-button")
            }
        }

        Section {
            ForEach(filteredDatumAxisFeatures) { datum in
                NavigatorDatumAxisRow(feature: datum)
            }
        } header: {
            HStack {
                Text("Datum Axes")
                Spacer()
                Button {
                    workspace.startDatumAxisCommand()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .frame(width: 16, height: 16)
                .help("New Datum Axis")
                .accessibilityIdentifier("navigator-add-datum-axis-button")
            }
        }

        Section {
            ForEach(filteredDatumPointFeatures) { datum in
                NavigatorDatumPointRow(feature: datum)
            }
        } header: {
            HStack {
                Text("Datum Points")
                Spacer()
                Button {
                    workspace.startDatumPointCommand()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .frame(width: 16, height: 16)
                .help("New Datum Point")
                .accessibilityIdentifier("navigator-add-datum-point-button")
            }
        }

        Section {
            ForEach(filteredDatumCoordinateSystemFeatures) { datum in
                NavigatorDatumCoordinateSystemRow(feature: datum)
            }
        } header: {
            HStack {
                Text("Coordinate Systems")
                Spacer()
                Button {
                    workspace.startDatumCoordinateSystemCommand()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .frame(width: 16, height: 16)
                .help("New Coordinate System")
                .accessibilityIdentifier("navigator-add-ucs-button")
            }
        }

        if !workspace.document.parameters.isEmpty {
            Section("Parameters") {
                ForEach(workspace.document.parameters) { param in
                    NavigatorParameterRow(param: param)
                }
            }
        }
    }

    @ViewBuilder
    private var simulationSections: some View {
        Section {
            ForEach(workspace.document.studies) { study in
                NavigatorSimulationStudyRow(study: study)
            }
        } header: {
            HStack {
                Text("Simulation Studies")
                Spacer()
                Menu {
                    Button("New Linear Static Study") {
                        _ = workspace.createSimulationStudy(type: .linearStatic)
                    }
                    Button("New Thermal Conduction Study") {
                        _ = workspace.createSimulationStudy(type: .thermalConduction)
                    }
                    Button("New Modal Frequency Study") {
                        _ = workspace.createSimulationStudy(type: .modalFrequency)
                    }
                    Button("New Linear Buckling Study") {
                        _ = workspace.createSimulationStudy(type: .linearBuckling)
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 16, height: 16)
                .help("New Simulation Study")
                .accessibilityIdentifier("navigator-add-study-button")
            }
        }
    }

    @ViewBuilder
    private var emptyStateOverlay: some View {
        switch workspace.navigatorTab {
        case .scene:
            if workspace.document.bodies.isEmpty && workspace.document.componentInstances.isEmpty && workspace.document.assemblyConstraints.isEmpty && workspace.document.explodedViews.isEmpty && workspace.document.sheets.isEmpty {
                ContentUnavailableView {
                    Label(workspace.document.documentType == .assembly ? "No Components" : "No Objects", systemImage: workspace.document.documentType == .assembly ? "square.3.layers.3d" : "cube.transparent")
                } description: {
                    Text(workspace.document.documentType == .assembly ? "Add components to begin assembling." : "Add a 3D solid primitive or open a part script to begin modeling.")
                } actions: {
                    if workspace.document.documentType == .assembly {
                        VStack(spacing: 8) {
                            Button("Insert from File…", systemImage: "doc.badge.plus") {
                                workspace.promptInsertComponentFromFile()
                            }
                            Button("Insert from Document…", systemImage: "doc.on.doc") {
                                workspace.promptInsertComponentFromDocument()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        VStack(spacing: 8) {
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
                }
            } else if !filterText.isEmpty && filteredBodies.isEmpty && filteredComponents.isEmpty && filteredConstraints.isEmpty && suppressedSolidFeatures.isEmpty {
                ContentUnavailableView.search(text: filterText)
            }

        case .construction:
            if sketchFeatures.isEmpty && datumPlaneFeatures.isEmpty && datumAxisFeatures.isEmpty && datumPointFeatures.isEmpty && datumCoordinateSystemFeatures.isEmpty && workspace.document.parameters.isEmpty {
                ContentUnavailableView {
                    Label("No Construction Geometry", systemImage: "ruler")
                } description: {
                    Text("Create sketches, datum planes, axes, points, or coordinate systems.")
                } actions: {
                    VStack(spacing: 8) {
                        Button("New Sketch…", systemImage: "pencil.and.ruler.fill") {
                            workspace.startNewSketchCommand()
                        }
                        Button("New Datum Plane…", systemImage: "square.dashed") {
                            workspace.startDatumPlaneCommand()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if !filterText.isEmpty && filteredSketchFeatures.isEmpty && filteredDatumPlaneFeatures.isEmpty && filteredDatumAxisFeatures.isEmpty && filteredDatumPointFeatures.isEmpty && filteredDatumCoordinateSystemFeatures.isEmpty {
                ContentUnavailableView.search(text: filterText)
            }

        case .simulation:
            if workspace.document.studies.isEmpty {
                ContentUnavailableView {
                    Label("No Simulation Studies", systemImage: "waveform.path.ecg")
                } description: {
                    Text("Create a finite element study to analyze stress, thermal conduction, or modal frequencies.")
                } actions: {
                    VStack(spacing: 8) {
                        Button("New Linear Static Study", systemImage: "arrow.down.to.line.compact") {
                            _ = workspace.createSimulationStudy(type: .linearStatic)
                        }
                        Button("New Thermal Study", systemImage: "flame") {
                            _ = workspace.createSimulationStudy(type: .thermalConduction)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var rollbackBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Rolled Back (\(workspace.document.rolledBackFeatures.count) features hidden)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Roll to End") {
                workspace.rollForwardToEnd()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu("Add", systemImage: "plus") {
                Menu("3D Primitives", systemImage: "cube") {
                    Button("Box Solid", systemImage: "shippingbox") {
                        workspace.addDefaultBox()
                    }
                    Button("Cylinder Solid", systemImage: "cylinder") {
                        workspace.addDefaultCylinder()
                    }
                    Button("Sphere Solid", systemImage: "globe") {
                        workspace.addDefaultSphere()
                    }
                    Button("Cone Solid", systemImage: "cone.fill") {
                        workspace.addDefaultCone()
                    }
                    Button("Torus Solid", systemImage: "circle.circle") {
                        workspace.addDefaultTorus()
                    }
                    Button("Wedge Solid", systemImage: "triangle.fill") {
                        workspace.addDefaultWedge()
                    }
                }
                Menu("Sketch & Features", systemImage: "pencil.and.ruler.fill") {
                    Button("New Ground Sketch…", systemImage: "pencil.and.ruler.fill") {
                        workspace.startNewSketchCommand()
                    }
                    Divider()
                    Button("Extrude Sketch…", systemImage: "arrow.up.forward.app.fill") {
                        workspace.startExtrudeCommand()
                    }
                    Button("Revolve Sketch…", systemImage: "arrow.triangle.2.circlepath") {
                        workspace.startRevolveCommand()
                    }
                    Divider()
                    Button("Chamfer Edges…", systemImage: "skew") {
                        workspace.startChamferCommand()
                    }
                    Button("Shell Solid…", systemImage: "square.dashed") {
                        workspace.startShellCommand()
                    }
                    Button("Hole Wizard…", systemImage: "circle.dotted.circle") {
                        workspace.startHoleCommand()
                    }
                    Divider()
                    Button("Linear Pattern…", systemImage: "square.grid.3x2") {
                        workspace.startLinearPatternCommand()
                    }
                    Button("Circular Pattern…", systemImage: "circle.grid.cross") {
                        workspace.startCircularPatternCommand()
                    }
                    Button("Mirror Body…", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                        workspace.startMirrorCommand()
                    }
                }
                Menu("Reference Geometry", systemImage: "ruler") {
                    Button("New Datum Plane…", systemImage: "square.dashed") {
                        workspace.startDatumPlaneCommand()
                    }
                    Button("New Datum Axis…", systemImage: "line.diagonal") {
                        workspace.startDatumAxisCommand()
                    }
                    Button("New Datum Point…", systemImage: "smallcircle.filled.circle") {
                        workspace.startDatumPointCommand()
                    }
                    Button("New Coordinate System…", systemImage: "move.3d") {
                        workspace.startDatumCoordinateSystemCommand()
                    }
                }
                Divider()
                Button("Part Script File…", systemImage: "curlybraces") {
                    workspace.promptOpenPartFile()
                }
                Button("Link External File…", systemImage: "link") {
                    workspace.promptLinkExternalFile()
                }
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add")
            BarFilterField(text: $filterText)
        }
        .barControl()
        .padding(.horizontal, 10)
        .frame(height: BarMetrics.height)
    }

    static func filter(objects: [SceneObject], query: String) -> [SceneObject] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return objects }
        return objects.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.id.rawValue.localizedCaseInsensitiveContains(trimmed)
                || $0.def.kind.localizedCaseInsensitiveContains(trimmed)
                || $0.parameterSummary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var filteredObjects: [SceneObject] {
        Self.filter(objects: workspace.document.objects, query: filterText)
    }

    private var filteredBodies: [MadeCore.Body] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return workspace.document.bodies }
        return workspace.document.bodies.filter { body in
            if body.name.localizedCaseInsensitiveContains(trimmed) || body.id.rawValue.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            if let obj = workspace.document.objects.first(where: { $0.id == body.id }) {
                return obj.def.kind.localizedCaseInsensitiveContains(trimmed) || obj.parameterSummary.localizedCaseInsensitiveContains(trimmed)
            }
            return false
        }
    }

    private var suppressedSolidFeatures: [Feature] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        let solidFeatures = workspace.document.activeFeatures.filter { feat in
            feat.isSuppressed && !Self.isConstructionFeature(feat)
        }
        guard !trimmed.isEmpty else { return solidFeatures }
        return solidFeatures.filter { feat in
            if feat.name.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            if let solidId = feat.outputSolidId, solidId.rawValue.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            return false
        }
    }

    nonisolated static func isConstructionFeature(_ feat: Feature) -> Bool {
        switch feat.operation {
        case .sketch, .datumPlane, .datumAxis, .datumPoint, .datumCoordinateSystem:
            return true
        default:
            return false
        }
    }

    private var filteredComponents: [ComponentInstance] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return workspace.document.componentInstances }
        return workspace.document.componentInstances.filter { comp in
            if comp.name.localizedCaseInsensitiveContains(trimmed) || comp.solidId.rawValue.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            switch comp.reference {
            case .internalPart(let name, _):
                return name.localizedCaseInsensitiveContains(trimmed)
            case .externalDocument(let url, let partName):
                return url.lastPathComponent.localizedCaseInsensitiveContains(trimmed) || (partName?.localizedCaseInsensitiveContains(trimmed) ?? false)
            case .subassembly(let name):
                return name.localizedCaseInsensitiveContains(trimmed)
            }
        }
    }

    private var filteredConstraints: [AssemblyConstraint] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return workspace.document.assemblyConstraints }
        return workspace.document.assemblyConstraints.filter { constraint in
            constraint.name.localizedCaseInsensitiveContains(trimmed) ||
            constraint.kind.displayName.localizedCaseInsensitiveContains(trimmed) ||
            constraint.kind.rawValue.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var sketchFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .sketch = $0.operation { return true }
            return false
        }
    }

    private var filteredSketchFeatures: [Feature] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sketchFeatures }
        return sketchFeatures.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var datumPlaneFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .datumPlane = $0.operation { return true }
            return false
        }
    }

    private var filteredDatumPlaneFeatures: [Feature] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return datumPlaneFeatures }
        return datumPlaneFeatures.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var datumAxisFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .datumAxis = $0.operation { return true }
            return false
        }
    }

    private var filteredDatumAxisFeatures: [Feature] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return datumAxisFeatures }
        return datumAxisFeatures.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var datumPointFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .datumPoint = $0.operation { return true }
            return false
        }
    }

    private var filteredDatumPointFeatures: [Feature] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return datumPointFeatures }
        return datumPointFeatures.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var datumCoordinateSystemFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .datumCoordinateSystem = $0.operation { return true }
            return false
        }
    }

    private var filteredDatumCoordinateSystemFeatures: [Feature] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return datumCoordinateSystemFeatures }
        return datumCoordinateSystemFeatures.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// One outline row. Visibility and lock buttons show on hover, and stay visible while the body is hidden or locked.
private struct NavigatorRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let bodyItem: MadeCore.Body
    @State private var isHovered = false

    init(body: MadeCore.Body) {
        self.bodyItem = body
    }

    init(object: SceneObject) {
        self.bodyItem = MadeCore.Body(from: object)
    }

    var body: some View {
        let object = workspace.document.objects.first(where: { $0.id == bodyItem.id })
        let errorState = workspace.document.feature(for: bodyItem.id)?.errorState
        let isSelected = workspace.document.isSelected(solidId: bodyItem.id)

        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon(for: object))
                .foregroundStyle(tint(for: object))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bodyItem.name)
                        .font(.body)
                        .lineLimit(1)

                    if let kind = object?.def.kind.capitalized {
                        Text(kind)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }

                    if let object, case .imported(_, _, _, let isLinked, _, _) = object.def, isLinked {
                        let status = workspace.linkStatus(for: bodyItem.id)
                        switch status {
                        case .outOfDate:
                            Text("Out of Date")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange))
                                .help("External file has been modified on disk")
                        case .missingFile:
                            Text("Missing")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.red))
                                .help("External file not found")
                        case .upToDate:
                            EmptyView()
                        }
                    }

                    if let errorState {
                        if errorState.severity == .warning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption2)
                                .help(errorState.message)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                                .help(errorState.message)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Text(bodyItem.id.rawValue)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)

                    if let summary = object?.parameterSummary, !summary.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            Group {
                if isHovered || !bodyItem.isVisible {
                    Button(bodyItem.isVisible ? "Hide Body" : "Show Body",
                           systemImage: bodyItem.isVisible ? "eye" : "eye.slash") {
                        workspace.toggleBodyVisibility(bodyItem.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(bodyItem.isVisible ? "Hide Body" : "Show Body")
                }
                if isHovered || bodyItem.isLocked {
                    Button(bodyItem.isLocked ? "Unlock Body" : "Lock Body",
                           systemImage: bodyItem.isLocked ? "lock.fill" : "lock.open") {
                        workspace.toggleBodyLocked(bodyItem.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(bodyItem.isLocked ? "Unlock Body" : "Lock Body")
                }
            }
            .barControl()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bodyItem.name), \(object?.def.kind ?? "Solid"), ID \(bodyItem.id.rawValue)\(object.map { ", \($0.parameterSummary)" } ?? "")\(errorState.map { ", \($0.severity == .warning ? "Warning" : "Error"): \($0.message)" } ?? "")")
        .accessibilityIdentifier("navigator-object-\(bodyItem.id.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction {
            workspace.select(solidId: bodyItem.id)
        }
        .accessibilityAction(named: bodyItem.isVisible ? "Hide Body" : "Show Body") {
            workspace.toggleBodyVisibility(bodyItem.id)
        }
        .accessibilityAction(named: bodyItem.isLocked ? "Unlock Body" : "Lock Body") {
            workspace.toggleBodyLocked(bodyItem.id)
        }
    }

    private func icon(for object: SceneObject?) -> String {
        guard let object else { return "cube.fill" }
        if let feat = workspace.document.feature(for: object.id) {
            switch feat.operation {
            case .combine: return "square.on.circle"
            case .moveBody: return "arrow.up.and.down.and.arrow.left.and.right"
            case .copyBody: return "plus.square.on.square"
            case .deleteBody: return "trash"
            default: break
            }
        }
        switch object.def {
        case .box: return "shippingbox.fill"
        case .cylinder: return "cylinder.fill"
        case .sphere: return "globe"
        case .cone: return "cone.fill"
        case .torus: return "circle.circle"
        case .wedge: return "triangle.fill"
        case .imported: return "cube.transparent"
        case .boolean: return "square.on.circle"
        case .part: return "curlybraces.square.fill"
        case .extrude: return "arrow.up.forward.app.fill"
        case .revolve: return "arrow.triangle.2.circlepath"
        case .chamfer: return "skew"
        case .shell: return "square.dashed"
        case .hole: return "circle.circle"
        case .pattern: return "square.grid.3x3.fill"
        case .mirror: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        }
    }

    private func tint(for object: SceneObject?) -> Color {
        guard let object else { return .accentColor }
        if let feat = workspace.document.feature(for: object.id) {
            switch feat.operation {
            case .combine: return .green
            case .moveBody: return .indigo
            case .copyBody: return .cyan
            case .deleteBody: return .red
            default: break
            }
        }
        switch object.def {
        case .box: return .blue
        case .cylinder: return .orange
        case .sphere: return .pink
        case .cone: return .indigo
        case .torus: return .mint
        case .wedge: return .brown
        case .imported: return .purple
        case .boolean: return .green
        case .part: return .teal
        case .extrude: return .purple
        case .revolve: return .cyan
        case .chamfer: return .orange
        case .shell: return .purple
        case .hole: return .teal
        case .pattern: return .indigo
        case .mirror: return .cyan
        }
    }
}

/// Outline row for a suppressed solid feature in the Navigator sidebar.
struct NavigatorSuppressedFeatureRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let feature: Feature
    @State private var isHovered = false

    init(feature: Feature) {
        self.feature = feature
    }

    nonisolated static let defaultAccessibilityTraits: AccessibilityTraits = .isButton

    nonisolated static func accessibilityTraits(isSelected: Bool = false) -> AccessibilityTraits {
        isSelected ? [defaultAccessibilityTraits, .isSelected] : defaultAccessibilityTraits
    }

    nonisolated static func accessibilityLabel(featureName: String, kind: String, isLocked: Bool = false) -> String {
        "\(featureName), \(kind), Suppressed\(isLocked ? ", Locked" : "")"
    }

    var body: some View {
        let isSelected = workspace.isFeatureSelected(feature)
        let kind = Self.featureKind(for: feature)

        HStack(alignment: .center, spacing: 8) {
            Image(systemName: Self.featureIcon(for: feature))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.name)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough()
                        .foregroundStyle(.secondary)

                    Text(kind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    Text("Suppressed")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }

                if let solidId = feature.outputSolidId {
                    Text(solidId.rawValue)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Group {
                if isHovered || feature.isSuppressed {
                    Button("Unsuppress Feature", systemImage: "eye.slash.fill") {
                        workspace.toggleFeatureSuppressed(feature.id)
                    }
                    .foregroundStyle(.orange)
                    .help("Unsuppress Feature")
                    .disabled(feature.isLocked)
                }
                if isHovered || feature.isLocked {
                    Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                           systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                        workspace.toggleFeatureLocked(feature.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                }
            }
            .barControl()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Button("Unsuppress") {
                workspace.toggleFeatureSuppressed(feature.id)
            }
            .disabled(feature.isLocked)

            Button(feature.isLocked ? "Unlock" : "Lock") {
                workspace.toggleFeatureLocked(feature.id)
            }

            Divider()

            Button("Delete", role: .destructive) {
                workspace.requestDeleteFeature(feature.id)
            }
            .disabled(feature.isLocked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(Self.accessibilityTraits(isSelected: isSelected))
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, kind: kind, isLocked: feature.isLocked))
        .accessibilityIdentifier("navigator-suppressed-feature-\(feature.id.uuidString)")
        .accessibilityAction {
            workspace.selectFeature(feature.id)
        }
        .accessibilityAction(named: "Unsuppress Feature") {
            workspace.toggleFeatureSuppressed(feature.id)
        }
        .accessibilityAction(named: feature.isLocked ? "Unlock Feature" : "Lock Feature") {
            workspace.toggleFeatureLocked(feature.id)
        }
        .accessibilityAction(named: "Delete") {
            workspace.requestDeleteFeature(feature.id)
        }
    }

    nonisolated static func featureKind(for feature: Feature) -> String {
        switch feature.operation {
        case .primitive(let data):
            switch data {
            case .box: return "Box"
            case .cylinder: return "Cylinder"
            case .sphere: return "Sphere"
            case .cone: return "Cone"
            case .torus: return "Torus"
            case .wedge: return "Wedge"
            }
        case .extrude:
            return "Extrude"
        case .revolve:
            return "Revolve"
        case .boolean(let data):
            return data.op.rawValue.capitalized
        case .part:
            return "Part"
        case .imported:
            return "Imported"
        case .chamfer:
            return "Chamfer"
        case .shell:
            return "Shell"
        case .hole:
            return "Hole"
        case .pattern:
            return "Pattern"
        case .mirror:
            return "Mirror"
        case .combine:
            return "Combine"
        case .moveBody:
            return "Move"
        case .copyBody:
            return "Copy"
        case .deleteBody:
            return "Delete"
        default:
            return "Solid"
        }
    }

    nonisolated static func featureIcon(for feature: Feature) -> String {
        switch feature.operation {
        case .primitive(let data):
            switch data {
            case .box: return "shippingbox.fill"
            case .cylinder: return "cylinder.fill"
            case .sphere: return "globe"
            case .cone: return "cone.fill"
            case .torus: return "circle.circle"
            case .wedge: return "triangle.fill"
            }
        case .extrude: return "arrow.up.forward.app.fill"
        case .revolve: return "arrow.triangle.2.circlepath"
        case .boolean: return "square.on.circle"
        case .part: return "curlybraces.square.fill"
        case .imported: return "cube.transparent"
        case .chamfer: return "skew"
        case .shell: return "square.dashed"
        case .hole: return "circle.circle"
        case .pattern: return "square.grid.3x3.fill"
        case .mirror: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .combine: return "square.on.circle"
        case .moveBody: return "arrow.up.and.down.and.arrow.left.and.right"
        case .copyBody: return "plus.square.on.square"
        case .deleteBody: return "trash"
        default: return "cube.fill"
        }
    }
}

/// Outline row for an assembly component instance in the Navigator sidebar.
private struct NavigatorComponentRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let component: ComponentInstance
    var indentLevel: Int = 0
    @State private var isHovered = false
    @State private var isExpanded = true

    var body: some View {
        let isSelected = workspace.document.isSelected(solidId: component.solidId)
        let dof = workspace.remainingAssemblyDOF(for: component.id)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                if indentLevel > 0 {
                    Spacer().frame(width: CGFloat(indentLevel * 12))
                }

                if component.isSubassembly && (!component.childInstances.isEmpty || !component.childConstraints.isEmpty) {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse Subassembly" : "Expand Subassembly")
                } else if indentLevel > 0 {
                    Spacer().frame(width: 12)
                }

                Image(systemName: component.isSubassembly ? "square.stack.3d.down.right" : "square.3.layers.3d")
                    .foregroundStyle(component.isSubassembly ? .purple : .blue)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(component.name)
                            .font(.body)
                            .lineLimit(1)

                        badges(dof: dof)
                    }

                    HStack(spacing: 6) {
                        Text(component.solidId.rawValue)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text(referenceDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Group {
                    if isHovered || component.isGrounded {
                        Button(component.isGrounded ? "Float Component" : "Ground Component",
                               systemImage: component.isGrounded ? "pin.fill" : "pin") {
                            workspace.toggleComponentInstanceGrounded(id: component.id)
                        }
                        .foregroundStyle(component.isGrounded ? .orange : .secondary)
                        .help(component.isGrounded ? "Float Component" : "Ground Component")
                    }
                    if isHovered || !component.isVisible {
                        Button(component.isVisible ? "Hide Component" : "Show Component",
                               systemImage: component.isVisible ? "eye" : "eye.slash") {
                            workspace.toggleBodyVisibility(component.solidId)
                        }
                        .foregroundStyle(.secondary)
                        .help(component.isVisible ? "Hide Component" : "Show Component")
                    }
                    if isHovered || component.isLocked {
                        Button(component.isLocked ? "Unlock Component" : "Lock Component",
                               systemImage: component.isLocked ? "lock.fill" : "lock.open") {
                            workspace.toggleBodyLocked(component.solidId)
                        }
                        .foregroundStyle(.secondary)
                        .help(component.isLocked ? "Unlock Component" : "Lock Component")
                    }
                }
                .barControl()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .contextMenu {
                componentContextMenu
            }

            if component.isSubassembly && isExpanded {
                ForEach(component.childInstances) { child in
                    NavigatorComponentRow(component: child, indentLevel: indentLevel + 1)
                        .tag(child.solidId)
                }
                ForEach(component.childConstraints) { constraint in
                    HStack(spacing: 0) {
                        Spacer().frame(width: CGFloat((indentLevel + 1) * 12 + 16))
                        NavigatorConstraintRow(constraint: constraint)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.name), \(component.isSubassembly ? "Subassembly" : "Component")\(component.isGrounded ? ", Grounded" : ", \(dof) degrees of freedom"), ID \(component.solidId.rawValue), \(referenceDescription)")
        .accessibilityValue(component.isGrounded ? "Grounded" : "\(dof) DOF")
        .accessibilityIdentifier("navigator-component-\(component.solidId.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: component.isGrounded ? "Float Component" : "Ground Component") {
            workspace.toggleComponentInstanceGrounded(id: component.id)
        }
        .accessibilityAction(named: component.isVisible ? "Hide Component" : "Show Component") {
            workspace.toggleBodyVisibility(component.solidId)
        }
        .accessibilityAction(named: component.isLocked ? "Unlock Component" : "Lock Component") {
            workspace.toggleBodyLocked(component.solidId)
        }
    }

    private var referenceDescription: String {
        switch component.reference {
        case .internalPart(let name, _):
            return "Internal: \(name)"
        case .externalDocument(let url, let partName):
            if let partName {
                return "\(url.lastPathComponent) (\(partName))"
            } else {
                return url.lastPathComponent
            }
        case .subassembly(let name):
            return "Subassembly: \(name)"
        }
    }

    @ViewBuilder
    private func badges(dof: Int) -> some View {
        if component.isSubassembly {
            subassemblyBadges
        } else {
            componentBadge
        }
        groundedOrDOFBadge(dof: dof)
        patternAndMirrorBadges
    }

    @ViewBuilder
    private var subassemblyBadges: some View {
        Text("Subassembly")
            .font(.caption2)
            .foregroundStyle(.purple)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.purple.opacity(0.12))
            )
            .accessibilityIdentifier("navigator-subassembly-badge-\(component.id.uuidString)")

        Text(component.subassemblyBehavior == .flexible ? "Flexible" : "Rigid")
            .font(.caption2)
            .foregroundStyle(component.subassemblyBehavior == .flexible ? .indigo : .secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(component.subassemblyBehavior == .flexible ? Color.indigo.opacity(0.15) : Color.secondary.opacity(0.12))
            )
            .accessibilityIdentifier("navigator-subassembly-behavior-badge-\(component.id.uuidString)")
    }

    @ViewBuilder
    private var componentBadge: some View {
        Text("Component")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    @ViewBuilder
    private func groundedOrDOFBadge(dof: Int) -> some View {
        if component.isGrounded {
            Text("Grounded")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.opacity(0.15))
                )
        } else {
            Text("\(dof) DOF")
                .font(.caption2)
                .foregroundStyle(dof == 0 ? .green : .secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(dof == 0 ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                )
                .accessibilityIdentifier("navigator-component-dof-badge-\(component.id.uuidString)")
        }
    }

    @ViewBuilder
    private var patternAndMirrorBadges: some View {
        if component.patternId != nil {
            Text("Pattern")
                .font(.caption2)
                .foregroundStyle(.cyan)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.cyan.opacity(0.15))
                )
                .accessibilityIdentifier("navigator-component-pattern-badge-\(component.id.uuidString)")
        }

        if component.mirrorId != nil {
            Text("Mirrored")
                .font(.caption2)
                .foregroundStyle(.teal)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.teal.opacity(0.15))
                )
                .accessibilityIdentifier("navigator-component-mirror-badge-\(component.id.uuidString)")
        }
    }

    @ViewBuilder
    private var componentContextMenu: some View {
        subassemblyContextGroup
        componentStateContextGroup
        patternAndMirrorContextGroup
        deleteContextGroup
    }

    @ViewBuilder
    private var subassemblyContextGroup: some View {
        if component.isSubassembly {
            Button(component.subassemblyBehavior == .flexible ? "Make Subassembly Rigid" : "Make Subassembly Flexible") {
                workspace.toggleSubassemblyBehavior(id: component.id)
            }
            Button("Dissolve Subassembly") {
                workspace.dissolveSubassembly(id: component.id)
            }
            Divider()
        }
    }

    @ViewBuilder
    private var componentStateContextGroup: some View {
        Button(component.isGrounded ? "Float Component" : "Ground Component") {
            workspace.toggleComponentInstanceGrounded(id: component.id)
        }
        Button(component.isVisible ? "Hide Component" : "Show Component") {
            workspace.toggleBodyVisibility(component.solidId)
        }
        Button(component.isLocked ? "Unlock Component" : "Lock Component") {
            workspace.toggleBodyLocked(component.solidId)
        }
        Divider()
    }

    @ViewBuilder
    private var patternAndMirrorContextGroup: some View {
        Menu("Pattern Component") {
            Button("Linear Pattern…") {
                _ = workspace.patternComponentLinear(id: component.id)
            }
            Button("Circular Pattern…") {
                _ = workspace.patternComponentCircular(id: component.id)
            }
            Button("Pattern by Part Feature…") {
                _ = workspace.patternComponentByFeaturePattern(id: component.id)
            }
        }
        Button("Mirror Component…") {
            _ = workspace.mirrorComponent(id: component.id)
        }
        if let pId = component.patternId {
            Button("Remove Pattern") {
                _ = workspace.removeComponentPattern(id: pId)
            }
        }
        if let mId = component.mirrorId {
            Button("Remove Mirror") {
                _ = workspace.removeComponentMirror(id: mId)
            }
        }
        Divider()
    }

    @ViewBuilder
    private var deleteContextGroup: some View {
        Button(role: .destructive) {
            workspace.removeComponentInstance(id: component.id)
        } label: {
            Text(component.isSubassembly ? "Remove Subassembly" : "Remove Component")
        }
    }
}

/// Outline row for an assembly mate or joint in the Navigator sidebar (BL-ASM-04, #165).
struct NavigatorConstraintRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let constraint: AssemblyConstraint
    @State private var isHovered = false

    var body: some View {
        let isSelected = workspace.selectedAssemblyConstraintId == constraint.id
        let isConflicting = workspace.isAssemblyConstraintConflicting(constraint.id)
        let isRedundant = workspace.isAssemblyConstraintRedundant(constraint.id)

        HStack(alignment: .center, spacing: 8) {
            Image(systemName: constraint.kind.systemImageName)
                .foregroundStyle(isConflicting ? Color.red : (constraint.isSuppressed ? Color.secondary : (constraint.kind.isJoint ? Color.purple : Color.blue)))
                .frame(width: 16)
                .help(constraint.kind.displayName)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(constraint.name)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough(constraint.isSuppressed)
                        .foregroundStyle(constraint.isSuppressed ? .secondary : .primary)

                    Text(constraint.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    if constraint.isSuppressed {
                        Text("Suppressed")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }

                    if isConflicting {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Conflict")
                        }
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red.opacity(0.15))
                        )
                        .accessibilityIdentifier("navigator-constraint-conflict-badge-\(constraint.id.uuidString)")
                    } else if isRedundant {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text("Redundant")
                        }
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.15))
                        )
                        .accessibilityIdentifier("navigator-constraint-redundant-badge-\(constraint.id.uuidString)")
                    }
                }
            }

            Spacer(minLength: 4)

            if isHovered || constraint.isSuppressed {
                Button(constraint.isSuppressed ? "Unsuppress Constraint" : "Suppress Constraint",
                       systemImage: constraint.isSuppressed ? "eye.slash.fill" : "eye") {
                    workspace.toggleAssemblyConstraintSuppressed(id: constraint.id)
                }
                .foregroundStyle(constraint.isSuppressed ? .orange : .secondary)
                .help(constraint.isSuppressed ? "Unsuppress Constraint" : "Suppress Constraint")
                .barControl()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectAssemblyConstraint(constraint.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Button(constraint.isSuppressed ? "Unsuppress" : "Suppress") {
                workspace.toggleAssemblyConstraintSuppressed(id: constraint.id)
            }
            Button("Solve Assembly") {
                _ = workspace.solveAssemblyConstraints()
            }
            Divider()
            Button("Delete", role: .destructive) {
                workspace.removeAssemblyConstraint(id: constraint.id)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(constraint.name), \(constraint.kind.displayName)\(constraint.isSuppressed ? ", Suppressed" : "")\(isConflicting ? ", Conflict" : "")\(isRedundant ? ", Redundant" : "")")
        .accessibilityIdentifier("navigator-constraint-\(constraint.id.uuidString)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: constraint.isSuppressed ? "Unsuppress Constraint" : "Suppress Constraint") {
            workspace.toggleAssemblyConstraintSuppressed(id: constraint.id)
        }
    }
}

/// Outline row for a 2D sketch feature in the Navigator sidebar (BL-SKT-18, #366).
struct NavigatorSketchRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let feature: Feature
    @State private var isHovered = false

    init(feature: Feature) {
        self.feature = feature
    }

    nonisolated static let defaultAccessibilityTraits: AccessibilityTraits = .isButton

    nonisolated static func accessibilityTraits(isSelected: Bool = false) -> AccessibilityTraits {
        isSelected ? [defaultAccessibilityTraits, .isSelected] : defaultAccessibilityTraits
    }

    var body: some View {
        let isSelected = workspace.isFeatureSelected(feature)
        let status = workspace.sketchDOFStatus(for: feature)
        let count = entityCount

        HStack(alignment: .center, spacing: 8) {
            Image(systemName: Self.treeIconSystemImage(for: status))
                .foregroundStyle(Self.treeIconColor(for: status))
                .frame(width: 16)
                .help(status.statusText)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.name)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough(feature.isSuppressed)
                        .foregroundStyle(feature.isSuppressed ? .secondary : .primary)

                    Text("Sketch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    if feature.isSuppressed {
                        Text("Suppressed")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }

                    if !status.isInactive {
                        dofBadge(for: status)
                    }
                }

                Text(Self.subtitle(entityCount: count, status: status))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Group {
                if isHovered || feature.isSuppressed {
                    Button(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature",
                           systemImage: feature.isSuppressed ? "eye.slash.fill" : "eye") {
                        workspace.toggleFeatureSuppressed(feature.id)
                    }
                    .foregroundStyle(feature.isSuppressed ? .orange : .secondary)
                    .help(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature")
                    .disabled(feature.isLocked)
                }
                if isHovered || feature.isLocked {
                    Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                           systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                        workspace.toggleFeatureLocked(feature.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                }
            }
            .barControl()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Button(feature.isSuppressed ? "Unsuppress" : "Suppress") {
                workspace.toggleFeatureSuppressed(feature.id)
            }
            .disabled(feature.isLocked)

            Button(feature.isLocked ? "Unlock" : "Lock") {
                workspace.toggleFeatureLocked(feature.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                workspace.requestDeleteFeature(feature.id)
            }
            .disabled(feature.isLocked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(Self.accessibilityTraits(isSelected: isSelected))
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, entityCount: count, status: status, isLocked: feature.isLocked, isSuppressed: feature.isSuppressed))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
        }
        .accessibilityAction(named: feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature") {
            workspace.toggleFeatureSuppressed(feature.id)
        }
        .accessibilityAction(named: feature.isLocked ? "Unlock Feature" : "Lock Feature") {
            workspace.toggleFeatureLocked(feature.id)
        }
        .accessibilityAction(named: "Delete") {
            workspace.requestDeleteFeature(feature.id)
        }
    }

    private var entityCount: Int {
        if case .sketch(let data) = feature.operation {
            return data.entities.count
        }
        return 0
    }

    @ViewBuilder
    private func dofBadge(for status: SketchDOFStatus) -> some View {
        let color = ViewportStatusBar.dofColor(for: status) ?? .secondary
        Text(status.badgeText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
    }

    nonisolated static func treeIconSystemImage(for status: SketchDOFStatus) -> String {
        switch status {
        case .inactive:
            return "pencil.and.ruler.fill"
        case .underConstrained:
            return "pencil.and.ruler.fill"
        case .fullyConstrained:
            return "checkmark.circle.fill"
        case .overConstrained:
            return "exclamationmark.triangle.fill"
        }
    }

    nonisolated static func treeIconColor(for status: SketchDOFStatus) -> Color {
        switch status {
        case .inactive:
            return .purple
        case .underConstrained:
            return .blue
        case .fullyConstrained:
            return .green
        case .overConstrained:
            return .red
        }
    }

    nonisolated static func badgeText(for status: SketchDOFStatus) -> String {
        status.badgeText
    }

    nonisolated static func subtitle(entityCount: Int, status: SketchDOFStatus) -> String {
        if status.isInactive {
            return "\(entityCount) entities"
        } else {
            return "\(entityCount) entities • \(status.summaryDescription)"
        }
    }

    nonisolated static func accessibilityLabel(featureName: String, entityCount: Int, status: SketchDOFStatus, isLocked: Bool = false, isSuppressed: Bool = false) -> String {
        "\(featureName), Sketch, \(entityCount) entities, \(status.statusText)\(isLocked ? ", Locked" : "")\(isSuppressed ? ", Suppressed" : "")"
    }
}

/// Outline row for a datum plane feature in the Navigator sidebar.
struct NavigatorDatumPlaneRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let feature: Feature
    @State private var isHovered = false

    init(feature: Feature) {
        self.feature = feature
    }

    nonisolated static let defaultAccessibilityTraits: AccessibilityTraits = .isButton

    nonisolated static func accessibilityTraits(isSelected: Bool = false) -> AccessibilityTraits {
        isSelected ? [defaultAccessibilityTraits, .isSelected] : defaultAccessibilityTraits
    }

    nonisolated static func accessibilityLabel(featureName: String, isLocked: Bool = false, isSuppressed: Bool = false) -> String {
        "\(featureName), Datum Plane\(isLocked ? ", Locked" : "")\(isSuppressed ? ", Suppressed" : "")"
    }

    var body: some View {
        let isSelected = workspace.isFeatureSelected(feature)
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "square.dashed")
                .foregroundStyle(Color.blue)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.name)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough(feature.isSuppressed)
                        .foregroundStyle(feature.isSuppressed ? .secondary : .primary)

                    Text("Datum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    if feature.isSuppressed {
                        Text("Suppressed")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }

                if case .datumPlane(let data) = feature.operation {
                    Text(data.mode.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Group {
                if isHovered || feature.isSuppressed {
                    Button(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature",
                           systemImage: feature.isSuppressed ? "eye.slash.fill" : "eye") {
                        workspace.toggleFeatureSuppressed(feature.id)
                    }
                    .foregroundStyle(feature.isSuppressed ? .orange : .secondary)
                    .help(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature")
                    .disabled(feature.isLocked)
                }
                if isHovered || feature.isLocked {
                    Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                           systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                        workspace.toggleFeatureLocked(feature.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                }
            }
            .barControl()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Button(feature.isSuppressed ? "Unsuppress" : "Suppress") {
                workspace.toggleFeatureSuppressed(feature.id)
            }
            .disabled(feature.isLocked)

            Button(feature.isLocked ? "Unlock" : "Lock") {
                workspace.toggleFeatureLocked(feature.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                workspace.requestDeleteFeature(feature.id)
            }
            .disabled(feature.isLocked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(Self.accessibilityTraits(isSelected: isSelected))
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, isLocked: feature.isLocked, isSuppressed: feature.isSuppressed))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
        }
        .accessibilityAction(named: feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature") {
            workspace.toggleFeatureSuppressed(feature.id)
        }
        .accessibilityAction(named: feature.isLocked ? "Unlock Feature" : "Lock Feature") {
            workspace.toggleFeatureLocked(feature.id)
        }
        .accessibilityAction(named: "Delete") {
            workspace.requestDeleteFeature(feature.id)
        }
    }
}

/// Outline row for a datum axis feature in the Navigator sidebar.
struct NavigatorDatumAxisRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let feature: Feature
    @State private var isHovered = false

    init(feature: Feature) {
        self.feature = feature
    }

    nonisolated static let defaultAccessibilityTraits: AccessibilityTraits = .isButton

    nonisolated static func accessibilityTraits(isSelected: Bool = false) -> AccessibilityTraits {
        isSelected ? [defaultAccessibilityTraits, .isSelected] : defaultAccessibilityTraits
    }

    nonisolated static func accessibilityLabel(featureName: String, isLocked: Bool = false, isSuppressed: Bool = false) -> String {
        "\(featureName), Datum Axis\(isLocked ? ", Locked" : "")\(isSuppressed ? ", Suppressed" : "")"
    }

    var body: some View {
        let isSelected = workspace.isFeatureSelected(feature)
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "line.diagonal")
                .foregroundStyle(Color.orange)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.name)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough(feature.isSuppressed)
                        .foregroundStyle(feature.isSuppressed ? .secondary : .primary)

                    Text("Axis")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    if feature.isSuppressed {
                        Text("Suppressed")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }

                if case .datumAxis(let data) = feature.operation {
                    Text(data.mode.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Group {
                if isHovered || feature.isSuppressed {
                    Button(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature",
                           systemImage: feature.isSuppressed ? "eye.slash.fill" : "eye") {
                        workspace.toggleFeatureSuppressed(feature.id)
                    }
                    .foregroundStyle(feature.isSuppressed ? .orange : .secondary)
                    .help(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature")
                    .disabled(feature.isLocked)
                }
                if isHovered || feature.isLocked {
                    Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                           systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                        workspace.toggleFeatureLocked(feature.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                }
            }
            .barControl()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Button(feature.isSuppressed ? "Unsuppress" : "Suppress") {
                workspace.toggleFeatureSuppressed(feature.id)
            }
            .disabled(feature.isLocked)

            Button(feature.isLocked ? "Unlock" : "Lock") {
                workspace.toggleFeatureLocked(feature.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                workspace.requestDeleteFeature(feature.id)
            }
            .disabled(feature.isLocked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(Self.accessibilityTraits(isSelected: isSelected))
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, isLocked: feature.isLocked, isSuppressed: feature.isSuppressed))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
        }
        .accessibilityAction(named: feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature") {
            workspace.toggleFeatureSuppressed(feature.id)
        }
        .accessibilityAction(named: feature.isLocked ? "Unlock Feature" : "Lock Feature") {
            workspace.toggleFeatureLocked(feature.id)
        }
        .accessibilityAction(named: "Delete") {
            workspace.requestDeleteFeature(feature.id)
        }
    }
}

/// Outline row for a datum point feature in the Navigator sidebar.
struct NavigatorDatumPointRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let feature: Feature
    @State private var isHovered = false

    init(feature: Feature) {
        self.feature = feature
    }

    nonisolated static let defaultAccessibilityTraits: AccessibilityTraits = .isButton

    nonisolated static func accessibilityTraits(isSelected: Bool = false) -> AccessibilityTraits {
        isSelected ? [defaultAccessibilityTraits, .isSelected] : defaultAccessibilityTraits
    }

    nonisolated static func accessibilityLabel(featureName: String, isLocked: Bool = false, isSuppressed: Bool = false) -> String {
        "\(featureName), Datum Point\(isLocked ? ", Locked" : "")\(isSuppressed ? ", Suppressed" : "")"
    }

    var body: some View {
        let isSelected = workspace.isFeatureSelected(feature)
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "smallcircle.filled.circle")
                .foregroundStyle(Color.green)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.name)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough(feature.isSuppressed)
                        .foregroundStyle(feature.isSuppressed ? .secondary : .primary)

                    Text("Point")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    if feature.isSuppressed {
                        Text("Suppressed")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }

                if case .datumPoint(let data) = feature.operation {
                    Text(data.mode.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Group {
                if isHovered || feature.isSuppressed {
                    Button(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature",
                           systemImage: feature.isSuppressed ? "eye.slash.fill" : "eye") {
                        workspace.toggleFeatureSuppressed(feature.id)
                    }
                    .foregroundStyle(feature.isSuppressed ? .orange : .secondary)
                    .help(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature")
                    .disabled(feature.isLocked)
                }
                if isHovered || feature.isLocked {
                    Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                           systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                        workspace.toggleFeatureLocked(feature.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                }
            }
            .barControl()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Button(feature.isSuppressed ? "Unsuppress" : "Suppress") {
                workspace.toggleFeatureSuppressed(feature.id)
            }
            .disabled(feature.isLocked)

            Button(feature.isLocked ? "Unlock" : "Lock") {
                workspace.toggleFeatureLocked(feature.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                workspace.requestDeleteFeature(feature.id)
            }
            .disabled(feature.isLocked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(Self.accessibilityTraits(isSelected: isSelected))
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, isLocked: feature.isLocked, isSuppressed: feature.isSuppressed))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
        }
        .accessibilityAction(named: feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature") {
            workspace.toggleFeatureSuppressed(feature.id)
        }
        .accessibilityAction(named: feature.isLocked ? "Unlock Feature" : "Lock Feature") {
            workspace.toggleFeatureLocked(feature.id)
        }
        .accessibilityAction(named: "Delete") {
            workspace.requestDeleteFeature(feature.id)
        }
    }
}

/// Outline row for a User Coordinate System (UCS) feature in the Navigator sidebar.
struct NavigatorDatumCoordinateSystemRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let feature: Feature
    @State private var isHovered = false

    init(feature: Feature) {
        self.feature = feature
    }

    nonisolated static let defaultAccessibilityTraits: AccessibilityTraits = .isButton

    nonisolated static func accessibilityTraits(isSelected: Bool = false) -> AccessibilityTraits {
        isSelected ? [defaultAccessibilityTraits, .isSelected] : defaultAccessibilityTraits
    }

    nonisolated static func accessibilityLabel(featureName: String, isLocked: Bool = false, isSuppressed: Bool = false) -> String {
        "\(featureName), Datum UCS\(isLocked ? ", Locked" : "")\(isSuppressed ? ", Suppressed" : "")"
    }

    var body: some View {
        let isSelected = workspace.isFeatureSelected(feature)
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "dot.scope")
                .foregroundStyle(Color.purple)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.name)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough(feature.isSuppressed)
                        .foregroundStyle(feature.isSuppressed ? .secondary : .primary)

                    Text("UCS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    if feature.isSuppressed {
                        Text("Suppressed")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }

                if case .datumCoordinateSystem(let data) = feature.operation {
                    Text(data.mode.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Group {
                if isHovered || feature.isSuppressed {
                    Button(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature",
                           systemImage: feature.isSuppressed ? "eye.slash.fill" : "eye") {
                        workspace.toggleFeatureSuppressed(feature.id)
                    }
                    .foregroundStyle(feature.isSuppressed ? .orange : .secondary)
                    .help(feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature")
                    .disabled(feature.isLocked)
                }
                if isHovered || feature.isLocked {
                    Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                           systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                        workspace.toggleFeatureLocked(feature.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                }
            }
            .barControl()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Button(feature.isSuppressed ? "Unsuppress" : "Suppress") {
                workspace.toggleFeatureSuppressed(feature.id)
            }
            .disabled(feature.isLocked)

            Button(feature.isLocked ? "Unlock" : "Lock") {
                workspace.toggleFeatureLocked(feature.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                workspace.requestDeleteFeature(feature.id)
            }
            .disabled(feature.isLocked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(Self.accessibilityTraits(isSelected: isSelected))
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, isLocked: feature.isLocked, isSuppressed: feature.isSuppressed))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
        }
        .accessibilityAction(named: feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature") {
            workspace.toggleFeatureSuppressed(feature.id)
        }
        .accessibilityAction(named: feature.isLocked ? "Unlock Feature" : "Lock Feature") {
            workspace.toggleFeatureLocked(feature.id)
        }
        .accessibilityAction(named: "Delete") {
            workspace.requestDeleteFeature(feature.id)
        }
    }
}

struct NavigatorParameterRow: View {
    let param: DocumentParameter

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.below.rectangle")
                .foregroundStyle(.secondary)
            Text(param.name)
                .font(.callout)
            Spacer()
            Text("\(param.value, specifier: "%.1f")\(param.unit.isEmpty ? "" : " " + param.unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(param.comment.isEmpty ? "\(param.name): \(param.value) \(param.unit)" : "\(param.name) (\(param.comment))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(param.name), \(param.value) \(param.unit)")
    }
}

/// Outline row for an exploded view in the Navigator sidebar (BL-ASM-12).
struct NavigatorExplodedViewRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let view: ExplodedView
    @State private var isExpanded: Bool = true
    @State private var isHovered: Bool = false

    var body: some View {
        let isSelected = workspace.selectedExplodedViewId == view.id && workspace.selectedExplodeStepId == nil
        let isActive = workspace.activeExplodedViewId == view.id && !view.isCollapsed

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                if !view.steps.isEmpty {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: "shippingbox.and.arrow.backward")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 16)

                Text(view.name)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .accessibilityIdentifier("navigator-exploded-view-active-badge-\(view.id.uuidString)")
                } else if view.isCollapsed && workspace.activeExplodedViewId == view.id {
                    Text("Collapsed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }

                Spacer(minLength: 4)

                if isHovered || isActive {
                    Button(isActive ? "Collapse" : "Explode", systemImage: isActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                        workspace.toggleExplodedView(id: view.id)
                    }
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .help(isActive ? "Collapse Exploded View" : "Activate and Explode")
                    .barControl()
                }

                if isHovered {
                    Button("Add Step", systemImage: "plus") {
                        _ = workspace.addExplodeStep(viewId: view.id)
                    }
                    .foregroundStyle(.secondary)
                    .help("Add Explode Step")
                    .barControl()
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                workspace.selectExplodedView(view.id)
            }
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
            .contextMenu {
                Button(isActive ? "Collapse" : "Explode") {
                    workspace.toggleExplodedView(id: view.id)
                }
                Button(view.isCollapsed ? "Expand Steps" : "Collapse Steps") {
                    workspace.toggleExplodedViewCollapsed(id: view.id)
                }
                Divider()
                Button("Add Step") {
                    _ = workspace.addExplodeStep(viewId: view.id)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    workspace.removeExplodedView(id: view.id)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(view.name), Exploded View, \(view.steps.count) steps\(isActive ? ", Active" : "")")
            .accessibilityIdentifier("navigator-exploded-view-\(view.id.uuidString)")

            if isExpanded {
                ForEach(view.steps) { step in
                    NavigatorExplodeStepRow(view: view, step: step, indentLevel: 1)
                }
            }
        }
    }
}

/// Outline row for an explode step in the Navigator sidebar (BL-ASM-12).
struct NavigatorExplodeStepRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let view: ExplodedView
    let step: ExplodeStep
    var indentLevel: Int = 1
    @State private var isHovered: Bool = false

    var body: some View {
        let isSelected = workspace.selectedExplodedViewId == view.id && workspace.selectedExplodeStepId == step.id
        let lengthUnit = workspace.document.settings.units.lengthUnit
        let displayDist = InspectorUnitConversion.displayLength(Double(step.distance), unit: lengthUnit)

        HStack(alignment: .center, spacing: 6) {
            Spacer().frame(width: CGFloat(indentLevel * 12 + 8))

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(step.name)
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text("\(step.targetInstanceIds.count) parts")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))
                )

            Text("\(displayDist.formatted(.number.precision(.fractionLength(1)))) \(lengthUnit.symbol)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if step.hasTrail {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .help("Trail enabled")
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectExplodeStep(viewId: view.id, stepId: step.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Button(step.hasTrail ? "Hide Trail" : "Show Trail") {
                var copy = step
                copy.hasTrail.toggle()
                workspace.updateExplodeStep(viewId: view.id, step: copy)
            }
            Divider()
            Button("Delete Step", role: .destructive) {
                workspace.removeExplodeStep(viewId: view.id, stepId: step.id)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.name), Step, \(step.targetInstanceIds.count) targets, \(displayDist.formatted(.number.precision(.fractionLength(1)))) \(lengthUnit.symbol)")
        .accessibilityIdentifier("navigator-explode-step-\(step.id.uuidString)")
    }
}

/// Outline row for a drawing sheet in the Navigator sidebar (BL-DRW-01, #208).
struct NavigatorSheetRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let sheet: DrawingSheet
    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""
    @State private var isExpanded: Bool = true

    private var isActive: Bool {
        workspace.document.activeSheetId == sheet.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if !sheet.views.isEmpty || !sheet.annotations.isEmpty {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse Sheet Contents" : "Expand Sheet Contents")
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: "doc.text")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sheet.name)
                        .fontWeight(isActive ? .semibold : .regular)
                    Text("\(sheet.size.displayName) · \(sheet.orientation.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                workspace.setActiveSheetId(sheet.id)
            }
            .contextMenu {
                Menu("Add Base View") {
                    Button("Front") { _ = workspace.addBaseView(standardView: .front) }
                    Button("Top") { _ = workspace.addBaseView(standardView: .top) }
                    Button("Right") { _ = workspace.addBaseView(standardView: .right) }
                    Button("Back") { _ = workspace.addBaseView(standardView: .back) }
                    Button("Bottom") { _ = workspace.addBaseView(standardView: .bottom) }
                    Button("Left") { _ = workspace.addBaseView(standardView: .left) }
                    Divider()
                    Button("Isometric") { _ = workspace.addBaseView(standardView: .isometric) }
                }
                Divider()
                Button("Duplicate") {
                    _ = workspace.duplicateSheet(id: sheet.id)
                }
                Button("Rename…") {
                    renameText = sheet.name
                    isRenaming = true
                }
                Divider()
                Button("Delete Sheet", role: .destructive) {
                    _ = workspace.removeSheet(id: sheet.id)
                }
                .disabled(workspace.document.sheets.count <= 1)
            }

            if isExpanded {
                if !sheet.views.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(sheet.views) { v in
                            NavigatorDrawingViewRow(view: v, sheet: sheet)
                        }
                    }
                    .padding(.leading, 24)
                }

                if !sheet.annotations.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(sheet.annotations) { a in
                            NavigatorDrawingAnnotationRow(annotation: a, sheet: sheet)
                        }
                    }
                    .padding(.leading, 24)
                }

                if !sheet.bomTables.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(sheet.bomTables) { table in
                            NavigatorDrawingBOMTableRow(table: table, sheet: sheet)
                        }
                    }
                    .padding(.leading, 24)
                }
            }
        }
        .sheet(isPresented: $isRenaming) {
            VStack(spacing: 16) {
                Text("Rename Sheet")
                    .font(.headline)
                TextField("Sheet Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                HStack {
                    Button("Cancel") { isRenaming = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Rename") {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            var updated = sheet
                            updated.name = trimmed
                            _ = workspace.updateSheet(updated)
                        }
                        isRenaming = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .accessibilityIdentifier("navigator-sheet-row-\(sheet.name)")
    }
}

/// Outline row for a drawing view inside a drawing sheet (BL-DRW-03, #210).
struct NavigatorDrawingViewRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let view: DrawingView
    let sheet: DrawingSheet
    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""

    private var isSelected: Bool {
        workspace.selectedDrawingViewId == view.id
    }

    private var kindIconName: String {
        switch view.kind {
        case .base:
            return "rectangle.inset.filled"
        case .projected:
            return "square.split.2x1"
        case .section:
            return "scissors"
        case .detail:
            return "magnifyingglass"
        case .auxiliary:
            return "arrow.up.right.square"
        case .broken:
            return "divide"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kindIconName)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(view.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(view.kind.displayName) · \(view.standardView.rawValue.capitalized) · [\(view.scale.displayString)]")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.selectDrawingView(view.id)
            if workspace.document.activeSheetId != sheet.id {
                workspace.setActiveSheetId(sheet.id)
            }
        }
        .contextMenu {
            Menu("Add Projected View") {
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
                Divider()
                Button("Isometric") {
                    _ = workspace.addProjectedView(parentViewId: view.id, direction: .isometricTopRight)
                }
            }
            Menu("Add Derived View") {
                Button("Section View") {
                    _ = workspace.addSectionView(parentViewId: view.id)
                }
                Button("Detail View") {
                    _ = workspace.addDetailView(parentViewId: view.id)
                }
                Button("Auxiliary View") {
                    _ = workspace.addAuxiliaryView(parentViewId: view.id)
                }
                Button("Broken View") {
                    _ = workspace.addBrokenView(parentViewId: view.id)
                }
            }
            Divider()
            Button("Rename…") {
                renameText = view.name
                isRenaming = true
            }
            Divider()
            Button("Delete View", role: .destructive) {
                _ = workspace.removeDrawingView(id: view.id)
            }
        }
        .sheet(isPresented: $isRenaming) {
            VStack(spacing: 16) {
                Text("Rename View")
                    .font(.headline)
                TextField("View Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                HStack {
                    Button("Cancel") { isRenaming = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Rename") {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            var updated = view
                            updated.name = trimmed
                            _ = workspace.updateDrawingView(updated)
                        }
                        isRenaming = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .accessibilityIdentifier("navigator-drawing-view-\(view.id.uuidString)")
    }
}

/// Outline row for a drawing annotation or dimension inside a drawing sheet (BL-DRW-05, #212).
struct NavigatorDrawingAnnotationRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let annotation: DrawingAnnotation
    let sheet: DrawingSheet

    private var isSelected: Bool {
        workspace.selectedDrawingAnnotationId == annotation.id
    }

    private var iconName: String {
        switch annotation.kind {
        case .linear:
            return "ruler"
        case .angular:
            return "angle"
        case .radial:
            return "circle.circle"
        case .ordinate:
            return "arrow.left.and.right"
        case .baseline:
            return "chart.bar"
        case .note:
            return "text.alignleft"
        case .leader:
            return "arrow.up.left"
        case .centerMark:
            return "plus"
        case .centerline:
            return "line.diagonal"
        case .holeCallout:
            return "circle.dotted"
        case .balloon:
            return "circle.circle"
        }
    }

    private var summaryText: String {
        switch annotation.data {
        case .linear(let d):
            return d.formattedText
        case .angular(let d):
            return d.formattedText
        case .radial(let d):
            return d.formattedText
        case .ordinate(let d):
            return d.formattedText
        case .baseline(let d):
            return "\(d.targetPointsMM.count) items"
        case .note(let d):
            return d.text
        case .leader(let d):
            return d.text
        case .centerMark:
            return "Mark"
        case .centerline:
            return "Centerline"
        case .holeCallout(let d):
            return d.formattedCalloutLines.first ?? "Callout"
        case .balloon(let d):
            return "Item \(d.formattedText)"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(annotation.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if annotation.isDangling {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.orange)
            }

            Spacer()

            if !annotation.isVisible {
                Image(systemName: "eye.slash")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .contentShape(Rectangle())
        .onTapGesture {
            if workspace.document.activeSheetId != sheet.id {
                workspace.setActiveSheetId(sheet.id)
            }
            workspace.selectDrawingAnnotation(annotation.id)
        }
        .contextMenu {
            Button("Delete Annotation", role: .destructive) {
                _ = workspace.removeDrawingAnnotation(id: annotation.id)
            }
        }
        .accessibilityIdentifier("navigator-annotation-\(annotation.id.uuidString)")
    }
}

/// Outline row for a BOM table placed on a drawing sheet (BL-DRW-08, #215).
struct NavigatorDrawingBOMTableRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let table: DrawingBOMTable
    let sheet: DrawingSheet

    private var isSelected: Bool {
        workspace.selectedDrawingBOMTableId == table.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(table.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(table.columns.count) columns • \(table.structure.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .contentShape(Rectangle())
        .onTapGesture {
            if workspace.document.activeSheetId != sheet.id {
                workspace.setActiveSheetId(sheet.id)
            }
            workspace.selectDrawingBOMTable(table.id)
        }
        .contextMenu {
            Button("Delete BOM Table", role: .destructive) {
                _ = workspace.removeBOMTable(id: table.id)
            }
        }
        .accessibilityIdentifier("navigator-bom-table-\(table.id.uuidString)")
    }
}

// MARK: - Simulation Study Rows (BL-SIM-01, #157)

/// Outline row for a simulation study in the Navigator sidebar (BL-SIM-01, #157).
struct NavigatorSimulationStudyRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy
    @State private var isHovered: Bool = false

    var body: some View {
        let isSelected = workspace.selectedSimulationStudyId == study.id &&
            workspace.selectedSimulationFixtureId == nil &&
            workspace.selectedSimulationLoadId == nil &&
            workspace.selectedSimulationMaterialAssignmentId == nil &&
            !workspace.isSimulationMeshSelected &&
            !workspace.isSimulationResultsSelected
        let isActive = workspace.document.activeStudy?.id == study.id

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Button {
                    workspace.toggleSimulationStudyCollapsed(id: study.id)
                } label: {
                    Image(systemName: study.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                Image(systemName: study.studyType.systemImageName)
                    .font(.caption)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 14)

                Text(study.name)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .accessibilityIdentifier("navigator-study-active-badge-\(study.id)")
                }

                Spacer(minLength: 4)

                if isHovered {
                    Menu {
                        if workspace.isStudyRunning(study.id) {
                            Button("Cancel Solve") {
                                workspace.cancelSimulationStudy(id: study.id)
                            }
                        } else {
                            Button("Run Study") {
                                workspace.runSimulationStudy(id: study.id)
                            }
                        }
                        Divider()
                        if !isActive {
                            Button("Set as Active Study") {
                                workspace.setActiveSimulationStudy(id: study.id)
                            }
                        }
                        Button("Add Fixture…") {
                            _ = workspace.addSimulationFixture(studyId: study.id)
                        }
                        Button("Add Load…") {
                            _ = workspace.addSimulationLoad(studyId: study.id)
                        }
                        Button("Add Connection…") {
                            _ = workspace.addSimulationConnection(studyId: study.id)
                        }
                        Divider()
                        Button("Delete Study", role: .destructive) {
                            workspace.removeSimulationStudy(id: study.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                workspace.selectSimulationStudy(study.id)
            }
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
            .contextMenu {
                if workspace.isStudyRunning(study.id) {
                    Button("Cancel Solve") {
                        workspace.cancelSimulationStudy(id: study.id)
                    }
                } else {
                    Button("Run Study") {
                        workspace.runSimulationStudy(id: study.id)
                    }
                }
                Divider()
                if !isActive {
                    Button("Set as Active Study") {
                        workspace.setActiveSimulationStudy(id: study.id)
                    }
                }
                Button("Add Fixture…") {
                    _ = workspace.addSimulationFixture(studyId: study.id)
                }
                Button("Add Load…") {
                    _ = workspace.addSimulationLoad(studyId: study.id)
                }
                Button("Add Connection…") {
                    _ = workspace.addSimulationConnection(studyId: study.id)
                }
                Divider()
                Button("Delete Study", role: .destructive) {
                    workspace.removeSimulationStudy(id: study.id)
                }
            }
            .accessibilityIdentifier("navigator-study-\(study.id)")

            if !study.isCollapsed {
                VStack(spacing: 2) {
                    // Materials row / children
                    if study.materials.isEmpty {
                        NavigatorSimulationMaterialRow(study: study, assignment: nil)
                    } else {
                        ForEach(study.materials) { assignment in
                            NavigatorSimulationMaterialRow(study: study, assignment: assignment)
                        }
                    }

                    // Fixtures rows
                    if study.fixtures.isEmpty {
                        NavigatorSimulationFixtureRow(study: study, fixture: nil)
                    } else {
                        ForEach(study.fixtures) { fixture in
                            NavigatorSimulationFixtureRow(study: study, fixture: fixture)
                        }
                    }

                    // Loads rows
                    if study.loads.isEmpty {
                        NavigatorSimulationLoadRow(study: study, load: nil)
                    } else {
                        ForEach(study.loads) { load in
                            NavigatorSimulationLoadRow(study: study, load: load)
                        }
                    }

                    // Connections rows
                    if study.connections.isEmpty {
                        NavigatorSimulationConnectionRow(study: study, connection: nil)
                    } else {
                        ForEach(study.connections) { connection in
                            NavigatorSimulationConnectionRow(study: study, connection: connection)
                        }
                    }

                    // Mesh row
                    NavigatorSimulationMeshRow(study: study)

                    // Results row
                    NavigatorSimulationResultsRow(study: study)
                }
                .padding(.leading, 12)
            }
        }
    }
}

/// Outline row for simulation material assignment.
struct NavigatorSimulationMaterialRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy
    let assignment: SimulationMaterialAssignment?

    var body: some View {
        let isSelected = assignment != nil && workspace.selectedSimulationMaterialAssignmentId == assignment?.id
        HStack(spacing: 6) {
            Image(systemName: "shippingbox")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(assignment?.name ?? "Materials")
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if let assignment {
                Text(assignment.materialId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    _ = workspace.addSimulationMaterialAssignment(studyId: study.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Add Material Assignment")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if let assignment {
                workspace.selectSimulationMaterialAssignment(studyId: study.id, assignmentId: assignment.id)
            } else {
                workspace.selectSimulationStudy(study.id)
            }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        .contextMenu {
            if let assignment {
                Button("Delete Assignment", role: .destructive) {
                    workspace.removeSimulationMaterialAssignment(studyId: study.id, assignmentId: assignment.id)
                }
            } else {
                Button("Add Material Assignment") {
                    _ = workspace.addSimulationMaterialAssignment(studyId: study.id)
                }
            }
        }
        .accessibilityIdentifier(assignment != nil ? "navigator-study-material-\(assignment!.id)" : "navigator-study-materials-\(study.id)")
    }
}

/// Outline row for simulation boundary fixture.
struct NavigatorSimulationFixtureRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy
    let fixture: SimulationFixture?

    var body: some View {
        let isSelected = fixture != nil && workspace.selectedSimulationFixtureId == fixture?.id
        HStack(spacing: 6) {
            Image(systemName: fixture?.kind.systemImageName ?? "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(fixture?.name ?? "Fixtures")
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if let fixture {
                Text(fixture.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    _ = workspace.addSimulationFixture(studyId: study.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Add Fixture")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if let fixture {
                workspace.selectSimulationFixture(studyId: study.id, fixtureId: fixture.id)
            } else {
                workspace.selectSimulationStudy(study.id)
            }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        .contextMenu {
            if let fixture {
                Button("Delete Fixture", role: .destructive) {
                    workspace.removeSimulationFixture(studyId: study.id, fixtureId: fixture.id)
                }
            } else {
                Button("Add Fixture") {
                    _ = workspace.addSimulationFixture(studyId: study.id)
                }
            }
        }
        .accessibilityIdentifier(fixture != nil ? "navigator-study-fixture-\(fixture!.id)" : "navigator-study-fixtures-\(study.id)")
    }
}

/// Outline row for simulation load.
struct NavigatorSimulationLoadRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy
    let load: SimulationLoad?

    var body: some View {
        let isSelected = load != nil && workspace.selectedSimulationLoadId == load?.id
        HStack(spacing: 6) {
            Image(systemName: load?.kind.systemImageName ?? "arrow.down.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(load?.name ?? "Loads")
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if let load {
                Text("\(Int(load.magnitude)) \(load.kind.unitSymbol)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    _ = workspace.addSimulationLoad(studyId: study.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Add Load")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if let load {
                workspace.selectSimulationLoad(studyId: study.id, loadId: load.id)
            } else {
                workspace.selectSimulationStudy(study.id)
            }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        .contextMenu {
            if let load {
                Button("Delete Load", role: .destructive) {
                    workspace.removeSimulationLoad(studyId: study.id, loadId: load.id)
                }
            } else {
                Button("Add Load") {
                    _ = workspace.addSimulationLoad(studyId: study.id)
                }
            }
        }
        .accessibilityIdentifier(load != nil ? "navigator-study-load-\(load!.id)" : "navigator-study-loads-\(study.id)")
    }
}

/// Outline row for simulation connection (BL-FEA-04, #222).
struct NavigatorSimulationConnectionRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy
    let connection: SimulationConnection?

    var body: some View {
        let isSelected = connection != nil && workspace.selectedSimulationConnectionId == connection?.id
        HStack(spacing: 6) {
            Image(systemName: connection?.kind.systemImageName ?? "link")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(connection?.name ?? "Connections")
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if let connection {
                Text(connection.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    _ = workspace.addSimulationConnection(studyId: study.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Add Connection")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if let connection {
                workspace.selectSimulationConnection(studyId: study.id, connectionId: connection.id)
            } else {
                workspace.selectSimulationStudy(study.id)
            }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        .contextMenu {
            if let connection {
                Button("Delete Connection", role: .destructive) {
                    workspace.removeSimulationConnection(studyId: study.id, connectionId: connection.id)
                }
            } else {
                Button("Add Connection") {
                    _ = workspace.addSimulationConnection(studyId: study.id)
                }
            }
        }
        .accessibilityIdentifier(connection != nil ? "navigator-study-connection-\(connection!.id)" : "navigator-study-connections-\(study.id)")
    }
}

/// Outline row for simulation mesh specification.
struct NavigatorSimulationMeshRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy

    var body: some View {
        let isSelected = workspace.selectedSimulationStudyId == study.id && workspace.isSimulationMeshSelected
        let isMeshing = workspace.isStudyMeshing(study.id)
        let elementCount = study.results.meshStatistics.elementCount

        HStack(spacing: 6) {
            Image(systemName: "square.split.diagonal.2x2")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text("Mesh")
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if isMeshing {
                ProgressView()
                    .controlSize(.mini)
            } else if elementCount > 0 {
                Button {
                    workspace.toggleSimulationMeshVisibility(studyId: study.id)
                } label: {
                    Image(systemName: study.meshDisplay.isVisible ? "eye" : "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("navigator-study-mesh-visibility-\(study.id)")

                Text("\(elementCount)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            } else {
                Text(study.mesh.elementOrder.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.selectSimulationMesh(studyId: study.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityIdentifier("navigator-study-mesh-\(study.id)")
    }
}

/// Outline row for simulation results.
struct NavigatorSimulationResultsRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let study: SimulationStudy

    var body: some View {
        let isSelected = workspace.selectedSimulationStudyId == study.id && workspace.isSimulationResultsSelected
        HStack(spacing: 6) {
            Image(systemName: study.results.status.systemImageName)
                .font(.caption2)
                .foregroundStyle(study.results.status == .completed ? Color.green : (study.results.status == .failed ? Color.red : Color.secondary))
                .frame(width: 14)

            Text("Results")
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(study.results.status.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.selectSimulationResults(studyId: study.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityIdentifier("navigator-study-results-\(study.id)")
    }
}


