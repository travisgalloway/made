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
                    Section("Bodies") {
                        ForEach(filteredBodies) { body in
                            NavigatorRow(body: body)
                                .tag(body.id)
                                .id(body.id)
                        }
                    }

                    if !sketchFeatures.isEmpty {
                        Section("Sketches") {
                            ForEach(sketchFeatures) { sketch in
                                NavigatorSketchRow(feature: sketch)
                            }
                        }
                    }

                    if !datumPlaneFeatures.isEmpty {
                        Section("Datum Planes") {
                            ForEach(datumPlaneFeatures) { datum in
                                NavigatorDatumPlaneRow(feature: datum)
                            }
                        }
                    }

                    if !datumAxisFeatures.isEmpty {
                        Section("Datum Axes") {
                            ForEach(datumAxisFeatures) { datum in
                                NavigatorDatumAxisRow(feature: datum)
                            }
                        }
                    }

                    if !datumPointFeatures.isEmpty {
                        Section("Datum Points") {
                            ForEach(datumPointFeatures) { datum in
                                NavigatorDatumPointRow(feature: datum)
                            }
                        }
                    }

                    if !datumCoordinateSystemFeatures.isEmpty {
                        Section("Coordinate Systems") {
                            ForEach(datumCoordinateSystemFeatures) { datum in
                                NavigatorDatumCoordinateSystemRow(feature: datum)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if workspace.document.bodies.isEmpty && sketchFeatures.isEmpty && datumPlaneFeatures.isEmpty && datumAxisFeatures.isEmpty && datumPointFeatures.isEmpty && datumCoordinateSystemFeatures.isEmpty {
                        ContentUnavailableView {
                            Label("No Objects", systemImage: "cube.transparent")
                        } description: {
                            Text("Add a 3D solid primitive or open a part script to begin modeling.")
                        } actions: {
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
                    } else if filteredBodies.isEmpty {
                        ContentUnavailableView.search(text: filterText)
                    }
                }
                .contextMenu(forSelectionType: ObjectId.self) { ids in
                    if let id = ids.first, let body = workspace.document.body(for: id) {
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
                        Divider()
                        Button("Delete", role: .destructive) { workspace.requestDeleteObject(id) }
                            .disabled(body.isLocked)
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
            PaneTabBar(label: "Navigator", selection: $workspace.navigatorTab)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
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
            Menu("Add Solid", systemImage: "plus") {
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
                Divider()
                Button("New Ground Sketch", systemImage: "pencil.and.ruler.fill") {
                    workspace.startNewSketchCommand()
                }
                Button("Extrude Sketch…", systemImage: "arrow.up.forward.app.fill") {
                    workspace.startExtrudeCommand()
                }
                Button("New Datum Plane…", systemImage: "square.dashed") {
                    workspace.startDatumPlaneCommand()
                }
                Divider()
                Button("Part Script File…", systemImage: "curlybraces") {
                    workspace.promptOpenPartFile()
                }
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add Solid")
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

    private var sketchFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .sketch = $0.operation { return true }
            return false
        }
    }

    private var datumPlaneFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .datumPlane = $0.operation { return true }
            return false
        }
    }

    private var datumAxisFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .datumAxis = $0.operation { return true }
            return false
        }
    }

    private var datumPointFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .datumPoint = $0.operation { return true }
            return false
        }
    }

    private var datumCoordinateSystemFeatures: [Feature] {
        workspace.document.activeFeatures.filter {
            if case .datumCoordinateSystem = $0.operation { return true }
            return false
        }
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
        .accessibilityAction(named: bodyItem.isVisible ? "Hide Body" : "Show Body") {
            workspace.toggleBodyVisibility(bodyItem.id)
        }
        .accessibilityAction(named: bodyItem.isLocked ? "Unlock Body" : "Lock Body") {
            workspace.toggleBodyLocked(bodyItem.id)
        }
    }

    private func icon(for object: SceneObject?) -> String {
        guard let object else { return "cube.fill" }
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
        }
    }

    private func tint(for object: SceneObject?) -> Color {
        guard let object else { return .accentColor }
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

                    Text("Sketch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    if !status.isInactive {
                        dofBadge(for: status)
                    }
                }

                Text(Self.subtitle(entityCount: count, status: status))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if isHovered || feature.isLocked {
                Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                       systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                    workspace.toggleFeatureLocked(feature.id)
                }
                .foregroundStyle(.secondary)
                .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                .barControl()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
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
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, entityCount: count, status: status, isLocked: feature.isLocked))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
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

    nonisolated static func accessibilityLabel(featureName: String, entityCount: Int, status: SketchDOFStatus, isLocked: Bool = false) -> String {
        "\(featureName), Sketch, \(entityCount) entities, \(status.statusText)\(isLocked ? ", Locked" : "")"
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

    nonisolated static func accessibilityLabel(featureName: String, isLocked: Bool = false) -> String {
        "\(featureName), Datum Plane\(isLocked ? ", Locked" : "")"
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

                    Text("Datum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }

                if case .datumPlane(let data) = feature.operation {
                    Text(data.mode.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if isHovered || feature.isLocked {
                Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                       systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                    workspace.toggleFeatureLocked(feature.id)
                }
                .foregroundStyle(.secondary)
                .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                .barControl()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
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
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, isLocked: feature.isLocked))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
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

    nonisolated static func accessibilityLabel(featureName: String, isLocked: Bool = false) -> String {
        "\(featureName), Datum Axis\(isLocked ? ", Locked" : "")"
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

                    Text("Axis")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }

                if case .datumAxis(let data) = feature.operation {
                    Text(data.mode.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if isHovered || feature.isLocked {
                Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                       systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                    workspace.toggleFeatureLocked(feature.id)
                }
                .foregroundStyle(.secondary)
                .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                .barControl()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
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
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, isLocked: feature.isLocked))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
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

    nonisolated static func accessibilityLabel(featureName: String, isLocked: Bool = false) -> String {
        "\(featureName), Datum Point\(isLocked ? ", Locked" : "")"
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

                    Text("Point")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }

                if case .datumPoint(let data) = feature.operation {
                    Text(data.mode.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if isHovered || feature.isLocked {
                Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                       systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                    workspace.toggleFeatureLocked(feature.id)
                }
                .foregroundStyle(.secondary)
                .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                .barControl()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
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
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, isLocked: feature.isLocked))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
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

    nonisolated static func accessibilityLabel(featureName: String, isLocked: Bool = false) -> String {
        "\(featureName), Datum UCS\(isLocked ? ", Locked" : "")"
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

                    Text("UCS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }

                if case .datumCoordinateSystem(let data) = feature.operation {
                    Text(data.mode.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if isHovered || feature.isLocked {
                Button(feature.isLocked ? "Unlock Feature" : "Lock Feature",
                       systemImage: feature.isLocked ? "lock.fill" : "lock.open") {
                    workspace.toggleFeatureLocked(feature.id)
                }
                .foregroundStyle(.secondary)
                .help(feature.isLocked ? "Unlock Feature" : "Lock Feature")
                .barControl()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            workspace.selectFeature(feature.id)
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
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
        .accessibilityLabel(Self.accessibilityLabel(featureName: feature.name, isLocked: feature.isLocked))
        .accessibilityAction {
            workspace.selectFeature(feature.id)
        }
        .accessibilityAction(named: feature.isLocked ? "Unlock Feature" : "Lock Feature") {
            workspace.toggleFeatureLocked(feature.id)
        }
        .accessibilityAction(named: "Delete") {
            workspace.requestDeleteFeature(feature.id)
        }
    }
}
