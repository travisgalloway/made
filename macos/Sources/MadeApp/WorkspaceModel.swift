import SwiftUI
import AppKit
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
    private let faultInjector = FaultInjectingKernelClient(wrapping: KernelClient.makeDefault())
    var kernelClient: any KernelClientProtocol { faultInjector }
    #else
    let kernelClient: any KernelClientProtocol = KernelClient.makeDefault()
    #endif
    let partRuntime = PartRuntime()
    let viewportManager = ViewportStateManager()

    var selectedId: ObjectId? {
        get { document.selectedId }
        set { document.selectedId = newValue }
    }
    var pendingDeleteId: ObjectId?
    // Document Persistence & State
    var currentDocumentURL: URL?
    var isDocumentModified: Bool = false
    var autosaveDebounceNanoseconds: UInt64 = 2_000_000_000
    private var autosaveTask: Task<Void, Never>?

    var documentTitle: String {
        let base = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "Untitled Project"
        return isDocumentModified ? "\(base) — Edited" : base
    }
    var coordinator: CADMetalViewRepresentable.Coordinator?
    private(set) var renderStats = RenderStats()
    private(set) var kernelStats = KernelStats()
    var activeSnapKind: SnapKind?
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
    private(set) var perspective: ViewportPerspective = .perspective
    private(set) var projectionMode: CameraProjection = .perspective
    var tool: ViewportTool = .select {
        didSet {
            if tool != oldValue { log(.info, "Viewport", "Selected \(tool.title) tool") }
        }
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
    public static let linearToleranceDefaultsKey = "com.made.tolerances.linear"
    public static let angularToleranceDefaultsKey = "com.made.tolerances.angular"
    public static let chordalToleranceDefaultsKey = "com.made.tolerances.chordal"

    private let defaults: UserDefaults
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
    var kernelTolerances: KernelTolerances {
        didSet {
            let clamped = kernelTolerances.clamped()
            if kernelTolerances != clamped { kernelTolerances = clamped }
            defaults.set(kernelTolerances.linearTolerance, forKey: Self.linearToleranceDefaultsKey)
            defaults.set(kernelTolerances.angularTolerance, forKey: Self.angularToleranceDefaultsKey)
            defaults.set(kernelTolerances.chordalTolerance, forKey: Self.chordalToleranceDefaultsKey)
        }
    }
    var activeCommand: CommandSession?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

        let linear = defaults.object(forKey: Self.linearToleranceDefaultsKey) != nil ? defaults.double(forKey: Self.linearToleranceDefaultsKey) : KernelTolerances.defaultLinearTolerance
        let angular = defaults.object(forKey: Self.angularToleranceDefaultsKey) != nil ? defaults.double(forKey: Self.angularToleranceDefaultsKey) : KernelTolerances.defaultAngularTolerance
        let chordal = defaults.object(forKey: Self.chordalToleranceDefaultsKey) != nil ? defaults.double(forKey: Self.chordalToleranceDefaultsKey) : KernelTolerances.defaultChordalTolerance
        self.kernelTolerances = KernelTolerances(linearTolerance: linear, angularTolerance: angular, chordalTolerance: chordal).clamped()

        self.document.onUndoRedoMutation = { [weak self] mutation in
            self?.handleUndoRedoMutation(mutation)
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
        kernelTolerances = KernelTolerances.default
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

    var objectPendingDeletion: SceneObject? {
        guard let pendingDeleteId else { return nil }
        return document.objects.first { $0.id == pendingDeleteId }
    }

    // MARK: - Setup

    func setUp() {
        guard !isSetUp else { return }
        isSetUp = true

        _ = viewportManager.setup()
        if let renderer = viewportManager.renderer {
            renderer.showsGrid = showsGrid
            renderer.showsAxes = showsAxes
            let isLocked = selectedObject?.isLocked ?? false
            renderer.showsGizmo = showsGizmo && !isLocked
            self.camera = renderer.camera
        }
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

    /// A restarted kernel service holds no solids; resubmit each one, except the solid whose job stopped it.
    private func watchKernelRestarts() {
        Task { [weak self, kernelClient] in
            for await restart in await kernelClient.restarts() {
                guard let self else { return }
                let culprit = restart.excludedSolid.map { ", skipping \($0.rawValue)" } ?? ""
                self.log(.error, "Kernel", "Kernel service restarted (\(restart.reason))\(culprit); regenerating solids")
                for obj in self.document.objects where obj.id != restart.excludedSolid {
                    self.recomputeSolid(id: obj.id)
                }
            }
        }
    }

    // MARK: - Command Panel & Sessions

    func startCommand(_ session: CommandSession) {
        if activeCommand != nil {
            cancelActiveCommand()
        }
        activeCommand = session
        if session.isPreviewEnabled {
            session.onPreviewUpdate?()
        }
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
        guard let session = activeCommand else { return }
        let name = document.objects.first(where: { $0.id == id })?.name ?? id.rawValue
        if let activeIndex = session.selectionSlots.firstIndex(where: { $0.isActive }) {
            let activeSlotId = session.selectionSlots[activeIndex].id
            session.setSlotSelection(slotId: activeSlotId, objectId: id, objectName: name)
            if let nextEmpty = session.selectionSlots.firstIndex(where: { $0.selectedObjectId == nil }) {
                session.selectSlot(id: session.selectionSlots[nextEmpty].id)
            }
        } else if let emptyIndex = session.selectionSlots.firstIndex(where: { $0.selectedObjectId == nil }) {
            let emptySlotId = session.selectionSlots[emptyIndex].id
            session.setSlotSelection(slotId: emptySlotId, objectId: id, objectName: name)
            if let nextEmpty = session.selectionSlots.firstIndex(where: { $0.selectedObjectId == nil }) {
                session.selectSlot(id: session.selectionSlots[nextEmpty].id)
            }
        }
    }

    func startAddBoxCommand() {
        startCommand(CommandSession.makeAddBox(workspace: self))
    }

    func startAddCylinderCommand() {
        startCommand(CommandSession.makeAddCylinder(workspace: self))
    }

    func startTransformCommand() {
        startCommand(CommandSession.makeTransform(workspace: self, targetId: selectedId))
    }

    func startBooleanCommand() {
        startCommand(CommandSession.makeBoolean(workspace: self, selectedId: selectedId))
    }

    // MARK: - Scene editing

    // MARK: - Document Lifecycle & Autosave

    func markDocumentModified() {
        isDocumentModified = true
        syncWindowState()
        scheduleAutosaveIfNeeded()
    }

    func scheduleAutosaveIfNeeded() {
        guard currentDocumentURL != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.autosaveDebounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, self.isDocumentModified, let url = self.currentDocumentURL else { return }
            self.performAutosave(to: url)
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

        let defaultObjects = [
            SceneObject(
                id: boxSolidId,
                def: .box(BoxParams(width: 40, depth: 30, height: 20)),
                transform: Transform(position: SIMD3<Float>(-25, 0, 0))
            ),
            SceneObject(
                id: cylinderSolidId,
                def: .cylinder(CylinderParams(radius: 15, height: 40)),
                transform: Transform(position: SIMD3<Float>(25, 0, 0))
            )
        ]
        document.reset(with: defaultObjects, selectedId: boxSolidId)
        currentDocumentURL = nil
        isDocumentModified = false
        syncWindowState()
        log(.info, "Document", "Created new document")

        for obj in document.objects {
            recomputeSolid(id: obj.id)
        }
    }

    @discardableResult
    func openDocument(at url: URL) -> Bool {
        do {
            let package = try MadePackage(directoryURL: url)
            cancelActiveCommand()
            autosaveTask?.cancel()
            autosaveTask = nil

            self.lengthUnit = package.manifest.units.lengthUnit
            self.angleUnit = package.manifest.units.angleUnit
            self.decimalPrecision = package.manifest.units.decimalPrecision
            self.kernelTolerances = package.manifest.tolerances

            document.reset(with: package.documentData.objects, selectedId: package.documentData.selectedId)
            currentDocumentURL = url
            isDocumentModified = false
            syncWindowState()
            log(.info, "Document", "Opened document from \(url.lastPathComponent)")

            for obj in document.objects {
                recomputeSolid(id: obj.id)
            }
            return true
        } catch {
            log(.error, "Document", "Failed to open document: \(error.localizedDescription)")
            return false
        }
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
            let manifest = MadeManifest(
                schemaVersion: 1,
                appVersion: "0.1",
                units: UnitSettings(lengthUnit: lengthUnit, angleUnit: angleUnit, decimalPrecision: decimalPrecision),
                tolerances: kernelTolerances
            )
            let docData = DocumentData(schemaVersion: 1, objects: document.objects, selectedId: selectedId)

            var assets: [String: Data] = [:]
            for obj in document.objects {
                if case .imported(let name, let sourceURL, let data) = obj.def {
                    let filename = sourceURL?.lastPathComponent ?? (name.hasSuffix(".step") || name.hasSuffix(".stp") ? name : "\(name).step")
                    if let data {
                        assets[filename] = data
                    } else if let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path), let fileData = try? Data(contentsOf: sourceURL) {
                        assets[filename] = fileData
                    }
                }
            }

            var parts: [String: Data] = [:]
            for obj in document.objects {
                if case .part(let url, _) = obj.def {
                    let filename = url.lastPathComponent
                    if FileManager.default.fileExists(atPath: url.path), let fileData = try? Data(contentsOf: url) {
                        parts[filename] = fileData
                    }
                }
            }

            let package = MadePackage(manifest: manifest, documentData: docData, assets: assets, parts: parts)
            try package.write(to: destinationURL)

            currentDocumentURL = destinationURL
            isDocumentModified = false
            syncWindowState()
            log(.info, "Document", "Saved document to \(destinationURL.lastPathComponent)")
            return true
        } catch {
            log(.error, "Document", "Failed to save document: \(error.localizedDescription)")
            return false
        }
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

    func addDefaultBox() {
        addObject(.box(Self.defaultBoxParams))
    }

    func addDefaultCylinder() {
        addObject(.cylinder(Self.defaultCylinderParams))
    }

    func addObject(_ def: ObjectDef) {
        let id = document.addObject(def: def)
        selectedId = id
        markDocumentModified()
        log(.info, "Scene", "Added object \(id.rawValue)")
        recomputeSolid(id: id)
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
        importStepFile(at: url)
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
            return false
        }
        let result = await kernelClient.exportStep(objects: candidateObjects)
        switch result {
        case .success(_, let data):
            do {
                try data.write(to: url)
                log(.info, "Kernel", "Exported STEP to \(url.lastPathComponent)")
                return true
            } catch {
                log(.error, "Kernel", "Failed to write STEP file: \(error.localizedDescription)")
                return false
            }
        case .failure(_, let error):
            log(.error, "Kernel", "Failed to export STEP: \(error.message)")
            return false
        }
    }

    @discardableResult
    func importStepFile(at url: URL) -> ObjectId? {
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                log(.error, "Kernel", "STEP file is empty")
                return nil
            }
            let id = document.reserveId(for: .imported(name: url.lastPathComponent))
            document.addObject(id, def: .imported(name: url.lastPathComponent, sourceURL: url, data: data))
            selectedId = id
            markDocumentModified()
            recomputeSolid(id: id)
            log(.info, "Kernel", "Importing STEP file \(url.lastPathComponent) (\(id.rawValue))")
            return id
        } catch {
            log(.error, "Kernel", "Failed to import STEP file: \(error.localizedDescription)")
            return nil
        }
    }

    var canDeleteSelectedObject: Bool {
        guard let obj = selectedObject else { return false }
        return !obj.isLocked
    }

    func deleteSelectedObject() {
        guard let id = selectedId else { return }
        requestDeleteObject(id)
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

    @discardableResult
    func removeObject(_ id: ObjectId) -> Task<Void, Never> {
        guard let obj = document.objects.first(where: { $0.id == id }), !obj.isLocked else {
            return Task {}
        }
        let dependents = document.dependentObjects(of: id)
        partReloadController?.stopWatching(id: id)
        document.removeObject(id: id)
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
        markDocumentModified()
        log(.info, "Scene", "\(obj.isLocked ? "Unlocked" : "Locked") object \(id.rawValue)")
    }

    func setName(id: ObjectId, name: String) {
        guard let obj = document.objects.first(where: { $0.id == id }), obj.name != name else { return }
        document.setName(id: id, name: name)
        markDocumentModified()
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

    func setParam(_ id: ObjectId, _ key: String, _ value: Float) {
        let result = document.setParam(id: id, key: key, value: value)
        guard case .success = result else { return }
        markDocumentModified()
        log(.kernel, "CSG", "Updated \(id.rawValue) \(key) to \(String(format: "%.1f", value))")
        recomputeSolid(id: id)
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
        if let registry = toolRegistry {
            let task = registry.scheduleRecompute(id: id)
            Task { [weak self] in
                await Task.yield()
                await self?.updateKernelStats()
                _ = await task?.value
                await self?.updateKernelStats()
            }
            return
        }
        guard let request = KernelRegeneration.request(for: obj, jobId: JobId("job-\(UUID().uuidString)")) else { return }

        Task { [weak self] in
            guard let self else { return }
            let result = await self.kernelClient.request(request)
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
            if case .failure = result, case .imported = self.document.objects.first(where: { $0.id == id })?.def {
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
                    self.recomputeSolid(id: depId)
                }
            }
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

    func undo() {
        document.undo()
    }

    func redo() {
        document.redo()
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
        let code = KernelErrorCode.invalidParams
        Task { await faultInjector.failNextRequest(with: code) }
        log(.info, "Kernel", "Next recompute will fail with \(code.rawValue)")
    }
    #endif

    // MARK: - Viewport

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

    func alignNormalTo() {
        let currentCamera = viewportManager.renderer?.camera ?? camera
        let target: SIMD3<Float>
        var normal: SIMD3<Float>

        if let selected = selectedObject {
            target = selected.transform.position
            normal = simd_normalize(selected.transform.rotation.act(Orientation.worldUp))
            let eyeVec = currentCamera.position - target
            let eyeDist = simd_length(eyeVec)
            if eyeDist > 1e-4 {
                let eyeDir = simd_normalize(eyeVec)
                if simd_dot(eyeDir, normal) > 0.99 {
                    normal = -normal
                }
            }
        } else {
            target = currentCamera.target
            normal = Orientation.groundNormal
            let eyeVec = currentCamera.position - target
            let eyeDist = simd_length(eyeVec)
            if eyeDist > 1e-4 {
                let eyeDir = simd_normalize(eyeVec)
                if simd_dot(eyeDir, normal) > 0.99 {
                    normal = -normal
                }
            }
        }

        let currentDist = max(1.0, simd_length(currentCamera.position - currentCamera.target))
        var eyePosition = target + normal * currentDist

        // Singular look-at protection: if |normal.z| > 0.999, add 0.001 Y offset
        if abs(normal.z) > 0.999 {
            eyePosition.y += 0.001
        }

        let newCamera = Camera(
            position: eyePosition,
            target: target,
            minDistance: currentCamera.minDistance,
            maxDistance: currentCamera.maxDistance,
            minPitch: currentCamera.minPitch,
            maxPitch: currentCamera.maxPitch,
            projection: projectionMode,
            orthographicScale: currentCamera.orthographicScale
        )

        if let renderer = viewportManager.renderer {
            renderer.camera = newCamera
        }
        self.camera = newCamera
        log(.info, "Camera", "Aligned normal to \(selectedObject?.name ?? "ground plane")")
        invalidateViewport(.camera)
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
        activeSnapKind = result?.kind
        if let result { log(.snap, "Snapping", "Snapped to \(result.kind.rawValue)") }
    }

    func invalidateViewport(_ reason: InvalidateReason) {
        if let coordinator {
            coordinator.invalidate(reason: reason)
        } else {
            RenderInstrumentation.shared.recordInvalidation(reason: reason)
            updateStats()
        }
    }

    func updateStats() {
        let shared = RenderInstrumentation.shared
        let nextRenderStats = RenderStats(
            renderCount: shared.renderCount,
            drawCalls: shared.drawCalls,
            lastReason: shared.lastReason?.rawValue ?? "idle"
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

    static let hideSolidShortcutKey: KeyEquivalent = "h"
    static let hideSolidShortcutModifiers: EventModifiers = [.command, .shift]

    static let lockSolidShortcutKey: KeyEquivalent = "l"
    static let lockSolidShortcutModifiers: EventModifiers = [.command, .shift]

    static let reloadPartShortcutKey: KeyEquivalent = "r"
    static let reloadPartShortcutModifiers: EventModifiers = [.control, .command]

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
    static let toolShortcutModifiers: EventModifiers = [.command, .option]

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
        ShortcutCheatsheetEntry(title: "Hide/Show Solid", shortcut: "⇧⌘H", category: .editing, description: "Toggle visibility of selected solid"),
        ShortcutCheatsheetEntry(title: "Lock/Unlock Solid", shortcut: "⇧⌘L", category: .editing, description: "Toggle lock state of selected solid to prevent edits"),
        ShortcutCheatsheetEntry(title: "Reload Part", shortcut: "⌃⌘R", category: .editing, description: "Force recompute and rebuild active CAD part or script"),

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
