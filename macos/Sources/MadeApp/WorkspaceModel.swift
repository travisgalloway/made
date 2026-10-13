import SwiftUI
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
    let viewportManager = ViewportStateManager()

    var selectedId: ObjectId? = boxSolidId
    var coordinator: CADMetalViewRepresentable.Coordinator?
    private(set) var renderStats = RenderStats()
    var activeSnapKind: SnapKind?
    /// Last failed recompute per solid, shown in the Inspector (invariant 3: panels only).
    private(set) var recomputeFailures = RecomputeFailures()

    // Layout
    var columnVisibility: NavigationSplitViewVisibility = .all
    var isInspectorPresented = true
    var isConsoleVisible = false

    // Viewport
    private(set) var perspective: ViewportPerspective = .perspective
    var tool: ViewportTool = .select {
        didSet {
            if tool != oldValue { log(.info, "Viewport", "Selected \(tool.title) tool") }
        }
    }

    // Console
    private(set) var logs: [ConsoleLogEntry] = [
        ConsoleLogEntry(level: .info, subsystem: "App", message: "made macOS workspace initialized")
    ]

    // MCP
    private(set) var toolRegistry: CADToolRegistry?
    private(set) var mcpServer: MCPServer?
    private(set) var isMCPServerRunning = false
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

    // MARK: - Setup

    func setUp() {
        guard !isSetUp else { return }
        isSetUp = true

        _ = viewportManager.setup()
        viewportManager.renderer?.onDeviceLost = { [weak viewportManager] in
            Task { @MainActor in viewportManager?.handleDeviceLost() }
        }

        let registry = CADToolRegistry(document: document, kernelClient: kernelClient, snapshotProvider: viewportManager.renderer)
        toolRegistry = registry
        let server = MCPServer(toolRegistry: registry)
        server.onStateChange = { @Sendable [weak self] running in
            Task { @MainActor in self?.isMCPServerRunning = running }
        }
        mcpServer = server

        for obj in document.objects { recomputeSolid(id: obj.id) }
        log(.info, "Metal", "Metal 4 pipeline initialized")
        watchKernelRestarts()
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

    func addObject(_ def: ObjectDef) {
        let id = document.addObject(def: def)
        selectedId = id
        log(.info, "Scene", "Added object \(id.rawValue)")
        recomputeSolid(id: id)
    }

    func removeObject(_ id: ObjectId) {
        document.removeObject(id: id)
        Task { await kernelClient.dispose(solidId: id) }
        recomputeFailures.clear(id)
        viewportManager.renderer?.meshes.removeValue(forKey: id)
        if selectedId == id { selectedId = document.objects.first?.id }
        log(.info, "Scene", "Removed object \(id.rawValue)")
        invalidateViewport(.model)
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

    func toggleLock(_ id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        document.setLocked(id: id, isLocked: !obj.isLocked)
        log(.info, "Scene", "\(obj.isLocked ? "Unlocked" : "Locked") object \(id.rawValue)")
    }

    func setTransform(_ id: ObjectId, _ transform: Transform) {
        document.setTransform(id: id, transform: transform)
        if var mesh = viewportManager.renderer?.meshes[id] {
            mesh.transform = transform
            mesh.candidateMesh.transform = transform
            viewportManager.renderer?.meshes[id] = mesh
        }
        invalidateViewport(.model)
    }

    func setParam(_ id: ObjectId, _ key: String, _ value: Float) {
        document.setParam(id: id, key: key, value: value)
        log(.kernel, "CSG", "Updated \(id.rawValue) \(key) to \(String(format: "%.1f", value))")
        recomputeSolid(id: id)
    }

    /// Drops meshes for objects removed by any path, including MCP agent tools.
    func syncMeshes(removedFrom old: [SceneObject], to new: [SceneObject]) {
        let remaining = Set(new.map(\.id))
        for obj in old where !remaining.contains(obj.id) {
            viewportManager.renderer?.meshes.removeValue(forKey: obj.id)
            recomputeFailures.clear(obj.id)
            invalidateViewport(.model)
        }
    }

    private func recomputeSolid(id: ObjectId) {
        guard let obj = document.objects.first(where: { $0.id == id }) else { return }
        guard let request = KernelRegeneration.request(for: obj, jobId: JobId("job-\(UUID().uuidString)")) else { return }

        Task {
            let result = await kernelClient.request(request)
            // The solid was removed while the request was in flight; release what it repopulated.
            guard document.objects.contains(where: { $0.id == id }) else {
                await kernelClient.dispose(solidId: id)
                return
            }
            // A failure leaves the previous mesh installed; only the message changes.
            if let message = recomputeFailures.record(result, for: id) {
                log(.error, "Kernel", message)
            }
            guard let renderer = viewportManager.renderer,
                  SolidMeshApplier.apply(result, to: id, document: document, sink: renderer) else { return }
            invalidateViewport(.model)
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

    func applyPerspective(_ perspective: ViewportPerspective) {
        self.perspective = perspective
        guard let renderer = viewportManager.renderer else { return }
        renderer.camera = Camera.preset(perspective)
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
        renderStats = RenderStats(
            renderCount: shared.renderCount,
            drawCalls: shared.drawCalls,
            lastReason: shared.lastReason?.rawValue ?? "idle"
        )
    }

    // MARK: - MCP

    func toggleMCPServer() {
        guard let server = mcpServer else { return }
        if isMCPServerRunning {
            server.stop()
            isMCPServerRunning = false
            log(.info, "MCP", "Stopped MCP server")
        } else {
            do {
                try server.start(port: mcpPort)
                isMCPServerRunning = true
                log(.info, "MCP", "Started MCP server on port \(mcpPort)")
            } catch {
                log(.error, "MCP", "Failed to start MCP server: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Console

    /// Writes to the unified log (Console.app, `log stream`) and to the in-app console.
    func log(_ level: ConsoleLogLevel, _ subsystem: String, _ message: String) {
        Logger(subsystem: "com.made.app", category: subsystem).log(level: level.osLogType, "\(message, privacy: .public)")
        logs.append(ConsoleLogEntry(level: level, subsystem: subsystem, message: message))
        if logs.count > 200 { logs.removeFirst(50) }
    }

    func clearLogs() { logs.removeAll() }

    func toggleConsole() {
        withAnimation(.easeInOut(duration: 0.15)) { isConsoleVisible.toggle() }
    }
}
