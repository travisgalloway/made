import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers
import MadeCore
import os
import simd

/// App-wide workspace state and the actions that change it. Views read it from the environment.
@Observable
@MainActor
final class WorkspaceModel {
    let document = DocumentModel()
    #if DEBUG
    private var customKernelClient: (any KernelClientProtocol)?
    private let faultInjector = FaultInjectingKernelClient(wrapping: KernelClient.makeDefault())
    var kernelClient: any KernelClientProtocol {
        get { customKernelClient ?? faultInjector }
        set { customKernelClient = newValue }
    }
    #else
    let kernelClient: any KernelClientProtocol = KernelClient.makeDefault()
    #endif
    let partRuntime = PartRuntime()
    let viewportManager = ViewportStateManager()
    public private(set) var userMaterialStore: UserMaterialStore
    public private(set) var userMaterials: [MaterialDefinition] = []

    public var selectedAssemblyConstraintId: UUID? = nil

    public var selectedExplodedViewId: UUID? = nil
    public var selectedExplodeStepId: UUID? = nil

    public var selectedExplodedView: ExplodedView? {
        guard let id = selectedExplodedViewId else { return nil }
        return document.explodedView(id: id)
    }

    public var selectedExplodeStep: ExplodeStep? {
        guard let view = selectedExplodedView, let stepId = selectedExplodeStepId else { return nil }
        return view.steps.first(where: { $0.id == stepId })
    }

    public var activeExplodedViewId: UUID? {
        document.activeExplodedViewId
    }

    // MARK: - Simulation Study Selection (BL-SIM-01, #157)

    public var selectedSimulationStudyId: UUID? = nil
    public var selectedSimulationFixtureId: UUID? = nil
    public var selectedSimulationLoadId: UUID? = nil
    public var selectedSimulationMaterialAssignmentId: UUID? = nil
    public var isSimulationMeshSelected: Bool = false
    public var isSimulationResultsSelected: Bool = false

    // Active simulation solve execution tracking (BL-SIM-02, #187)
    public private(set) var activeRunningStudyIds: Set<UUID> = []
    @ObservationIgnored private var activeSolveTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored public var solverRunner: any SolverRunnerProtocol

    // Active simulation mesh generation tracking (BL-MSH-01, #188, #189)
    public private(set) var activeMeshingStudyIds: Set<UUID> = []
    @ObservationIgnored private var activeMeshTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored public var volumeMesher: any VolumeMesherProtocol
    @ObservationIgnored public var cachedStudyMeshes: [UUID: VolumeMesh] = [:]

    public var selectedSimulationStudy: SimulationStudy? {
        guard let id = selectedSimulationStudyId else { return nil }
        return document.study(id: id)
    }

    public var selectedSimulationFixture: SimulationFixture? {
        guard let study = selectedSimulationStudy, let fixtureId = selectedSimulationFixtureId else { return nil }
        return study.fixtures.first(where: { $0.id == fixtureId })
    }

    public var selectedSimulationLoad: SimulationLoad? {
        guard let study = selectedSimulationStudy, let loadId = selectedSimulationLoadId else { return nil }
        return study.loads.first(where: { $0.id == loadId })
    }

    public var selectedSimulationMaterialAssignment: SimulationMaterialAssignment? {
        guard let study = selectedSimulationStudy, let assignmentId = selectedSimulationMaterialAssignmentId else { return nil }
        return study.materials.first(where: { $0.id == assignmentId })
    }

    public func clearSimulationSelections() {
        selectedSimulationStudyId = nil
        selectedSimulationFixtureId = nil
        selectedSimulationLoadId = nil
        selectedSimulationMaterialAssignmentId = nil
        isSimulationMeshSelected = false
        isSimulationResultsSelected = false
    }

    public func clearNonSimulationSelections() {
        if radialMenuState != nil {
            radialMenuState = nil
        }
        selectedId = nil
        selectedAssemblyConstraintId = nil
        selectedExplodedViewId = nil
        selectedExplodeStepId = nil
        selectedDrawingViewId = nil
        selectedDrawingAnnotationId = nil
        selectedDrawingBOMTableId = nil
    }

    public func selectSimulationStudy(_ id: UUID?) {
        if id != nil {
            clearNonSimulationSelections()
        }
        selectedSimulationStudyId = id
        selectedSimulationFixtureId = nil
        selectedSimulationLoadId = nil
        selectedSimulationMaterialAssignmentId = nil
        isSimulationMeshSelected = false
        isSimulationResultsSelected = false
    }

    public func selectSimulationFixture(studyId: UUID, fixtureId: UUID?) {
        if fixtureId != nil {
            clearNonSimulationSelections()
        }
        selectedSimulationStudyId = studyId
        selectedSimulationFixtureId = fixtureId
        selectedSimulationLoadId = nil
        selectedSimulationMaterialAssignmentId = nil
        isSimulationMeshSelected = false
        isSimulationResultsSelected = false
    }

    public func selectSimulationLoad(studyId: UUID, loadId: UUID?) {
        if loadId != nil {
            clearNonSimulationSelections()
        }
        selectedSimulationStudyId = studyId
        selectedSimulationFixtureId = nil
        selectedSimulationLoadId = loadId
        selectedSimulationMaterialAssignmentId = nil
        isSimulationMeshSelected = false
        isSimulationResultsSelected = false
    }

    public func selectSimulationMaterialAssignment(studyId: UUID, assignmentId: UUID?) {
        if assignmentId != nil {
            clearNonSimulationSelections()
        }
        selectedSimulationStudyId = studyId
        selectedSimulationFixtureId = nil
        selectedSimulationLoadId = nil
        selectedSimulationMaterialAssignmentId = assignmentId
        isSimulationMeshSelected = false
        isSimulationResultsSelected = false
    }

    public func selectSimulationMesh(studyId: UUID, isSelected: Bool = true) {
        if isSelected {
            clearNonSimulationSelections()
        }
        selectedSimulationStudyId = studyId
        selectedSimulationFixtureId = nil
        selectedSimulationLoadId = nil
        selectedSimulationMaterialAssignmentId = nil
        isSimulationMeshSelected = isSelected
        isSimulationResultsSelected = false
    }

    public func selectSimulationResults(studyId: UUID, isSelected: Bool = true) {
        if isSelected {
            clearNonSimulationSelections()
        }
        selectedSimulationStudyId = studyId
        selectedSimulationFixtureId = nil
        selectedSimulationLoadId = nil
        selectedSimulationMaterialAssignmentId = nil
        isSimulationMeshSelected = false
        isSimulationResultsSelected = isSelected
    }

    public func selectExplodedView(_ id: UUID?) {
        selectedExplodedViewId = id
        selectedExplodeStepId = nil
        if id != nil {
            selectedId = nil
            selectedAssemblyConstraintId = nil
            clearSimulationSelections()
        }
    }

    public func selectExplodeStep(viewId: UUID, stepId: UUID?) {
        selectedExplodedViewId = viewId
        selectedExplodeStepId = stepId
        if stepId != nil {
            selectedId = nil
            selectedAssemblyConstraintId = nil
            clearSimulationSelections()
        }
    }

    public var selectedDrawingViewId: UUID? {
        get { document.selectedDrawingViewId }
        set { document.setSelectedDrawingViewId(newValue) }
    }

    public var selectedDrawingView: DrawingView? {
        document.selectedDrawingView
    }

    public func selectDrawingView(_ id: UUID?) {
        selectedDrawingViewId = id
        if id != nil {
            selectedId = nil
            selectedDrawingAnnotationId = nil
            selectedDrawingBOMTableId = nil
            selectedAssemblyConstraintId = nil
            selectedExplodedViewId = nil
            clearSimulationSelections()
        }
    }

    public var selectedDrawingAnnotationId: UUID? {
        get { document.selectedDrawingAnnotationId }
        set { document.setSelectedDrawingAnnotationId(newValue) }
    }

    public var selectedDrawingAnnotation: DrawingAnnotation? {
        document.selectedDrawingAnnotation
    }

    public func selectDrawingAnnotation(_ id: UUID?) {
        selectedDrawingAnnotationId = id
        if id != nil {
            selectedId = nil
            selectedDrawingViewId = nil
            selectedDrawingBOMTableId = nil
            selectedAssemblyConstraintId = nil
            selectedExplodedViewId = nil
            clearSimulationSelections()
        }
    }

    public var selectedDrawingBOMTableId: UUID? {
        get { document.selectedDrawingBOMTableId }
        set { document.setSelectedDrawingBOMTableId(newValue) }
    }

    public var selectedDrawingBOMTable: DrawingBOMTable? {
        document.selectedDrawingBOMTable
    }

    public func selectDrawingBOMTable(_ id: UUID?) {
        selectedDrawingBOMTableId = id
        if id != nil {
            selectedId = nil
            selectedDrawingViewId = nil
            selectedDrawingAnnotationId = nil
            selectedAssemblyConstraintId = nil
            selectedExplodedViewId = nil
            clearSimulationSelections()
        }
    }

    public var selectedAssemblyConstraint: AssemblyConstraint? {
        guard let id = selectedAssemblyConstraintId else { return nil }
        return document.assemblyConstraints.first(where: { $0.id == id })
    }

    public private(set) var lastAssemblySolverResult: AssemblySolverResult?

    public var conflictingAssemblyConstraintIds: Set<UUID> {
        guard let result = lastAssemblySolverResult else { return [] }
        return Set(result.status.conflictingConstraints)
    }

    public var redundantAssemblyConstraintIds: Set<UUID> {
        guard let result = lastAssemblySolverResult else { return [] }
        return Set(result.status.redundantConstraints)
    }

    public func isAssemblyConstraintConflicting(_ id: UUID) -> Bool {
        conflictingAssemblyConstraintIds.contains(id)
    }

    public func isAssemblyConstraintRedundant(_ id: UUID) -> Bool {
        redundantAssemblyConstraintIds.contains(id)
    }

    public func remainingAssemblyDOF(for componentId: UUID) -> Int {
        if let comp = document.findComponentInstance(id: componentId), comp.isGrounded {
            return 0
        }
        if let cached = lastAssemblySolverResult?.instanceDOF[componentId] {
            return cached
        }
        let dof = document.computeAssemblyDOF()
        return dof.instanceDOF[componentId] ?? 6
    }

    public var totalAssemblyDOF: Int {
        if let cached = lastAssemblySolverResult?.totalDOF {
            return cached
        }
        return document.computeAssemblyDOF().totalDOF
    }

    public func clearAssemblySolverDiagnostics() {
        lastAssemblySolverResult = nil
    }

    public func selectAssemblyConstraint(_ id: UUID?) {
        selectedAssemblyConstraintId = id
        if id != nil {
            selectedId = nil
            selectedExplodedViewId = nil
            selectedExplodeStepId = nil
            clearSimulationSelections()
        }
    }

    var selectedId: ObjectId? {
        get { document.selectedId }
        set {
            if radialMenuState != nil {
                radialMenuState = nil
            }
            if newValue != nil {
                selectedAssemblyConstraintId = nil
                selectedExplodedViewId = nil
                selectedExplodeStepId = nil
                clearSimulationSelections()
            }
            if document.selectedId != newValue {
                document.selectedId = newValue
                syncViewportSelection()
            } else if document.selectedSubElement != nil {
                document.selectedSubElement = nil
                syncViewportSelection()
            }
        }
    }

    var selectedIds: Set<ObjectId> {
        get { document.selectedIds }
        set {
            if radialMenuState != nil {
                radialMenuState = nil
            }
            if !newValue.isEmpty {
                selectedAssemblyConstraintId = nil
                selectedExplodedViewId = nil
                selectedExplodeStepId = nil
                clearSimulationSelections()
            }
            if document.selectedIds != newValue {
                document.selectedIds = newValue
                syncViewportSelection()
            }
        }
    }

    func clearSelection() {
        if radialMenuState != nil {
            radialMenuState = nil
        }
        selectedAssemblyConstraintId = nil
        selectedExplodedViewId = nil
        selectedExplodeStepId = nil
        clearSimulationSelections()
        document.clearSelection()
        syncViewportSelection()
    }

    func select(solidId: ObjectId) {
        if radialMenuState != nil {
            radialMenuState = nil
        }
        selectedAssemblyConstraintId = nil
        selectedExplodedViewId = nil
        selectedExplodeStepId = nil
        clearSimulationSelections()
        document.select(solidId: solidId)
        syncViewportSelection()
    }

    func toggleSelection(solidId: ObjectId) {
        if radialMenuState != nil {
            radialMenuState = nil
        }
        selectedAssemblyConstraintId = nil
        selectedExplodedViewId = nil
        selectedExplodeStepId = nil
        clearSimulationSelections()
        document.toggleSelection(solidId: solidId)
        syncViewportSelection()
    }

    var pendingDeleteId: ObjectId?
    var pendingDeleteFeatureId: UUID?
    // Document Persistence & State
    var currentDocumentURL: URL?
    var isDocumentModified: Bool = false
    var autosaveDebounceNanoseconds: UInt64 = 2_000_000_000
    private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored var recoveryStore: CrashRecoveryStore
    var pendingRecoveryRecord: CrashRecoveryRecord? = nil
    var isShowingRecoveryAlert: Bool = false
    var pendingSaveError: SaveErrorInfo? = nil
    var isShowingSaveErrorAlert: Bool = false
    var pendingOpenError: OpenErrorInfo? = nil
    var isShowingOpenErrorAlert: Bool = false
    var pendingExportError: ExportErrorInfo? = nil
    var isShowingExportErrorAlert: Bool = false
    var pendingImportError: ImportErrorInfo? = nil
    var isShowingImportErrorAlert: Bool = false
    @ObservationIgnored nonisolated(unsafe) private var terminateObserver: (any NSObjectProtocol)?

    var documentTitle: String {
        let base = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "Untitled Project"
        return isDocumentModified ? "\(base) — Edited" : base
    }
    var coordinator: CADMetalViewRepresentable.Coordinator?
    public var radialMenuState: RadialMenuState? = nil
    var renderInstrumentation: RenderInstrumentation = .shared
    private(set) var renderStats = RenderStats()
    private(set) var kernelStats = KernelStats()
    var activeSnapResult: SnapResult?
    var activeSnapKind: SnapKind?
    /// Current sketch degrees-of-freedom constraint status (ADR-D4, BL-WSP-10).
    var sketchDOFStatus: SketchDOFStatus = .inactive
    /// Current per-entity degrees-of-freedom constraint statuses (BL-CON-05, #196).
    public var entityDOFStatus: [UUID: SketchDOFStatus] = [:]
    /// Whether predictive live constraint inference is enabled during sketch editing (ADR-D4, #37).
    var isLiveInferenceEnabled: Bool = true
    /// Current candidate constraint inferences generated live from sketch geometry (ADR-D4, #37).
    var inferredConstraints: [SketchConstraint] = []
    /// Diagnostic message when sketch constraints are over-constrained or conflicting (ADR-D4, #37).
    public var overConstrainedMessage: String? = nil
    /// Identifiers of constraints involved in an over-constrained conflict (BL-CON-06, #197).
    public var conflictingConstraintIds: Set<UUID> = []
    /// Identifiers of constraints identified as algebraically redundant (BL-CON-06, #197).
    public var redundantConstraintIds: Set<UUID> = []
    /// Diagnostic message when sketch constraints are redundant (BL-CON-06, #197).
    public var redundantConstraintsMessage: String? = nil
    /// Currently hovered sketch region identifier for viewport preview highlight (BL-SKT-12).
    var hoveredSketchRegionId: UUID? = nil
    /// Currently selected sketch region identifier for feature extrusion (BL-SKT-12).
    var selectedSketchRegionId: UUID? = nil
    /// Detected closed planar regions for the active or selected sketch (BL-SKT-12).
    var detectedSketchRegions: [SketchRegion] = []
    /// Current component pending interactive viewport placement (BL-ASM-02).
    public var pendingComponentPlacement: PendingComponentPlacement? = nil
    /// Whether the body picker sheet for document component insertion is displayed (BL-ASM-02).
    public var isShowingBodyPickerForInsertion: Bool = false
    /// Duration of the most recent solid kernel recomputation (BL-WSP-10).
    private(set) var lastRegenerationDuration: Duration? = nil

    /// Formatted string representing the last kernel regeneration duration (BL-WSP-10).
    var formattedRegenerationDuration: String {
        guard let duration = lastRegenerationDuration else { return "--" }
        let (seconds, attoseconds) = duration.components
        let ms = Double(seconds) * 1000.0 + Double(attoseconds) / 1_000_000_000_000_000.0
        if ms < 1.0 {
            return "< 1 ms"
        } else if ms < 1000.0 {
            return String(format: "%.0f ms", ms)
        } else {
            return String(format: "%.2f s", ms / 1000.0)
        }
    }

    func setSketchDOFStatus(_ status: SketchDOFStatus) {
        sketchDOFStatus = status
        if status == .inactive {
            entityDOFStatus = [:]
            conflictingConstraintIds = []
            redundantConstraintIds = []
            redundantConstraintsMessage = nil
            overConstrainedMessage = nil
        }
    }

    /// Returns the degree of freedom status for a specific sketch entity (BL-CON-05, #196).
    public func dofStatus(for entityId: UUID) -> SketchDOFStatus {
        entityDOFStatus[entityId] ?? .inactive
    }

    /// Returns whether the specified feature is actively selected in the document (BL-SKT-18, #366).
    public func isFeatureSelected(_ feature: Feature) -> Bool {
        if document.selection.contains(where: { ref in
            switch ref.target {
            case .feature(let featId):
                return featId == feature.id
            case .sketchEntity(let featId, _):
                return featId == feature.id
            default:
                return false
            }
        }) {
            return true
        }
        if let selectedId {
            if let feat = document.feature(for: selectedId), feat.id == feature.id {
                return true
            }
            if let uuid = UUID(uuidString: selectedId.rawValue), uuid == feature.id {
                return true
            }
        }
        return false
    }

    /// Returns the degrees-of-freedom constraint status for a sketch feature (BL-SKT-18, #366).
    /// If the feature is currently selected, returns the live workspace status; otherwise evaluates the constraint system directly.
    public func sketchDOFStatus(for feature: Feature) -> SketchDOFStatus {
        if isFeatureSelected(feature) {
            return sketchDOFStatus
        }
        guard case .sketch(let sketchData) = feature.operation else { return .inactive }
        let system = ConstraintSystem(entities: sketchData.entities, constraints: sketchData.constraints)
        return ConstraintSolver.computeDOFStatus(system: system)
    }

    /// Returns the degrees-of-freedom constraint status for a feature by identifier (BL-SKT-18, #366).
    public func sketchDOFStatus(for featureId: UUID) -> SketchDOFStatus {
        guard let feature = document.feature(for: featureId) else { return .inactive }
        return sketchDOFStatus(for: feature)
    }

    func setHoveredSketchRegion(_ id: UUID?) {
        guard hoveredSketchRegionId != id else { return }
        hoveredSketchRegionId = id
        updateRegionHighlightMesh()
    }

    func selectSketchRegion(featureId: UUID, regionId: UUID?) {
        selectedSketchRegionId = regionId
        updateRegionHighlightMesh()
    }

    func refreshDetectedSketchRegions(for sketchFeatureId: UUID? = nil) {
        let targetId = sketchFeatureId ?? selectedSketchFeature?.id
        guard let targetId,
              let feat = document.feature(for: targetId),
              case .sketch(let data) = feat.operation else {
            detectedSketchRegions = []
            if hoveredSketchRegionId != nil || selectedSketchRegionId != nil {
                hoveredSketchRegionId = nil
                selectedSketchRegionId = nil
                updateRegionHighlightMesh()
            }
            return
        }
        let plane = document.resolveSketchPlane(for: data)
        detectedSketchRegions = (try? SketchProfileBuilder.detectRegions(from: data.entities, plane: plane)) ?? []
        updateRegionHighlightMesh()
    }

    func updateRegionHighlightMesh() {
        let highlightId = ObjectId("sketch-hover-region")
        let targetRegionId = hoveredSketchRegionId ?? selectedSketchRegionId
        if let targetRegionId,
           let region = detectedSketchRegions.first(where: { $0.id == targetRegionId }) {
            let plane = selectedSketchFeature.flatMap {
                if case .sketch(let data) = $0.operation { return document.resolveSketchPlane(for: data) }
                return nil
            } ?? .xy
            let profile = region.toProfile(plane: plane)
            Task { @MainActor in
                let req = KernelRequest.evaluateShape(
                    jobId: JobId("highlight-\(UUID().uuidString)"),
                    solidId: highlightId,
                    shape: .extrude(profile: profile, distance: 0.05, centered: true)
                )
                let result = await kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let color = (hoveredSketchRegionId != nil && hoveredSketchRegionId == targetRegionId) ?
                        SIMD4<Float>(0.2, 0.7, 1.0, 0.45) :
                        SIMD4<Float>(0.2, 0.9, 0.4, 0.55)
                    _ = viewportManager.renderer?.installMesh(
                        payload,
                        for: highlightId,
                        transform: .identity,
                        color: color,
                        isHidden: false
                    )
                    invalidateViewport(.interaction)
                }
            }
        } else {
            _ = viewportManager.renderer?.removeMesh(for: highlightId)
            invalidateViewport(.interaction)
        }
    }

    func setLastRegenerationDuration(_ duration: Duration?) {
        lastRegenerationDuration = duration
    }

    /// Last failed recompute per solid, shown in the Inspector (invariant 3: panels only).
    private(set) var recomputeFailures = RecomputeFailures()

    // Layout
    var columnVisibility: NavigationSplitViewVisibility = .all
    var isInspectorPresented = true
    var isConsoleVisible = false
    var navigatorTab: NavigatorTab = .scene
    var inspectorTab: InspectorTab = .properties

    // Viewport
    private(set) var camera: Camera = Camera()
    @ObservationIgnored private var cameraAnimationTask: Task<Void, Never>?
    private(set) var perspective: ViewportPerspective = .perspective
    private(set) var projectionMode: CameraProjection = .perspective
    var tool: ViewportTool = .select {
        didSet {
            if tool != oldValue { log(.info, "Viewport", "Selected \(tool.title) tool") }
        }
    }
    var activeRectangleKind: SketchRectangleKind = .corner
    var selectionFilter: SelectionFilter = .all {
        didSet {
            if selectionFilter != oldValue {
                log(.info, "Viewport", "Selection filter updated: \(selectionFilter.rawValue)")
            }
        }
    }

    func toggleSelectionFilter(_ filter: SelectionFilter, enabled: Bool? = nil) {
        let shouldEnable = enabled ?? !selectionFilter.contains(filter)
        if shouldEnable {
            selectionFilter.insert(filter)
        } else {
            selectionFilter.remove(filter)
        }
        if selectionFilter.isEmpty {
            selectionFilter = .all
        }
    }

    func isolateSelectionFilter(_ filter: SelectionFilter) {
        if selectionFilter == filter {
            selectionFilter = .all
        } else {
            selectionFilter = filter
        }
    }

    func resetSelectionFilters() {
        selectionFilter = .all
    }

    // Console
    private(set) var logs: [ConsoleLogEntry] = [
        ConsoleLogEntry(level: .info, subsystem: "App", message: "made macOS workspace initialized")
    ]

    // MCP & Part Reload
    private(set) var toolRegistry: CADToolRegistry?
    private(set) var partReloadController: PartReloadController?
    private(set) var mcpServer: MCPServer?
    var isMCPServerRunning = false
    private(set) var mcpServerError: String? = nil
    let mcpPort: UInt16 = 9820
    var externalLinkCheckVersion: Int = 0

    // Defaults Keys
    public static let commandPanelPlacementDefaultsKey = "com.made.commandPanelPlacement"
    public static let lengthUnitDefaultsKey = "com.made.units.length"
    public static let angleUnitDefaultsKey = "com.made.units.angle"
    public static let decimalPrecisionDefaultsKey = "com.made.units.precision"
    public static let navigationPresetDefaultsKey = "com.made.navigation.preset"
    public static let defaultProjectionDefaultsKey = "com.made.display.defaultProjection"
    public static let defaultPerspectiveDefaultsKey = "com.made.display.defaultPerspective"
    public static let showsGridDefaultsKey = "com.made.display.showsGrid"
    public static let showsAxesDefaultsKey = "com.made.display.showsAxes"
    public static let showsGizmoDefaultsKey = "com.made.display.showsGizmo"
    public static let showsEdgesDefaultsKey = "viewport.showsEdges"
    public static let displayModeDefaultsKey = "com.made.display.mode"
    public static let linearToleranceDefaultsKey = "com.made.tolerances.linear"
    public static let angularToleranceDefaultsKey = "com.made.tolerances.angular"
    public static let chordalToleranceDefaultsKey = "com.made.tolerances.chordal"

    let defaults: UserDefaults
    var commandPanelPlacement: CommandPanelPlacement {
        didSet {
            defaults.set(commandPanelPlacement.rawValue, forKey: Self.commandPanelPlacementDefaultsKey)
        }
    }
    var lengthUnit: LengthUnit {
        didSet {
            defaults.set(lengthUnit.rawValue, forKey: Self.lengthUnitDefaultsKey)
        }
    }
    var angleUnit: AngleUnit {
        didSet {
            defaults.set(angleUnit.rawValue, forKey: Self.angleUnitDefaultsKey)
        }
    }
    var decimalPrecision: Int {
        didSet {
            let clamped = UnitSettings.clampPrecision(decimalPrecision)
            if decimalPrecision != clamped { decimalPrecision = clamped }
            defaults.set(decimalPrecision, forKey: Self.decimalPrecisionDefaultsKey)
        }
    }
    var navigationPreset: NavigationPreset {
        didSet {
            defaults.set(navigationPreset.rawValue, forKey: Self.navigationPresetDefaultsKey)
        }
    }
    var defaultProjection: CameraProjection {
        didSet {
            defaults.set(defaultProjection.rawValue, forKey: Self.defaultProjectionDefaultsKey)
        }
    }
    var defaultPerspective: ViewportPerspective {
        didSet {
            defaults.set(defaultPerspective.rawValue, forKey: Self.defaultPerspectiveDefaultsKey)
        }
    }
    var showsGrid: Bool {
        didSet {
            defaults.set(showsGrid, forKey: Self.showsGridDefaultsKey)
            if let renderer = viewportManager.renderer {
                renderer.showsGrid = showsGrid
                invalidateViewport(.interaction)
            }
        }
    }
    var showsAxes: Bool {
        didSet {
            defaults.set(showsAxes, forKey: Self.showsAxesDefaultsKey)
            if let renderer = viewportManager.renderer {
                renderer.showsAxes = showsAxes
                invalidateViewport(.interaction)
            }
        }
    }
    var showsGizmo: Bool {
        didSet {
            defaults.set(showsGizmo, forKey: Self.showsGizmoDefaultsKey)
            if let renderer = viewportManager.renderer {
                let isLocked = selectedObject?.isLocked ?? false
                renderer.showsGizmo = showsGizmo && !isLocked
                invalidateViewport(.interaction)
            }
        }
    }
    var showsEdges: Bool {
        didSet {
            defaults.set(showsEdges, forKey: Self.showsEdgesDefaultsKey)
            if let renderer = viewportManager.renderer {
                renderer.showsEdges = showsEdges
                invalidateViewport(.interaction)
            }
        }
    }
    var displayMode: DisplayMode {
        didSet {
            defaults.set(displayMode.rawValue, forKey: Self.displayModeDefaultsKey)
            if let renderer = viewportManager.renderer {
                renderer.displayMode = displayMode
                invalidateViewport(.interaction)
            }
        }
    }
    var kernelTolerances: KernelTolerances {
        didSet {
            let clamped = kernelTolerances.clamped()
            if kernelTolerances != clamped { kernelTolerances = clamped }
            defaults.set(clamped.linearTolerance, forKey: Self.linearToleranceDefaultsKey)
            defaults.set(clamped.angularTolerance, forKey: Self.angularToleranceDefaultsKey)
            defaults.set(clamped.chordalTolerance, forKey: Self.chordalToleranceDefaultsKey)
            setDocumentTolerances(clamped)
        }
    }
    var activeCommand: CommandSession?
    public var commandBlockedMessage: String? = nil
    public var isPredictiveCommandsVisible: Bool = true

    func togglePredictiveCommandSurface() {
        isPredictiveCommandsVisible.toggle()
    }

    init(
        defaults: UserDefaults = .standard,
        recoveryStore: CrashRecoveryStore = CrashRecoveryStore(),
        userMaterialStore: UserMaterialStore = UserMaterialStore(),
        solverRunner: any SolverRunnerProtocol = SolverRunnerActor(),
        volumeMesher: any VolumeMesherProtocol = VolumeMesherActor()
    ) {
        self.defaults = defaults
        self.recoveryStore = recoveryStore
        self.userMaterialStore = userMaterialStore
        self.solverRunner = solverRunner
        self.volumeMesher = volumeMesher
        self.userMaterials = userMaterialStore.loadMaterials()
        if let raw = defaults.string(forKey: Self.commandPanelPlacementDefaultsKey),
           let placement = CommandPanelPlacement(rawValue: raw) {
            self.commandPanelPlacement = placement
        } else {
            self.commandPanelPlacement = .floatingHUD
        }

        if let raw = defaults.string(forKey: Self.lengthUnitDefaultsKey),
           let unit = LengthUnit(rawValue: raw) {
            self.lengthUnit = unit
        } else {
            self.lengthUnit = .millimeters
        }

        if let raw = defaults.string(forKey: Self.angleUnitDefaultsKey),
           let unit = AngleUnit(rawValue: raw) {
            self.angleUnit = unit
        } else {
            self.angleUnit = .degrees
        }

        if defaults.object(forKey: Self.decimalPrecisionDefaultsKey) != nil {
            let p = defaults.integer(forKey: Self.decimalPrecisionDefaultsKey)
            self.decimalPrecision = UnitSettings.clampPrecision(p)
        } else {
            self.decimalPrecision = UnitSettings.defaultDecimalPrecision
        }

        if let raw = defaults.string(forKey: Self.navigationPresetDefaultsKey),
           let preset = NavigationPreset(rawValue: raw) {
            self.navigationPreset = preset
        } else {
            self.navigationPreset = .defaultPreset
        }

        if let raw = defaults.string(forKey: Self.defaultProjectionDefaultsKey),
           let proj = CameraProjection(rawValue: raw) {
            self.defaultProjection = proj
        } else {
            self.defaultProjection = .perspective
        }

        if let raw = defaults.string(forKey: Self.defaultPerspectiveDefaultsKey),
           let persp = ViewportPerspective(rawValue: raw) {
            self.defaultPerspective = persp
        } else {
            self.defaultPerspective = .perspective
        }

        if defaults.object(forKey: Self.showsGridDefaultsKey) != nil {
            self.showsGrid = defaults.bool(forKey: Self.showsGridDefaultsKey)
        } else {
            self.showsGrid = true
        }

        if defaults.object(forKey: Self.showsAxesDefaultsKey) != nil {
            self.showsAxes = defaults.bool(forKey: Self.showsAxesDefaultsKey)
        } else {
            self.showsAxes = true
        }

        if defaults.object(forKey: Self.showsGizmoDefaultsKey) != nil {
            self.showsGizmo = defaults.bool(forKey: Self.showsGizmoDefaultsKey)
        } else {
            self.showsGizmo = true
        }

        if defaults.object(forKey: Self.showsEdgesDefaultsKey) != nil {
            self.showsEdges = defaults.bool(forKey: Self.showsEdgesDefaultsKey)
        } else {
            self.showsEdges = true
        }

        if let raw = defaults.string(forKey: Self.displayModeDefaultsKey),
           let mode = DisplayMode(rawValue: raw) {
            self.displayMode = mode
        } else {
            self.displayMode = .shadedWithEdges
        }

        let linear = defaults.object(forKey: Self.linearToleranceDefaultsKey) != nil ? defaults.double(forKey: Self.linearToleranceDefaultsKey) : KernelTolerances.defaultLinearTolerance
        let angular = defaults.object(forKey: Self.angularToleranceDefaultsKey) != nil ? defaults.double(forKey: Self.angularToleranceDefaultsKey) : KernelTolerances.defaultAngularTolerance
        let chordal = defaults.object(forKey: Self.chordalToleranceDefaultsKey) != nil ? defaults.double(forKey: Self.chordalToleranceDefaultsKey) : KernelTolerances.defaultChordalTolerance
        self.kernelTolerances = KernelTolerances(linearTolerance: linear, angularTolerance: angular, chordalTolerance: chordal).clamped()

        let initialSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: self.lengthUnit, angleUnit: self.angleUnit, decimalPrecision: self.decimalPrecision),
            tolerances: self.kernelTolerances
        )
        self.document.setSettings(initialSettings, registerUndo: false)
        self.document.undoManager?.removeAllActions()

        self.document.onUndoRedoMutation = { [weak self] mutation in
            self?.handleUndoRedoMutation(mutation)
        }
    }

    convenience init(recoveryDirectoryURL: URL) {
        self.init(defaults: .standard, recoveryStore: CrashRecoveryStore(recoveryDirectoryURL: recoveryDirectoryURL))
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    func resetSettingsToDefaults() {
        commandPanelPlacement = .floatingHUD
        lengthUnit = .millimeters
        angleUnit = .degrees
        decimalPrecision = UnitSettings.defaultDecimalPrecision
        navigationPreset = .defaultPreset
        defaultProjection = .perspective
        defaultPerspective = .perspective
        showsGrid = true
        showsAxes = true
        showsGizmo = true
        showsEdges = true
        displayMode = .shadedWithEdges
        kernelTolerances = KernelTolerances.default
    }

    func resetDisplaySettings() {
        showsGrid = true
        showsAxes = true
        showsGizmo = true
        showsEdges = true
        displayMode = .shadedWithEdges
    }

    func resetTolerancesToDefaults() {
        kernelTolerances = KernelTolerances.default
    }

    private var isSetUp = false

    struct RenderStats: Equatable {
        var renderCount = 0
        var drawCalls = 0
        var lastReason = "init"
    }

    var selectedObject: SceneObject? {
        guard let selectedId else { return nil }
        return document.objects.first { $0.id == selectedId }
    }

    var selectedBody: Body? {
        guard let selectedId else { return nil }
        return document.body(for: selectedId)
    }

    public var selectedComponentInstance: ComponentInstance? {
        guard let selectedId else { return nil }
        return document.findComponentInstance(solidId: selectedId)
    }

    var selectedFeature: Feature? {
        if let selectedId {
            if let feat = document.feature(for: selectedId) {
                return feat
            }
            if let uuid = UUID(uuidString: selectedId.rawValue), let feat = document.feature(for: uuid) {
                return feat
            }
        }
        if let sel = document.selection.first, case .feature(let featId) = sel.target {
            return document.feature(for: featId)
        }
        return document.selectedFeatures.first
    }

    var selectedSketchFeature: Feature? {
        if let sel = document.selection.first {
            if case .feature(let featId) = sel.target, let feat = document.feature(for: featId), case .sketch = feat.operation {
                return feat
            }
            if case .sketchEntity(let featId, _) = sel.target, let feat = document.feature(for: featId), case .sketch = feat.operation {
                return feat
            }
        }
        if let feat = selectedFeature, case .sketch = feat.operation {
            return feat
        }
        if let selectedId {
            if let feat = document.feature(for: selectedId), case .sketch = feat.operation {
                return feat
            }
            if let uuid = UUID(uuidString: selectedId.rawValue), let feat = document.feature(for: uuid), case .sketch = feat.operation {
                return feat
            }
        }
        if let sketch = document.features.last(where: {
            if case .sketch = $0.operation { return true }
            return false
        }) {
            return sketch
        }
        return nil
    }

    var selectedSketchEntity: (featureId: UUID, entity: SketchEntity)? {
        guard let sel = document.selection.first, case .sketchEntity(let featId, let entityId) = sel.target else {
            return nil
        }
        guard let feat = document.feature(for: featId), case .sketch(let sketchData) = feat.operation else {
            return nil
        }
        guard let entity = sketchData.entities.first(where: { $0.id == entityId }) else {
            return nil
        }
        return (featureId: featId, entity: entity)
    }

    var selectedSketchLineEntity: (featureId: UUID, entity: SketchEntity)? {
        guard let pair = selectedSketchEntity, pair.entity.kind == "line" else { return nil }
        return pair
    }

    var hasAvailableSketchLine: Bool {
        if selectedSketchLineEntity != nil { return true }
        if let feat = selectedSketchFeature, case .sketch(let sketchData) = feat.operation {
            return sketchData.entities.contains(where: { $0.kind == "line" })
        }
        return false
    }

    func selectSketchEntity(featureId: UUID, entityId: UUID) {
        selectedId = nil
        document.selection = [Reference.sketchEntity(featureId: featureId, entityId: entityId)]
        refreshSketchStatus(for: featureId)
    }

    var selectedDatumPlaneFeature: Feature? {
        if let sel = document.selection.first, case .feature(let featId) = sel.target {
            if let feat = document.feature(for: featId), case .datumPlane = feat.operation {
                return feat
            }
        }
        if let feat = selectedFeature, case .datumPlane = feat.operation {
            return feat
        }
        return nil
    }

    var selectedDatumAxisFeature: Feature? {
        if let sel = document.selection.first, case .feature(let featId) = sel.target {
            if let feat = document.feature(for: featId), case .datumAxis = feat.operation {
                return feat
            }
        }
        if let feat = selectedFeature, case .datumAxis = feat.operation {
            return feat
        }
        return nil
    }

    var selectedDatumPointFeature: Feature? {
        if let sel = document.selection.first, case .feature(let featId) = sel.target {
            if let feat = document.feature(for: featId), case .datumPoint = feat.operation {
                return feat
            }
        }
        if let feat = selectedFeature, case .datumPoint = feat.operation {
            return feat
        }
        return nil
    }

    var selectedDatumCoordinateSystemFeature: Feature? {
        if let sel = document.selection.first, case .feature(let featId) = sel.target {
            if let feat = document.feature(for: featId), case .datumCoordinateSystem = feat.operation {
                return feat
            }
        }
        if let feat = selectedFeature, case .datumCoordinateSystem = feat.operation {
            return feat
        }
        return nil
    }

    func selectFeature(_ featureId: UUID) {
        selectedId = nil
        document.selection = [Reference.feature(featureId)]
        if let feat = document.feature(for: featureId), case .sketch = feat.operation {
            refreshSketchStatus(for: featureId)
        } else {
            setSketchDOFStatus(.inactive)
            overConstrainedMessage = nil
            inferredConstraints = []
        }
    }

    var objectPendingDeletion: SceneObject? {
        guard let pendingDeleteId else { return nil }
        return document.objects.first { $0.id == pendingDeleteId }
    }

    var featurePendingDeletion: Feature? {
        guard let pendingDeleteFeatureId else { return nil }
        return document.feature(for: pendingDeleteFeatureId)
    }

    // MARK: - Setup

    func syncViewportSelection() {
        guard let renderer = viewportManager.renderer else { return }
        var needsInvalidate = false
        let targetSelectedIds = document.selectedIds
        let targetSelectedId = document.selectedId
        let targetSubElement = document.selectedSubElement
        if renderer.selectedIds != targetSelectedIds || renderer.selectedId != targetSelectedId || renderer.selectedSubElement != targetSubElement {
            renderer.selectedIds = targetSelectedIds
            renderer.selectedId = targetSelectedId
            renderer.selectedSubElement = targetSubElement
            needsInvalidate = true
        }
        let isLocked = selectedObject?.isLocked ?? false
        let effectiveGizmo = showsGizmo && !isLocked && targetSelectedIds.count <= 1
        if renderer.showsGizmo != effectiveGizmo {
            renderer.showsGizmo = effectiveGizmo
            needsInvalidate = true
        }
        if needsInvalidate {
            invalidateViewport(.interaction)
        }
    }

    func connectViewport() {
        guard let renderer = viewportManager.renderer else { return }
        renderer.showsGrid = showsGrid
        renderer.showsAxes = showsAxes
        renderer.showsEdges = showsEdges
        renderer.displayMode = displayMode
        renderer.selectedId = selectedId
        renderer.selectedIds = document.selectedIds
        renderer.selectedSubElement = document.selectedSubElement
        let isLocked = selectedObject?.isLocked ?? false
        renderer.showsGizmo = showsGizmo && !isLocked && document.selectedIds.count <= 1
        self.camera = renderer.camera
    }

    func setUp() {
        guard !isSetUp else { return }
        isSetUp = true

        _ = viewportManager.setup()
        connectViewport()
        if defaultProjection != .perspective {
            setProjectionMode(defaultProjection)
        }
        if defaultPerspective != .perspective {
            applyPerspective(defaultPerspective)
        }
        viewportManager.renderer?.onDeviceLost = { [weak viewportManager] in
            Task { @MainActor in viewportManager?.handleDeviceLost() }
        }

        let reloadController = PartReloadController(
            document: document,
            partRuntime: partRuntime,
            kernelClient: kernelClient,
            meshSink: viewportManager.renderer,
            onViewportInvalidated: { [weak self] in self?.invalidateViewport(.model) },
            onReloadResult: { [weak self] result, id in
                guard let self else { return }
                if let message = self.recomputeFailures.record(result, for: id) {
                    self.log(.error, "Part", message)
                    self.isConsoleVisible = true
                } else if case .success(_, let output) = result {
                    let name = self.document.objects.first(where: { $0.id == id })?.name ?? id.rawValue
                    self.log(.info, "Part", "Reloaded \(name) (\(output.payload.triangleCount) triangles)")
                }
                Task { [weak self] in
                    await self?.updateKernelStats()
                }
            }
        )
        partReloadController = reloadController

        let registry = CADToolRegistry(
            document: document,
            kernelClient: kernelClient,
            partReloadController: reloadController,
            snapshotProvider: viewportManager.renderer,
            meshSink: viewportManager.renderer,
            onViewportInvalidated: { [weak self] in self?.invalidateViewport(.model) },
            onRecomputeResult: { [weak self] result, id in
                guard let self else { return }
                if let message = self.recomputeFailures.record(result, for: id) {
                    self.log(.error, "Kernel", message)
                }
                Task { [weak self] in
                    await self?.updateKernelStats()
                }
            }
        )
        toolRegistry = registry

        let server = MCPServer(toolRegistry: registry)
        server.onStateChange = { @Sendable [weak self] running in
            Task { @MainActor in
                guard let self else { return }
                self.isMCPServerRunning = running
                if running {
                    self.mcpServerError = nil
                    self.log(.info, "MCP", "Started MCP server on port \(self.mcpPort)")
                }
            }
        }
        server.onError = { @Sendable [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                let message = error.localizedDescription
                self.mcpServerError = message
                self.isMCPServerRunning = false
                self.log(.error, "MCP", "Failed to start MCP server: \(message)")
            }
        }
        mcpServer = server

        for obj in document.objects { recomputeSolid(id: obj.id) }
        openInitialPartFilesFromEnvironmentOrArguments()
        log(.info, "Metal", "Metal 4 pipeline initialized")
        watchKernelRestarts()
        checkForPendingRecovery()
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearRecoverySnapshot()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLinkedReferenceStatuses()
            }
        }
    }

    private func openInitialPartFilesFromEnvironmentOrArguments() {
        if let envPath = ProcessInfo.processInfo.environment["MADE_PART_FILE"], !envPath.isEmpty {
            openPartFile(at: URL(fileURLWithPath: envPath))
        }
        for arg in CommandLine.arguments.dropFirst() where !arg.hasPrefix("-") {
            let lower = arg.lowercased()
            if lower.hasSuffix(".part.ts") || lower.hasSuffix(".part.js") || lower.hasSuffix(".made") {
                openPartFile(at: URL(fileURLWithPath: arg))
            }
        }
    }

    func handleKernelRestart(_ restart: KernelRestart) {
        let culprit = restart.excludedSolid.map { ", skipping \($0.rawValue)" } ?? ""
        log(.error, "Kernel", "Kernel service restarted (\(restart.reason))\(culprit); regenerating solids")
        for obj in document.objects where obj.id != restart.excludedSolid {
            recomputeSolid(id: obj.id)
        }
        if let activeCommand, activeCommand.isPreviewEnabled {
            activeCommand.onPreviewUpdate?()
        }
    }

    /// A restarted kernel service holds no solids; resubmit each one, except the solid whose job stopped it.
    private func watchKernelRestarts() {
        Task { [weak self, kernelClient] in
            for await restart in await kernelClient.restarts() {
                guard let self else { return }
                self.handleKernelRestart(restart)
            }
        }
    }

    // MARK: - Command Panel & Sessions

    func startCommand(_ session: CommandSession) {
        if activeCommand != nil {
            cancelActiveCommand()
        }
        commandBlockedMessage = nil
        activeCommand = session
        if session.isPreviewEnabled {
            session.onPreviewUpdate?()
        }
    }

    func startEditFeature(for solidId: SolidId) {
        if activeCommand != nil {
            commandBlockedMessage = "A command session is already active. Complete or cancel it first."
            return
        }
        commandBlockedMessage = nil
        guard let feature = document.feature(for: solidId) else { return }
        guard !feature.isLocked else { return }
        startEditFeature(id: feature.id)
    }

    func startEditFeature(id: UUID) {
        if activeCommand != nil {
            commandBlockedMessage = "A command session is already active. Complete or cancel it first."
            return
        }
        commandBlockedMessage = nil
        guard let feature = document.feature(for: id), !feature.isLocked else { return }
        guard let session = CommandSession.makeEditFeature(workspace: self, featureId: id) else { return }
        startCommand(session)
    }

    func cancelActiveCommand() {
        guard let session = activeCommand else { return }
        activeCommand = nil
        session.cancel()
    }

    func commitActiveCommand() {
        guard let session = activeCommand else { return }
        guard session.canCommit else { return }
        activeCommand = nil
        session.commit()
    }

    func selectObjectForActiveCommand(_ id: ObjectId) {
        selectElementForActiveCommand(id, subElement: nil)
    }

    func selectElementForActiveCommand(_ id: ObjectId, subElement: SelectedSubElement?) {
        guard let session = activeCommand else { return }
        let hiddenIds = viewportManager.renderer?.hiddenSolidIds ?? []
        guard MeasureTool.isSolidVisible(id, in: document, hiddenSolidIds: hiddenIds) else { return }

        let name: String
        if let sub = subElement {
            let baseName = document.objects.first(where: { $0.id == id })?.name ?? id.rawValue
            switch sub.elementType {
            case .face:
                name = "Face \(sub.elementId) (\(baseName))"
            case .edge:
                name = "Edge \(sub.elementId) (\(baseName))"
            case .vertex:
                name = "Vertex \(sub.elementId) (\(baseName))"
            }
        } else {
            name = document.objects.first(where: { $0.id == id })?.name ?? id.rawValue
        }

        if let activeIndex = session.selectionSlots.firstIndex(where: { $0.isActive }) {
            let activeSlotId = session.selectionSlots[activeIndex].id
            session.setSlotSelection(slotId: activeSlotId, objectId: id, objectName: name, subElement: subElement)
            if let nextEmpty = session.selectionSlots.firstIndex(where: { $0.selectedObjectId == nil && $0.selectedSubElement == nil }) {
                session.selectSlot(id: session.selectionSlots[nextEmpty].id)
            }
        } else if let emptyIndex = session.selectionSlots.firstIndex(where: { $0.selectedObjectId == nil && $0.selectedSubElement == nil }) {
            let emptySlotId = session.selectionSlots[emptyIndex].id
            session.setSlotSelection(slotId: emptySlotId, objectId: id, objectName: name, subElement: subElement)
            if let nextEmpty = session.selectionSlots.firstIndex(where: { $0.selectedObjectId == nil && $0.selectedSubElement == nil }) {
                session.selectSlot(id: session.selectionSlots[nextEmpty].id)
            }
        }
        session.onPreviewUpdate?()
    }

    func startMeasureCommand() {
        let session = CommandSession.makeMeasure(workspace: self)
        startCommand(session)
        if let sub = document.selectedSubElement {
            selectElementForActiveCommand(sub.solidId, subElement: sub)
        }
    }

    func startAddBoxCommand() {
        startCommand(CommandSession.makeAddBox(workspace: self))
    }

    func startAddCylinderCommand() {
        startCommand(CommandSession.makeAddCylinder(workspace: self))
    }

    func startAddSphereCommand() {
        startCommand(CommandSession.makeAddSphere(workspace: self))
    }

    func startAddConeCommand() {
        startCommand(CommandSession.makeAddCone(workspace: self))
    }

    func startAddTorusCommand() {
        startCommand(CommandSession.makeAddTorus(workspace: self))
    }

    func startAddWedgeCommand() {
        startCommand(CommandSession.makeAddWedge(workspace: self))
    }

    func startTransformCommand() {
        startCommand(CommandSession.makeTransform(workspace: self, targetId: selectedId))
    }

    func startBooleanCommand() {
        startCommand(CommandSession.makeBoolean(workspace: self, selectedId: selectedId))
    }

    func startExtrudeCommand(sketchFeatureId: UUID? = nil) {
        startCommand(CommandSession.makeExtrude(workspace: self, sketchFeatureId: sketchFeatureId))
    }

    func startRevolveCommand(sketchFeatureId: UUID? = nil) {
        startCommand(CommandSession.makeRevolve(workspace: self, sketchFeatureId: sketchFeatureId))
    }

    func startPushPullCommand(solidId: SolidId, faceId: Int) {
        startCommand(CommandSession.makePushPull(workspace: self, solidId: solidId, faceId: faceId))
    }

    func startChamferCommand() {
        var targetSolidId: SolidId? = nil
        var initialEdgeRef: TopologicalReference? = nil
        if let sub = document.selectedSubElement, sub.elementType == .edge {
            targetSolidId = sub.solidId
            if let feat = document.feature(for: sub.solidId) {
                if let detId = sub.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                    initialEdgeRef = existing
                } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "edge:\(sub.elementId)" }) {
                    initialEdgeRef = named
                } else {
                    initialEdgeRef = TopologicalReference(
                        sourceFeatureId: feat.id,
                        elementType: .edge,
                        historyPath: [HistoryStep(kind: .generated, label: "edge:\(sub.elementId)")]
                    )
                }
            }
        } else if let selectedId {
            targetSolidId = selectedId
        } else if let firstObj = document.objects.first {
            targetSolidId = firstObj.id
        }

        startCommand(CommandSession.makeChamfer(
            workspace: self,
            targetSolidId: targetSolidId,
            edgeReferences: initialEdgeRef.map { [$0] } ?? []
        ))
    }

    func startShellCommand() {
        var targetSolidId: SolidId? = nil
        var initialFaceRef: TopologicalReference? = nil
        if let sub = document.selectedSubElement, sub.elementType == .face {
            targetSolidId = sub.solidId
            if let feat = document.feature(for: sub.solidId) {
                if let detId = sub.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                    initialFaceRef = existing
                } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "face:\(sub.elementId)" }) {
                    initialFaceRef = named
                } else {
                    initialFaceRef = TopologicalReference(
                        sourceFeatureId: feat.id,
                        elementType: .face,
                        historyPath: [HistoryStep(kind: .generated, label: "face:\(sub.elementId)")]
                    )
                }
            }
        } else if let selectedId {
            targetSolidId = selectedId
        } else if let firstObj = document.objects.first {
            targetSolidId = firstObj.id
        }

        startCommand(CommandSession.makeShell(
            workspace: self,
            targetSolidId: targetSolidId,
            removedFaceReferences: initialFaceRef.map { [$0] } ?? []
        ))
    }

    func startHoleCommand() {
        var targetSolidId: SolidId? = nil
        var initialFaceRef: TopologicalReference? = nil
        if let sub = document.selectedSubElement, sub.elementType == .face {
            targetSolidId = sub.solidId
            if let feat = document.feature(for: sub.solidId) {
                if let detId = sub.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                    initialFaceRef = existing
                } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "face:\(sub.elementId)" }) {
                    initialFaceRef = named
                } else {
                    initialFaceRef = TopologicalReference(
                        sourceFeatureId: feat.id,
                        elementType: .face,
                        historyPath: [HistoryStep(kind: .generated, label: "face:\(sub.elementId)")]
                    )
                }
            }
        } else if let selectedId {
            targetSolidId = selectedId
        } else if let firstObj = document.objects.first {
            targetSolidId = firstObj.id
        }

        startCommand(CommandSession.makeHole(
            workspace: self,
            targetSolidId: targetSolidId,
            faceReference: initialFaceRef
        ))
    }

    func startLinearPatternCommand() {
        var targetSolidId: SolidId? = nil
        if let sub = document.selectedSubElement {
            targetSolidId = sub.solidId
        } else if let selectedId {
            targetSolidId = selectedId
        } else if let firstObj = document.objects.first {
            targetSolidId = firstObj.id
        }

        startCommand(CommandSession.makeLinearPattern(
            workspace: self,
            targetSolidId: targetSolidId
        ))
    }

    func startCircularPatternCommand() {
        var targetSolidId: SolidId? = nil
        if let sub = document.selectedSubElement {
            targetSolidId = sub.solidId
        } else if let selectedId {
            targetSolidId = selectedId
        } else if let firstObj = document.objects.first {
            targetSolidId = firstObj.id
        }

        startCommand(CommandSession.makeCircularPattern(
            workspace: self,
            targetSolidId: targetSolidId
        ))
    }

    func startMirrorCommand() {
        var targetSolidId: SolidId? = nil
        var initialPlaneRef: Reference? = nil
        var presetPlane = "XY Plane"

        if let sub = document.selectedSubElement {
            if sub.elementType == .face {
                if let feat = document.feature(for: sub.solidId) {
                    let topRef: TopologicalReference
                    if let detId = sub.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                        topRef = existing
                    } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "face:\(sub.elementId)" }) {
                        topRef = named
                    } else {
                        topRef = TopologicalReference(
                            sourceFeatureId: feat.id,
                            elementType: .face,
                            historyPath: [HistoryStep(kind: .generated, label: "face:\(sub.elementId)")]
                        )
                    }
                    initialPlaneRef = Reference.face(topRef)
                    presetPlane = "From Selection"
                }
            } else {
                targetSolidId = sub.solidId
            }
        }

        if targetSolidId == nil {
            if let selectedId {
                targetSolidId = selectedId
            } else if let firstObj = document.objects.first {
                targetSolidId = firstObj.id
            }
        }

        if initialPlaneRef == nil, let feat = selectedFeature {
            if case .datumPlane = feat.operation {
                initialPlaneRef = Reference.feature(feat.id)
                presetPlane = "From Selection"
            }
        }

        startCommand(CommandSession.makeMirror(
            workspace: self,
            targetSolidId: targetSolidId,
            planeReference: initialPlaneRef,
            presetPlane: presetPlane
        ))
    }

    public func boundingBoxes(for solidId: SolidId) -> (axisAligned: AxisAlignedBoundingBox, oriented: OrientedBoundingBox)? {
        let candidates = viewportManager.renderer?.candidateMeshes() ?? []
        return BoundingBoxCalculator.boxes(for: solidId, in: document, candidateMeshes: candidates)
    }

    public func massProperties(
        for solidId: SolidId,
        coordinateSystem: MassPropertiesCoordinateSystem = .centroid
    ) -> MassProperties? {
        let candidates = viewportManager.renderer?.candidateMeshes() ?? []
        return MassPropertiesCalculator.calculate(
            for: solidId,
            in: document,
            candidateMeshes: candidates,
            userMaterials: userMaterials,
            coordinateSystem: coordinateSystem
        )
    }

    func isFacePlanar(solidId: SolidId, faceId: Int) -> Bool {
        if let renderer = viewportManager.renderer,
           let mesh = renderer.candidateMeshes().first(where: { $0.id == solidId }) {
            return mesh.isFacePlanar(forFaceId: faceId)
        }
        if let obj = document.objects.first(where: { $0.id == solidId }) {
            let candidate: CandidateMesh?
            switch obj.def {
            case .box(let p):
                let payload = NativeGeometryGenerator.generateBox(width: p.width, depth: p.depth, height: p.height)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .cylinder(let p):
                let payload = NativeGeometryGenerator.generateCylinder(radius: p.radius, height: p.height)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .sphere(let p):
                let payload = NativeGeometryGenerator.generateSphere(radius: p.radius)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .cone(let p):
                let payload = NativeGeometryGenerator.generateCone(bottomRadius: p.bottomRadius, topRadius: p.topRadius, height: p.height)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .torus(let p):
                let payload = NativeGeometryGenerator.generateTorus(majorRadius: p.majorRadius, minorRadius: p.minorRadius)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .wedge(let p):
                let payload = NativeGeometryGenerator.generateWedge(width: p.width, depth: p.depth, height: p.height, topWidth: p.topWidth)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            default:
                candidate = nil
            }
            return candidate?.isFacePlanar(forFaceId: faceId) ?? false
        }
        return false
    }

    func subElementScreenPosition(for sub: SelectedSubElement, viewportSize: CGSize) -> CGPoint? {
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return nil }

        let worldPoint: SIMD3<Float>?
        if let hit = sub.hitPoint {
            worldPoint = hit
        } else if let renderer = viewportManager.renderer,
                  let mesh = renderer.candidateMeshes().first(where: { $0.id == sub.solidId }) {
            worldPoint = mesh.subElementCentroid(elementType: sub.elementType, elementId: sub.elementId)
        } else if let obj = document.objects.first(where: { $0.id == sub.solidId }) {
            let candidate: CandidateMesh?
            switch obj.def {
            case .box(let p):
                let payload = NativeGeometryGenerator.generateBox(width: p.width, depth: p.depth, height: p.height)
                candidate = CandidateMesh(id: sub.solidId, payload: payload, transform: obj.transform)
            case .cylinder(let p):
                let payload = NativeGeometryGenerator.generateCylinder(radius: p.radius, height: p.height)
                candidate = CandidateMesh(id: sub.solidId, payload: payload, transform: obj.transform)
            case .sphere(let p):
                let payload = NativeGeometryGenerator.generateSphere(radius: p.radius)
                candidate = CandidateMesh(id: sub.solidId, payload: payload, transform: obj.transform)
            case .cone(let p):
                let payload = NativeGeometryGenerator.generateCone(bottomRadius: p.bottomRadius, topRadius: p.topRadius, height: p.height)
                candidate = CandidateMesh(id: sub.solidId, payload: payload, transform: obj.transform)
            case .torus(let p):
                let payload = NativeGeometryGenerator.generateTorus(majorRadius: p.majorRadius, minorRadius: p.minorRadius)
                candidate = CandidateMesh(id: sub.solidId, payload: payload, transform: obj.transform)
            case .wedge(let p):
                let payload = NativeGeometryGenerator.generateWedge(width: p.width, depth: p.depth, height: p.height, topWidth: p.topWidth)
                candidate = CandidateMesh(id: sub.solidId, payload: payload, transform: obj.transform)
            default:
                candidate = nil
            }
            worldPoint = candidate?.subElementCentroid(elementType: sub.elementType, elementId: sub.elementId)
        } else {
            worldPoint = nil
        }

        guard let pt = worldPoint else { return nil }
        let aspect = Float(max(1.0, viewportSize.width) / max(1.0, viewportSize.height))
        let matrices: (view: simd_float4x4, projection: simd_float4x4)
        if let renderer = viewportManager.renderer {
            matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        } else {
            let eye = camera.position
            let target = camera.target
            let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: Orientation.worldUp)
            let projMatrix: simd_float4x4
            if camera.projection == .orthographic {
                let baseDist = max(10.0, simd_length(eye - target))
                let dist = max(1.0, baseDist * camera.orthographicScale)
                let halfH = dist * 0.4
                let halfW = halfH * aspect
                projMatrix = Orientation.makeOrthographic(left: -halfW, right: halfW, bottom: -halfH, top: halfH, nearZ: 0.1, farZ: 1000.0)
            } else {
                projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
            }
            matrices = (view: viewMatrix, projection: projMatrix)
        }
        let vp = simd_mul(matrices.projection, matrices.view)
        guard let screenMetal = projectToScreen(point: pt, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
            return nil
        }
        return SnapOverlayView.canvasPosition(screenPoint: screenMetal, viewportHeight: viewportSize.height)
    }

    func startNewSketchCommand() {
        startCommand(CommandSession.makeNewSketch(workspace: self))
    }

    func startDatumPlaneCommand() {
        startCommand(CommandSession.makeDatumPlane(workspace: self))
    }

    func startDatumAxisCommand() {
        startCommand(CommandSession.makeDatumAxis(workspace: self))
    }

    func startDatumPointCommand() {
        startCommand(CommandSession.makeDatumPoint(workspace: self))
    }

    func startDatumCoordinateSystemCommand() {
        startCommand(CommandSession.makeDatumCoordinateSystem(workspace: self))
    }

    func startDimensionCommand(sketchFeatureId: UUID? = nil, entityId: UUID? = nil) {
        startCommand(CommandSession.makeDimension(workspace: self, sketchFeatureId: sketchFeatureId, entityId: entityId))
    }

    @discardableResult
    func extrudeSketch(sketchFeatureId: UUID, distance: Double, isSymmetric: Bool = false, regionId: UUID? = nil) async -> ObjectId? {
        do {
            let extrudeFeature = try document.extrudeSketch(
                sketchFeatureId: sketchFeatureId,
                distance: distance,
                isSymmetric: isSymmetric,
                regionId: regionId
            )
            guard let solidId = extrudeFeature.outputSolidId else { return nil }
            selectedId = solidId
            recomputeSolid(id: solidId)
            return solidId
        } catch {
            return nil
        }
    }

    @discardableResult
    func revolveSketch(
        sketchFeatureId: UUID,
        regionId: UUID? = nil,
        mode: RevolveMode = .full,
        angle: Double = 360.0,
        angle2: Double = 0.0,
        axisReference: Reference
    ) async -> ObjectId? {
        do {
            let revolveFeature = try document.revolveSketch(
                sketchFeatureId: sketchFeatureId,
                regionId: regionId,
                mode: mode,
                angle: angle,
                angle2: angle2,
                axisReference: axisReference
            )
            guard let solidId = revolveFeature.outputSolidId else { return nil }
            selectedId = solidId
            recomputeSolid(id: solidId)
            return solidId
        } catch {
            return nil
        }
    }

    @discardableResult
    func chamferEdges(
        targetSolidId: SolidId,
        edgeReferences: [TopologicalReference],
        mode: ChamferMode = .equalDistance,
        distance: Double = 1.0,
        distance2: Double = 1.0,
        angle: Double = 45.0
    ) async -> ObjectId? {
        do {
            let chamferFeature = try document.chamferEdges(
                targetSolidId: targetSolidId,
                edgeReferences: edgeReferences,
                mode: mode,
                distance: distance,
                distance2: distance2,
                angle: angle
            )
            guard let solidId = chamferFeature.outputSolidId else { return nil }
            selectedId = solidId
            markDocumentModified()
            recomputeSolid(id: solidId)
            return solidId
        } catch {
            return nil
        }
    }

    @discardableResult
    func shellBody(
        targetSolidId: SolidId,
        thickness: Double = 1.0,
        removedFaceReferences: [TopologicalReference] = [],
        perFaceOverrides: [FaceThicknessOverride] = []
    ) async -> ObjectId? {
        do {
            let shellFeature = try document.shellBody(
                targetSolidId: targetSolidId,
                thickness: thickness,
                removedFaceReferences: removedFaceReferences,
                perFaceOverrides: perFaceOverrides
            )
            guard let solidId = shellFeature.outputSolidId else { return nil }
            selectedId = solidId
            markDocumentModified()
            recomputeSolid(id: solidId)
            return solidId
        } catch {
            return nil
        }
    }

    @discardableResult
    func holeBody(
        targetSolidId: SolidId,
        faceReference: TopologicalReference,
        sketchFeatureId: UUID? = nil,
        points: [SIMD2<Double>] = [],
        holeType: HoleType = .simple,
        standard: HoleStandard = .custom,
        sizeDesignation: String? = nil,
        diameter: Double = 5.0,
        depth: Double = 10.0,
        isThrough: Bool = true,
        counterboreDiameter: Double = 0.0,
        counterboreDepth: Double = 0.0,
        countersinkDiameter: Double = 0.0,
        countersinkAngle: Double = 90.0,
        drillTipAngle: Double? = nil,
        threadMetadata: ThreadMetadata? = nil
    ) async -> ObjectId? {
        do {
            let holeFeature = try document.holeBody(
                targetSolidId: targetSolidId,
                faceReference: faceReference,
                sketchFeatureId: sketchFeatureId,
                points: points,
                holeType: holeType,
                standard: standard,
                sizeDesignation: sizeDesignation,
                diameter: diameter,
                depth: depth,
                isThrough: isThrough,
                counterboreDiameter: counterboreDiameter,
                counterboreDepth: counterboreDepth,
                countersinkDiameter: countersinkDiameter,
                countersinkAngle: countersinkAngle,
                drillTipAngle: drillTipAngle,
                threadMetadata: threadMetadata
            )
            guard let solidId = holeFeature.outputSolidId else { return nil }
            selectedId = solidId
            markDocumentModified()
            recomputeSolid(id: solidId)
            return solidId
        } catch {
            return nil
        }
    }

    @discardableResult
    func patternBody(
        params: PatternParams,
        actionName: String = "Pattern Body"
    ) async -> ObjectId? {
        do {
            let patternFeature = try document.patternBody(params: params, actionName: actionName)
            guard let solidId = patternFeature.outputSolidId else { return nil }
            selectedId = solidId
            markDocumentModified()
            recomputeSolid(id: solidId)
            return solidId
        } catch {
            return nil
        }
    }

    @discardableResult
    func patternBody(
        targetSolidId: SolidId,
        targetType: PatternTargetType = .body,
        patternType: PatternType = .linear,
        direction: [Double] = [1.0, 0.0, 0.0],
        linearSpacing: Double = 20.0,
        count: Int = 3,
        isSymmetric: Bool = false,
        axisOrigin: [Double] = [0.0, 0.0, 0.0],
        axisDirection: [Double] = [0.0, 0.0, 1.0],
        totalAngle: Double = 360.0,
        isFullCircle: Bool = true,
        skippedIndices: [Int] = [],
        actionName: String = "Pattern Body"
    ) async -> ObjectId? {
        let params = PatternParams(
            targetSolidId: targetSolidId,
            targetType: targetType,
            patternType: patternType,
            direction: direction,
            linearSpacing: linearSpacing,
            count: count,
            isSymmetric: isSymmetric,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection,
            totalAngle: totalAngle,
            isFullCircle: isFullCircle,
            skippedIndices: skippedIndices
        )
        return await patternBody(params: params, actionName: actionName)
    }

    @discardableResult
    func mirrorBody(
        params: MirrorParams,
        actionName: String = "Mirror Body"
    ) async -> ObjectId? {
        do {
            let mirrorFeature = try document.mirrorBody(params: params, actionName: actionName)
            guard let solidId = mirrorFeature.outputSolidId else { return nil }
            selectedId = solidId
            markDocumentModified()
            recomputeSolid(id: solidId)
            return solidId
        } catch {
            return nil
        }
    }

    @discardableResult
    func mirrorBody(
        targetSolidId: SolidId,
        targetType: MirrorTargetType = .body,
        planeNormal: [Double] = [0.0, 0.0, 1.0],
        planeOrigin: [Double] = [0.0, 0.0, 0.0],
        keepOriginal: Bool = true,
        planeReference: Reference? = nil,
        actionName: String = "Mirror Body"
    ) async -> ObjectId? {
        let params = MirrorParams(
            targetSolidId: targetSolidId,
            targetType: targetType,
            planeNormal: planeNormal,
            planeOrigin: planeOrigin,
            keepOriginal: keepOriginal,
            planeReference: planeReference
        )
        return await mirrorBody(params: params, actionName: actionName)
    }

    @discardableResult
    func combineBodies(
        targetBodyId: SolidId,
        toolBodyId: SolidId,
        operation: BooleanOp = .union,
        keepTool: Bool = false,
        actionName: String? = nil
    ) -> Feature? {
        do {
            let feat = try document.combineBodies(
                targetBodyId: targetBodyId,
                toolBodyId: toolBodyId,
                operation: operation,
                keepTool: keepTool,
                actionName: actionName
            )
            selectedId = targetBodyId
            markDocumentModified()
            recomputeSolid(id: targetBodyId)
            return feat
        } catch {
            return nil
        }
    }

    @discardableResult
    func moveBody(
        targetBodyId: ObjectId,
        transform: Transform,
        actionName: String = "Move Body"
    ) -> Feature? {
        do {
            let feat = try document.moveBody(targetBodyId: targetBodyId, transform: transform, actionName: actionName)
            markDocumentModified()
            recomputeSolid(id: targetBodyId)
            invalidateViewport(.model)
            return feat
        } catch {
            return nil
        }
    }

    @discardableResult
    func copyBody(
        sourceBodyId: ObjectId,
        transform: Transform = .identity,
        actionName: String = "Copy Body"
    ) -> Feature? {
        do {
            let feat = try document.copyBody(sourceBodyId: sourceBodyId, transform: transform, actionName: actionName)
            if let outputId = feat.outputSolidId {
                selectedId = outputId
                recomputeSolid(id: outputId)
            }
            markDocumentModified()
            invalidateViewport(.model)
            return feat
        } catch {
            return nil
        }
    }

    @discardableResult
    func deleteBody(
        _ id: ObjectId,
        actionName: String = "Delete Body"
    ) -> Feature? {
        do {
            let feat = try document.deleteBody(targetBodyId: id, actionName: actionName)
            if selectedId == id {
                selectedId = nil
            }
            markDocumentModified()
            invalidateViewport(.model)
            return feat
        } catch {
            return nil
        }
    }

    private func processSolverResult(
        _ result: SolverResult,
        for featureId: UUID,
        sketchData: SketchFeatureData,
        updateEntities: Bool
    ) {
        entityDOFStatus = result.entityDOF

        switch result.status {
        case .converged:
            conflictingConstraintIds = []
            redundantConstraintIds = []
            overConstrainedMessage = nil
            redundantConstraintsMessage = nil
            if result.dof == 0 {
                setSketchDOFStatus(.fullyConstrained)
            } else {
                setSketchDOFStatus(.underConstrained(dof: result.dof))
            }
            if updateEntities && result.solvedEntities != sketchData.entities {
                _ = document.updateSketchEntities(in: featureId, entities: result.solvedEntities)
            }

        case .redundant(let redundant):
            conflictingConstraintIds = []
            overConstrainedMessage = nil
            redundantConstraintIds = Set(redundant)
            let names = redundant.compactMap { id in
                sketchData.constraints.first(where: { $0.id == id })?.kind.rawValue.capitalized
            }
            let desc = names.isEmpty ? "Redundant constraints" : names.joined(separator: " and ")
            redundantConstraintsMessage = "Redundant: \(desc) have no effect on degrees of freedom"
            if result.dof == 0 {
                setSketchDOFStatus(.fullyConstrained)
            } else {
                setSketchDOFStatus(.underConstrained(dof: result.dof))
            }
            if updateEntities && result.solvedEntities != sketchData.entities {
                _ = document.updateSketchEntities(in: featureId, entities: result.solvedEntities)
            }

        case .overConstrained(let conflicting):
            redundantConstraintIds = []
            redundantConstraintsMessage = nil
            conflictingConstraintIds = Set(conflicting)
            let names = conflicting.compactMap { id in
                sketchData.constraints.first(where: { $0.id == id })?.kind.rawValue.capitalized
            }
            let desc = names.isEmpty ? "Conflicting constraints" : names.joined(separator: " and ")
            overConstrainedMessage = "Over-constrained: \(desc) conflict on sketch entities"
            setSketchDOFStatus(.overConstrained(dof: result.dof))

        case .failedToConverge(let reason):
            redundantConstraintIds = []
            redundantConstraintsMessage = nil
            conflictingConstraintIds = []
            overConstrainedMessage = "Failed to converge: \(reason)"
            setSketchDOFStatus(.overConstrained(dof: result.dof))
        }
    }

    func refreshSketchStatus(for featureId: UUID) {
        refreshDetectedSketchRegions(for: featureId)
        guard let feat = document.feature(for: featureId), case .sketch(let sketchData) = feat.operation else {
            setSketchDOFStatus(.inactive)
            inferredConstraints = []
            return
        }
        let system = ConstraintSystem(entities: sketchData.entities, constraints: sketchData.constraints)
        let result = ConstraintSolver.solve(system: system)
        processSolverResult(result, for: featureId, sketchData: sketchData, updateEntities: false)
        if isLiveInferenceEnabled {
            inferredConstraints = ConstraintInference.inferCandidates(for: sketchData.entities, existingConstraints: sketchData.constraints)
        } else {
            inferredConstraints = []
        }
    }

    // MARK: - Interactive Sketch Drag Solving (BL-CON-07)

    public func beginInteractiveSketchDrag(featureId: UUID, entityId: UUID? = nil) {
        if let entityId {
            selectSketchEntity(featureId: featureId, entityId: entityId)
        }
        document.beginInteractiveSketchDrag(featureId: featureId)
    }

    public func endInteractiveSketchDrag(featureId: UUID) {
        document.endInteractiveSketchDrag(featureId: featureId)
        refreshSketchStatus(for: featureId)
        recomputeDependents(of: featureId)
    }

    public func solveSketchDrag(featureId: UUID, dragTarget: DragTarget) {
        guard let feat = document.feature(for: featureId), case .sketch(let sketchData) = feat.operation else { return }

        let system = ConstraintSystem(entities: sketchData.entities, constraints: sketchData.constraints)
        let result = ConstraintSolver.solve(system: system, dragTarget: dragTarget)
        processSolverResult(result, for: featureId, sketchData: sketchData, updateEntities: true)

        if isLiveInferenceEnabled {
            if let updatedFeat = document.feature(for: featureId), case .sketch(let updatedData) = updatedFeat.operation {
                inferredConstraints = ConstraintInference.inferCandidates(for: updatedData.entities, existingConstraints: updatedData.constraints)
            }
        }
    }

    func solveSketchConstraints(featureId: UUID, draggedEntityId: UUID? = nil) {
        guard let feat = document.feature(for: featureId), case .sketch(let sketchData) = feat.operation else { return }
        guard !sketchData.constraints.isEmpty else {
            refreshSketchStatus(for: featureId)
            return
        }

        let dragTarget: DragTarget?
        if let draggedId = draggedEntityId, let entity = sketchData.entities.first(where: { $0.id == draggedId }) {
            if let end = entity.endPoint {
                dragTarget = DragTarget(entityId: draggedId, endpoint: .end, targetPosition: end)
            } else if let center = entity.centerPoint {
                dragTarget = DragTarget(entityId: draggedId, endpoint: .center, targetPosition: center)
            } else {
                dragTarget = nil
            }
        } else {
            dragTarget = nil
        }

        let system = ConstraintSystem(entities: sketchData.entities, constraints: sketchData.constraints)
        let result = ConstraintSolver.solve(system: system, dragTarget: dragTarget)
        processSolverResult(result, for: featureId, sketchData: sketchData, updateEntities: true)
    }

    func addSketchEntity(to featureId: UUID, entity: SketchEntity) {
        _ = document.addSketchEntity(to: featureId, entity: entity)
        refreshSketchStatus(for: featureId)
        recomputeDependents(of: featureId)
    }

    @discardableResult
    func addCornerRectangle(
        to featureId: UUID? = nil,
        corner1: SIMD2<Double>? = nil,
        corner2: SIMD2<Double>? = nil
    ) throws -> SketchRectangleResult {
        guard let targetId = featureId ?? selectedSketchFeature?.id else {
            throw SketchError.invalidEntity("No active sketch selected")
        }
        let c1 = corner1 ?? SIMD2<Double>(0, 0)
        let c2 = corner2 ?? SIMD2<Double>(40, 30)
        let result = try SketchRectangle.makeCornerRectangle(corner1: c1, corner2: c2)
        let res = document.addSketchEntitiesAndConstraints(
            to: targetId,
            entities: result.entities,
            constraints: result.constraints,
            actionName: "Add Corner Rectangle"
        )
        if case .failure(let err) = res {
            throw SketchError.invalidEntity("Document mutation failed: \(err)")
        }
        refreshSketchStatus(for: targetId)
        solveSketchConstraints(featureId: targetId)
        recomputeDependents(of: targetId)
        return result
    }

    @discardableResult
    func addCenterRectangle(
        to featureId: UUID? = nil,
        center: SIMD2<Double>? = nil,
        corner: SIMD2<Double>? = nil
    ) throws -> SketchRectangleResult {
        guard let targetId = featureId ?? selectedSketchFeature?.id else {
            throw SketchError.invalidEntity("No active sketch selected")
        }
        let c = center ?? SIMD2<Double>(0, 0)
        let cr = corner ?? SIMD2<Double>(20, 15)
        let result = try SketchRectangle.makeCenterRectangle(center: c, corner: cr)
        let res = document.addSketchEntitiesAndConstraints(
            to: targetId,
            entities: result.entities,
            constraints: result.constraints,
            actionName: "Add Center Rectangle"
        )
        if case .failure(let err) = res {
            throw SketchError.invalidEntity("Document mutation failed: \(err)")
        }
        refreshSketchStatus(for: targetId)
        solveSketchConstraints(featureId: targetId)
        recomputeDependents(of: targetId)
        return result
    }

    @discardableResult
    func addThreePointRectangle(
        to featureId: UUID? = nil,
        point1: SIMD2<Double>? = nil,
        point2: SIMD2<Double>? = nil,
        point3: SIMD2<Double>? = nil
    ) throws -> SketchRectangleResult {
        guard let targetId = featureId ?? selectedSketchFeature?.id else {
            throw SketchError.invalidEntity("No active sketch selected")
        }
        let p1 = point1 ?? SIMD2<Double>(0, 0)
        let p2 = point2 ?? SIMD2<Double>(40, 0)
        let p3 = point3 ?? SIMD2<Double>(40, 30)
        let result = try SketchRectangle.makeThreePointRectangle(point1: p1, point2: p2, point3: p3)
        let res = document.addSketchEntitiesAndConstraints(
            to: targetId,
            entities: result.entities,
            constraints: result.constraints,
            actionName: "Add Three-Point Rectangle"
        )
        if case .failure(let err) = res {
            throw SketchError.invalidEntity("Document mutation failed: \(err)")
        }
        refreshSketchStatus(for: targetId)
        solveSketchConstraints(featureId: targetId)
        recomputeDependents(of: targetId)
        return result
    }

    func updateSketchEntity(in featureId: UUID, entity: SketchEntity) {
        _ = document.updateSketchEntity(in: featureId, entity: entity)
        solveSketchConstraints(featureId: featureId, draggedEntityId: entity.id)
        if isLiveInferenceEnabled {
            if let feat = document.feature(for: featureId), case .sketch(let sketchData) = feat.operation {
                inferredConstraints = ConstraintInference.inferCandidates(for: sketchData.entities, existingConstraints: sketchData.constraints)
            }
        }
        recomputeDependents(of: featureId)
    }

    @discardableResult
    func dimensionSketchLine(featureId: UUID, entityId: UUID, length: Double) throws -> SketchEntity {
        let updated = try document.setSketchLineLength(in: featureId, entityId: entityId, length: length)
        solveSketchConstraints(featureId: featureId, draggedEntityId: entityId)
        if isLiveInferenceEnabled {
            if let feat = document.feature(for: featureId), case .sketch(let sketchData) = feat.operation {
                inferredConstraints = ConstraintInference.inferCandidates(for: sketchData.entities, existingConstraints: sketchData.constraints)
            }
        }
        recomputeDependents(of: featureId)
        return updated
    }

    func removeSketchEntity(from featureId: UUID, entityId: UUID) {
        _ = document.removeSketchEntity(from: featureId, entityId: entityId)
        refreshSketchStatus(for: featureId)
        recomputeDependents(of: featureId)
    }

    func toggleSelectedSketchEntityConstruction() {
        guard let pair = selectedSketchEntity else { return }
        _ = document.toggleSketchEntityConstruction(in: pair.featureId, entityId: pair.entity.id)
        refreshDetectedSketchRegions(for: pair.featureId)
        solveSketchConstraints(featureId: pair.featureId, draggedEntityId: pair.entity.id)
        if isLiveInferenceEnabled {
            if let feat = document.feature(for: pair.featureId), case .sketch(let sketchData) = feat.operation {
                inferredConstraints = ConstraintInference.inferCandidates(for: sketchData.entities, existingConstraints: sketchData.constraints)
            }
        }
        recomputeDependents(of: pair.featureId)
    }

    // MARK: - Sketch Operations Coordination (BL-SKT-08)

    @discardableResult
    func trimSketchEntity(in featureId: UUID, entityId: UUID, clickPoint: SIMD2<Double>) -> Result<TrimResult, DocumentMutationError> {
        let res = document.trimSketchEntity(in: featureId, entityId: entityId, clickPoint: clickPoint)
        if case .success(let trimResult) = res {
            solveSketchConstraints(featureId: featureId)
            refreshDetectedSketchRegions(for: featureId)
            refreshSketchStatus(for: featureId)
            recomputeDependents(of: featureId)
            if case .deleted = trimResult {
                if let sel = selectedSketchEntity, sel.entity.id == entityId {
                    document.selection = [Reference.feature(featureId)]
                }
            }
        }
        return res
    }

    @discardableResult
    func trimSketchEntitiesAlongPath(in featureId: UUID, path: [SIMD2<Double>]) -> Result<[TrimResult], DocumentMutationError> {
        let res = document.trimSketchEntitiesAlongPath(in: featureId, path: path)
        if case .success(let results) = res, !results.isEmpty {
            solveSketchConstraints(featureId: featureId)
            refreshDetectedSketchRegions(for: featureId)
            refreshSketchStatus(for: featureId)
            recomputeDependents(of: featureId)
        }
        return res
    }

    @discardableResult
    func extendSketchEntity(in featureId: UUID, entityId: UUID, targetEnd: SketchEntityEnd) -> Result<SketchEntity, DocumentMutationError> {
        let res = document.extendSketchEntity(in: featureId, entityId: entityId, targetEnd: targetEnd)
        if case .success = res {
            solveSketchConstraints(featureId: featureId)
            refreshDetectedSketchRegions(for: featureId)
            refreshSketchStatus(for: featureId)
            recomputeDependents(of: featureId)
        }
        return res
    }

    @discardableResult
    func splitSketchEntity(in featureId: UUID, entityId: UUID, at point: SIMD2<Double>) -> Result<(SketchEntity, SketchEntity), DocumentMutationError> {
        let res = document.splitSketchEntity(in: featureId, entityId: entityId, at: point)
        if case .success = res {
            solveSketchConstraints(featureId: featureId)
            refreshDetectedSketchRegions(for: featureId)
            refreshSketchStatus(for: featureId)
            recomputeDependents(of: featureId)
        }
        return res
    }

    @discardableResult
    func projectReference(_ reference: Reference, into sketchFeatureId: UUID? = nil) -> Result<SketchEntity, DocumentMutationError> {
        guard let targetId = sketchFeatureId ?? selectedSketchFeature?.id else {
            return .failure(.objectNotFound(ObjectId("sketch")))
        }
        let res = document.projectEntity(reference: reference, into: targetId)
        if case .success = res {
            solveSketchConstraints(featureId: targetId)
            refreshDetectedSketchRegions(for: targetId)
            refreshSketchStatus(for: targetId)
            recomputeDependents(of: targetId)
            markDocumentModified()
        }
        return res
    }

    @discardableResult
    func projectSelectedGeometry() -> Result<SketchEntity, DocumentMutationError>? {
        guard let targetSketch = selectedSketchFeature else { return nil }

        // 1. Check sub-element selection for an edge
        if let sub = document.selectedSubElement, sub.elementType == .edge {
            if let feat = document.feature(for: sub.solidId) {
                let topRef: TopologicalReference
                if let detId = sub.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                    topRef = existing
                } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "edge:\(sub.elementId)" }) {
                    topRef = named
                } else {
                    topRef = TopologicalReference(
                        sourceFeatureId: feat.id,
                        elementType: .edge,
                        historyPath: [HistoryStep(kind: .generated, label: "edge:\(sub.elementId)")]
                    )
                }
                let ref = Reference.edge(topRef)
                return projectReference(ref, into: targetSketch.id)
            }
        }

        // 2. Check selected upstream sketch entity
        if let pair = selectedSketchEntity, pair.featureId != targetSketch.id {
            let ref = Reference.sketchEntity(featureId: pair.featureId, entityId: pair.entity.id)
            return projectReference(ref, into: targetSketch.id)
        }

        // 3. Check document selection references
        for selRef in document.selection {
            switch selRef.target {
            case .edge:
                return projectReference(selRef, into: targetSketch.id)
            case .sketchEntity(let featId, _):
                if featId != targetSketch.id {
                    return projectReference(selRef, into: targetSketch.id)
                }
            default:
                break
            }
        }

        return nil
    }

    func extendSelectedSketchEntity(targetEnd: SketchEntityEnd) {
        guard let pair = selectedSketchEntity else { return }
        _ = extendSketchEntity(in: pair.featureId, entityId: pair.entity.id, targetEnd: targetEnd)
    }

    func splitSelectedSketchEntityAtMidpoint() {
        guard let pair = selectedSketchEntity else { return }
        let entity = pair.entity
        let midpoint: SIMD2<Double>?
        switch entity.kind {
        case "line":
            if let sp = entity.startPoint, let ep = entity.endPoint {
                midpoint = (sp + ep) * 0.5
            } else { midpoint = nil }
        case "arc":
            if let sp = entity.startPoint, let ep = entity.endPoint, let cp = entity.centerPoint {
                let r = entity.radius ?? hypot(sp.x - cp.x, sp.y - cp.y)
                let cw = entity.isClockwise
                let sweep = SketchOperations.arcSweepAngle(start: sp, end: ep, center: cp, clockwise: cw)
                let sAngle = atan2(sp.y - cp.y, sp.x - cp.x)
                let midAngle = cw ? (sAngle - sweep * 0.5) : (sAngle + sweep * 0.5)
                midpoint = cp + r * SIMD2<Double>(cos(midAngle), sin(midAngle))
            } else { midpoint = nil }
        case "circle":
            if let cp = entity.centerPoint, let r = entity.radius {
                midpoint = cp + SIMD2<Double>(r, 0.0)
            } else { midpoint = nil }
        default:
            midpoint = nil
        }
        if let pt = midpoint {
            _ = splitSketchEntity(in: pair.featureId, entityId: entity.id, at: pt)
        }
    }

    func addSketchConstraint(to featureId: UUID, constraint: SketchConstraint) {
        _ = document.addSketchConstraint(to: featureId, constraint: constraint)
        solveSketchConstraints(featureId: featureId)
        if isLiveInferenceEnabled {
            if let feat = document.feature(for: featureId), case .sketch(let sketchData) = feat.operation {
                inferredConstraints = ConstraintInference.inferCandidates(for: sketchData.entities, existingConstraints: sketchData.constraints)
            }
        }
        recomputeDependents(of: featureId)
    }

    func removeSketchConstraint(from featureId: UUID, constraintId: UUID) {
        _ = document.removeSketchConstraint(from: featureId, constraintId: constraintId)
        solveSketchConstraints(featureId: featureId)
        if isLiveInferenceEnabled {
            if let feat = document.feature(for: featureId), case .sketch(let sketchData) = feat.operation {
                inferredConstraints = ConstraintInference.inferCandidates(for: sketchData.entities, existingConstraints: sketchData.constraints)
            }
        }
        recomputeDependents(of: featureId)
    }

    public func setSketchConstraintDriven(in featureId: UUID, constraintId: UUID, isDriven: Bool) {
        _ = document.setSketchConstraintDriven(in: featureId, constraintId: constraintId, isDriven: isDriven)
        solveSketchConstraints(featureId: featureId)
        if isLiveInferenceEnabled {
            if let feat = document.feature(for: featureId), case .sketch(let sketchData) = feat.operation {
                inferredConstraints = ConstraintInference.inferCandidates(for: sketchData.entities, existingConstraints: sketchData.constraints)
            }
        }
        recomputeDependents(of: featureId)
    }

    public func toggleSketchConstraintDriven(in featureId: UUID, constraintId: UUID) {
        guard let feat = document.feature(for: featureId), case .sketch(let data) = feat.operation,
              let constraint = data.constraints.first(where: { $0.id == constraintId }) else { return }
        setSketchConstraintDriven(in: featureId, constraintId: constraintId, isDriven: !constraint.isDriven)
    }

    func toggleLiveInference() {
        isLiveInferenceEnabled.toggle()
        if isLiveInferenceEnabled, let sketch = selectedSketchFeature {
            refreshSketchStatus(for: sketch.id)
        } else {
            inferredConstraints = []
        }
    }

    func applyInferredConstraint(_ constraint: SketchConstraint) {
        guard let sketch = selectedSketchFeature else { return }
        var committed = constraint
        committed.isTemporary = false
        addSketchConstraint(to: sketch.id, constraint: committed)
    }

    func solveActiveSketchConstraints() {
        guard let sketch = selectedSketchFeature else { return }
        solveSketchConstraints(featureId: sketch.id)
    }

    func applyConstraintToSelectedSketch(_ kind: SketchConstraint.Kind) {
        guard let sketch = selectedSketchFeature, case .sketch(let data) = sketch.operation else { return }
        let lines = data.entities.filter { $0.kind == "line" }
        let circles = data.entities.filter { $0.kind == "circle" }

        switch kind {
        case .parallel, .perpendicular:
            if lines.count >= 2 {
                let constraint = SketchConstraint(kind: kind, entityIds: [lines[0].id, lines[1].id])
                addSketchConstraint(to: sketch.id, constraint: constraint)
            }
        case .tangent:
            if let line = lines.first, let circle = circles.first {
                let constraint = SketchConstraint(kind: kind, entityIds: [line.id, circle.id])
                addSketchConstraint(to: sketch.id, constraint: constraint)
            } else if circles.count >= 2 {
                let constraint = SketchConstraint(kind: kind, entityIds: [circles[0].id, circles[1].id])
                addSketchConstraint(to: sketch.id, constraint: constraint)
            }
        case .concentric:
            if circles.count >= 2 {
                let constraint = SketchConstraint(kind: kind, entityIds: [circles[0].id, circles[1].id])
                addSketchConstraint(to: sketch.id, constraint: constraint)
            }
        case .symmetric:
            if lines.count >= 3 {
                let constraint = SketchConstraint(kind: kind, entityIds: [lines[0].id, lines[1].id], referenceEntityId: lines[2].id)
                addSketchConstraint(to: sketch.id, constraint: constraint)
            } else if lines.count >= 1 && circles.count >= 2 {
                let constraint = SketchConstraint(kind: kind, entityIds: [circles[0].id, circles[1].id], referenceEntityId: lines[0].id)
                addSketchConstraint(to: sketch.id, constraint: constraint)
            }
        case .horizontal, .vertical:
            if let line = lines.first {
                let constraint = SketchConstraint(kind: kind, entityIds: [line.id])
                addSketchConstraint(to: sketch.id, constraint: constraint)
            }
        case .coincident:
            if data.entities.count >= 2 {
                let constraint = SketchConstraint(kind: kind, entityIds: [data.entities[0].id, data.entities[1].id])
                addSketchConstraint(to: sketch.id, constraint: constraint)
            }
        }
    }

    private func recomputeDependents(of featureId: UUID) {
        let dependents = document.dependentFeatures(referencing: featureId)
        for dep in dependents {
            if let solidId = dep.outputSolidId {
                recomputeSolid(id: solidId)
            }
        }
        invalidateViewport(.interaction)
    }

    // MARK: - Scene editing

    // MARK: - Document Lifecycle & Autosave

    func markDocumentModified() {
        isDocumentModified = true
        syncWindowState()
        scheduleAutosaveIfNeeded()
    }

    func scheduleAutosaveIfNeeded() {
        guard isDocumentModified else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.autosaveDebounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, self.isDocumentModified else { return }
            self.performAutosave()
        }
    }

    func performAutosave() {
        if let url = currentDocumentURL {
            _ = saveDocument(to: url)
        } else {
            saveRecoverySnapshot()
        }
    }

    func performAutosave(to url: URL) {
        _ = saveDocument(to: url)
    }

    func syncWindowState() {
        let app: NSApplication? = NSApp
        guard let app else { return }
        guard let window = app.keyWindow ?? app.mainWindow ?? app.windows.first(where: { !($0 is NSPanel) }) else { return }
        window.isDocumentEdited = isDocumentModified
        window.representedURL = currentDocumentURL
    }

    func newDocument() {
        cancelActiveCommand()
        autosaveTask?.cancel()
        autosaveTask = nil
        clearRecoverySnapshot()
        pendingRecoveryRecord = nil
        isShowingRecoveryAlert = false
        pendingSaveError = nil
        isShowingSaveErrorAlert = false
        pendingOpenError = nil
        isShowingOpenErrorAlert = false
        pendingExportError = nil
        isShowingExportErrorAlert = false
        pendingImportError = nil
        isShowingImportErrorAlert = false

        let initialSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: lengthUnit, angleUnit: angleUnit, decimalPrecision: decimalPrecision),
            tolerances: kernelTolerances
        )
        let defaultObjects = [
            SceneObject(
                id: boxSolidId,
                def: .box(BoxParams(width: 40, depth: 30, height: 20)),
                transform: Transform(position: SIMD3<Float>(-25, 0, 0)),
                material: initialSettings.defaultMaterial
            ),
            SceneObject(
                id: cylinderSolidId,
                def: .cylinder(CylinderParams(radius: 15, height: 40)),
                transform: Transform(position: SIMD3<Float>(25, 0, 0)),
                material: initialSettings.defaultMaterial
            )
        ]
        document.reset(with: defaultObjects, selectedId: boxSolidId, settings: initialSettings)
        currentDocumentURL = nil
        isDocumentModified = false
        syncWindowState()
        syncHiddenSolidIds()
        syncViewportSelection()
        log(.info, "Document", "Created new document")

        for obj in document.objects {
            recomputeSolid(id: obj.id)
        }
    }

    func newAssemblyDocument() {
        cancelActiveCommand()
        autosaveTask?.cancel()
        autosaveTask = nil
        clearRecoverySnapshot()
        pendingRecoveryRecord = nil
        isShowingRecoveryAlert = false
        pendingSaveError = nil
        isShowingSaveErrorAlert = false
        pendingOpenError = nil
        isShowingOpenErrorAlert = false
        pendingExportError = nil
        isShowingExportErrorAlert = false
        pendingImportError = nil
        isShowingImportErrorAlert = false

        let initialSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: lengthUnit, angleUnit: angleUnit, decimalPrecision: decimalPrecision),
            tolerances: kernelTolerances
        )
        document.reset(with: [SceneObject](), selectedId: nil, settings: initialSettings, documentType: .assembly, componentInstances: [])
        currentDocumentURL = nil
        isDocumentModified = false
        syncWindowState()
        syncHiddenSolidIds()
        syncViewportSelection()
        log(.info, "Document", "Created new assembly document")
        invalidateViewport(.model)
    }

    func newDrawingDocument() {
        cancelActiveCommand()
        autosaveTask?.cancel()
        autosaveTask = nil
        clearRecoverySnapshot()
        pendingRecoveryRecord = nil
        isShowingRecoveryAlert = false
        pendingSaveError = nil
        isShowingSaveErrorAlert = false
        pendingOpenError = nil
        isShowingOpenErrorAlert = false
        pendingExportError = nil
        isShowingExportErrorAlert = false
        pendingImportError = nil
        isShowingImportErrorAlert = false

        let initialSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: lengthUnit, angleUnit: angleUnit, decimalPrecision: decimalPrecision),
            tolerances: kernelTolerances
        )
        let defaultSheet = DrawingSheet(name: "Sheet 1", size: .isoA3, orientation: .landscape)
        document.reset(
            with: [SceneObject](),
            selectedId: nil,
            settings: initialSettings,
            documentType: .drawing,
            componentInstances: [],
            sheets: [defaultSheet],
            activeSheetId: defaultSheet.id
        )
        currentDocumentURL = nil
        isDocumentModified = false
        syncWindowState()
        syncHiddenSolidIds()
        syncViewportSelection()
        log(.info, "Document", "Created new drawing document")
        invalidateViewport(.model)
    }

    // MARK: - Drawing Sheet Workspace Actions (BL-DRW-01, #208)

    @discardableResult
    func addSheet(
        name: String? = nil,
        size: DrawingSheetSize = .isoA3,
        orientation: DrawingSheetOrientation = .landscape
    ) -> DrawingSheet {
        let sheet = DrawingSheet(
            name: name ?? "Sheet \(document.sheets.count + 1)",
            size: size,
            orientation: orientation
        )
        let added = document.addSheet(sheet)
        isDocumentModified = true
        return added
    }

    @discardableResult
    func removeSheet(id: UUID) -> Bool {
        let result = document.removeSheet(id: id)
        if result {
            isDocumentModified = true
        }
        return result
    }

    @discardableResult
    func updateSheet(_ sheet: DrawingSheet) -> Bool {
        let result = document.updateSheet(sheet)
        if result {
            isDocumentModified = true
        }
        return result
    }

    func setActiveSheetId(_ id: UUID?) {
        document.setActiveSheetId(id)
    }

    @discardableResult
    func duplicateSheet(id: UUID) -> DrawingSheet? {
        let duplicated = document.duplicateSheet(id: id)
        if duplicated != nil {
            isDocumentModified = true
        }
        return duplicated
    }

    func reorderSheets(_ newSheets: [DrawingSheet]) {
        document.reorderSheets(newSheets)
        isDocumentModified = true
    }

    @discardableResult
    func setSheetProperty(sheetId: UUID, key: String, value: String?) -> Bool {
        let result = document.setSheetProperty(sheetId: sheetId, key: key, value: value)
        if result {
            isDocumentModified = true
        }
        return result
    }

    // MARK: - Drawing View Workspace Actions (BL-DRW-03, #210)

    @discardableResult
    func addBaseView(
        standardView: HLRStandardView = .front,
        scale: DrawingViewScale? = nil,
        displayStyle: DrawingDisplayStyle = .visibleLinesOnly,
        positionMM: SIMD2<Double>? = nil
    ) -> DrawingView? {
        guard let sheet = document.activeSheet else { return nil }
        let centerPos = SIMD2<Double>(sheet.dimensionsMM.width * 0.5, sheet.dimensionsMM.height * 0.5)
        let pos = positionMM ?? centerPos
        let viewScale = scale ?? (DrawingViewScale.parse(sheet.scale) ?? .full)

        let hlr = HLREngine.computeHLR(
            objects: document.objects,
            direction: standardView.direction,
            options: displayStyle.hlrOptions
        )

        let view = DrawingView(
            name: "\(standardView.rawValue.capitalized) View",
            kind: .base,
            standardView: standardView,
            parentViewId: nil,
            projectionDirection: nil,
            positionMM: pos,
            scale: viewScale,
            displayStyle: displayStyle,
            projectionAngle: sheet.projectionAngle,
            cachedHLR: hlr
        )

        guard let added = document.addDrawingView(view, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    func addProjectedView(
        parentViewId: UUID,
        direction: ProjectionDirection,
        distanceMM: Double = 60.0
    ) -> DrawingView? {
        guard let sheet = document.activeSheet else { return nil }
        guard let parent = sheet.views.first(where: { $0.id == parentViewId }) else { return nil }

        let projAngle = sheet.projectionAngle
        let derivedStandardView = projAngle.projectedView(from: parent.standardView, direction: direction)

        let offset = direction.offset(distance: distanceMM)
        let newX = max(10.0, min(sheet.dimensionsMM.width - 10.0, parent.positionMM.x + offset.x))
        let newY = max(10.0, min(sheet.dimensionsMM.height - 10.0, parent.positionMM.y + offset.y))
        let newPos = SIMD2<Double>(newX, newY)

        let hlr = HLREngine.computeHLR(
            objects: document.objects,
            direction: derivedStandardView.direction,
            options: parent.displayStyle.hlrOptions
        )

        let projView = DrawingView(
            name: "\(derivedStandardView.rawValue.capitalized) View",
            kind: .projected,
            standardView: derivedStandardView,
            parentViewId: parent.id,
            projectionDirection: direction,
            positionMM: newPos,
            scale: parent.scale,
            displayStyle: parent.displayStyle,
            projectionAngle: projAngle,
            cachedHLR: hlr
        )

        guard let added = document.addDrawingView(projView, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    func addSectionView(
        parentViewId: UUID,
        startPointMM: SIMD2<Double> = SIMD2(-20, 0),
        endPointMM: SIMD2<Double> = SIMD2(20, 0),
        arrowDirection: SIMD2<Double> = SIMD2(0, 1),
        label: String = "A",
        hatchPattern: HatchPatternDefinition = .standard,
        distanceMM: Double = 60.0
    ) -> DrawingView? {
        guard let sheet = document.activeSheet else { return nil }
        guard let parent = sheet.views.first(where: { $0.id == parentViewId }) else { return nil }

        let newX = max(10.0, min(sheet.dimensionsMM.width - 10.0, parent.positionMM.x))
        let newY = max(10.0, min(sheet.dimensionsMM.height - 10.0, parent.positionMM.y + distanceMM))
        let newPos = SIMD2<Double>(newX, newY)

        let baseHLR = HLREngine.computeHLR(
            objects: document.objects,
            direction: parent.effectiveViewDirection,
            options: parent.displayStyle.hlrOptions
        )

        let hatchEdges: [HLREdge]
        if let bounds = baseHLR.bounds2D {
            hatchEdges = DrawingHatchGenerator.generateHatchLines(in: bounds, pattern: hatchPattern)
        } else {
            hatchEdges = []
        }
        let sectionHLR = HLRResult(edges: baseHLR.edges + hatchEdges, viewDirection: baseHLR.viewDirection)

        let sectionDef = SectionLineDefinition(
            label: label,
            startPointMM: startPointMM,
            endPointMM: endPointMM,
            arrowDirection: arrowDirection
        )

        let sectionView = DrawingView(
            name: "Section \(label)-\(label)",
            kind: .section,
            standardView: parent.standardView,
            parentViewId: parent.id,
            positionMM: newPos,
            scale: parent.scale,
            displayStyle: parent.displayStyle,
            projectionAngle: sheet.projectionAngle,
            cachedHLR: sectionHLR,
            sectionDefinition: sectionDef,
            hatchPattern: hatchPattern,
            customViewDirection: parent.customViewDirection
        )

        guard let added = document.addDrawingView(sectionView, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    func addDetailView(
        parentViewId: UUID,
        centerMM: SIMD2<Double> = .zero,
        radiusMM: Double = 15.0,
        scale: DrawingViewScale = .double,
        label: String = "B",
        distanceMM: Double = 60.0
    ) -> DrawingView? {
        guard let sheet = document.activeSheet else { return nil }
        guard let parent = sheet.views.first(where: { $0.id == parentViewId }) else { return nil }

        let newX = max(10.0, min(sheet.dimensionsMM.width - 10.0, parent.positionMM.x + distanceMM))
        let newY = max(10.0, min(sheet.dimensionsMM.height - 10.0, parent.positionMM.y))
        let newPos = SIMD2<Double>(newX, newY)

        let baseHLR = HLREngine.computeHLR(
            objects: document.objects,
            direction: parent.effectiveViewDirection,
            options: parent.displayStyle.hlrOptions
        )

        let clippedEdges = DrawingDetailProcessor.clipEdgesToCircle(
            edges: baseHLR.edges,
            centerMM: centerMM,
            radiusMM: radiusMM
        )
        let detailHLR = HLRResult(edges: clippedEdges, viewDirection: baseHLR.viewDirection)

        let detailDef = DetailCircleDefinition(
            label: label,
            centerMM: centerMM,
            radiusMM: radiusMM
        )

        let detailView = DrawingView(
            name: "Detail \(label)",
            kind: .detail,
            standardView: parent.standardView,
            parentViewId: parent.id,
            positionMM: newPos,
            scale: scale,
            displayStyle: parent.displayStyle,
            projectionAngle: sheet.projectionAngle,
            cachedHLR: detailHLR,
            detailDefinition: detailDef,
            customViewDirection: parent.customViewDirection
        )

        guard let added = document.addDrawingView(detailView, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    func addAuxiliaryView(
        parentViewId: UUID,
        angleDegrees: Double = 45.0,
        distanceMM: Double = 60.0,
        label: String = "C"
    ) -> DrawingView? {
        guard let sheet = document.activeSheet else { return nil }
        guard let parent = sheet.views.first(where: { $0.id == parentViewId }) else { return nil }

        let rad = angleDegrees * .pi / 180.0
        let newX = max(10.0, min(sheet.dimensionsMM.width - 10.0, parent.positionMM.x + cos(rad) * distanceMM))
        let newY = max(10.0, min(sheet.dimensionsMM.height - 10.0, parent.positionMM.y - sin(rad) * distanceMM))
        let newPos = SIMD2<Double>(newX, newY)

        let derivedDir = DrawingAuxiliaryDerivation.deriveDirection(
            from: parent.effectiveViewDirection,
            angleDegrees: angleDegrees
        )

        let hlr = HLREngine.computeHLR(
            objects: document.objects,
            direction: derivedDir,
            options: parent.displayStyle.hlrOptions
        )

        let auxDef = AuxiliaryViewDefinition(
            label: label,
            angleDegrees: angleDegrees,
            customDirection: derivedDir
        )

        let auxView = DrawingView(
            name: "Auxiliary View \(label)",
            kind: .auxiliary,
            standardView: parent.standardView,
            parentViewId: parent.id,
            positionMM: newPos,
            scale: parent.scale,
            displayStyle: parent.displayStyle,
            projectionAngle: sheet.projectionAngle,
            cachedHLR: hlr,
            auxiliaryDefinition: auxDef,
            customViewDirection: derivedDir
        )

        guard let added = document.addDrawingView(auxView, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    func addBrokenView(
        parentViewId: UUID,
        orientation: BreakOrientation = .horizontal,
        startMM: Double = -10.0,
        endMM: Double = 10.0,
        gapMM: Double = 5.0,
        style: BreakLineStyle = .zigzag,
        distanceMM: Double = 60.0
    ) -> DrawingView? {
        guard let sheet = document.activeSheet else { return nil }
        guard let parent = sheet.views.first(where: { $0.id == parentViewId }) else { return nil }

        let offset = orientation == .horizontal ? SIMD2<Double>(distanceMM, 0) : SIMD2<Double>(0, distanceMM)
        let newX = max(10.0, min(sheet.dimensionsMM.width - 10.0, parent.positionMM.x + offset.x))
        let newY = max(10.0, min(sheet.dimensionsMM.height - 10.0, parent.positionMM.y + offset.y))
        let newPos = SIMD2<Double>(newX, newY)

        let baseHLR = HLREngine.computeHLR(
            objects: document.objects,
            direction: parent.effectiveViewDirection,
            options: parent.displayStyle.hlrOptions
        )

        let breakDef = BreakViewDefinition(
            orientation: orientation,
            startMM: startMM,
            endMM: endMM,
            gapMM: gapMM,
            style: style
        )

        let brokenHLR = DrawingBreakProcessor.applyBreak(to: baseHLR, definition: breakDef)

        let brokenView = DrawingView(
            name: "Broken View",
            kind: .broken,
            standardView: parent.standardView,
            parentViewId: parent.id,
            positionMM: newPos,
            scale: parent.scale,
            displayStyle: parent.displayStyle,
            projectionAngle: sheet.projectionAngle,
            cachedHLR: brokenHLR,
            breakDefinition: breakDef,
            customViewDirection: parent.customViewDirection
        )

        guard let added = document.addDrawingView(brokenView, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    func removeDrawingView(id: UUID, preserveAnnotationsAsDangling: Bool = false) -> Bool {
        let result = document.removeDrawingView(id: id, preserveAnnotationsAsDangling: preserveAnnotationsAsDangling)
        if result {
            isDocumentModified = true
        }
        return result
    }

    @discardableResult
    func updateDrawingView(_ view: DrawingView) -> Bool {
        let result = document.updateDrawingView(view)
        if result {
            isDocumentModified = true
        }
        return result
    }

    @discardableResult
    func repositionDrawingView(id: UUID, positionMM: SIMD2<Double>) -> Bool {
        let result = document.repositionDrawingView(id: id, positionMM: positionMM)
        if result {
            isDocumentModified = true
        }
        return result
    }

    // MARK: - Drawing Annotation & Dimension Actions (BL-DRW-05)

    @discardableResult
    public func addLinearDimension(
        viewId: UUID? = nil,
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        offset: Double = 10.0,
        orientation: LinearDimensionOrientation = .aligned,
        prefix: String = "",
        suffix: String = "",
        sourceFeatureId: UUID? = nil,
        attachment: DrawingAnnotationAttachment? = nil
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .linear }).count + 1
        let data = LinearDimensionData(
            startPointMM: start,
            endPointMM: end,
            offsetMM: offset,
            orientation: orientation,
            prefix: prefix,
            suffix: suffix
        )
        let annotation = DrawingAnnotation(
            name: "Linear Dim \(count)",
            viewId: viewId,
            data: .linear(data),
            sourceFeatureId: sourceFeatureId,
            attachment: attachment
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addAngularDimension(
        viewId: UUID? = nil,
        vertex: SIMD2<Double>,
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        radius: Double = 15.0
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .angular }).count + 1
        let data = AngularDimensionData(
            vertexMM: vertex,
            startPointMM: start,
            endPointMM: end,
            arcRadiusMM: radius
        )
        let annotation = DrawingAnnotation(
            name: "Angular Dim \(count)",
            viewId: viewId,
            data: .angular(data)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addRadialDimension(
        viewId: UUID? = nil,
        center: SIMD2<Double>,
        arcPoint: SIMD2<Double>,
        isDiameter: Bool = false
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .radial }).count + 1
        let data = RadialDimensionData(
            centerMM: center,
            arcPointMM: arcPoint,
            isDiameter: isDiameter
        )
        let annotation = DrawingAnnotation(
            name: isDiameter ? "Diameter Dim \(count)" : "Radial Dim \(count)",
            viewId: viewId,
            data: .radial(data)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addOrdinateDimension(
        viewId: UUID? = nil,
        datum: SIMD2<Double>,
        location: SIMD2<Double>,
        axis: OrdinateDimensionAxis = .x
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .ordinate }).count + 1
        let data = OrdinateDimensionData(
            datumOriginMM: datum,
            locationMM: location,
            axis: axis
        )
        let annotation = DrawingAnnotation(
            name: "Ordinate Dim \(count)",
            viewId: viewId,
            data: .ordinate(data)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addBaselineDimension(
        viewId: UUID? = nil,
        basePoint: SIMD2<Double>,
        targets: [SIMD2<Double>],
        orientation: LinearDimensionOrientation = .horizontal
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .baseline }).count + 1
        let data = BaselineDimensionData(
            basePointMM: basePoint,
            targetPointsMM: targets,
            orientation: orientation
        )
        let annotation = DrawingAnnotation(
            name: "Baseline Dim \(count)",
            viewId: viewId,
            data: .baseline(data)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addNote(
        viewId: UUID? = nil,
        position: SIMD2<Double>,
        text: String = "NOTE"
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .note }).count + 1
        let data = NoteAnnotationData(
            positionMM: position,
            text: text
        )
        let annotation = DrawingAnnotation(
            name: "Note \(count)",
            viewId: viewId,
            data: .note(data)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addLeader(
        viewId: UUID? = nil,
        arrowPoint: SIMD2<Double>,
        elbowPoint: SIMD2<Double>,
        text: String = "NOTE"
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .leader }).count + 1
        let data = LeaderAnnotationData(
            arrowPointMM: arrowPoint,
            elbowPointMM: elbowPoint,
            text: text
        )
        let annotation = DrawingAnnotation(
            name: "Leader \(count)",
            viewId: viewId,
            data: .leader(data)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addCenterMark(
        viewId: UUID? = nil,
        center: SIMD2<Double>,
        size: Double = 5.0,
        extensionMM: Double = 3.0
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .centerMark }).count + 1
        let data = CenterMarkData(
            centerMM: center,
            markSizeMM: size,
            extensionMM: extensionMM
        )
        let annotation = DrawingAnnotation(
            name: "Center Mark \(count)",
            viewId: viewId,
            data: .centerMark(data)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addCenterline(
        viewId: UUID? = nil,
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        extensionMM: Double = 3.0
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .centerline }).count + 1
        let data = CenterlineData(
            startPointMM: start,
            endPointMM: end,
            extensionMM: extensionMM
        )
        let annotation = DrawingAnnotation(
            name: "Centerline \(count)",
            viewId: viewId,
            data: .centerline(data)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addHoleCallout(
        viewId: UUID? = nil,
        anchor: SIMD2<Double>,
        elbow: SIMD2<Double>,
        holeData: HoleCalloutAnnotationData,
        sourceFeatureId: UUID? = nil,
        attachment: DrawingAnnotationAttachment? = nil
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .holeCallout }).count + 1
        var configuredData = holeData
        configuredData.anchorPointMM = anchor
        configuredData.elbowPointMM = elbow
        let annotation = DrawingAnnotation(
            name: "Hole Callout \(count)",
            viewId: viewId,
            data: .holeCallout(configuredData),
            sourceFeatureId: sourceFeatureId,
            attachment: attachment
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func addHoleCalloutFromHoleWizard(
        viewId: UUID? = nil,
        anchor: SIMD2<Double>,
        elbow: SIMD2<Double>,
        holeParams: HoleParams,
        count: Int = 1,
        sourceFeatureId: UUID? = nil,
        attachment: DrawingAnnotationAttachment? = nil
    ) -> DrawingAnnotation? {
        let holeData = HoleCalloutAnnotationData(
            anchorPointMM: anchor,
            elbowPointMM: elbow,
            holeParams: holeParams,
            holeCount: count
        )
        return addHoleCallout(
            viewId: viewId,
            anchor: anchor,
            elbow: elbow,
            holeData: holeData,
            sourceFeatureId: sourceFeatureId,
            attachment: attachment
        )
    }

    @discardableResult
    public func addHoleCalloutFromFeature(
        featureId: UUID,
        viewId: UUID? = nil,
        anchor: SIMD2<Double>,
        elbow: SIMD2<Double>
    ) -> DrawingAnnotation? {
        guard let feature = document.features.first(where: { $0.id == featureId }) else {
            return nil
        }
        guard case .hole(let holeParams) = feature.operation else {
            return nil
        }
        let attachment = DrawingAnnotationAttachment(featureId: featureId)
        return addHoleCalloutFromHoleWizard(
            viewId: viewId,
            anchor: anchor,
            elbow: elbow,
            holeParams: holeParams,
            count: max(1, holeParams.points.count),
            sourceFeatureId: featureId,
            attachment: attachment
        )
    }

    @discardableResult
    public func updateDrawingAnnotation(_ annotation: DrawingAnnotation) -> Bool {
        let result = document.updateDrawingAnnotation(annotation)
        if result {
            isDocumentModified = true
        }
        return result
    }

    @discardableResult
    public func removeDrawingAnnotation(id: UUID) -> Bool {
        let result = document.removeDrawingAnnotation(id: id)
        if result {
            isDocumentModified = true
        }
        return result
    }

    @discardableResult
    public func addBOMTable(
        to sheetId: UUID? = nil,
        positionMM: SIMD2<Double> = SIMD2<Double>(20.0, 20.0),
        structure: BOMStructure = .flat
    ) -> DrawingBOMTable? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.bomTables.count + 1
        let table = DrawingBOMTable(
            name: "BOM Table \(count)",
            positionMM: positionMM,
            structure: structure
        )
        guard let added = document.addDrawingBOMTable(table, to: sheetId ?? sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func updateBOMTable(_ table: DrawingBOMTable) -> Bool {
        let result = document.updateDrawingBOMTable(table)
        if result {
            isDocumentModified = true
        }
        return result
    }

    @discardableResult
    public func removeBOMTable(id: UUID) -> Bool {
        let result = document.removeDrawingBOMTable(id: id)
        if result {
            isDocumentModified = true
        }
        return result
    }

    @discardableResult
    public func addBalloonAnnotation(
        viewId: UUID? = nil,
        anchorPoint: SIMD2<Double>,
        balloonCenter: SIMD2<Double>,
        shape: BalloonShape = .circular,
        itemNumber: String? = nil,
        quantity: Int? = nil,
        componentInstanceId: UUID? = nil
    ) -> DrawingAnnotation? {
        guard let sheet = document.activeSheet else { return nil }
        let count = sheet.annotations.filter({ $0.kind == .balloon }).count + 1

        var resolvedItemNumber = itemNumber
        var resolvedQuantity = quantity ?? 1
        var resolvedCompName: String? = nil

        // If componentInstanceId is provided, try to resolve from active document's BOM
        if let compId = componentInstanceId {
            let tableStructure = sheet.bomTables.first?.structure ?? .flat
            let bom = BillOfMaterials.generate(from: document, structure: tableStructure)
            if let comp = document.componentInstances.first(where: { $0.id == compId }) {
                resolvedCompName = comp.name
                let compPN = comp.partNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? comp.metadata.property(forKey: CustomPropertyKey.partNumber)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""
                if let matchingItem = bom.items.first(where: { item in
                    if !compPN.isEmpty && item.partNumber == compPN { return true }
                    return item.name == comp.name
                }) {
                    if resolvedItemNumber == nil {
                        resolvedItemNumber = matchingItem.itemNumber
                    }
                    if quantity == nil {
                        resolvedQuantity = matchingItem.quantity
                    }
                } else if resolvedItemNumber == nil {
                    if let idx = document.componentInstances.firstIndex(where: { $0.id == compId }) {
                        resolvedItemNumber = "\(idx + 1)"
                    }
                }
            }
        }

        let finalItemNumber = resolvedItemNumber ?? "\(count)"

        let balloonData = BalloonAnnotationData(
            anchorPointMM: anchorPoint,
            balloonCenterMM: balloonCenter,
            shape: shape,
            itemNumber: finalItemNumber,
            quantity: resolvedQuantity,
            componentInstanceId: componentInstanceId,
            componentName: resolvedCompName
        )
        let annotation = DrawingAnnotation(
            name: "Balloon \(count)",
            viewId: viewId,
            data: .balloon(balloonData)
        )
        guard let added = document.addDrawingAnnotation(annotation, to: sheet.id) else { return nil }
        isDocumentModified = true
        return added
    }

    @discardableResult
    public func autoBalloon(viewId: UUID) -> [DrawingAnnotation] {
        guard let sheet = document.activeSheet,
              let view = sheet.views.first(where: { $0.id == viewId }) else {
            return []
        }

        let tableStructure = sheet.bomTables.first?.structure ?? .flat
        let bom = BillOfMaterials.generate(from: document, structure: tableStructure)
        guard !bom.items.isEmpty else { return [] }

        var createdBalloons: [DrawingAnnotation] = []
        let totalCount = bom.items.count

        for (index, item) in bom.items.enumerated() {
            let comp = document.componentInstances.first(where: { c in
                let compPN = c.partNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? c.metadata.property(forKey: CustomPropertyKey.partNumber)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""
                if !compPN.isEmpty && item.partNumber == compPN { return true }
                return c.name == item.name
            })

            let anchorMM: SIMD2<Double>
            if let comp = comp {
                let compPos = SIMD3<Double>(Double(comp.transform.position.x), Double(comp.transform.position.y), Double(comp.transform.position.z))
                let proj = view.project(point3D: compPos)
                anchorMM = (abs(proj.x) < 1e-6 && abs(proj.y) < 1e-6)
                    ? SIMD2<Double>(Double(index - totalCount / 2) * 12.0, 0.0)
                    : proj
            } else {
                anchorMM = SIMD2<Double>(Double(index - totalCount / 2) * 12.0, 0.0)
            }

            let angle = (Double(index) / Double(max(1, totalCount))) * 2.0 * .pi - (.pi / 2.0)
            let radiusMM = 35.0
            let balloonCenterMM = anchorMM + SIMD2<Double>(cos(angle) * radiusMM, sin(angle) * radiusMM)

            if let balloon = addBalloonAnnotation(
                viewId: view.id,
                anchorPoint: anchorMM,
                balloonCenter: balloonCenterMM,
                shape: .circular,
                itemNumber: item.itemNumber,
                quantity: item.quantity,
                componentInstanceId: comp?.id
            ) {
                createdBalloons.append(balloon)
            }
        }

        return createdBalloons
    }

    func recomputeDrawingViewHLR(viewId: UUID) {
        document.updateDrawingAssociativity()
        isDocumentModified = true
    }

    @discardableResult
    func openDocument(at url: URL) -> Bool {
        do {
            let package = try MadePackage(directoryURL: url)
            cancelActiveCommand()
            autosaveTask?.cancel()
            autosaveTask = nil
            clearRecoverySnapshot()
            pendingRecoveryRecord = nil
            isShowingRecoveryAlert = false
            pendingSaveError = nil
            isShowingSaveErrorAlert = false
            pendingOpenError = nil
            isShowingOpenErrorAlert = false
            pendingExportError = nil
            isShowingExportErrorAlert = false
            pendingImportError = nil
            isShowingImportErrorAlert = false

            let docSettings = package.manifest.documentSettings
            let docMetadata = package.manifest.metadata
            let restoredSelection: Set<Reference>? = {
                if let sel = package.documentData.selection {
                    return Set(sel)
                } else if let selId = package.documentData.selectedId {
                    return [Reference.body(selId)]
                } else {
                    return nil
                }
            }()
            let docType = package.documentData.documentType ?? package.manifest.documentType
            let componentInstances = package.documentData.componentInstances ?? []
            let sheets = package.documentData.sheets ?? []
            let activeSheetId = package.documentData.activeSheetId
            if let features = package.documentData.features {
                document.reset(
                    with: features,
                    selection: restoredSelection,
                    selectedId: package.documentData.selectedId,
                    rollbackIndex: package.documentData.rollbackIndex,
                    settings: docSettings,
                    parameters: package.documentData.parameters ?? [],
                    documentType: docType,
                    componentInstances: componentInstances,
                    sheets: sheets,
                    activeSheetId: activeSheetId,
                    metadata: docMetadata
                )
            } else {
                document.reset(
                    with: package.documentData.objects,
                    selection: restoredSelection,
                    selectedId: package.documentData.selectedId,
                    rollbackIndex: package.documentData.rollbackIndex,
                    settings: docSettings,
                    parameters: package.documentData.parameters ?? [],
                    documentType: docType,
                    componentInstances: componentInstances,
                    sheets: sheets,
                    activeSheetId: activeSheetId,
                    metadata: docMetadata
                )
            }
            currentDocumentURL = url
            isDocumentModified = false
            syncWindowState()
            syncHiddenSolidIds()
            syncViewportSelection()
            log(.info, "Document", "Opened document from \(url.lastPathComponent)")

            for obj in document.objects {
                recomputeSolid(id: obj.id)
            }
            retessellateAll(tolerances: docSettings.tolerances)
            return true
        } catch {
            log(.error, "Document", "Failed to open document: \(error.localizedDescription)")
            pendingOpenError = OpenErrorInfo(documentURL: url, reason: error.localizedDescription)
            isShowingOpenErrorAlert = true
            return false
        }
    }

    func makePackage() throws -> MadePackage {
        let manifest = MadeManifest(
            schemaVersion: MadeManifest.currentSchemaVersion,
            appVersion: "0.1",
            documentSettings: document.settings,
            documentType: document.documentType,
            metadata: document.metadata
        )
        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            features: document.features,
            objects: document.objects,
            selectedId: selectedId,
            rollbackIndex: document.rollbackIndex,
            bodies: document.bodies,
            selection: Array(document.selection).sorted { $0.id.uuidString < $1.id.uuidString },
            parameters: document.parameters,
            documentType: document.documentType,
            componentInstances: document.componentInstances,
            assemblyConstraints: document.assemblyConstraints,
            componentPatterns: document.componentPatterns,
            componentMirrors: document.componentMirrors,
            explodedViews: document.explodedViews,
            activeExplodedViewId: document.activeExplodedViewId,
            sheets: document.sheets,
            activeSheetId: document.activeSheetId
        )

        var assets: [String: Data] = [:]
        func collectAsset(name: String, sourceURL: URL?, data: Data?) throws {
            let filename = (sourceURL?.lastPathComponent.isEmpty == false ? sourceURL?.lastPathComponent : nil)
                ?? (name.hasSuffix(".step") || name.hasSuffix(".stp") ? name : "\(name).step")
            if assets[filename] != nil {
                return
            }
            if let data {
                assets[filename] = data
            } else if let sourceURL {
                var resolvedURL = sourceURL.path.hasPrefix("/")
                    ? sourceURL
                    : (currentDocumentURL?.appendingPathComponent(sourceURL.path) ?? sourceURL)
                if sourceURL.path.hasPrefix("/"), !FileManager.default.fileExists(atPath: resolvedURL.path), let currentDoc = currentDocumentURL {
                    let insideAssets = currentDoc.appendingPathComponent("assets").appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: insideAssets.path) {
                        resolvedURL = insideAssets
                    }
                }
                do {
                    assets[filename] = try Data(contentsOf: resolvedURL)
                } catch {
                    throw MadeDocumentError.unreadableFile(filename)
                }
            } else {
                throw MadeDocumentError.unreadableFile(filename)
            }
        }

        for obj in document.objects {
            if document.componentInstances.contains(where: { $0.solidId == obj.id }) {
                continue
            }
            if case .imported(let name, let sourceURL, let data, let isLinked, _, _) = obj.def {
                if !isLinked {
                    try collectAsset(name: name, sourceURL: sourceURL, data: data)
                }
            }
        }

        for feature in document.features {
            if case .imported(let imp) = feature.operation {
                if !imp.isLinked {
                    try collectAsset(name: imp.name, sourceURL: imp.sourceURL, data: imp.data)
                }
            }
        }

        var parts: [String: Data] = [:]
        func collectPart(url: URL) throws {
            let filename = url.lastPathComponent
            guard !filename.isEmpty else { return }
            if parts[filename] != nil {
                return
            }
            var resolvedURL = url.path.hasPrefix("/")
                ? url
                : (currentDocumentURL?.appendingPathComponent(url.path) ?? url)
            if url.path.hasPrefix("/"), !FileManager.default.fileExists(atPath: resolvedURL.path), let currentDoc = currentDocumentURL {
                let insideParts = currentDoc.appendingPathComponent("parts").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: insideParts.path) {
                    resolvedURL = insideParts
                }
            }
            do {
                parts[filename] = try Data(contentsOf: resolvedURL)
            } catch {
                throw MadeDocumentError.unreadableFile(filename)
            }
        }

        for obj in document.objects {
            if case .part(let url, _) = obj.def {
                try collectPart(url: url)
            }
        }

        for feature in document.features {
            if case .part(let partData) = feature.operation {
                try collectPart(url: partData.url)
            }
        }

        return MadePackage(manifest: manifest, documentData: docData, assets: assets, parts: parts)
    }

    func rebaseDocumentPathsToPackage(_ packageURL: URL) {
        document.rebasePaths(to: packageURL)
    }

    @discardableResult
    func saveDocument(to targetURL: URL? = nil) -> Bool {
        guard let destinationURL = targetURL ?? currentDocumentURL else {
            promptSaveDocument()
            return false
        }

        autosaveTask?.cancel()
        autosaveTask = nil

        do {
            let package = try makePackage()
            try package.write(to: destinationURL)

            rebaseDocumentPathsToPackage(destinationURL)
            partReloadController?.syncWithDocument()

            currentDocumentURL = destinationURL
            isDocumentModified = false
            clearRecoverySnapshot()
            syncWindowState()
            pendingSaveError = nil
            isShowingSaveErrorAlert = false
            log(.info, "Document", "Saved document to \(destinationURL.lastPathComponent)")
            return true
        } catch {
            log(.error, "Document", "Failed to save document: \(error.localizedDescription)")
            pendingSaveError = SaveErrorInfo(destinationURL: destinationURL, reason: error.localizedDescription)
            isShowingSaveErrorAlert = true
            return false
        }
    }

    func dismissSaveErrorAlert() {
        pendingSaveError = nil
        isShowingSaveErrorAlert = false
    }

    func dismissOpenErrorAlert() {
        pendingOpenError = nil
        isShowingOpenErrorAlert = false
    }

    func dismissExportErrorAlert() {
        pendingExportError = nil
        isShowingExportErrorAlert = false
    }

    func dismissImportErrorAlert() {
        pendingImportError = nil
        isShowingImportErrorAlert = false
    }

    // MARK: - Crash Recovery Actions

    func saveRecoverySnapshot() {
        do {
            let package = try makePackage()
            let metadata = CrashRecoveryMetadata(
                version: CrashRecoveryMetadata.currentVersion,
                savedAt: Date(),
                originalDocumentURL: currentDocumentURL,
                documentTitle: documentTitle
            )
            try recoveryStore.saveSnapshot(package: package, metadata: metadata)
            log(.info, "Recovery", "Saved crash recovery snapshot for \(documentTitle)")
        } catch {
            log(.error, "Recovery", "Failed to save recovery snapshot: \(error.localizedDescription)")
        }
    }

    func clearRecoverySnapshot() {
        do {
            try recoveryStore.clearRecovery()
        } catch {
            log(.error, "Recovery", "Failed to clear recovery snapshot: \(error.localizedDescription)")
        }
    }

    func checkForPendingRecovery() {
        if let record = recoveryStore.loadPendingRecovery() {
            self.pendingRecoveryRecord = record
            self.isShowingRecoveryAlert = true
            log(.info, "Recovery", "Found pending crash recovery record for \"\(record.metadata.documentTitle)\"")
        }
    }

    func recoverDocument() {
        guard let record = pendingRecoveryRecord else { return }
        do {
            let package = try MadePackage(directoryURL: record.packageURL)
            cancelActiveCommand()
            autosaveTask?.cancel()
            autosaveTask = nil

            let docSettings = package.manifest.documentSettings
            let docMetadata = package.manifest.metadata
            let restoredSelection: Set<Reference>? = {
                if let sel = package.documentData.selection {
                    return Set(sel)
                } else if let selId = package.documentData.selectedId {
                    return [Reference.body(selId)]
                } else {
                    return nil
                }
            }()
            if let features = package.documentData.features {
                document.reset(
                    with: features,
                    selection: restoredSelection,
                    selectedId: package.documentData.selectedId,
                    rollbackIndex: package.documentData.rollbackIndex,
                    settings: docSettings,
                    metadata: docMetadata
                )
            } else {
                document.reset(
                    with: package.documentData.objects,
                    selection: restoredSelection,
                    selectedId: package.documentData.selectedId,
                    rollbackIndex: package.documentData.rollbackIndex,
                    settings: docSettings,
                    metadata: docMetadata
                )
            }
            currentDocumentURL = record.metadata.originalDocumentURL
            isDocumentModified = true
            syncWindowState()
            syncHiddenSolidIds()
            syncViewportSelection()
            log(.info, "Recovery", "Recovered document from snapshot: \(record.metadata.documentTitle)")

            for obj in document.objects {
                recomputeSolid(id: obj.id)
            }

            try recoveryStore.discardRecord(record)
            pendingRecoveryRecord = nil
            isShowingRecoveryAlert = false
        } catch {
            log(.error, "Recovery", "Failed to recover document: \(error.localizedDescription)")
            try? recoveryStore.discardRecord(record)
            pendingRecoveryRecord = nil
            isShowingRecoveryAlert = false
        }
    }

    func discardRecovery() {
        if let record = pendingRecoveryRecord {
            do {
                try recoveryStore.discardRecord(record)
                log(.info, "Recovery", "Discarded recovery record for \(record.metadata.documentTitle)")
            } catch {
                log(.error, "Recovery", "Failed to discard recovery record: \(error.localizedDescription)")
            }
        } else {
            clearRecoverySnapshot()
        }
        pendingRecoveryRecord = nil
        isShowingRecoveryAlert = false
    }

    func promptSaveDocument() {
        if let current = currentDocumentURL {
            _ = saveDocument(to: current)
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.title = "Save Document As"
        panel.allowedContentTypes = [.madeDocument]
        panel.canCreateDirectories = true
        let defaultName = currentDocumentURL?.lastPathComponent ?? "Untitled.made"
        panel.nameFieldStringValue = defaultName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = saveDocument(to: url)
    }

    func promptOpenDocument() {
        let panel = NSOpenPanel()
        panel.title = "Open Document"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.madeDocument]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(at: url)
    }

    static let defaultBoxParams = BoxParams(width: 30, depth: 30, height: 30)
    static let defaultCylinderParams = CylinderParams(radius: 12, height: 35)
    static let defaultSphereParams = SphereParams(radius: 15)
    static let defaultConeParams = ConeParams(bottomRadius: 15, topRadius: 0, height: 30)
    static let defaultTorusParams = TorusParams(majorRadius: 20, minorRadius: 5)
    static let defaultWedgeParams = WedgeParams(width: 30, depth: 30, height: 30, topWidth: 0)

    func addDefaultBox() {
        addObject(.box(Self.defaultBoxParams))
    }

    func addDefaultCylinder() {
        addObject(.cylinder(Self.defaultCylinderParams))
    }

    func addDefaultSphere() {
        addObject(.sphere(Self.defaultSphereParams))
    }

    func addDefaultCone() {
        addObject(.cone(Self.defaultConeParams))
    }

    func addDefaultTorus() {
        addObject(.torus(Self.defaultTorusParams))
    }

    func addDefaultWedge() {
        addObject(.wedge(Self.defaultWedgeParams))
    }

    func addObject(_ def: ObjectDef) {
        let id = document.addObject(def: def)
        selectedId = id
        markDocumentModified()
        log(.info, "Scene", "Added object \(id.rawValue)")
        recomputeSolid(id: id)
    }

    // MARK: - Rollback Timeline (BL-FND-05)

    var isRolledBack: Bool {
        document.isRolledBack
    }

    func rollBack(to index: Int) {
        setRollbackIndex(index)
    }

    func rollBack(to id: ObjectId) {
        guard let feat = document.feature(for: id) else { return }
        let oldObjects = document.objects
        let res = document.rollBack(to: feat.id)
        guard case .success = res else { return }
        markDocumentModified()
        syncMeshes(removedFrom: oldObjects, to: document.objects)
        log(.info, "Timeline", "Rolled back to \(id.rawValue)")
    }

    func rollBack(before id: ObjectId) {
        guard let feat = document.feature(for: id) else { return }
        let oldObjects = document.objects
        let res = document.rollBack(before: feat.id)
        guard case .success = res else { return }
        markDocumentModified()
        syncMeshes(removedFrom: oldObjects, to: document.objects)
        log(.info, "Timeline", "Rolled back before \(id.rawValue)")
    }

    func rollForwardToEnd() {
        let oldObjects = document.objects
        let res = document.rollForwardToEnd()
        guard case .success = res else { return }
        markDocumentModified()
        syncMeshes(removedFrom: oldObjects, to: document.objects)
        for obj in document.objects {
            recomputeSolid(id: obj.id)
        }
        log(.info, "Timeline", "Rolled forward to end")
    }

    func setRollbackIndex(_ index: Int?) {
        let oldObjects = document.objects
        let res = document.setRollbackIndex(index)
        guard case .success = res else { return }
        markDocumentModified()
        syncMeshes(removedFrom: oldObjects, to: document.objects)
        for obj in document.objects {
            recomputeSolid(id: obj.id)
        }
        log(.info, "Timeline", index != nil ? "Rollback marker set to \(index!)" : "Rolled forward to end")
    }

    /// Opens and watches a standalone `.part.ts` / `.part.js` file or all part files inside a `.made` directory package (#427).
    @discardableResult
    func openPartFile(at url: URL) -> ObjectId? {
        let canonical = url.standardizedFileURL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDir), isDir.boolValue {
            let partsDir = canonical.appendingPathComponent("parts", isDirectory: true)
            let scanDir = FileManager.default.fileExists(atPath: partsDir.path) ? partsDir : canonical
            let contents = (try? FileManager.default.contentsOfDirectory(at: scanDir, includingPropertiesForKeys: nil)) ?? []
            let partFiles = contents
                .filter {
                    let name = $0.lastPathComponent.lowercased()
                    return name.hasSuffix(".part.ts") || name.hasSuffix(".part.js")
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            var lastOpened: ObjectId? = nil
            for file in partFiles {
                lastOpened = openSinglePartFile(at: file)
            }
            return lastOpened
        }
        return openSinglePartFile(at: canonical)
    }

    private func openSinglePartFile(at url: URL) -> ObjectId {
        if let controller = partReloadController {
            let id = controller.openPartFile(at: url)
            selectedId = id
            markDocumentModified()
            log(.info, "Part", "Watching \(url.lastPathComponent) (\(id.rawValue))")
            return id
        } else {
            let id = document.addPart(url: url)
            selectedId = id
            markDocumentModified()
            log(.info, "Part", "Added part \(url.lastPathComponent) (\(id.rawValue))")
            return id
        }
    }

    var selectedPartId: ObjectId? {
        guard let obj = selectedObject, case .part = obj.def else { return nil }
        return obj.id
    }

    func reloadSelectedPart() {
        guard let id = selectedPartId else { return }
        reloadPart(id)
    }

    func reloadPart(_ id: ObjectId) {
        partReloadController?.reloadNow(id: id)
    }

    func reloadAllParts() {
        partReloadController?.reloadAll()
    }

    // MARK: - DSL Feature Import (BL-SCR-04 / #332)

    /// Evaluates a part script and imports the resulting geometry directly into the document feature list.
    @discardableResult
    func importPartScriptAsFeatures(at url: URL) async throws -> [Feature] {
        let runtime = partReloadController?.partRuntime ?? PartRuntime()
        let result = await runtime.evaluateScriptFile(at: url)
        switch result {
        case .success(_, let evaluation):
            let baseName = url.deletingPathExtension().lastPathComponent
            let features = try document.importFeatures(from: evaluation.shape, baseName: baseName)
            for feature in features {
                if let solidId = feature.outputSolidId {
                    recomputeSolid(id: solidId)
                }
            }
            markDocumentModified()
            return features
        case .failure(_, let error):
            throw error
        }
    }

    /// Converts an existing `.part` object into editable features in the document feature list.
    @discardableResult
    func convertPartToFeatures(id: ObjectId) async throws -> [Feature] {
        guard let obj = document.objects.first(where: { $0.id == id }) else {
            return []
        }
        guard case .part(let url, let cachedShape) = obj.def else {
            return []
        }

        let shapeToDecompose: ShapeNode
        if let cachedShape {
            shapeToDecompose = cachedShape
        } else if let settleResult = await partReloadController?.settle(for: id),
                  case .success(_, let output) = settleResult {
            shapeToDecompose = output.shape
        } else {
            let runtime = partReloadController?.partRuntime ?? PartRuntime()
            let result = await runtime.evaluateScriptFile(at: url)
            switch result {
            case .success(_, let evaluation):
                shapeToDecompose = evaluation.shape
            case .failure(_, let error):
                throw error
            }
        }

        partReloadController?.stopWatching(id: id)
        document.undoManager?.beginUndoGrouping()
        _ = document.removeObject(id: id)
        let baseName = obj.name.isEmpty ? url.deletingPathExtension().lastPathComponent : obj.name
        let features = try document.importFeatures(from: shapeToDecompose, baseName: baseName)
        document.undoManager?.setActionName("Convert to Features")
        document.undoManager?.endUndoGrouping()

        for feature in features {
            if let solidId = feature.outputSolidId {
                recomputeSolid(id: solidId)
            }
        }
        markDocumentModified()
        return features
    }


    func promptOpenPartFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Part Script"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.sourceCode, .javaScript, .data, .package, .folder]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            openPartFile(at: url)
        }
    }

    func promptImportStepFile() {
        let panel = NSOpenPanel()
        panel.title = "Import STEP Solid"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var contentTypes: [UTType] = []
        if let t1 = UTType(filenameExtension: "step") { contentTypes.append(t1) }
        if let t2 = UTType(filenameExtension: "stp") { contentTypes.append(t2) }
        panel.allowedContentTypes = contentTypes.isEmpty ? [.data] : contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await importStepFile(at: url)
        }
    }

    func promptLinkExternalFile() {
        let panel = NSOpenPanel()
        panel.title = "Link External File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        var contentTypes: [UTType] = [.madeDocument, .package, .folder, .data]
        if let t1 = UTType(filenameExtension: "step") { contentTypes.append(t1) }
        if let t2 = UTType(filenameExtension: "stp") { contentTypes.append(t2) }
        panel.allowedContentTypes = contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await linkExternalFile(at: url)
        }
    }

    func promptRelinkReference(_ id: ObjectId) {
        let panel = NSOpenPanel()
        panel.title = "Relink External Reference"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        var contentTypes: [UTType] = [.madeDocument, .package, .folder, .data]
        if let t1 = UTType(filenameExtension: "step") { contentTypes.append(t1) }
        if let t2 = UTType(filenameExtension: "stp") { contentTypes.append(t2) }
        panel.allowedContentTypes = contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await relinkReference(id, to: url)
        }
    }

    func promptExportStepFile(selectedOnly: Bool = false) {
        let panel = NSSavePanel()
        panel.title = selectedOnly ? "Export STEP Solid" : "Export STEP"
        panel.canCreateDirectories = true
        var contentTypes: [UTType] = []
        if let t1 = UTType(filenameExtension: "step") { contentTypes.append(t1) }
        if let t2 = UTType(filenameExtension: "stp") { contentTypes.append(t2) }
        panel.allowedContentTypes = contentTypes.isEmpty ? [.data] : contentTypes
        let defaultName = (selectedOnly ? selectedObject?.name : nil) ?? "scene"
        panel.nameFieldStringValue = defaultName.hasSuffix(".step") || defaultName.hasSuffix(".stp") ? defaultName : "\(defaultName).step"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await exportStepFile(to: url, selectedOnly: selectedOnly)
        }
    }

    @discardableResult
    func exportStepFile(to url: URL, selectedOnly: Bool = false) async -> Bool {
        let candidateObjects: [SceneObject]
        if selectedOnly {
            if let obj = selectedObject {
                candidateObjects = [obj]
            } else {
                candidateObjects = []
            }
        } else {
            candidateObjects = document.objects.filter { $0.isVisible }
        }
        guard !candidateObjects.isEmpty else {
            log(.error, "Kernel", "No objects to export")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: "No objects to export")
            isShowingExportErrorAlert = true
            return false
        }
        let result = await kernelClient.exportStep(objects: candidateObjects)
        switch result {
        case .success(_, let data):
            do {
                try data.write(to: url)
                pendingExportError = nil
                isShowingExportErrorAlert = false
                log(.info, "Kernel", "Exported STEP to \(url.lastPathComponent)")
                return true
            } catch {
                log(.error, "Kernel", "Failed to write STEP file: \(error.localizedDescription)")
                pendingExportError = ExportErrorInfo(destinationURL: url, reason: error.localizedDescription)
                isShowingExportErrorAlert = true
                return false
            }
        case .failure(_, let error):
            log(.error, "Kernel", "Failed to export STEP: \(error.message)")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: error.message)
            isShowingExportErrorAlert = true
            return false
        }
    }

    func promptExportSTLFile() {
        let panel = NSSavePanel()
        panel.title = "Export STL"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.stl]
        let defaultName = (document.objects.count == 1 ? document.objects.first?.name : selectedObject?.name) ?? "scene"
        panel.nameFieldStringValue = defaultName.hasSuffix(".stl") ? defaultName : "\(defaultName).stl"

        let initialTolerance = document.settings.tolerances.chordalTolerance
        let options = STLExportOptions(tolerance: initialTolerance, unit: .millimeters)
        panel.accessoryView = STLExportAccessoryHostingView(options: options)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await exportSTLFile(to: url, tolerance: options.tolerance, unit: options.unit)
        }
    }

    @discardableResult
    func exportSTLFile(to url: URL, tolerance: Double? = nil, unit: LengthUnit = .millimeters) async -> Bool {
        let candidateObjects = document.objects.filter { $0.isVisible }
        guard !candidateObjects.isEmpty else {
            log(.error, "Export", "No visible objects to export")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: "No visible objects to export")
            isShowingExportErrorAlert = true
            return false
        }
        let tol = tolerance ?? document.settings.tolerances.chordalTolerance
        guard STLExporter.validateTolerance(tol) else {
            let msg = "Invalid tessellation tolerance: \(tol). Tolerance must be positive."
            log(.error, "Export", msg)
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: msg)
            isShowingExportErrorAlert = true
            return false
        }
        let result = await kernelClient.exportSTL(objects: candidateObjects, tolerance: tol, unit: unit, to: url)
        switch result {
        case .success(_, let count):
            pendingExportError = nil
            isShowingExportErrorAlert = false
            log(.info, "Export", "Exported \(count) triangles to STL at \(url.lastPathComponent)")
            return true
        case .failure(_, let error):
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            log(.error, "Export", "Failed to export STL: \(error.message)")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: error.message)
            isShowingExportErrorAlert = true
            return false
        }
    }

    func promptExportThreeMFFile() {
        let panel = NSSavePanel()
        panel.title = "Export 3MF"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.threeMF]
        let defaultName = (document.objects.count == 1 ? document.objects.first?.name : selectedObject?.name) ?? "scene"
        panel.nameFieldStringValue = defaultName.hasSuffix(".3mf") ? defaultName : "\(defaultName).3mf"

        let initialTolerance = document.settings.tolerances.chordalTolerance
        let options = ThreeMFExportOptions(tolerance: initialTolerance, unit: .millimeters)
        panel.accessoryView = ThreeMFExportAccessoryHostingView(options: options)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await exportThreeMFFile(to: url, tolerance: options.tolerance, unit: options.unit)
        }
    }

    @discardableResult
    func exportThreeMFFile(to url: URL, tolerance: Double? = nil, unit: LengthUnit = .millimeters) async -> Bool {
        let candidateObjects = document.objects.filter { $0.isVisible }
        guard !candidateObjects.isEmpty else {
            log(.error, "Export", "No visible objects to export")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: "No visible objects to export")
            isShowingExportErrorAlert = true
            return false
        }
        let tol = tolerance ?? document.settings.tolerances.chordalTolerance
        guard ThreeMFExporter.validateTolerance(tol) else {
            let msg = "Invalid tessellation tolerance: \(tol). Tolerance must be positive."
            log(.error, "Export", msg)
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: msg)
            isShowingExportErrorAlert = true
            return false
        }
        let result = await kernelClient.exportThreeMF(objects: candidateObjects, tolerance: tol, unit: unit, to: url)
        switch result {
        case .success(_, let exportResult):
            pendingExportError = nil
            isShowingExportErrorAlert = false
            if !exportResult.warnings.isEmpty {
                for warning in exportResult.warnings {
                    log(.warning, "Export", warning)
                }
            }
            log(.info, "Export", "Exported \(exportResult.objectCount) objects (\(exportResult.triangleCount) triangles) to 3MF at \(url.lastPathComponent)")
            return true
        case .failure(_, let error):
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            log(.error, "Export", "Failed to export 3MF: \(error.message)")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: error.message)
            isShowingExportErrorAlert = true
            return false
        }
    }

    // MARK: - Bill of Materials Export (BL-ASM-10, #173)

    public var canExportBillOfMaterials: Bool {
        !document.componentInstances.isEmpty
    }

    public func promptExportBillOfMaterials(structure: BOMStructure = .flat) {
        guard canExportBillOfMaterials else { return }
        let panel = NSSavePanel()
        panel.title = "Export \(structure.displayName) Bill of Materials"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]
        let baseName = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "assembly"
        let suffix = structure == .flat ? "flat" : "hierarchical"
        panel.nameFieldStringValue = "\(baseName)-bom-\(suffix).csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await exportBillOfMaterials(to: url, structure: structure)
        }
    }

    @discardableResult
    public func exportBillOfMaterials(to url: URL, structure: BOMStructure = .flat) async -> Bool {
        guard canExportBillOfMaterials else {
            let msg = "No component instances to export in bill of materials"
            log(.error, "Export", msg)
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: msg)
            isShowingExportErrorAlert = true
            return false
        }
        do {
            let bom = BillOfMaterials.generate(from: document, structure: structure)
            try bom.exportCSV(to: url)
            pendingExportError = nil
            isShowingExportErrorAlert = false
            log(.info, "Export", "Exported \(structure.displayName) Bill of Materials (\(bom.items.count) items) to \(url.lastPathComponent)")
            return true
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            log(.error, "Export", "Failed to export Bill of Materials: \(error.localizedDescription)")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: error.localizedDescription)
            isShowingExportErrorAlert = true
            return false
        }
    }

    // MARK: - 2D Drawing Export (BL-DRW-09, #216)

    public var canExportDrawing: Bool {
        !document.sheets.isEmpty
    }

    public func promptExportDrawingPDF(sheetId: UUID? = nil) {
        guard canExportDrawing else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]
        let baseName = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "drawing"
        if let sheetId, let targetSheet = document.sheets.first(where: { $0.id == sheetId }) {
            panel.title = "Export Drawing Sheet as PDF"
            let sanitizedSheet = targetSheet.name.replacingOccurrences(of: " ", with: "-").lowercased()
            panel.nameFieldStringValue = "\(baseName)-\(sanitizedSheet).pdf"
        } else {
            panel.title = "Export Drawing PDF"
            panel.nameFieldStringValue = "\(baseName)-drawing.pdf"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await exportDrawingPDF(sheetId: sheetId, to: url)
        }
    }

    @discardableResult
    public func exportDrawingPDF(sheetId: UUID? = nil, to url: URL) async -> Bool {
        guard canExportDrawing else {
            let msg = "No drawing sheets to export as PDF"
            log(.error, "Export", msg)
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: msg)
            isShowingExportErrorAlert = true
            return false
        }
        let sheetsToExport: [DrawingSheet]
        if let sheetId {
            guard let targetSheet = document.sheets.first(where: { $0.id == sheetId }) else {
                let msg = "Sheet with ID \(sheetId) not found"
                log(.error, "Export", msg)
                pendingExportError = ExportErrorInfo(destinationURL: url, reason: msg)
                isShowingExportErrorAlert = true
                return false
            }
            sheetsToExport = [targetSheet]
        } else {
            sheetsToExport = document.sheets
        }

        do {
            try DrawingPDFExporter.exportPDF(sheets: sheetsToExport, document: document, to: url)
            pendingExportError = nil
            isShowingExportErrorAlert = false
            log(.info, "Export", "Exported drawing PDF (\(sheetsToExport.count) sheet(s)) to \(url.lastPathComponent)")
            return true
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            log(.error, "Export", "Failed to export drawing PDF: \(error.localizedDescription)")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: error.localizedDescription)
            isShowingExportErrorAlert = true
            return false
        }
    }

    public func promptExportDrawingDXF(sheetId: UUID? = nil) {
        guard canExportDrawing else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.dxf]
        panel.title = "Export Drawing Sheet as DXF"
        let baseName = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "drawing"
        let targetSheet = (sheetId != nil ? document.sheets.first(where: { $0.id == sheetId }) : (document.activeSheet ?? document.sheets.first))
        let sanitizedSheet = targetSheet?.name.replacingOccurrences(of: " ", with: "-").lowercased() ?? "sheet"
        panel.nameFieldStringValue = "\(baseName)-\(sanitizedSheet).dxf"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await exportDrawingDXF(sheetId: targetSheet?.id, to: url)
        }
    }

    @discardableResult
    public func exportDrawingDXF(sheetId: UUID? = nil, to url: URL) async -> Bool {
        guard canExportDrawing else {
            let msg = "No drawing sheets to export as DXF"
            log(.error, "Export", msg)
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: msg)
            isShowingExportErrorAlert = true
            return false
        }
        guard let targetSheet = (sheetId != nil ? document.sheets.first(where: { $0.id == sheetId }) : (document.activeSheet ?? document.sheets.first)) else {
            let msg = "Target drawing sheet not found for DXF export"
            log(.error, "Export", msg)
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: msg)
            isShowingExportErrorAlert = true
            return false
        }

        do {
            try DrawingDXFExporter.exportDXF(sheet: targetSheet, document: document, to: url)
            pendingExportError = nil
            isShowingExportErrorAlert = false
            log(.info, "Export", "Exported drawing sheet '\(targetSheet.name)' as DXF to \(url.lastPathComponent)")
            return true
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            log(.error, "Export", "Failed to export drawing DXF: \(error.localizedDescription)")
            pendingExportError = ExportErrorInfo(destinationURL: url, reason: error.localizedDescription)
            isShowingExportErrorAlert = true
            return false
        }
    }

    @discardableResult
    func importStepFile(at url: URL) async -> ObjectId? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log(.error, "Kernel", "Failed to import STEP file: \(error.localizedDescription)")
            pendingImportError = ImportErrorInfo(fileURL: url, errorCode: "read-failed", reason: error.localizedDescription)
            isShowingImportErrorAlert = true
            return nil
        }
        guard !data.isEmpty else {
            log(.error, "Kernel", "STEP file is empty")
            pendingImportError = ImportErrorInfo(fileURL: url, errorCode: "empty-file", reason: "STEP file is empty")
            isShowingImportErrorAlert = true
            return nil
        }
        let id = document.reserveId(for: .imported(name: url.lastPathComponent))
        let result = await kernelClient.request(.importStep(jobId: JobId("import-\(UUID().uuidString)"), solidId: id, data: data))
        switch result {
        case .failure(_, let error):
            log(.error, "Kernel", "Failed to import STEP: \(error.message)")
            pendingImportError = ImportErrorInfo(fileURL: url, errorCode: error.code.rawValue, reason: error.message)
            isShowingImportErrorAlert = true
            return nil
        case .success:
            pendingImportError = nil
            isShowingImportErrorAlert = false
            document.addObject(id, def: .imported(name: url.lastPathComponent, sourceURL: url, data: data))
            selectedId = id
            markDocumentModified()
            if let renderer = viewportManager.renderer,
               SolidMeshApplier.apply(result, to: id, document: document, sink: renderer) {
                invalidateViewport(.model)
            }
            log(.info, "Kernel", "Imported STEP file \(url.lastPathComponent) (\(id.rawValue))")
            return id
        }
    }

    @discardableResult
    func linkExternalFile(at url: URL) async -> ObjectId? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            log(.error, "Kernel", "External file not found: \(url.path)")
            pendingImportError = ImportErrorInfo(fileURL: url, errorCode: "not-found", reason: "File does not exist at path: \(url.path)")
            isShowingImportErrorAlert = true
            return nil
        }

        let isDirectoryPackage = url.pathExtension.lowercased() == "made" || (try? FileWrapper(url: url, options: []).isDirectory) == true
        let data: Data
        if isDirectoryPackage {
            do {
                let pkg = try MadePackage(directoryURL: url)
                let exportResult = await kernelClient.exportStep(objects: pkg.documentData.objects)
                switch exportResult {
                case .success(_, let stepData):
                    data = stepData
                case .failure(_, let error):
                    log(.error, "Kernel", "Failed to export compound STEP from .made package: \(error.message)")
                    pendingImportError = ImportErrorInfo(fileURL: url, errorCode: error.code.rawValue, reason: error.message)
                    isShowingImportErrorAlert = true
                    return nil
                }
            } catch {
                log(.error, "Kernel", "Failed to load .made package: \(error.localizedDescription)")
                pendingImportError = ImportErrorInfo(fileURL: url, errorCode: "package-read-failed", reason: error.localizedDescription)
                isShowingImportErrorAlert = true
                return nil
            }
        } else {
            do {
                data = try Data(contentsOf: url)
            } catch {
                log(.error, "Kernel", "Failed to read external file: \(error.localizedDescription)")
                pendingImportError = ImportErrorInfo(fileURL: url, errorCode: "read-failed", reason: error.localizedDescription)
                isShowingImportErrorAlert = true
                return nil
            }
        }

        guard !data.isEmpty else {
            log(.error, "Kernel", "External file is empty")
            pendingImportError = ImportErrorInfo(fileURL: url, errorCode: "empty-file", reason: "External file is empty")
            isShowingImportErrorAlert = true
            return nil
        }

        let modDate = ExternalReferenceDescriptor.modificationDate(of: url)
        let checksum = ExternalReferenceDescriptor.computeChecksum(of: url)
        let id = document.reserveId(for: .imported(name: url.lastPathComponent, sourceURL: url, data: nil, isLinked: true, lastModifiedDate: modDate, fileChecksum: checksum))

        let result = await kernelClient.request(.importStep(jobId: JobId("link-\(UUID().uuidString)"), solidId: id, data: data))
        switch result {
        case .failure(_, let error):
            log(.error, "Kernel", "Failed to link external file: \(error.message)")
            pendingImportError = ImportErrorInfo(fileURL: url, errorCode: error.code.rawValue, reason: error.message)
            isShowingImportErrorAlert = true
            return nil
        case .success:
            pendingImportError = nil
            isShowingImportErrorAlert = false
            document.addObject(id, def: .imported(
                name: url.lastPathComponent,
                sourceURL: url,
                data: nil,
                isLinked: true,
                lastModifiedDate: modDate,
                fileChecksum: checksum
            ))
            selectedId = id
            markDocumentModified()
            if let renderer = viewportManager.renderer,
               SolidMeshApplier.apply(result, to: id, document: document, sink: renderer) {
                invalidateViewport(.model)
            }
            refreshLinkedReferenceStatuses()
            log(.info, "Kernel", "Linked external file \(url.lastPathComponent) (\(id.rawValue))")
            return id
        }
    }

    @discardableResult
    func updateLinkedReference(_ id: ObjectId) async -> Bool {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return false }
        guard case .imported(let name, let sourceURL, _, let isLinked, _, _) = obj.def,
              isLinked, let sourceURL else {
            return false
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            log(.error, "Kernel", "Cannot update reference: external file not found at \(sourceURL.path)")
            refreshLinkedReferenceStatuses()
            return false
        }

        let isDirectoryPackage = sourceURL.pathExtension.lowercased() == "made" || (try? FileWrapper(url: sourceURL, options: []).isDirectory) == true
        let data: Data
        if isDirectoryPackage {
            do {
                let pkg = try MadePackage(directoryURL: sourceURL)
                let exportResult = await kernelClient.exportStep(objects: pkg.documentData.objects)
                switch exportResult {
                case .success(_, let stepData):
                    data = stepData
                case .failure(_, let error):
                    log(.error, "Kernel", "Failed to re-export compound STEP for update: \(error.message)")
                    return false
                }
            } catch {
                log(.error, "Kernel", "Failed to reload .made package for update: \(error.localizedDescription)")
                return false
            }
        } else {
            guard let fileData = try? Data(contentsOf: sourceURL), !fileData.isEmpty else {
                log(.error, "Kernel", "Failed to read external file for update: \(sourceURL.path)")
                return false
            }
            data = fileData
        }

        let result = await kernelClient.request(.importStep(jobId: JobId("update-\(UUID().uuidString)"), solidId: id, data: data))
        switch result {
        case .failure(_, let error):
            log(.error, "Kernel", "Failed to update linked reference: \(error.message)")
            return false
        case .success:
            let modDate = ExternalReferenceDescriptor.modificationDate(of: sourceURL)
            let checksum = ExternalReferenceDescriptor.computeChecksum(of: sourceURL)

            if var feat = document.feature(for: id) {
                feat.operation = .imported(ImportedFeatureData(
                    name: name,
                    sourceURL: sourceURL,
                    data: nil,
                    isLinked: true,
                    lastModifiedDate: modDate,
                    fileChecksum: checksum
                ))
                _ = document.updateFeature(feat)
            }

            markDocumentModified()
            if let renderer = viewportManager.renderer,
               SolidMeshApplier.apply(result, to: id, document: document, sink: renderer) {
                invalidateViewport(.model)
            }
            refreshLinkedReferenceStatuses()
            log(.info, "Kernel", "Updated linked reference \(sourceURL.lastPathComponent) (\(id.rawValue))")
            return true
        }
    }

    func embedLinkedReference(_ id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        guard case .imported(let name, let sourceURL, _, let isLinked, _, _) = obj.def,
              isLinked, let sourceURL else {
            return
        }

        let isDirectoryPackage = sourceURL.pathExtension.lowercased() == "made" || (try? FileWrapper(url: sourceURL, options: []).isDirectory) == true
        if isDirectoryPackage {
            Task {
                await embedLinkedReferenceAsync(id)
            }
            return
        }

        guard let embeddedData = try? Data(contentsOf: sourceURL), !embeddedData.isEmpty else {
            log(.error, "Kernel", "Cannot embed reference: failed to read source file at \(sourceURL.path)")
            return
        }

        let assetFilename = (sourceURL.lastPathComponent.isEmpty == false ? sourceURL.lastPathComponent : name)
        let assetNameWithExt = (assetFilename.hasSuffix(".step") || assetFilename.hasSuffix(".stp")) ? assetFilename : "\(assetFilename).step"
        let assetURL = URL(fileURLWithPath: "assets/\(assetNameWithExt)")

        if var feat = document.feature(for: id) {
            feat.operation = .imported(ImportedFeatureData(
                name: name,
                sourceURL: assetURL,
                data: embeddedData,
                isLinked: false,
                lastModifiedDate: nil,
                fileChecksum: nil
            ))
            _ = document.updateFeature(feat)
        }

        markDocumentModified()
        refreshLinkedReferenceStatuses()
        log(.info, "Kernel", "Converted linked reference to embedded asset (\(id.rawValue))")
    }

    @discardableResult
    func embedLinkedReferenceAsync(_ id: ObjectId) async -> Bool {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return false }
        guard case .imported(let name, let sourceURL, _, let isLinked, _, _) = obj.def,
              isLinked, let sourceURL else {
            return false
        }

        let isDirectoryPackage = sourceURL.pathExtension.lowercased() == "made" || (try? FileWrapper(url: sourceURL, options: []).isDirectory) == true
        let data: Data
        if isDirectoryPackage {
            guard let pkg = try? MadePackage(directoryURL: sourceURL) else {
                log(.error, "Kernel", "Failed to load .made package to embed: \(sourceURL.path)")
                return false
            }
            let res = await kernelClient.exportStep(objects: pkg.documentData.objects)
            guard case .success(_, let stepData) = res else {
                log(.error, "Kernel", "Failed to export compound STEP to embed: \(sourceURL.path)")
                return false
            }
            data = stepData
        } else {
            guard let fileData = try? Data(contentsOf: sourceURL), !fileData.isEmpty else {
                log(.error, "Kernel", "Failed to read external file to embed: \(sourceURL.path)")
                return false
            }
            data = fileData
        }

        let assetFilename = (sourceURL.lastPathComponent.isEmpty == false ? sourceURL.lastPathComponent : name)
        let assetNameWithExt = (assetFilename.hasSuffix(".step") || assetFilename.hasSuffix(".stp")) ? assetFilename : "\(assetFilename).step"
        let assetURL = URL(fileURLWithPath: "assets/\(assetNameWithExt)")

        if var feat = document.feature(for: id) {
            feat.operation = .imported(ImportedFeatureData(
                name: name,
                sourceURL: assetURL,
                data: data,
                isLinked: false,
                lastModifiedDate: nil,
                fileChecksum: nil
            ))
            _ = document.updateFeature(feat)
        }

        markDocumentModified()
        refreshLinkedReferenceStatuses()
        log(.info, "Kernel", "Converted linked reference to embedded asset (\(id.rawValue))")
        return true
    }

    @discardableResult
    func relinkReference(_ id: ObjectId, to newURL: URL) async -> Bool {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return false }
        guard case .imported = obj.def else { return false }
        guard FileManager.default.fileExists(atPath: newURL.path) else {
            log(.error, "Kernel", "Cannot relink: target file not found at \(newURL.path)")
            return false
        }

        let isDirectoryPackage = newURL.pathExtension.lowercased() == "made" || (try? FileWrapper(url: newURL, options: []).isDirectory) == true
        let data: Data
        if isDirectoryPackage {
            do {
                let pkg = try MadePackage(directoryURL: newURL)
                let exportResult = await kernelClient.exportStep(objects: pkg.documentData.objects)
                switch exportResult {
                case .success(_, let stepData):
                    data = stepData
                case .failure(_, let error):
                    log(.error, "Kernel", "Failed to export compound STEP from relinked .made package: \(error.message)")
                    return false
                }
            } catch {
                log(.error, "Kernel", "Failed to load relinked .made package: \(error.localizedDescription)")
                return false
            }
        } else {
            guard let fileData = try? Data(contentsOf: newURL), !fileData.isEmpty else {
                log(.error, "Kernel", "Failed to read relinked external file: \(newURL.path)")
                return false
            }
            data = fileData
        }

        let result = await kernelClient.request(.importStep(jobId: JobId("relink-\(UUID().uuidString)"), solidId: id, data: data))
        switch result {
        case .failure(_, let error):
            log(.error, "Kernel", "Failed to relink reference: \(error.message)")
            return false
        case .success:
            let modDate = ExternalReferenceDescriptor.modificationDate(of: newURL)
            let checksum = ExternalReferenceDescriptor.computeChecksum(of: newURL)
            let updatedName = newURL.lastPathComponent

            if var feat = document.feature(for: id) {
                feat.name = updatedName
                feat.operation = .imported(ImportedFeatureData(
                    name: updatedName,
                    sourceURL: newURL,
                    data: nil,
                    isLinked: true,
                    lastModifiedDate: modDate,
                    fileChecksum: checksum
                ))
                _ = document.updateFeature(feat)
            }

            markDocumentModified()
            if let renderer = viewportManager.renderer,
               SolidMeshApplier.apply(result, to: id, document: document, sink: renderer) {
                invalidateViewport(.model)
            }
            refreshLinkedReferenceStatuses()
            log(.info, "Kernel", "Relinked reference to \(newURL.lastPathComponent) (\(id.rawValue))")
            return true
        }
    }

    func linkStatus(for id: ObjectId) -> ExternalLinkStatus {
        _ = externalLinkCheckVersion
        guard let obj = document.objects.first(where: { $0.id == id }) else { return .upToDate }
        if case .imported(_, let sourceURL, _, let isLinked, let lastModifiedDate, let fileChecksum) = obj.def,
           isLinked, let sourceURL {
            let desc = ExternalReferenceDescriptor(
                sourceURL: sourceURL,
                isLinked: isLinked,
                lastModifiedDate: lastModifiedDate,
                fileChecksum: fileChecksum
            )
            return desc.checkStatus()
        }
        return .upToDate
    }

    func refreshLinkedReferenceStatuses() {
        externalLinkCheckVersion += 1
    }

    var canDeleteSelectedFeature: Bool {
        guard let feat = selectedFeature else { return false }
        return !feat.isLocked
    }

    var canDeleteSelectedObject: Bool {
        if let obj = selectedObject {
            return !obj.isLocked
        }
        if let feat = selectedFeature {
            return !feat.isLocked
        }
        return false
    }

    func deleteSelectedObject() {
        if let id = selectedId {
            requestDeleteObject(id)
        } else if let feat = selectedFeature {
            requestDeleteFeature(feat.id)
        }
    }

    func deleteSelectedFeature() {
        guard let feat = selectedFeature else { return }
        requestDeleteFeature(feat.id)
    }

    func requestDeleteObject(_ id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }), !obj.isLocked else { return }
        pendingDeleteId = id
    }

    func confirmDeleteObject() {
        guard let id = pendingDeleteId else { return }
        pendingDeleteId = nil
        removeObject(id)
    }

    func cancelDeleteObject() {
        pendingDeleteId = nil
    }

    func requestDeleteFeature(_ id: UUID) {
        guard let feat = document.feature(for: id), !feat.isLocked else { return }
        pendingDeleteFeatureId = id
    }

    func confirmDeleteFeature() {
        guard let id = pendingDeleteFeatureId else { return }
        pendingDeleteFeatureId = nil
        removeFeature(id)
    }

    func cancelDeleteFeature() {
        pendingDeleteFeatureId = nil
    }

    @discardableResult
    func removeFeature(_ id: UUID) -> Task<Void, Never> {
        guard let feature = document.feature(for: id), !feature.isLocked else {
            return Task {}
        }
        let dependents = document.dependentFeatures(referencing: id)
        let outputSolidId = feature.outputSolidId
        if let solidId = outputSolidId {
            partReloadController?.stopWatching(id: solidId)
        }
        let result = document.removeFeature(id: id)
        guard case .success = result else { return Task {} }

        syncViewportSelection()
        markDocumentModified()

        let task = Task {
            if let solidId = outputSolidId {
                await kernelClient.dispose(solidId: solidId)
            }
            await KernelRegeneration.regenerate(features: dependents, in: self.document, client: self.kernelClient)
            for dep in dependents {
                if let depSolidId = dep.outputSolidId {
                    self.recomputeSolid(id: depSolidId)
                }
            }
            self.invalidateViewport(.model)
        }
        if let solidId = outputSolidId {
            recomputeFailures.clear(solidId)
            if let renderer = viewportManager.renderer {
                _ = SolidMeshApplier.remove(id: solidId, from: renderer)
            }
        }
        log(.info, "Scene", "Removed feature \(feature.name) (\(id.uuidString))")
        invalidateViewport(.model)
        return task
    }

    @discardableResult
    func removeObject(_ id: ObjectId) -> Task<Void, Never> {
        guard let obj = document.objects.first(where: { $0.id == id }), !obj.isLocked else {
            return Task {}
        }
        let dependents = document.dependentObjects(of: id)
        partReloadController?.stopWatching(id: id)
        _ = document.removeObject(id: id)
        syncViewportSelection()
        markDocumentModified()
        let task = Task {
            await kernelClient.dispose(solidId: id)
            for depId in dependents {
                self.recomputeSolid(id: depId)
            }
        }
        recomputeFailures.clear(id)
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.remove(id: id, from: renderer)
        }
        log(.info, "Scene", "Removed object \(id.rawValue)")
        invalidateViewport(.model)
        return task
    }

    var hideToggleTitle: String {
        guard let obj = selectedObject else { return "Hide Solid" }
        return obj.isVisible ? "Hide Solid" : "Show Solid"
    }

    func toggleSelectedObjectVisibility() {
        guard let id = selectedId else { return }
        toggleVisibility(id)
    }

    func toggleVisibility(_ id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        let visible = !obj.isVisible
        setVisibility(id, isVisible: visible)
        log(.info, "Scene", "\(visible ? "Showed" : "Hid") object \(id.rawValue)")
    }

    func setVisibility(_ id: ObjectId, isVisible: Bool) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        guard obj.isVisible != isVisible else { return }
        document.setVisibility(id: id, isVisible: isVisible)
        markDocumentModified()
        if isVisible {
            viewportManager.renderer?.hiddenSolidIds.remove(id)
        } else {
            viewportManager.renderer?.hiddenSolidIds.insert(id)
        }
        invalidateViewport(.model)
    }

    var lockToggleTitle: String {
        guard let obj = selectedObject else { return "Lock Solid" }
        return obj.isLocked ? "Unlock Solid" : "Lock Solid"
    }

    func toggleSelectedObjectLock() {
        guard let id = selectedId else { return }
        toggleLock(id)
    }

    func toggleLock(_ id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        document.setLocked(id: id, isLocked: !obj.isLocked)
        if id == selectedId {
            syncViewportSelection()
        }
        markDocumentModified()
        log(.info, "Scene", "\(obj.isLocked ? "Unlocked" : "Locked") object \(id.rawValue)")
    }

    func setName(id: ObjectId, name: String) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, obj.name != trimmed, !obj.isLocked else { return }
        document.setName(id: id, name: trimmed)
        markDocumentModified()
    }

    // MARK: - Duplication & Radial Menu (INPUT-11, #42)

    @discardableResult
    public func duplicateObject(_ id: ObjectId) -> ObjectId? {
        let offsetTransform = Transform(position: SIMD3<Float>(10, 10, 0))
        do {
            let feature = try document.copyBody(sourceBodyId: id, transform: offsetTransform)
            guard let newId = feature.outputSolidId else { return nil }
            selectedId = newId
            markDocumentModified()
            log(.info, "Scene", "Duplicated body \(id.rawValue) to \(newId.rawValue)")
            recomputeSolid(id: newId)
            return newId
        } catch {
            guard let source = document.objects.first(where: { $0.id == id }) else { return nil }
            var newTransform = source.transform
            newTransform.position += SIMD3<Float>(10, 10, 0)
            let newId = document.addObject(def: source.def, transform: newTransform, material: source.material)
            document.setName(id: newId, name: "\(source.name) Copy")
            selectedId = newId
            markDocumentModified()
            undoManager?.setActionName("Duplicate Object")
            log(.info, "Scene", "Duplicated object \(id.rawValue) to \(newId.rawValue)")
            recomputeSolid(id: newId)
            return newId
        }
    }

    @discardableResult
    public func duplicateSelectedObject() -> ObjectId? {
        guard let id = selectedId else { return nil }
        return duplicateObject(id)
    }

    public func openRadialMenu(at point: CGPoint, targetSolidId: ObjectId?) {
        radialMenuState = RadialMenuState(position: point, targetSolidId: targetSolidId)
    }

    public func dismissRadialMenu() {
        radialMenuState = nil
    }

    public func openRadialMenuAtCenter() {
        let center: CGPoint
        if let size = coordinator?.mtkView?.bounds.size, size.width > 0, size.height > 0 {
            center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        } else {
            center = CGPoint(x: 400, y: 300)
        }
        openRadialMenu(at: center, targetSolidId: selectedId)
    }

    // MARK: - Feature Mutators (BL-FND-13)

    func setFeatureName(id: UUID, name: String) {
        let result = document.setFeatureName(id: id, name: name)
        guard case .success = result else { return }
        markDocumentModified()
    }

    func setFeatureVisibility(id: UUID, isVisible: Bool) {
        guard let feature = document.feature(for: id) else { return }
        guard feature.isVisible != isVisible else { return }
        let result = document.setFeatureVisibility(id: id, isVisible: isVisible)
        guard case .success = result else { return }
        if let solidId = feature.outputSolidId {
            if isVisible {
                viewportManager.renderer?.hiddenSolidIds.remove(solidId)
            } else {
                viewportManager.renderer?.hiddenSolidIds.insert(solidId)
            }
        }
        invalidateViewport(.model)
        markDocumentModified()
    }

    func toggleFeatureVisibility(_ id: UUID) {
        guard let feature = document.feature(for: id) else { return }
        setFeatureVisibility(id: id, isVisible: !feature.isVisible)
    }

    func setFeatureLocked(id: UUID, isLocked: Bool) {
        guard let feat = document.feature(for: id), feat.isLocked != isLocked else { return }
        let result = document.setFeatureLocked(id: id, isLocked: isLocked)
        guard case .success = result else { return }
        if isFeatureSelected(feat) {
            syncViewportSelection()
        }
        markDocumentModified()
        log(.info, "Scene", "\(isLocked ? "Locked" : "Unlocked") feature \(feat.name) (\(id.uuidString))")
    }

    func toggleFeatureLocked(_ id: UUID) {
        guard let feat = document.feature(for: id) else { return }
        setFeatureLocked(id: id, isLocked: !feat.isLocked)
    }

    // MARK: - Body Mutators (BL-FND-13)

    func setBodyName(id: BodyId, name: String) {
        guard let b = document.body(for: id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, b.name != trimmed, !b.isLocked else { return }
        document.setBodyName(id: id, name: trimmed)
        markDocumentModified()
    }

    func setBodyVisibility(id: BodyId, isVisible: Bool) {
        guard let b = document.body(for: id) else { return }
        guard b.isVisible != isVisible else { return }
        document.setBodyVisibility(id: id, isVisible: isVisible)
        markDocumentModified()
        if isVisible {
            viewportManager.renderer?.hiddenSolidIds.remove(id)
        } else {
            viewportManager.renderer?.hiddenSolidIds.insert(id)
        }
        invalidateViewport(.model)
    }

    func toggleBodyVisibility(_ id: BodyId) {
        guard let b = document.body(for: id) else { return }
        setBodyVisibility(id: id, isVisible: !b.isVisible)
    }

    func setBodyLocked(id: BodyId, isLocked: Bool) {
        guard let b = document.body(for: id) else { return }
        guard b.isLocked != isLocked else { return }
        document.setBodyLocked(id: id, isLocked: isLocked)
        if id == selectedId {
            syncViewportSelection()
        }
        markDocumentModified()
        log(.info, "Scene", "\(isLocked ? "Locked" : "Unlocked") body \(id.rawValue)")
    }

    func toggleBodyLocked(_ id: BodyId) {
        guard let b = document.body(for: id) else { return }
        setBodyLocked(id: id, isLocked: !b.isLocked)
    }

    func setBodyMaterial(id: BodyId, material: MaterialAttributes) {
        guard let b = document.body(for: id), !b.isLocked else { return }
        let result = document.setBodyMaterial(id: id, material: material)
        guard case .success = result else { return }
        markDocumentModified()
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.applyMaterial(to: id, document: document, sink: renderer)
        }
        log(.info, "Scene", "Updated material for body \(id.rawValue)")
        invalidateViewport(.model)
    }

    func setBodyColor(id: BodyId, color: SIMD4<Float>) {
        guard let b = document.body(for: id), !b.isLocked else { return }
        var mat = b.material
        mat.color = color
        setBodyMaterial(id: id, material: mat)
    }

    public func applyMaterialDefinition(_ material: MaterialDefinition, to bodyId: ObjectId) {
        let attributes = MaterialAttributes(
            color: material.color,
            materialDefinitionId: material.id,
            materialName: material.name
        )
        setBodyMaterial(id: bodyId, material: attributes)
    }

    // MARK: - Custom Materials Management (BL-MAT-03, #256)

    public func reloadUserMaterials() {
        userMaterials = userMaterialStore.loadMaterials()
    }

    public func addUserMaterial(_ material: MaterialDefinition) throws {
        try userMaterialStore.addMaterial(material)
        reloadUserMaterials()
    }

    public func updateUserMaterial(_ material: MaterialDefinition) throws {
        try userMaterialStore.updateMaterial(material)
        reloadUserMaterials()
    }

    public func removeUserMaterial(id: String) throws {
        try userMaterialStore.removeMaterial(id: id)
        reloadUserMaterials()
    }

    @discardableResult
    public func addDocumentCustomMaterial(_ material: MaterialDefinition) -> Result<Void, DocumentMutationError> {
        let result = document.addCustomMaterial(material)
        if case .success = result {
            markDocumentModified()
        }
        return result
    }

    @discardableResult
    public func updateDocumentCustomMaterial(_ material: MaterialDefinition) -> Result<Void, DocumentMutationError> {
        let result = document.updateCustomMaterial(material)
        if case .success = result {
            markDocumentModified()
        }
        return result
    }

    @discardableResult
    public func removeDocumentCustomMaterial(id: String) -> Result<Void, DocumentMutationError> {
        let result = document.removeCustomMaterial(id: id)
        if case .success = result {
            markDocumentModified()
        }
        return result
    }

    // MARK: - Custom Properties & Metadata (BL-FND-14, #172)

    public func setDocumentProperty(key: String, value: String?) {
        document.setDocumentProperty(key: key, value: value)
        markDocumentModified()
    }

    public func setBodyProperty(id: BodyId, key: String, value: String?) {
        document.setBodyProperty(id: id, key: key, value: value)
        markDocumentModified()
    }

    public func setComponentProperty(id: ComponentInstanceId, key: String, value: String?) {
        document.setComponentInstanceProperty(id: id, key: key, value: value)
        markDocumentModified()
    }

    // MARK: - Mass Overrides (BL-MAT-05, #258)

    public func setPurchasedOverride(id: SolidId, isPurchased: Bool) {
        setBodyProperty(id: id, key: CustomPropertyKey.isPurchased, value: isPurchased ? "true" : nil)
    }

    public func setOverrideMass(id: SolidId, massKg: Double?) {
        if let massKg, massKg > 0, massKg.isFinite {
            setBodyProperty(id: id, key: CustomPropertyKey.overrideMass, value: String(massKg))
        } else {
            setBodyProperty(id: id, key: CustomPropertyKey.overrideMass, value: nil)
        }
    }

    public func setOverrideCenterOfMass(id: SolidId, centerOfMassLocal: SIMD3<Double>?) {
        document.undoManager?.beginUndoGrouping()
        if let com = centerOfMassLocal, com.x.isFinite, com.y.isFinite, com.z.isFinite {
            setBodyProperty(id: id, key: CustomPropertyKey.overrideCenterOfMassX, value: String(com.x))
            setBodyProperty(id: id, key: CustomPropertyKey.overrideCenterOfMassY, value: String(com.y))
            setBodyProperty(id: id, key: CustomPropertyKey.overrideCenterOfMassZ, value: String(com.z))
        } else {
            setBodyProperty(id: id, key: CustomPropertyKey.overrideCenterOfMassX, value: nil)
            setBodyProperty(id: id, key: CustomPropertyKey.overrideCenterOfMassY, value: nil)
            setBodyProperty(id: id, key: CustomPropertyKey.overrideCenterOfMassZ, value: nil)
        }
        document.undoManager?.setActionName("Set Center of Mass Override")
        document.undoManager?.endUndoGrouping()
    }

    public func clearMassOverrides(id: SolidId) {
        document.undoManager?.beginUndoGrouping()
        for key in CustomPropertyKey.massOverrideKeys {
            setBodyProperty(id: id, key: key, value: nil)
        }
        document.undoManager?.setActionName("Clear Mass Overrides")
        document.undoManager?.endUndoGrouping()
    }

    // MARK: - Viewport Hidden State Synchronization (BL-FND-13)

    func syncHiddenSolidIds() {
        guard let renderer = viewportManager.renderer else { return }
        let expectedHidden = Set(document.objects.filter { !$0.isVisible }.map(\.id))
        if renderer.hiddenSolidIds != expectedHidden {
            renderer.hiddenSolidIds = expectedHidden
            invalidateViewport(.model)
        }
    }

    func syncMaterials() {
        guard let renderer = viewportManager.renderer else { return }
        var needsRedraw = false
        for body in document.bodies {
            if SolidMeshApplier.applyMaterial(to: body.id, document: document, sink: renderer) {
                needsRedraw = true
            }
        }
        if needsRedraw {
            invalidateViewport(.model)
        }
    }

    private func formatVec3(_ v: SIMD3<Float>) -> String {
        String(format: "(%.1f, %.1f, %.1f)", v.x, v.y, v.z)
    }

    func setTransform(_ id: ObjectId, _ transform: Transform) {
        guard let current = document.objects.first(where: { $0.id == id }),
              current.transform != transform else { return }
        let result = document.setTransform(id: id, transform: transform)
        guard case .success = result else { return }
        markDocumentModified()
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.applyTransform(to: id, document: document, sink: renderer)
        }
        log(.info, "Scene", "Updated \(id.rawValue) transform to position \(formatVec3(transform.position)) scale \(formatVec3(transform.scale))")
        invalidateViewport(.model)
    }

    func setMaterial(_ id: ObjectId, _ material: MaterialAttributes) {
        let result = document.setMaterial(id: id, material: material)
        guard case .success = result else { return }
        markDocumentModified()
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.applyMaterial(to: id, document: document, sink: renderer)
        }
        log(.info, "Scene", "Updated material for \(id.rawValue)")
        invalidateViewport(.model)
    }

    // MARK: - Assembly Component Management (BL-ASM-01)

    @discardableResult
    func addComponentInstance(
        name: String,
        reference: ComponentReference,
        transform: Transform = .identity,
        material: MaterialAttributes? = nil,
        isGrounded: Bool = false
    ) -> ComponentInstance {
        let instance = ComponentInstance(
            id: UUID(),
            name: name,
            reference: reference,
            transform: transform,
            isGrounded: isGrounded,
            material: material ?? document.settings.defaultMaterial
        )
        return addComponentInstance(instance)
    }

    @discardableResult
    func addComponentInstance(_ instance: ComponentInstance) -> ComponentInstance {
        _ = document.addComponentInstance(instance)
        selectedId = instance.solidId
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "Assembly", "Added component instance '\(instance.name)'")
        return instance
    }

    @discardableResult
    public func setComponentInstanceGrounded(id: UUID, isGrounded: Bool) -> Bool {
        let result = document.setComponentInstanceGrounded(id: id, isGrounded: isGrounded)
        guard case .success = result else { return false }
        clearAssemblySolverDiagnostics()
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "Assembly", "\(isGrounded ? "Grounded" : "Floated") component instance \(id)")
        return true
    }

    @discardableResult
    public func toggleComponentInstanceGrounded(id: UUID) -> Bool {
        guard let comp = document.componentInstances.first(where: { $0.id == id }) else { return false }
        return setComponentInstanceGrounded(id: id, isGrounded: !comp.isGrounded)
    }

    @discardableResult
    public func setComponentInstanceFixed(id: UUID, isFixed: Bool) -> Bool {
        setComponentInstanceGrounded(id: id, isGrounded: isFixed)
    }

    @discardableResult
    public func toggleComponentInstanceFixed(id: UUID) -> Bool {
        toggleComponentInstanceGrounded(id: id)
    }

    @discardableResult
    func removeComponentInstance(id: UUID) -> Bool {
        let solidId = SolidId("component-\(id.uuidString)")
        let result = document.removeComponentInstance(id: id)
        guard case .success = result else { return false }
        if selectedId == solidId {
            selectedId = nil
        }
        clearAssemblySolverDiagnostics()
        markDocumentModified()
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.remove(id: solidId, from: renderer)
        }
        invalidateViewport(.model)
        log(.info, "Assembly", "Removed component instance \(id)")
        return true
    }

    @discardableResult
    func updateComponentInstanceTransform(id: UUID, transform: Transform) -> Bool {
        let result = document.updateComponentInstanceTransform(id: id, transform: transform)
        guard case .success = result else { return false }
        let solidId = SolidId("component-\(id.uuidString)")
        markDocumentModified()
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.applyTransform(to: solidId, document: document, sink: renderer)
        }
        invalidateViewport(.model)
        log(.info, "Assembly", "Updated component instance \(id) transform")
        return true
    }

    func setComponentInstanceName(id: UUID, name: String) {
        guard let comp = document.findComponentInstance(id: id) else { return }
        var copy = comp
        copy.name = name
        _ = document.updateComponentInstance(copy)
        markDocumentModified()
    }

    // MARK: - Subassemblies (BL-ASM-07, #168)

    public var canGroupSelectedAsSubassembly: Bool {
        let selectedComps = selectedComponentInstanceIds
        return selectedComps.count >= 2 || (selectedComps.count == 1 && selectedComponentInstance?.isSubassembly == true)
    }

    public var selectedComponentInstanceIds: [UUID] {
        var ids: [UUID] = []
        for sel in selectedIds {
            if let comp = document.findComponentInstance(solidId: sel) {
                ids.append(comp.id)
            }
        }
        if ids.isEmpty, let selected = selectedComponentInstance {
            ids.append(selected.id)
        }
        return ids
    }

    @discardableResult
    public func groupAsSubassembly(instanceIds: [UUID], name: String? = nil) -> ComponentInstance? {
        let subName = name ?? "Subassembly \(document.componentInstances.filter { $0.isSubassembly }.count + 1)"
        let result = document.groupAsSubassembly(instanceIds: instanceIds, name: subName)
        switch result {
        case .success(let sub):
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Grouped \(instanceIds.count) components into subassembly '\(subName)'")
            return sub
        case .failure(let err):
            log(.warning, "Assembly", "Failed to group components into subassembly: \(err)")
            return nil
        }
    }

    @discardableResult
    public func groupSelectedAsSubassembly(name: String? = nil) -> ComponentInstance? {
        let ids = selectedComponentInstanceIds
        guard ids.count >= 2 else {
            log(.warning, "Assembly", "At least two components must be selected to group as a subassembly")
            return nil
        }
        return groupAsSubassembly(instanceIds: ids, name: name)
    }

    @discardableResult
    public func dissolveSubassembly(id: UUID) -> Bool {
        let result = document.dissolveSubassembly(id: id)
        switch result {
        case .success:
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Dissolved subassembly \(id)")
            return true
        case .failure(let err):
            log(.warning, "Assembly", "Failed to dissolve subassembly: \(err)")
            return false
        }
    }

    @discardableResult
    public func dissolveSelectedSubassembly() -> Bool {
        guard let selected = selectedComponentInstance, selected.isSubassembly else {
            return false
        }
        return dissolveSubassembly(id: selected.id)
    }

    @discardableResult
    public func setSubassemblyBehavior(id: UUID, behavior: SubassemblyBehavior) -> Bool {
        let result = document.setSubassemblyBehavior(id: id, behavior: behavior)
        switch result {
        case .success:
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Set subassembly \(id) behavior to \(behavior.rawValue)")
            return true
        case .failure(let err):
            log(.warning, "Assembly", "Failed to set subassembly behavior: \(err)")
            return false
        }
    }

    @discardableResult
    public func toggleSubassemblyBehavior(id: UUID) -> Bool {
        guard let sub = document.findComponentInstance(id: id), sub.isSubassembly else {
            return false
        }
        let nextBehavior: SubassemblyBehavior = sub.subassemblyBehavior == .rigid ? .flexible : .rigid
        return setSubassemblyBehavior(id: id, behavior: nextBehavior)
    }

    // MARK: - Component Patterns & Mirrors (BL-ASM-08, #169)

    @discardableResult
    public func patternComponentLinear(
        id: UUID,
        count: Int = 3,
        spacing: Float = 20.0,
        direction: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
        isSymmetric: Bool = false,
        skippedIndices: Set<Int> = []
    ) -> ComponentPattern? {
        let params = AssemblyPatternParams(
            sourceInstanceId: id,
            patternType: .linear,
            count: count,
            linearSpacing: spacing,
            linearDirection: direction,
            isSymmetric: isSymmetric,
            skippedIndices: skippedIndices
        )
        let result = document.patternComponentInstance(params: params)
        switch result {
        case .success(let pattern):
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Created linear pattern '\(pattern.name)' with \(pattern.replicaInstanceIds.count) replicas")
            return pattern
        case .failure(let err):
            log(.warning, "Assembly", "Failed to create linear pattern: \(err)")
            return nil
        }
    }

    @discardableResult
    public func patternSelectedComponentLinear(
        count: Int = 3,
        spacing: Float = 20.0,
        direction: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
        isSymmetric: Bool = false,
        skippedIndices: Set<Int> = []
    ) -> ComponentPattern? {
        guard let selected = selectedComponentInstance else {
            log(.warning, "Assembly", "No component selected for linear pattern")
            return nil
        }
        return patternComponentLinear(
            id: selected.id,
            count: count,
            spacing: spacing,
            direction: direction,
            isSymmetric: isSymmetric,
            skippedIndices: skippedIndices
        )
    }

    @discardableResult
    public func patternComponentCircular(
        id: UUID,
        count: Int = 4,
        totalAngle: Float = 360.0,
        isFullCircle: Bool = true,
        axisOrigin: SIMD3<Float> = .zero,
        axisDirection: SIMD3<Float> = SIMD3<Float>(0, 0, 1),
        skippedIndices: Set<Int> = []
    ) -> ComponentPattern? {
        let params = AssemblyPatternParams(
            sourceInstanceId: id,
            patternType: .circular,
            count: count,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection,
            totalAngle: totalAngle,
            isFullCircle: isFullCircle,
            skippedIndices: skippedIndices
        )
        let result = document.patternComponentInstance(params: params)
        switch result {
        case .success(let pattern):
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Created circular pattern '\(pattern.name)' with \(pattern.replicaInstanceIds.count) replicas")
            return pattern
        case .failure(let err):
            log(.warning, "Assembly", "Failed to create circular pattern: \(err)")
            return nil
        }
    }

    @discardableResult
    public func patternSelectedComponentCircular(
        count: Int = 4,
        totalAngle: Float = 360.0,
        isFullCircle: Bool = true,
        axisOrigin: SIMD3<Float> = .zero,
        axisDirection: SIMD3<Float> = SIMD3<Float>(0, 0, 1),
        skippedIndices: Set<Int> = []
    ) -> ComponentPattern? {
        guard let selected = selectedComponentInstance else {
            log(.warning, "Assembly", "No component selected for circular pattern")
            return nil
        }
        return patternComponentCircular(
            id: selected.id,
            count: count,
            totalAngle: totalAngle,
            isFullCircle: isFullCircle,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection,
            skippedIndices: skippedIndices
        )
    }

    @discardableResult
    public func patternComponentByFeaturePattern(
        id: UUID,
        featurePatternId: UUID? = nil
    ) -> ComponentPattern? {
        let driverId: UUID
        if let featurePatternId {
            driverId = featurePatternId
        } else if let firstPatternFeat = document.features.first(where: {
            if case .pattern = $0.operation { return true }
            return false
        }) {
            driverId = firstPatternFeat.id
        } else {
            log(.warning, "Assembly", "No driver pattern feature found in document")
            return nil
        }

        let result = document.patternComponentInstanceByFeaturePattern(
            instanceId: id,
            featurePatternId: driverId
        )
        switch result {
        case .success(let pattern):
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Created feature-driven pattern '\(pattern.name)' with \(pattern.replicaInstanceIds.count) replicas")
            return pattern
        case .failure(let err):
            log(.warning, "Assembly", "Failed to create feature-driven pattern: \(err)")
            return nil
        }
    }

    @discardableResult
    public func patternSelectedComponentByFeaturePattern(
        featurePatternId: UUID? = nil
    ) -> ComponentPattern? {
        guard let selected = selectedComponentInstance else {
            log(.warning, "Assembly", "No component selected for feature-driven pattern")
            return nil
        }
        let driverId: UUID
        if let featurePatternId {
            driverId = featurePatternId
        } else if let firstPatternFeat = document.features.first(where: {
            if case .pattern = $0.operation { return true }
            return false
        }) {
            driverId = firstPatternFeat.id
        } else {
            log(.warning, "Assembly", "No driver pattern feature found in document")
            return nil
        }
        return patternComponentByFeaturePattern(id: selected.id, featurePatternId: driverId)
    }

    @discardableResult
    public func mirrorComponent(
        id: UUID,
        planeNormal: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
        planeOrigin: SIMD3<Float> = .zero,
        keepOriginal: Bool = true,
        mode: ComponentMirrorMode = .symmetricReorient
    ) -> ComponentMirror? {
        let params = AssemblyMirrorParams(
            sourceInstanceId: id,
            planeNormal: planeNormal,
            planeOrigin: planeOrigin,
            keepOriginal: keepOriginal,
            mirrorMode: mode
        )
        let result = document.mirrorComponentInstance(params: params)
        switch result {
        case .success(let mirror):
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Mirrored component '\(id)' -> '\(mirror.name)'")
            return mirror
        case .failure(let err):
            log(.warning, "Assembly", "Failed to mirror component: \(err)")
            return nil
        }
    }

    @discardableResult
    public func mirrorSelectedComponent(
        planeNormal: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
        planeOrigin: SIMD3<Float> = .zero,
        keepOriginal: Bool = true,
        mode: ComponentMirrorMode = .symmetricReorient
    ) -> ComponentMirror? {
        guard let selected = selectedComponentInstance else {
            log(.warning, "Assembly", "No component selected to mirror")
            return nil
        }
        return mirrorComponent(
            id: selected.id,
            planeNormal: planeNormal,
            planeOrigin: planeOrigin,
            keepOriginal: keepOriginal,
            mode: mode
        )
    }

    @discardableResult
    public func removeComponentPattern(id: UUID) -> Bool {
        let result = document.removeComponentPattern(id: id)
        switch result {
        case .success:
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Removed component pattern \(id)")
            return true
        case .failure(let err):
            log(.warning, "Assembly", "Failed to remove component pattern: \(err)")
            return false
        }
    }

    @discardableResult
    public func removeComponentMirror(id: UUID) -> Bool {
        let result = document.removeComponentMirror(id: id)
        switch result {
        case .success:
            clearAssemblySolverDiagnostics()
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Removed component mirror \(id)")
            return true
        case .failure(let err):
            log(.warning, "Assembly", "Failed to remove component mirror: \(err)")
            return false
        }
    }

    // MARK: - Component Insertion (BL-ASM-02)

    public func beginInsertComponent(name: String, reference: ComponentReference, material: MaterialAttributes? = nil) {
        pendingComponentPlacement = PendingComponentPlacement(name: name, reference: reference, material: material)
        log(.info, "Assembly", "Began pending placement for '\(name)'")
    }

    @discardableResult
    public func placePendingComponent(at position: SIMD3<Float>) -> ComponentInstance? {
        guard let pending = pendingComponentPlacement else { return nil }
        let shouldGround = document.componentInstances.isEmpty
        let instance = ComponentInstance(
            name: pending.name,
            reference: pending.reference,
            transform: Transform(position: position),
            isGrounded: shouldGround,
            material: pending.material ?? document.settings.defaultMaterial
        )
        addComponentInstance(instance)
        pendingComponentPlacement = nil
        return instance
    }

    public func cancelPendingPlacement() {
        if let pending = pendingComponentPlacement {
            log(.info, "Assembly", "Cancelled pending placement for '\(pending.name)'")
            pendingComponentPlacement = nil
        }
    }

    public func promptInsertComponentFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Insert Component from File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        var contentTypes: [UTType] = [.madeDocument, .package, .folder, .data]
        if let t1 = UTType(filenameExtension: "step") { contentTypes.append(t1) }
        if let t2 = UTType(filenameExtension: "stp") { contentTypes.append(t2) }
        panel.allowedContentTypes = contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.deletingPathExtension().lastPathComponent
        beginInsertComponent(name: name, reference: .externalDocument(url: url))
    }

    public func promptInsertComponentFromDocument() {
        if document.bodies.isEmpty {
            log(.warning, "Assembly", "Cannot insert component from document: no bodies available")
            return
        }
        if document.bodies.count == 1 {
            let body = document.bodies[0]
            beginInsertComponent(name: body.name, reference: .internalPart(name: body.name, bodyId: body.id))
        } else {
            isShowingBodyPickerForInsertion = true
        }
    }

    public func insertComponentFromInternalBody(_ body: Body) {
        beginInsertComponent(name: body.name, reference: .internalPart(name: body.name, bodyId: body.id))
        isShowingBodyPickerForInsertion = false
    }

    // MARK: - Assembly Constraints & Joints (BL-ASM-04, #165)

    @discardableResult
    public func addAssemblyConstraint(_ constraint: AssemblyConstraint) -> Bool {
        let result = document.addAssemblyConstraint(constraint)
        guard case .success = result else { return false }
        selectedAssemblyConstraintId = constraint.id
        clearAssemblySolverDiagnostics()
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "Assembly", "Added assembly constraint '\(constraint.name)' (\(constraint.kind.displayName))")
        return true
    }

    @discardableResult
    public func removeAssemblyConstraint(id: UUID) -> Bool {
        let result = document.removeAssemblyConstraint(id: id)
        guard case .success = result else { return false }
        if selectedAssemblyConstraintId == id {
            selectedAssemblyConstraintId = nil
        }
        clearAssemblySolverDiagnostics()
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "Assembly", "Removed assembly constraint \(id)")
        return true
    }

    @discardableResult
    public func updateAssemblyConstraint(_ constraint: AssemblyConstraint) -> Bool {
        let result = document.updateAssemblyConstraint(constraint)
        guard case .success = result else { return false }
        clearAssemblySolverDiagnostics()
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "Assembly", "Updated assembly constraint '\(constraint.name)'")
        return true
    }

    @discardableResult
    public func toggleAssemblyConstraintSuppressed(id: UUID) -> Bool {
        guard let constraint = document.assemblyConstraints.first(where: { $0.id == id }) else { return false }
        var updated = constraint
        updated.isSuppressed.toggle()
        return updateAssemblyConstraint(updated)
    }

    @discardableResult
    public func solveAssemblyConstraints(dragTarget: AssemblyDragTarget? = nil) -> AssemblySolverResult {
        let result = document.solveAssemblyConstraints(dragTarget: dragTarget)
        lastAssemblySolverResult = result
        if result.status.isConverged {
            markDocumentModified()
            if let renderer = viewportManager.renderer {
                for (id, _) in result.solvedTransforms {
                    let solidId = SolidId("component-\(id.uuidString)")
                    _ = SolidMeshApplier.applyTransform(to: solidId, document: document, sink: renderer)
                }
            }
            invalidateViewport(.model)
            log(.info, "Assembly", "Solved assembly constraints successfully (total DOF: \(result.totalDOF))")
        } else {
            log(.warning, "Assembly", "Assembly solve status: \(result.status)")
        }
        return result
    }

    public func beginInteractiveAssemblyDrag(instanceId: UUID) {
        document.beginInteractiveAssemblyDrag(instanceId: instanceId)
    }

    @discardableResult
    public func solveAssemblyDrag(dragTarget: AssemblyDragTarget) -> AssemblySolverResult {
        let result = document.solveAssemblyConstraints(dragTarget: dragTarget, registerUndo: false)
        lastAssemblySolverResult = result
        if result.status.isConverged {
            if let renderer = viewportManager.renderer {
                for (id, _) in result.solvedTransforms {
                    let solidId = SolidId("component-\(id.uuidString)")
                    _ = SolidMeshApplier.applyTransform(to: solidId, document: document, sink: renderer)
                }
            }
            invalidateViewport(.model)
        }
        return result
    }

    public func endInteractiveAssemblyDrag(instanceId: UUID) {
        document.endInteractiveAssemblyDrag(instanceId: instanceId)
        markDocumentModified()
        if let renderer = viewportManager.renderer {
            for comp in document.componentInstances {
                let solidId = SolidId("component-\(comp.id.uuidString)")
                _ = SolidMeshApplier.applyTransform(to: solidId, document: document, sink: renderer)
            }
        }
        invalidateViewport(.model)
    }

    public func cancelInteractiveAssemblyDrag() {
        document.cancelInteractiveAssemblyDrag()
        if let renderer = viewportManager.renderer {
            for comp in document.componentInstances {
                let solidId = SolidId("component-\(comp.id.uuidString)")
                _ = SolidMeshApplier.applyTransform(to: solidId, document: document, sink: renderer)
            }
        }
        invalidateViewport(.model)
    }

    @discardableResult
    public func addDefaultAssemblyConstraint(kind: AssemblyConstraintKind) -> AssemblyConstraint? {
        guard !document.componentInstances.isEmpty else { return nil }
        let firstComp = selectedComponentInstance ?? document.componentInstances[0]
        let secondComp = document.componentInstances.first(where: { $0.id != firstComp.id })

        let f1 = AssemblyFeature(
            componentInstanceId: firstComp.id,
            origin: .zero,
            axis: SIMD3<Float>(0, 0, 1)
        )
        let f2 = AssemblyFeature(
            componentInstanceId: secondComp?.id,
            origin: .zero,
            axis: SIMD3<Float>(0, 0, 1)
        )
        let constraint = AssemblyConstraint(
            kind: kind,
            firstFeature: f1,
            secondFeature: f2
        )
        if addAssemblyConstraint(constraint) {
            return constraint
        }
        return nil
    }

    // MARK: - Exploded Views (BL-ASM-12)

    @discardableResult
    public func createExplodedView(name: String = "Exploded View") -> ExplodedView? {
        let result = document.addExplodedView(name: name)
        guard case .success(let view) = result else { return nil }
        selectExplodedView(view.id)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "Assembly", "Created exploded view '\(view.name)'")
        return view
    }

    public func removeExplodedView(id: UUID) {
        if selectedExplodedViewId == id {
            selectedExplodedViewId = nil
            selectedExplodeStepId = nil
        }
        let result = document.removeExplodedView(id: id)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Removed exploded view \(id)")
        }
    }

    public func renameExplodedView(id: UUID, name: String) {
        let result = document.renameExplodedView(id: id, name: name)
        if case .success = result {
            markDocumentModified()
            log(.info, "Assembly", "Renamed exploded view \(id) to '\(name)'")
        }
    }

    public func toggleExplodedView(id: UUID) {
        if document.activeExplodedViewId == id {
            _ = document.setActiveExplodedView(id: nil)
            if let view = document.explodedView(id: id), !view.isCollapsed {
                _ = document.toggleExplodedViewCollapsed(id: id)
            }
        } else {
            _ = document.setActiveExplodedView(id: id)
            if let view = document.explodedView(id: id), view.isCollapsed {
                _ = document.toggleExplodedViewCollapsed(id: id)
            }
        }
        markDocumentModified()
        invalidateViewport(.model)
    }

    public func toggleExplodedViewCollapsed(id: UUID) {
        let result = document.toggleExplodedViewCollapsed(id: id)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
        }
    }

    @discardableResult
    public func addExplodeStep(viewId: UUID, step: ExplodeStep = ExplodeStep()) -> ExplodeStep? {
        let result = document.addExplodeStep(viewId: viewId, step: step)
        guard case .success(let newStep) = result else { return nil }
        selectExplodeStep(viewId: viewId, stepId: newStep.id)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "Assembly", "Added explode step '\(newStep.name)' to view \(viewId)")
        return newStep
    }

    public func removeExplodeStep(viewId: UUID, stepId: UUID) {
        if selectedExplodeStepId == stepId {
            selectedExplodeStepId = nil
        }
        let result = document.removeExplodeStep(viewId: viewId, stepId: stepId)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Removed explode step \(stepId) from view \(viewId)")
        }
    }

    public func updateExplodeStep(viewId: UUID, step: ExplodeStep) {
        let result = document.updateExplodeStep(viewId: viewId, step: step)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Updated explode step '\(step.name)'")
        }
    }

    public func reorderExplodeSteps(viewId: UUID, stepIds: [UUID]) {
        let result = document.reorderExplodeSteps(viewId: viewId, stepIds: stepIds)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "Assembly", "Reordered explode steps in view \(viewId)")
        }
    }

    // MARK: - Simulation Study Actions (BL-SIM-01, #157)

    @discardableResult
    public func createSimulationStudy(
        type: SimulationStudyType = .linearStatic,
        name: String? = nil
    ) -> SimulationStudy? {
        let studyCount = document.studies.count + 1
        let defaultName = name ?? "Study \(studyCount)"
        let newStudy = SimulationStudy(
            id: UUID(),
            name: defaultName,
            studyType: type
        )
        let result = document.addStudy(newStudy)
        guard case .success(let study) = result else { return nil }
        selectSimulationStudy(study.id)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "CAE", "Created \(study.studyType.displayName) study '\(study.name)'")
        return study
    }

    public func removeSimulationStudy(id: UUID) {
        if isStudyRunning(id) {
            cancelSimulationStudy(id: id)
        }
        if isStudyMeshing(id) {
            cancelSimulationMesh(studyId: id)
        }
        if selectedSimulationStudyId == id {
            clearSimulationSelections()
        }
        let studyName = document.study(id: id)?.name ?? "\(id)"
        let result = document.removeStudy(id: id)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Removed simulation study '\(studyName)'")
        }
    }

    public func renameSimulationStudy(id: UUID, name: String) {
        let result = document.renameStudy(id: id, name: name)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Renamed simulation study to '\(name)'")
        }
    }

    public func setActiveSimulationStudy(id: UUID?) {
        let result = document.setActiveStudy(id: id)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            if let id, let study = document.study(id: id) {
                log(.info, "CAE", "Activated simulation study '\(study.name)'")
            } else {
                log(.info, "CAE", "Deactivated simulation study")
            }
        }
    }

    public func toggleSimulationStudyCollapsed(id: UUID) {
        let result = document.toggleStudyCollapsed(id: id)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
        }
    }

    public func updateSimulationStudy(_ study: SimulationStudy) {
        let result = document.updateStudy(study)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Updated simulation study '\(study.name)'")
        }
    }

    // MARK: - Simulation Solver Execution (BL-SIM-02, #187)

    public func isStudyRunning(_ id: UUID) -> Bool {
        activeRunningStudyIds.contains(id)
    }

    public func runSimulationStudy(id: UUID) {
        guard let study = document.study(id: id) else {
            log(.error, "CAE", "Cannot run simulation study: study \(id) not found")
            return
        }
        guard !isStudyRunning(id) else {
            log(.warning, "CAE", "Simulation study '\(study.name)' is already running")
            return
        }

        activeRunningStudyIds.insert(id)
        var initialResults = study.results
        initialResults.status = .solving
        initialResults.errorMessage = nil
        _ = document.updateSimulationStudyResults(studyId: id, results: initialResults)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "CAE", "Starting solver for simulation study '\(study.name)' (\(study.solver.engine.displayName))")

        let packageResultsURL = currentDocumentURL?.appendingPathComponent("cache/results/\(id.uuidString)")
        let deck = CAEDeck.fixture(for: study)
        let solverConfig = study.solver
        let runner = self.solverRunner

        let task = Task { [weak self] in
            let startTime = ContinuousClock.now
            do {
                let result = try await runner.run(
                    deck: deck,
                    configuration: solverConfig,
                    packageResultsURL: packageResultsURL
                ) { line in
                    Task { @MainActor in
                        self?.log(.info, "CAE", line)
                    }
                }

                let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                              Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

                await MainActor.run {
                    guard let self else { return }
                    self.activeRunningStudyIds.remove(id)
                    self.activeSolveTasks.removeValue(forKey: id)
                    if var currentStudy = self.document.study(id: id) {
                        currentStudy.results.status = .completed
                        currentStudy.results.runtimeDuration = result.runtimeDuration > 0 ? result.runtimeDuration : elapsed
                        currentStudy.results.errorMessage = nil
                        _ = self.document.updateSimulationStudyResults(studyId: id, results: currentStudy.results)
                        self.markDocumentModified()
                        self.invalidateViewport(.model)
                    }
                    self.log(.info, "CAE", "Simulation study '\(study.name)' completed in \(String(format: "%.2f", elapsed)) s")
                }
            } catch let error as CAEErrorCode {
                let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                              Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

                await MainActor.run {
                    guard let self else { return }
                    self.activeRunningStudyIds.remove(id)
                    self.activeSolveTasks.removeValue(forKey: id)
                    let status: SimulationExecutionStatus = (error == .executionCancelled) ? .cancelled : .failed
                    let errorMsg = error.localizedDescription

                    if var currentStudy = self.document.study(id: id) {
                        currentStudy.results.status = status
                        currentStudy.results.runtimeDuration = elapsed
                        currentStudy.results.errorMessage = errorMsg
                        _ = self.document.updateSimulationStudyResults(studyId: id, results: currentStudy.results)
                        self.markDocumentModified()
                        self.invalidateViewport(.model)
                    }
                    if status == .cancelled {
                        self.log(.warning, "CAE", "Simulation study '\(study.name)' cancelled")
                    } else {
                        self.log(.error, "CAE", "Simulation study '\(study.name)' failed: \(errorMsg)")
                    }
                }
            } catch is CancellationError {
                let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                              Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

                await MainActor.run {
                    guard let self else { return }
                    self.activeRunningStudyIds.remove(id)
                    self.activeSolveTasks.removeValue(forKey: id)
                    if var currentStudy = self.document.study(id: id) {
                        currentStudy.results.status = .cancelled
                        currentStudy.results.runtimeDuration = elapsed
                        currentStudy.results.errorMessage = "Simulation cancelled"
                        _ = self.document.updateSimulationStudyResults(studyId: id, results: currentStudy.results)
                        self.markDocumentModified()
                        self.invalidateViewport(.model)
                    }
                    self.log(.warning, "CAE", "Simulation study '\(study.name)' cancelled")
                }
            } catch {
                let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                              Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

                await MainActor.run {
                    guard let self else { return }
                    self.activeRunningStudyIds.remove(id)
                    self.activeSolveTasks.removeValue(forKey: id)
                    let isCancelled = Task.isCancelled
                    let status: SimulationExecutionStatus = isCancelled ? .cancelled : .failed
                    let errorMsg = isCancelled ? "Simulation cancelled" : error.localizedDescription

                    if var currentStudy = self.document.study(id: id) {
                        currentStudy.results.status = status
                        currentStudy.results.runtimeDuration = elapsed
                        currentStudy.results.errorMessage = errorMsg
                        _ = self.document.updateSimulationStudyResults(studyId: id, results: currentStudy.results)
                        self.markDocumentModified()
                        self.invalidateViewport(.model)
                    }
                    if status == .cancelled {
                        self.log(.warning, "CAE", "Simulation study '\(study.name)' cancelled")
                    } else {
                        self.log(.error, "CAE", "Simulation study '\(study.name)' failed: \(errorMsg)")
                    }
                }
            }
        }
        activeSolveTasks[id] = task
    }

    public func cancelSimulationStudy(id: UUID) {
        guard isStudyRunning(id) else { return }
        log(.info, "CAE", "Cancelling simulation study \(id)...")
        activeSolveTasks[id]?.cancel()
        let runner = self.solverRunner
        Task {
            await runner.cancel(studyId: id)
        }
    }

    // MARK: - Simulation Volume Meshing Execution (BL-MSH-01, #188)

    public func isStudyMeshing(_ id: UUID) -> Bool {
        activeMeshingStudyIds.contains(id)
    }

    public func generateSimulationMesh(studyId: UUID) {
        guard let study = document.study(id: studyId) else {
            log(.error, "CAE", "Cannot mesh simulation study: study \(studyId) not found")
            return
        }
        guard !isStudyMeshing(studyId) else {
            log(.warning, "CAE", "Simulation study '\(study.name)' is already meshing")
            return
        }

        activeMeshingStudyIds.insert(studyId)
        var initialResults = study.results
        initialResults.status = .meshing
        initialResults.errorMessage = nil
        _ = document.updateSimulationStudyResults(studyId: studyId, results: initialResults)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "CAE", "Starting volume mesher for simulation study '\(study.name)'")

        let packageResultsURL = currentDocumentURL?.appendingPathComponent("cache/results/\(studyId.uuidString)")
        let spec = study.mesh
        let mesher = self.volumeMesher

        let task = Task { [weak self] in
            let startTime = ContinuousClock.now
            do {
                let stepData: Data
                if let self {
                    let candidateObjects: [SceneObject]
                    if !study.targets.isEmpty {
                        let targetStrings = Set(study.targets.map { $0.targetId.uuidString.lowercased() })
                        let matched = self.document.objects.filter { obj in
                            obj.isVisible && (targetStrings.contains(obj.id.rawValue.lowercased()) || study.targets.contains { $0.targetName == obj.name })
                        }
                        candidateObjects = matched.isEmpty ? self.document.objects.filter { $0.isVisible } : matched
                    } else {
                        candidateObjects = self.document.objects.filter { $0.isVisible }
                    }

                    if !candidateObjects.isEmpty {
                        let exportRes = await self.kernelClient.exportStep(objects: candidateObjects)
                        switch exportRes {
                        case .success(_, let data):
                            stepData = data
                        case .failure(_, let err):
                            throw CAEErrorCode.meshingFailed(reason: "Failed to export STEP geometry: \(err.message)", exitCode: 1)
                        }
                    } else {
                        stepData = VolumeMesherFixture.minimalStepBoxData
                    }
                } else {
                    stepData = VolumeMesherFixture.minimalStepBoxData
                }

                let result = try await mesher.mesh(
                    stepData: stepData,
                    specification: spec,
                    studyId: studyId,
                    packageResultsURL: packageResultsURL
                ) { line in
                    Task { @MainActor in
                        self?.log(.info, "CAE", line)
                    }
                }

                let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                              Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

                await MainActor.run {
                    guard let self else { return }
                    self.activeMeshingStudyIds.remove(studyId)
                    self.activeMeshTasks.removeValue(forKey: studyId)
                    if var currentStudy = self.document.study(id: studyId) {
                        var updatedMesh = result.mesh
                        let sets = MeshGeometryAssociator.associate(mesh: updatedMesh, study: currentStudy)
                        updatedMesh.sets = sets
                        self.cachedStudyMeshes[studyId] = updatedMesh
                        currentStudy.results.meshStatistics = updatedMesh.statistics
                        currentStudy.results.meshSets = sets
                        currentStudy.results.status = .notRun
                        currentStudy.results.errorMessage = nil
                        _ = self.document.updateSimulationStudyResults(studyId: studyId, results: currentStudy.results)
                        self.markDocumentModified()
                        self.invalidateViewport(.model)
                    }
                    self.log(.info, "CAE", "Meshing completed for study '\(study.name)': \(result.mesh.statistics.nodeCount) nodes, \(result.mesh.statistics.elementCount) elements in \(String(format: "%.2f", elapsed)) s")
                }
            } catch let error as CAEErrorCode {
                let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                              Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

                await MainActor.run {
                    guard let self else { return }
                    self.activeMeshingStudyIds.remove(studyId)
                    self.activeMeshTasks.removeValue(forKey: studyId)
                    let status: SimulationExecutionStatus = (error == .executionCancelled) ? .cancelled : .failed
                    let errorMsg = error.localizedDescription

                    if var currentStudy = self.document.study(id: studyId) {
                        currentStudy.results.status = status
                        currentStudy.results.runtimeDuration = elapsed
                        currentStudy.results.errorMessage = errorMsg
                        _ = self.document.updateSimulationStudyResults(studyId: studyId, results: currentStudy.results)
                        self.markDocumentModified()
                        self.invalidateViewport(.model)
                    }
                    if status == .cancelled {
                        self.log(.warning, "CAE", "Meshing cancelled for study '\(study.name)'")
                    } else {
                        self.log(.error, "CAE", "Meshing failed for study '\(study.name)': \(errorMsg)")
                    }
                }
            } catch is CancellationError {
                let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                              Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

                await MainActor.run {
                    guard let self else { return }
                    self.activeMeshingStudyIds.remove(studyId)
                    self.activeMeshTasks.removeValue(forKey: studyId)
                    if var currentStudy = self.document.study(id: studyId) {
                        currentStudy.results.status = .cancelled
                        currentStudy.results.runtimeDuration = elapsed
                        currentStudy.results.errorMessage = "Meshing cancelled"
                        _ = self.document.updateSimulationStudyResults(studyId: studyId, results: currentStudy.results)
                        self.markDocumentModified()
                        self.invalidateViewport(.model)
                    }
                    self.log(.warning, "CAE", "Meshing cancelled for study '\(study.name)'")
                }
            } catch {
                let elapsed = Double(startTime.duration(to: .now).components.seconds) +
                              Double(startTime.duration(to: .now).components.attoseconds) * 1e-18

                await MainActor.run {
                    guard let self else { return }
                    self.activeMeshingStudyIds.remove(studyId)
                    self.activeMeshTasks.removeValue(forKey: studyId)
                    let isCancelled = Task.isCancelled
                    let status: SimulationExecutionStatus = isCancelled ? .cancelled : .failed
                    let errorMsg = isCancelled ? "Meshing cancelled" : error.localizedDescription

                    if var currentStudy = self.document.study(id: studyId) {
                        currentStudy.results.status = status
                        currentStudy.results.runtimeDuration = elapsed
                        currentStudy.results.errorMessage = errorMsg
                        _ = self.document.updateSimulationStudyResults(studyId: studyId, results: currentStudy.results)
                        self.markDocumentModified()
                        self.invalidateViewport(.model)
                    }
                    if status == .cancelled {
                        self.log(.warning, "CAE", "Meshing cancelled for study '\(study.name)'")
                    } else {
                        self.log(.error, "CAE", "Meshing failed for study '\(study.name)': \(errorMsg)")
                    }
                }
            }
        }
        activeMeshTasks[studyId] = task
    }

    public func cancelSimulationMesh(studyId: UUID) {
        guard isStudyMeshing(studyId) else { return }
        log(.info, "CAE", "Cancelling volume mesher for study \(studyId)...")
        activeMeshTasks[studyId]?.cancel()
        let mesher = self.volumeMesher
        Task {
            await mesher.cancel(studyId: studyId)
        }
    }

    @discardableResult
    public func addSimulationFixture(
        studyId: UUID,
        fixture: SimulationFixture = SimulationFixture()
    ) -> SimulationFixture? {
        let result = document.addSimulationFixture(studyId: studyId, fixture: fixture)
        guard case .success(let newFixture) = result else { return nil }
        selectSimulationFixture(studyId: studyId, fixtureId: newFixture.id)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "CAE", "Added fixture '\(newFixture.name)' to study")
        return newFixture
    }

    public func removeSimulationFixture(studyId: UUID, fixtureId: UUID) {
        if selectedSimulationFixtureId == fixtureId {
            selectedSimulationFixtureId = nil
        }
        let result = document.removeSimulationFixture(studyId: studyId, fixtureId: fixtureId)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Removed fixture \(fixtureId)")
        }
    }

    public func updateSimulationFixture(studyId: UUID, fixture: SimulationFixture) {
        let result = document.updateSimulationFixture(studyId: studyId, fixture: fixture)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Updated fixture '\(fixture.name)'")
        }
    }

    @discardableResult
    public func addSimulationLoad(
        studyId: UUID,
        load: SimulationLoad = SimulationLoad()
    ) -> SimulationLoad? {
        let result = document.addSimulationLoad(studyId: studyId, load: load)
        guard case .success(let newLoad) = result else { return nil }
        selectSimulationLoad(studyId: studyId, loadId: newLoad.id)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "CAE", "Added load '\(newLoad.name)' to study")
        return newLoad
    }

    public func removeSimulationLoad(studyId: UUID, loadId: UUID) {
        if selectedSimulationLoadId == loadId {
            selectedSimulationLoadId = nil
        }
        let result = document.removeSimulationLoad(studyId: studyId, loadId: loadId)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Removed load \(loadId)")
        }
    }

    public func updateSimulationLoad(studyId: UUID, load: SimulationLoad) {
        let result = document.updateSimulationLoad(studyId: studyId, load: load)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Updated load '\(load.name)'")
        }
    }

    @discardableResult
    public func addSimulationMaterialAssignment(
        studyId: UUID,
        assignment: SimulationMaterialAssignment = SimulationMaterialAssignment()
    ) -> SimulationMaterialAssignment? {
        let result = document.addSimulationMaterialAssignment(studyId: studyId, assignment: assignment)
        guard case .success(let newAssignment) = result else { return nil }
        selectSimulationMaterialAssignment(studyId: studyId, assignmentId: newAssignment.id)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "CAE", "Added material assignment '\(newAssignment.name)' to study")
        return newAssignment
    }

    public func removeSimulationMaterialAssignment(studyId: UUID, assignmentId: UUID) {
        if selectedSimulationMaterialAssignmentId == assignmentId {
            selectedSimulationMaterialAssignmentId = nil
        }
        let result = document.removeSimulationMaterialAssignment(studyId: studyId, assignmentId: assignmentId)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Removed material assignment \(assignmentId)")
        }
    }

    public func updateSimulationMaterialAssignment(studyId: UUID, assignment: SimulationMaterialAssignment) {
        let result = document.updateSimulationMaterialAssignment(studyId: studyId, assignment: assignment)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Updated material assignment '\(assignment.name)'")
        }
    }

    public func updateSimulationMeshSpecification(studyId: UUID, mesh: MeshSpecification) {
        let result = document.updateSimulationMeshSpecification(studyId: studyId, mesh: mesh)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Updated mesh specification for study")
        }
    }

    public func updateSimulationSolverConfiguration(studyId: UUID, solver: SolverConfiguration) {
        let result = document.updateSimulationSolverConfiguration(studyId: studyId, solver: solver)
        if case .success = result {
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Updated solver configuration for study")
        }
    }

    public func volumeMesh(for studyId: UUID) -> VolumeMesh? {
        cachedStudyMeshes[studyId]
    }

    public func reassociateSimulationMeshSets(studyId: UUID) {
        guard var mesh = cachedStudyMeshes[studyId],
              var study = document.study(id: studyId) else { return }
        let sets = MeshGeometryAssociator.associate(mesh: mesh, study: study)
        mesh.sets = sets
        cachedStudyMeshes[studyId] = mesh
        study.results.meshSets = sets
        _ = document.updateSimulationStudyResults(studyId: studyId, results: study.results)
    }

    public func assignSelectedSubElementToFixture(studyId: UUID, fixtureId: UUID) {
        guard let sub = document.selectedSubElement else { return }
        let targetName: String
        switch sub.elementType {
        case .face:
            targetName = "Face \(sub.elementId)"
        case .edge:
            targetName = "Edge \(sub.elementId)"
        case .vertex:
            targetName = "Vertex \(sub.elementId)"
        }
        let targetId = sub.deterministicId ?? UUID(uuidString: sub.solidId.rawValue) ?? UUID()
        let ref = SimulationGeometryReference(
            targetId: targetId,
            targetName: targetName,
            subelementType: sub.elementType
        )
        _ = document.assignTargetReferenceToFixture(studyId: studyId, fixtureId: fixtureId, reference: ref)
        reassociateSimulationMeshSets(studyId: studyId)
        markDocumentModified()
        invalidateViewport(.model)
    }

    public func removeTargetReferenceFromFixture(studyId: UUID, fixtureId: UUID, referenceId: UUID) {
        _ = document.removeTargetReferenceFromFixture(studyId: studyId, fixtureId: fixtureId, referenceId: referenceId)
        reassociateSimulationMeshSets(studyId: studyId)
        markDocumentModified()
        invalidateViewport(.model)
    }

    public func assignSelectedSubElementToLoad(studyId: UUID, loadId: UUID) {
        guard let sub = document.selectedSubElement else { return }
        let targetName: String
        switch sub.elementType {
        case .face:
            targetName = "Face \(sub.elementId)"
        case .edge:
            targetName = "Edge \(sub.elementId)"
        case .vertex:
            targetName = "Vertex \(sub.elementId)"
        }
        let targetId = sub.deterministicId ?? UUID(uuidString: sub.solidId.rawValue) ?? UUID()
        let ref = SimulationGeometryReference(
            targetId: targetId,
            targetName: targetName,
            subelementType: sub.elementType
        )
        _ = document.assignTargetReferenceToLoad(studyId: studyId, loadId: loadId, reference: ref)
        reassociateSimulationMeshSets(studyId: studyId)
        markDocumentModified()
        invalidateViewport(.model)
    }

    public func removeTargetReferenceFromLoad(studyId: UUID, loadId: UUID, referenceId: UUID) {
        _ = document.removeTargetReferenceFromLoad(studyId: studyId, loadId: loadId, referenceId: referenceId)
        reassociateSimulationMeshSets(studyId: studyId)
        markDocumentModified()
        invalidateViewport(.model)
    }

    @discardableResult
    public func addSimulationGeometryGroup(
        studyId: UUID,
        group: SimulationGeometryGroup = SimulationGeometryGroup()
    ) -> SimulationGeometryGroup? {
        let result = document.addSimulationGeometryGroup(studyId: studyId, group: group)
        guard case .success(let newGroup) = result else { return nil }
        reassociateSimulationMeshSets(studyId: studyId)
        markDocumentModified()
        invalidateViewport(.model)
        log(.info, "CAE", "Added geometry group '\(newGroup.name)' to study")
        return newGroup
    }

    public func removeSimulationGeometryGroup(studyId: UUID, groupId: UUID) {
        let result = document.removeSimulationGeometryGroup(studyId: studyId, groupId: groupId)
        if case .success = result {
            reassociateSimulationMeshSets(studyId: studyId)
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Removed geometry group \(groupId)")
        }
    }

    public func updateSimulationGeometryGroup(studyId: UUID, group: SimulationGeometryGroup) {
        let result = document.updateSimulationGeometryGroup(studyId: studyId, group: group)
        if case .success = result {
            reassociateSimulationMeshSets(studyId: studyId)
            markDocumentModified()
            invalidateViewport(.model)
            log(.info, "CAE", "Updated geometry group '\(group.name)'")
        }
    }

    // MARK: - Document Settings (BL-FND-11)

    func setDocumentSettings(_ newSettings: DocumentSettings) {
        document.setSettings(newSettings)
        markDocumentModified()
    }

    func setDocumentUnits(_ units: UnitSettings) {
        document.setUnits(units)
        markDocumentModified()
    }

    func setDocumentTolerances(_ tolerances: KernelTolerances) {
        let clamped = tolerances.clamped()
        document.setTolerances(clamped)
        markDocumentModified()
        retessellateAll(tolerances: clamped)
    }

    func setDocumentDefaultMaterial(_ material: MaterialAttributes) {
        document.setDefaultMaterial(material)
        markDocumentModified()
    }

    func setParam(_ id: ObjectId, _ key: String, _ value: Float, expression: String? = nil) {
        let result = document.setParam(id: id, key: key, value: value, expression: expression)
        guard case .success = result else { return }
        markDocumentModified()
        log(.kernel, "CSG", "Updated \(id.rawValue) \(key) to \(String(format: "%.1f", value))")
        recomputeSolid(id: id)
    }

    // MARK: - Document Parameters (BL-PAR-01)

    func addParameter(_ parameter: DocumentParameter) throws {
        try document.addParameter(parameter)
        markDocumentModified()
    }

    func deleteParameter(id: UUID) throws {
        try document.deleteParameter(id: id)
        markDocumentModified()
    }

    func renameParameter(id: UUID, newName: String) throws {
        try document.renameParameter(id: id, newName: newName)
        markDocumentModified()
    }

    func updateParameter(
        id: UUID,
        value: Double? = nil,
        unit: String? = nil,
        comment: String? = nil,
        expression: String?? = nil,
        min: Double?? = nil,
        max: Double?? = nil,
        step: Double?? = nil
    ) throws {
        let affected = try document.updateParameter(
            id: id,
            value: value,
            unit: unit,
            comment: comment,
            expression: expression,
            min: min,
            max: max,
            step: step
        )
        markDocumentModified()
        for solidId in affected {
            recomputeSolid(id: solidId)
        }
    }

    /// Drops meshes for objects removed by any path, including MCP agent tools.
    func syncMeshes(removedFrom old: [SceneObject], to new: [SceneObject]) {
        let remaining = Set(new.map(\.id))
        var removedIds: [ObjectId] = []
        for obj in old where !remaining.contains(obj.id) {
            removedIds.append(obj.id)
            partReloadController?.stopWatching(id: obj.id)
            Task { await kernelClient.dispose(solidId: obj.id) }
            if let renderer = viewportManager.renderer, SolidMeshApplier.remove(id: obj.id, from: renderer) {
                invalidateViewport(.model)
            }
            recomputeFailures.clear(obj.id)
        }
        partReloadController?.syncWithDocument()
        for id in removedIds {
            for depId in document.dependentObjects(of: id) {
                recomputeSolid(id: depId)
            }
        }
    }

    func recomputeSolid(id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        if case .part(let url, _) = obj.def {
            partReloadController?.watchPart(id: id, url: url, evaluateImmediately: true)
            return
        }
        if case .imported(_, let sourceURL, let data, let isLinked, _, _) = obj.def,
           isLinked, data == nil, let sourceURL,
           sourceURL.pathExtension.lowercased() == "made" || (try? FileWrapper(url: sourceURL, options: []).isDirectory) == true {
            Task { [weak self] in
                await self?.updateLinkedReference(id)
            }
            return
        }
        if let registry = toolRegistry {
            let task = registry.scheduleRecompute(id: id)
            let clock = ContinuousClock()
            let start = clock.now
            Task { [weak self] in
                await Task.yield()
                await self?.updateKernelStats()
                _ = await task?.value
                let elapsed = clock.now - start
                self?.lastRegenerationDuration = elapsed
                await self?.updateKernelStats()
            }
            return
        }
        let request: KernelRequest? = {
            if let feat = document.features.first(where: { $0.outputSolidId == id }),
               let req = KernelRegeneration.request(for: feat, jobId: JobId("job-\(UUID().uuidString)")) {
                return req
            }
            return KernelRegeneration.request(for: obj, jobId: JobId("job-\(UUID().uuidString)"))
        }()
        guard let request else { return }

        let clock = ContinuousClock()
        let start = clock.now
        Task { [weak self] in
            guard let self else { return }
            let result = await self.kernelClient.request(request)
            let elapsed = clock.now - start
            self.lastRegenerationDuration = elapsed
            await self.updateKernelStats()
            // The solid was removed while the request was in flight; release what it repopulated.
            guard self.document.objects.contains(where: { $0.id == id }) else {
                await self.kernelClient.dispose(solidId: id)
                return
            }
            // A failure leaves the previous mesh installed; only the message changes.
            if let message = self.recomputeFailures.record(result, for: id) {
                self.log(.error, "Kernel", message)
            }
            switch result {
            case .failure(_, let err):
                guard err.code != .cancelled else { return }
                if let feat = self.document.feature(for: id) {
                    self.document.setFeatureError(
                        id: feat.id,
                        error: FeatureErrorState(code: err.code.rawValue, message: err.message, severity: .error)
                    )
                    for depFeat in self.document.dependentFeatures(referencing: feat.id) {
                        self.document.setFeatureError(
                            id: depFeat.id,
                            error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
                        )
                    }
                }
            case .success:
                if let feat = self.document.feature(for: id) {
                    self.document.setFeatureError(id: feat.id, error: nil)
                }
            }
            if case .failure(_, let err) = result,
               let obj = self.document.objects.first(where: { $0.id == id }),
               case .imported(let name, let sourceURL, _, _, _, _) = obj.def {
                let fileURL = sourceURL ?? URL(fileURLWithPath: name)
                self.pendingImportError = ImportErrorInfo(
                    fileURL: fileURL,
                    errorCode: err.code.rawValue,
                    reason: err.message
                )
                self.isShowingImportErrorAlert = true
                self.document.removeObject(id: id)
                await self.kernelClient.dispose(solidId: id)
                if self.selectedId == id {
                    self.selectedId = nil
                }
                return
            }
            guard let renderer = self.viewportManager.renderer,
                  SolidMeshApplier.apply(result, to: id, document: self.document, sink: renderer) else { return }
            self.invalidateViewport(.model)
            if case .success = result {
                for depId in self.document.directDependentObjects(of: id) {
                    if let depFeat = self.document.feature(for: depId), depFeat.errorState?.code == "parent-failed" {
                        self.document.setFeatureError(id: depFeat.id, error: nil)
                    }
                    self.recomputeSolid(id: depId)
                }
            }
        }
    }

    func retessellateSolid(id: ObjectId, tolerances: KernelTolerances? = nil) {
        guard document.objects.contains(where: { $0.id == id }) else { return }
        let tol = (tolerances ?? document.settings.tolerances).clamped()
        if let registry = toolRegistry {
            let task = registry.scheduleRetessellate(id: id, tolerances: tol)
            let clock = ContinuousClock()
            let start = clock.now
            Task { [weak self] in
                await Task.yield()
                await self?.updateKernelStats()
                _ = await task?.value
                let elapsed = clock.now - start
                self?.lastRegenerationDuration = elapsed
                await self?.updateKernelStats()
            }
            return
        }
        let jobId = JobId("tess-\(UUID().uuidString)")
        let request = KernelRequest.tessellate(jobId: jobId, solidId: id, tolerances: tol)
        let clock = ContinuousClock()
        let start = clock.now
        Task { [weak self] in
            guard let self else { return }
            let result = await self.kernelClient.request(request)
            let elapsed = clock.now - start
            self.lastRegenerationDuration = elapsed
            await self.updateKernelStats()
            guard self.document.objects.contains(where: { $0.id == id }) else {
                if case .success = result {
                    await self.kernelClient.dispose(solidId: id)
                }
                return
            }
            if let message = self.recomputeFailures.record(result, for: id) {
                self.log(.error, "Kernel", message)
            }
            switch result {
            case .failure(_, let err):
                guard err.code != .cancelled else { return }
                if let feat = self.document.feature(for: id) {
                    self.document.setFeatureError(
                        id: feat.id,
                        error: FeatureErrorState(code: err.code.rawValue, message: err.message, severity: .error)
                    )
                }
            case .success:
                if let feat = self.document.feature(for: id) {
                    self.document.setFeatureError(id: feat.id, error: nil)
                }
            }
            guard let renderer = self.viewportManager.renderer,
                  SolidMeshApplier.apply(result, to: id, document: self.document, sink: renderer) else { return }
            self.invalidateViewport(.model)
        }
    }

    func retessellateAll(tolerances: KernelTolerances? = nil) {
        let tol = (tolerances ?? document.settings.tolerances).clamped()
        for obj in document.objects {
            retessellateSolid(id: obj.id, tolerances: tol)
        }
    }

    // MARK: - Undo & Redo

    var undoManager: UndoManager? {
        document.undoManager
    }

    var canUndo: Bool {
        document.canUndo
    }

    var canRedo: Bool {
        document.canRedo
    }

    var undoTitle: String {
        document.undoActionTitle
    }

    var redoTitle: String {
        document.redoActionTitle
    }

    @discardableResult
    func undo() -> Task<Void, Never> {
        let oldObjects = document.objects
        let oldFeatureIds = Set(document.features.map(\.id))
        document.undo()
        syncMeshes(removedFrom: oldObjects, to: document.objects)
        syncHiddenSolidIds()
        syncMaterials()
        let oldSet = Set(oldObjects.map(\.id))
        for obj in document.objects where !oldSet.contains(obj.id) {
            recomputeSolid(id: obj.id)
        }
        for obj in document.objects {
            if let old = oldObjects.first(where: { $0.id == obj.id }) {
                if old.def != obj.def {
                    recomputeSolid(id: obj.id)
                } else if old.transform != obj.transform {
                    if let renderer = viewportManager.renderer {
                        _ = SolidMeshApplier.applyTransform(to: obj.id, document: document, sink: renderer)
                    }
                }
            }
        }
        if let sketch = selectedSketchFeature {
            refreshSketchStatus(for: sketch.id)
        }
        if oldFeatureIds != Set(document.features.map(\.id)) {
            return Task {
                await KernelRegeneration.regenerate(document: self.document, client: self.kernelClient)
                self.invalidateViewport(.model)
            }
        }
        return Task {}
    }

    @discardableResult
    func redo() -> Task<Void, Never> {
        let oldObjects = document.objects
        let oldFeatureIds = Set(document.features.map(\.id))
        document.redo()
        syncMeshes(removedFrom: oldObjects, to: document.objects)
        syncHiddenSolidIds()
        syncMaterials()
        let oldSet = Set(oldObjects.map(\.id))
        for obj in document.objects where !oldSet.contains(obj.id) {
            recomputeSolid(id: obj.id)
        }
        for obj in document.objects {
            if let old = oldObjects.first(where: { $0.id == obj.id }) {
                if old.def != obj.def {
                    recomputeSolid(id: obj.id)
                } else if old.transform != obj.transform {
                    if let renderer = viewportManager.renderer {
                        _ = SolidMeshApplier.applyTransform(to: obj.id, document: document, sink: renderer)
                    }
                }
            }
        }
        if let sketch = selectedSketchFeature {
            refreshSketchStatus(for: sketch.id)
        }
        if oldFeatureIds != Set(document.features.map(\.id)) {
            return Task {
                await KernelRegeneration.regenerate(document: self.document, client: self.kernelClient)
                self.invalidateViewport(.model)
            }
        }
        return Task {}
    }

    func beginInteractiveParamEdit(_ id: ObjectId, _ key: String) {
        document.beginInteractiveParamEdit(id: id, key: key)
    }

    func endInteractiveParamEdit(_ id: ObjectId, _ key: String) {
        document.endInteractiveParamEdit(id: id, key: key)
    }

    func handleUndoRedoMutation(_ mutation: DocumentMutation) {
        switch mutation {
        case .added(let id):
            selectedId = id
            recomputeSolid(id: id)
            invalidateViewport(.model)

        case .removed(let id):
            partReloadController?.stopWatching(id: id)
            Task {
                await kernelClient.dispose(solidId: id)
                for depId in self.document.dependentObjects(of: id) {
                    self.recomputeSolid(id: depId)
                }
            }
            recomputeFailures.clear(id)
            if let renderer = viewportManager.renderer {
                _ = SolidMeshApplier.remove(id: id, from: renderer)
            }
            log(.info, "Scene", "Removed object \(id.rawValue)")
            invalidateViewport(.model)

        case .paramChanged(let id, let key, let value):
            log(.kernel, "CSG", "Updated \(id.rawValue) \(key) to \(String(format: "%.1f", value))")
            recomputeSolid(id: id)

        case .transformChanged(let id, let transform):
            if let renderer = viewportManager.renderer {
                _ = SolidMeshApplier.applyTransform(to: id, document: document, sink: renderer)
            }
            log(.info, "Scene", "Updated \(id.rawValue) transform to position \(formatVec3(transform.position)) scale \(formatVec3(transform.scale))")
            invalidateViewport(.model)
        }
        markDocumentModified()
    }

    #if DEBUG
    /// Forces the next recompute of any solid to fail, so the failure message can be checked by hand.
    func failNextRecompute() {
        Task { await injectRecomputeFailure(code: .invalidParams) }
    }

    func injectRecomputeFailure(code: KernelErrorCode = .invalidParams) async {
        await faultInjector.failNextRequest(with: code)
        log(.info, "Kernel", "Next recompute will fail with \(code.rawValue)")
    }
    #endif

    // MARK: - Viewport

    func setDisplayMode(_ mode: DisplayMode) {
        guard mode != displayMode else { return }
        displayMode = mode
    }

    func setProjectionMode(_ mode: CameraProjection) {
        guard mode != projectionMode else { return }
        projectionMode = mode
        if let renderer = viewportManager.renderer {
            renderer.projectionMode = mode
            renderer.camera.orthographicScale = 1.0
            self.camera = renderer.camera
        } else {
            self.camera.projection = mode
            self.camera.orthographicScale = 1.0
        }
        log(.info, "Camera", "Switched projection to \(mode.rawValue)")
        invalidateViewport(.camera)
    }

    func applyPerspective(_ perspective: ViewportPerspective) {
        self.perspective = perspective
        var newCamera = Camera.preset(perspective)
        newCamera.projection = projectionMode
        if let renderer = viewportManager.renderer {
            renderer.camera = newCamera
            renderer.projectionMode = projectionMode
            self.camera = renderer.camera
        } else {
            self.camera = newCamera
        }
        log(.info, "Camera", "Switched to \(perspective.rawValue) perspective")
        invalidateViewport(.camera)
    }

    func cancelCameraAnimation() {
        cameraAnimationTask?.cancel()
        cameraAnimationTask = nil
    }

    private func setCameraImmediate(_ newCamera: Camera) {
        if let renderer = viewportManager.renderer {
            renderer.camera = newCamera
        }
        self.camera = newCamera
        invalidateViewport(.camera)
    }

    func animateCamera(to targetCamera: Camera, duration: TimeInterval = 0.25) {
        cancelCameraAnimation()

        guard duration > 0, viewportManager.renderer != nil, coordinator != nil else {
            setCameraImmediate(targetCamera)
            return
        }

        let startCamera = viewportManager.renderer?.camera ?? camera
        let startTime = CACurrentMediaTime()

        cameraAnimationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let progress = Float(min(max(elapsed / duration, 0.0), 1.0))

                guard let self else { return }

                if progress >= 1.0 {
                    self.setCameraImmediate(targetCamera)
                    self.cameraAnimationTask = nil
                    return
                } else {
                    let current = Camera.interpolate(from: startCamera, to: targetCamera, t: progress)
                    if let renderer = self.viewportManager.renderer {
                        renderer.camera = current
                    }
                    self.camera = current
                    self.invalidateViewport(.camera)
                }

                do {
                    try await Task.sleep(nanoseconds: 16_666_667)
                } catch {
                    return
                }
            }
        }
    }

    func snapCameraToFace(solidId: SolidId, faceId: Int, animated: Bool = true) {
        let currentCamera = viewportManager.renderer?.camera ?? camera

        let normal: SIMD3<Float>?
        let centroid: SIMD3<Float>?

        if let mesh = viewportManager.renderer?.meshes[solidId] {
            normal = mesh.faceNormal(forFaceId: faceId)
            centroid = mesh.faceCentroid(forFaceId: faceId)
        } else if let obj = document.objects.first(where: { $0.id == solidId }) {
            // Headless fallback if renderer mesh is unavailable
            let candidate: CandidateMesh?
            switch obj.def {
            case .box(let p):
                let payload = NativeGeometryGenerator.generateBox(width: p.width, depth: p.depth, height: p.height)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .cylinder(let p):
                let payload = NativeGeometryGenerator.generateCylinder(radius: p.radius, height: p.height)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .sphere(let p):
                let payload = NativeGeometryGenerator.generateSphere(radius: p.radius)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .cone(let p):
                let payload = NativeGeometryGenerator.generateCone(bottomRadius: p.bottomRadius, topRadius: p.topRadius, height: p.height)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .torus(let p):
                let payload = NativeGeometryGenerator.generateTorus(majorRadius: p.majorRadius, minorRadius: p.minorRadius)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .wedge(let p):
                let payload = NativeGeometryGenerator.generateWedge(width: p.width, depth: p.depth, height: p.height, topWidth: p.topWidth)
                candidate = CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            default:
                candidate = nil
            }
            normal = candidate?.faceNormal(forFaceId: faceId)
            centroid = candidate?.faceCentroid(forFaceId: faceId)
        } else {
            normal = nil
            centroid = nil
        }

        guard let norm = normal, let center = centroid else {
            log(.error, "Camera", "Could not determine face normal or centroid for face \(faceId) on solid \(solidId)")
            return
        }

        let currentDist = max(1.0, simd_length(currentCamera.position - currentCamera.target))
        let targetCamera = Camera.alignedToNormal(
            norm,
            target: center,
            distance: currentDist,
            currentCamera: currentCamera,
            allowFlip: true,
            projection: projectionMode
        )

        log(.info, "Camera", "Squaring camera to face \(faceId) of solid \(solidId)")
        if animated && viewportManager.renderer != nil && coordinator != nil {
            animateCamera(to: targetCamera)
        } else {
            setCameraImmediate(targetCamera)
        }
    }

    func alignNormalTo(animated: Bool = true) {
        if let subElement = document.selectedSubElement, subElement.elementType == .face {
            snapCameraToFace(solidId: subElement.solidId, faceId: subElement.elementId, animated: animated)
            return
        }

        let currentCamera = viewportManager.renderer?.camera ?? camera
        let target: SIMD3<Float>
        let normal: SIMD3<Float>
        let solidName: String

        if let selected = selectedObject {
            target = selected.transform.position
            normal = simd_normalize(selected.transform.rotation.act(Orientation.worldUp))
            solidName = selected.name
        } else {
            target = currentCamera.target
            normal = Orientation.groundNormal
            solidName = "ground plane"
        }

        let currentDist = max(1.0, simd_length(currentCamera.position - currentCamera.target))
        let targetCamera = Camera.alignedToNormal(
            normal,
            target: target,
            distance: currentDist,
            currentCamera: currentCamera,
            allowFlip: true,
            projection: projectionMode
        )

        log(.info, "Camera", "Aligned normal to \(solidName)")
        if animated && viewportManager.renderer != nil && coordinator != nil {
            animateCamera(to: targetCamera)
        } else {
            setCameraImmediate(targetCamera)
        }
    }

    func applyViewCubeRegion(_ region: ViewCube.Region) {
        switch region {
        case .home:
            resetView()
        case .face(let f):
            applyPerspective(f.perspective)
        case .edge, .corner:
            let currentCamera = viewportManager.renderer?.camera ?? camera
            let currentDist = max(1.0, simd_length(currentCamera.position - currentCamera.target))
            var dir = region.direction
            if abs(dir.z) > 0.999 && abs(dir.x) < 1e-3 && abs(dir.y) < 1e-3 {
                dir = simd_normalize(dir + SIMD3<Float>(0, 0.001, 0))
            }
            let newCam = Camera(
                position: currentCamera.target + dir * currentDist,
                target: currentCamera.target,
                minDistance: currentCamera.minDistance,
                maxDistance: currentCamera.maxDistance,
                minPitch: currentCamera.minPitch,
                maxPitch: currentCamera.maxPitch,
                projection: projectionMode,
                orthographicScale: currentCamera.orthographicScale
            )
            if let renderer = viewportManager.renderer {
                renderer.camera = newCam
            }
            self.camera = newCam
            log(.info, "Camera", "Switched view to \(region.displayName)")
            invalidateViewport(.camera)
        }
    }

    func resetView() { applyPerspective(defaultPerspective) }
    func zoomStep(zoomIn: Bool) { coordinator?.zoomStep(zoomIn: zoomIn) }
    func fitToScene() { coordinator?.fitToScene() }

    func handleSnapChanged(_ result: SnapResult?) {
        activeSnapResult = result
        activeSnapKind = result?.kind
        if let result { log(.snap, "Snapping", "Snapped to \(result.kind.rawValue)") }
    }

    func invalidateViewport(_ reason: InvalidateReason) {
        if let coordinator {
            coordinator.invalidate(reason: reason)
        } else {
            renderInstrumentation.recordInvalidation(reason: reason)
            updateStats()
        }
    }

    func updateStats() {
        let inst = renderInstrumentation
        let nextRenderStats = RenderStats(
            renderCount: inst.renderCount,
            drawCalls: inst.drawCalls,
            lastReason: inst.lastReason?.rawValue ?? "idle"
        )
        if renderStats != nextRenderStats {
            renderStats = nextRenderStats
        }
        if let currentCamera = viewportManager.renderer?.camera, camera != currentCamera {
            camera = currentCamera
        }
        Task { [weak self] in
            await self?.updateKernelStats()
        }
    }

    func updateKernelStats() async {
        let stats = await kernelClient.getStats()
        if kernelStats != stats {
            kernelStats = stats
        }
    }

    // MARK: - MCP

    func toggleMCPServer() {
        guard let server = mcpServer else { return }
        if isMCPServerRunning {
            server.stop()
            isMCPServerRunning = false
            mcpServerError = nil
            log(.info, "MCP", "Stopped MCP server")
        } else {
            mcpServerError = nil
            do {
                try server.start(port: mcpPort)
            } catch {
                let message = error.localizedDescription
                mcpServerError = message
                log(.error, "MCP", "Failed to start MCP server: \(message)")
            }
        }
    }

    var mcpServerToggleTitle: String {
        isMCPServerRunning ? "Stop MCP Server" : "Start MCP Server"
    }

    // MARK: - Keyboard Shortcuts & Modifiers (BL-MAC-04)

    static let newDocumentShortcutKey: KeyEquivalent = "n"
    static let newDocumentShortcutModifiers: EventModifiers = [.command]

    static let newAssemblyShortcutKey: KeyEquivalent = "n"
    static let newAssemblyShortcutModifiers: EventModifiers = [.command, .option]

    static let newDrawingShortcutKey: KeyEquivalent = "d"
    static let newDrawingShortcutModifiers: EventModifiers = [.command, .shift]

    static let solveAssemblyShortcutKey: KeyEquivalent = "s"
    static let solveAssemblyShortcutModifiers: EventModifiers = [.command, .option]

    static let openDocumentShortcutKey: KeyEquivalent = "o"
    static let openDocumentShortcutModifiers: EventModifiers = [.command]

    static let openPartShortcutKey: KeyEquivalent = "o"
    static let openPartShortcutModifiers: EventModifiers = [.command, .option]

    static let saveDocumentShortcutKey: KeyEquivalent = "s"
    static let saveDocumentShortcutModifiers: EventModifiers = [.command]

    static let saveAsDocumentShortcutKey: KeyEquivalent = "s"
    static let saveAsDocumentShortcutModifiers: EventModifiers = [.command, .shift]

    static let undoShortcutKey: KeyEquivalent = "z"
    static let undoShortcutModifiers: EventModifiers = [.command]

    static let redoShortcutKey: KeyEquivalent = "z"
    static let redoShortcutModifiers: EventModifiers = [.command, .shift]

    static let deleteShortcutKey: KeyEquivalent = .delete
    static let deleteShortcutModifiers: EventModifiers = [.command]

    static let addBoxShortcutKey: KeyEquivalent = "b"
    static let addBoxShortcutModifiers: EventModifiers = [.command, .shift]

    static let addCylinderShortcutKey: KeyEquivalent = "c"
    static let addCylinderShortcutModifiers: EventModifiers = [.command, .shift]

    static let dimensionLineShortcutKey: KeyEquivalent = "d"
    static let dimensionLineShortcutModifiers: EventModifiers = [.command, .shift]

    static let toggleConstructionShortcutKey: KeyEquivalent = "x"
    static let toggleConstructionShortcutModifiers: EventModifiers = [.command, .shift]

    static let hideSolidShortcutKey: KeyEquivalent = "h"
    static let hideSolidShortcutModifiers: EventModifiers = [.command, .shift]

    static let lockSolidShortcutKey: KeyEquivalent = "l"
    static let lockSolidShortcutModifiers: EventModifiers = [.command, .shift]

    static let reloadPartShortcutKey: KeyEquivalent = "r"
    static let reloadPartShortcutModifiers: EventModifiers = [.control, .command]

    static let rollBackToSelectedShortcutKey: KeyEquivalent = "["
    static let rollBackToSelectedShortcutModifiers: EventModifiers = [.command, .option]

    static let rollForwardToEndShortcutKey: KeyEquivalent = "]"
    static let rollForwardToEndShortcutModifiers: EventModifiers = [.command, .option]

    static let zoomInShortcutKey: KeyEquivalent = "="
    static let zoomInShortcutModifiers: EventModifiers = [.command]

    static let zoomOutShortcutKey: KeyEquivalent = "-"
    static let zoomOutShortcutModifiers: EventModifiers = [.command]

    static let zoomToFitShortcutKey: KeyEquivalent = "f"
    static let zoomToFitShortcutModifiers: EventModifiers = [.command, .shift]

    static let resetViewShortcutKey: KeyEquivalent = "0"
    static let resetViewShortcutModifiers: EventModifiers = [.command]

    static let mcpServerShortcutKey: KeyEquivalent = "m"
    static let mcpServerShortcutModifiers: EventModifiers = [.command, .shift]

    static let toolSelectShortcutKey: KeyEquivalent = "1"
    static let toolOrbitShortcutKey: KeyEquivalent = "2"
    static let toolPanShortcutKey: KeyEquivalent = "3"
    static let toolZoomShortcutKey: KeyEquivalent = "4"
    static let toolTrimShortcutKey: KeyEquivalent = "5"
    static let toolRectangleShortcutKey: KeyEquivalent = "6"
    static let toolShortcutModifiers: EventModifiers = [.command, .option]
    static let projectGeometryShortcutKey: KeyEquivalent = "j"
    static let projectGeometryShortcutModifiers: EventModifiers = [.command]

    // MARK: - Selection Filter Shortcuts (BL-SEL-06)

    static let filterFaceShortcutKey: KeyEquivalent = "f"
    static let filterEdgeShortcutKey: KeyEquivalent = "e"
    static let filterVertexShortcutKey: KeyEquivalent = "v"
    static let filterBodyShortcutKey: KeyEquivalent = "b"
    static let filterSketchShortcutKey: KeyEquivalent = "s"
    static let filterAllShortcutKey: KeyEquivalent = "a"
    static let filterShortcutModifiers: EventModifiers = [.option]

    // MARK: - View Navigation Shortcuts (BL-VPT-07)

    static let viewShortcutModifiers: EventModifiers = [.control]
    static let viewFrontShortcutKey: KeyEquivalent = "1"
    static let viewTopShortcutKey: KeyEquivalent = "2"
    static let viewRightShortcutKey: KeyEquivalent = "3"
    static let viewIsometricShortcutKey: KeyEquivalent = "7"
    static let viewNormalToShortcutKey: KeyEquivalent = "8"

    // MARK: - Console

    static let consoleShortcutKey: KeyEquivalent = "y"
    static let consoleShortcutModifiers: EventModifiers = [.command, .shift]

    var consoleToggleTitle: String {
        isConsoleVisible ? "Hide Console" : "Show Console"
    }

    var consoleToggleHelp: String {
        isConsoleVisible ? "Hide Console (⇧⌘Y)" : "Show Console (⇧⌘Y)"
    }

    /// Writes to the unified log (Console.app, `log stream`) and to the in-app console.
    func log(_ level: ConsoleLogLevel, _ subsystem: String, _ message: String) {
        Logger(subsystem: "com.made.app", category: subsystem).log(level: level.osLogType, "\(message, privacy: .public)")
        logs.append(ConsoleLogEntry(level: level, subsystem: subsystem, message: message))
        if logs.count > 200 { logs.removeFirst(50) }
    }

    func clearLogs() { logs.removeAll() }

    func toggleConsole() {
        withAnimation(.easeInOut(duration: 0.15)) { isConsoleVisible.toggle() }
        if isConsoleVisible {
            updateStats()
        }
    }

    // MARK: - Shortcuts Catalog

    public static let standardShortcuts: [ShortcutCheatsheetEntry] = [
        ShortcutCheatsheetEntry(title: "Select", shortcut: "V / ⌥⌘1", category: .tools, description: "Select tool — select and manipulate solids or gizmos"),
        ShortcutCheatsheetEntry(title: "Orbit", shortcut: "O / ⌥⌘2", category: .tools, description: "Orbit tool — orbit camera view around target or cursor"),
        ShortcutCheatsheetEntry(title: "Pan", shortcut: "P / ⌥⌘3", category: .tools, description: "Pan tool — pan camera view parallel to screen"),
        ShortcutCheatsheetEntry(title: "Zoom", shortcut: "Z / ⌥⌘4", category: .tools, description: "Zoom tool — drag to smoothly zoom in or out"),
        ShortcutCheatsheetEntry(title: "Rectangle", shortcut: "R / ⌥⌘6", category: .tools, description: "Rectangle tool — draw corner, center, or 3-point rectangles"),

        ShortcutCheatsheetEntry(title: "Filter Faces", shortcut: "⌥F", category: .editing, description: "Filter selection to faces"),
        ShortcutCheatsheetEntry(title: "Filter Edges", shortcut: "⌥E", category: .editing, description: "Filter selection to edges"),
        ShortcutCheatsheetEntry(title: "Filter Vertices", shortcut: "⌥V", category: .editing, description: "Filter selection to vertices"),
        ShortcutCheatsheetEntry(title: "Filter Bodies", shortcut: "⌥B", category: .editing, description: "Filter selection to solid bodies"),
        ShortcutCheatsheetEntry(title: "Filter Sketch Entities", shortcut: "⌥S", category: .editing, description: "Filter selection to sketch entities"),
        ShortcutCheatsheetEntry(title: "All Filters", shortcut: "⌥A", category: .editing, description: "Reset selection filters to allow all entities"),

        ShortcutCheatsheetEntry(title: "Reset View", shortcut: "⌘0", category: .navigation, description: "Reset camera to default perspective view"),
        ShortcutCheatsheetEntry(title: "Zoom to Fit", shortcut: "⇧⌘F", category: .navigation, description: "Frame all visible solids within viewport"),
        ShortcutCheatsheetEntry(title: "Zoom In", shortcut: "⌘=", category: .navigation, description: "Step zoom closer to scene center"),
        ShortcutCheatsheetEntry(title: "Zoom Out", shortcut: "⌘-", category: .navigation, description: "Step zoom further from scene center"),
        ShortcutCheatsheetEntry(title: "Front View", shortcut: "⌃1", category: .navigation, description: "Align camera to front plane (+Y view)"),
        ShortcutCheatsheetEntry(title: "Top View", shortcut: "⌃2", category: .navigation, description: "Align camera to top plane (+Z view)"),
        ShortcutCheatsheetEntry(title: "Right View", shortcut: "⌃3", category: .navigation, description: "Align camera to right plane (+X view)"),
        ShortcutCheatsheetEntry(title: "Isometric View", shortcut: "⌃7", category: .navigation, description: "Align camera to standard isometric viewpoint"),
        ShortcutCheatsheetEntry(title: "Normal To", shortcut: "⌃8", category: .navigation, description: "Align camera perpendicular to selected solid's active face or flip 180°"),

        ShortcutCheatsheetEntry(title: "Undo", shortcut: "⌘Z", category: .editing, description: "Undo last parameter, transform, add, or delete edit"),
        ShortcutCheatsheetEntry(title: "Redo", shortcut: "⇧⌘Z", category: .editing, description: "Redo previously undone edit"),
        ShortcutCheatsheetEntry(title: "Add Box", shortcut: "⇧⌘B", category: .editing, description: "Add new parametric box solid to document"),
        ShortcutCheatsheetEntry(title: "Add Cylinder", shortcut: "⇧⌘C", category: .editing, description: "Add new parametric cylinder solid to document"),
        ShortcutCheatsheetEntry(title: "Dimension Line", shortcut: "⇧⌘D", category: .editing, description: "Dimension selected 2D sketch line to target length"),
        ShortcutCheatsheetEntry(title: "Toggle Construction", shortcut: "⇧⌘X", category: .editing, description: "Toggle construction geometry for selected sketch entity"),
        ShortcutCheatsheetEntry(title: "Project Geometry", shortcut: "⌘J", category: .editing, description: "Project selected 3D model edge or upstream sketch entity into active sketch"),
        ShortcutCheatsheetEntry(title: "Hide/Show Solid", shortcut: "⇧⌘H", category: .editing, description: "Toggle visibility of selected solid"),
        ShortcutCheatsheetEntry(title: "Lock/Unlock Solid", shortcut: "⇧⌘L", category: .editing, description: "Toggle lock state of selected solid to prevent edits"),
        ShortcutCheatsheetEntry(title: "Reload Part", shortcut: "⌃⌘R", category: .editing, description: "Force recompute and rebuild active CAD part or script"),
        ShortcutCheatsheetEntry(title: "Roll Back to Selected", shortcut: "⌥⌘[", category: .editing, description: "Roll model timeline back to selected solid"),
        ShortcutCheatsheetEntry(title: "Roll Forward to End", shortcut: "⌥⌘]", category: .editing, description: "Roll model timeline forward to latest feature"),

        ShortcutCheatsheetEntry(title: "New Document", shortcut: "⌘N", category: .workspace, description: "Create a new CAD document with default scene solids"),
        ShortcutCheatsheetEntry(title: "Open Document", shortcut: "⌘O", category: .workspace, description: "Open a native .made CAD directory package"),
        ShortcutCheatsheetEntry(title: "Open Part Script", shortcut: "⌥⌘O", category: .workspace, description: "Open and live-watch a TypeScript or JavaScript CAD part script"),
        ShortcutCheatsheetEntry(title: "Save Document", shortcut: "⌘S", category: .workspace, description: "Save current document to its .made package"),
        ShortcutCheatsheetEntry(title: "Save As", shortcut: "⇧⌘S", category: .workspace, description: "Save current document to a new .made package location"),
        ShortcutCheatsheetEntry(title: "Toggle Console", shortcut: "⇧⌘Y", category: .workspace, description: "Toggle visibility of bottom telemetry and error console drawer"),
        ShortcutCheatsheetEntry(title: "MCP Server", shortcut: "⇧⌘M", category: .workspace, description: "Open MCP Server status popover and configuration"),
        ShortcutCheatsheetEntry(title: "Settings", shortcut: "⌘,", category: .workspace, description: "Open Made application preferences and settings window")
    ]

    public var shortcuts: [ShortcutCheatsheetEntry] { Self.standardShortcuts }
}

public enum ShortcutCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case tools = "Tools"
    case navigation = "Navigation"
    case editing = "Scene Editing"
    case workspace = "Workspace"

    public var id: String { rawValue }
}

public struct ShortcutCheatsheetEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let shortcut: String
    public let category: ShortcutCategory
    public let description: String

    public init(id: String? = nil, title: String, shortcut: String, category: ShortcutCategory, description: String) {
        self.id = id ?? "\(category.rawValue)-\(title)"
        self.title = title
        self.shortcut = shortcut
        self.category = category
        self.description = description
    }
}

public struct RadialMenuState: Equatable, Sendable {
    public var position: CGPoint
    public var targetSolidId: ObjectId?

    public init(position: CGPoint, targetSolidId: ObjectId? = nil) {
        self.position = position
        self.targetSolidId = targetSolidId
    }
}
