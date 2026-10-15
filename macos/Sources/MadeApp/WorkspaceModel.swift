import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MadeCore
import os

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

    // MARK: - Scene editing

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
            log(.info, "Part", "Watching \(url.lastPathComponent) (\(id.rawValue))")
            return id
        } else {
            let id = document.addPart(url: url)
            selectedId = id
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

    func removeObject(_ id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }), !obj.isLocked else { return }
        partReloadController?.stopWatching(id: id)
        document.removeObject(id: id)
        Task { await kernelClient.dispose(solidId: id) }
        recomputeFailures.clear(id)
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.remove(id: id, from: renderer)
        }
        log(.info, "Scene", "Removed object \(id.rawValue)")
        invalidateViewport(.model)
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
        document.setVisibility(id: id, isVisible: visible)
        if visible {
            viewportManager.renderer?.hiddenSolidIds.remove(id)
        } else {
            viewportManager.renderer?.hiddenSolidIds.insert(id)
        }
        log(.info, "Scene", "\(visible ? "Showed" : "Hid") object \(id.rawValue)")
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
        log(.info, "Scene", "\(obj.isLocked ? "Unlocked" : "Locked") object \(id.rawValue)")
    }

    private func formatVec3(_ v: SIMD3<Float>) -> String {
        String(format: "(%.1f, %.1f, %.1f)", v.x, v.y, v.z)
    }

    func setTransform(_ id: ObjectId, _ transform: Transform) {
        guard let current = document.objects.first(where: { $0.id == id }),
              current.transform != transform else { return }
        let result = document.setTransform(id: id, transform: transform)
        guard case .success = result else { return }
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.applyTransform(to: id, document: document, sink: renderer)
        }
        log(.info, "Scene", "Updated \(id.rawValue) transform to position \(formatVec3(transform.position)) scale \(formatVec3(transform.scale))")
        invalidateViewport(.model)
    }

    func setMaterial(_ id: ObjectId, _ material: MaterialAttributes) {
        let result = document.setMaterial(id: id, material: material)
        guard case .success = result else { return }
        if let renderer = viewportManager.renderer {
            _ = SolidMeshApplier.applyMaterial(to: id, document: document, sink: renderer)
        }
        log(.info, "Scene", "Updated material for \(id.rawValue)")
        invalidateViewport(.model)
    }

    func setParam(_ id: ObjectId, _ key: String, _ value: Float) {
        let result = document.setParam(id: id, key: key, value: value)
        guard case .success = result else { return }
        log(.kernel, "CSG", "Updated \(id.rawValue) \(key) to \(String(format: "%.1f", value))")
        recomputeSolid(id: id)
    }

    /// Drops meshes for objects removed by any path, including MCP agent tools.
    func syncMeshes(removedFrom old: [SceneObject], to new: [SceneObject]) {
        let remaining = Set(new.map(\.id))
        for obj in old where !remaining.contains(obj.id) {
            partReloadController?.stopWatching(id: obj.id)
            Task { await kernelClient.dispose(solidId: obj.id) }
            if let renderer = viewportManager.renderer, SolidMeshApplier.remove(id: obj.id, from: renderer) {
                invalidateViewport(.model)
            }
            recomputeFailures.clear(obj.id)
        }
        partReloadController?.syncWithDocument()
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
            guard let renderer = self.viewportManager.renderer,
                  SolidMeshApplier.apply(result, to: id, document: self.document, sink: renderer) else { return }
            self.invalidateViewport(.model)
        }
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
        guard let renderer = viewportManager.renderer else { return }
        renderer.projectionMode = mode
        renderer.camera.orthographicScale = 1.0
        log(.info, "Camera", "Switched projection to \(mode.rawValue)")
        invalidateViewport(.camera)
    }

    func applyPerspective(_ perspective: ViewportPerspective) {
        self.perspective = perspective
        guard let renderer = viewportManager.renderer else { return }
        renderer.camera = Camera.preset(perspective)
        renderer.projectionMode = projectionMode
        log(.info, "Camera", "Switched to \(perspective.rawValue) perspective")
        invalidateViewport(.camera)
    }

    func resetView() { applyPerspective(.perspective) }
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
}
