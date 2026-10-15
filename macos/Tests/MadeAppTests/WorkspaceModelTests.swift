import Testing
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct WorkspaceModelTests {
    @Test @MainActor func testSetTransformLogsConsoleEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        let initialLogsCount = model.logs.count

        var newTransform = Transform()
        newTransform.position = SIMD3<Float>(15.0, 0.0, 0.0)
        newTransform.scale = SIMD3<Float>(2.0, 2.0, 2.0)

        model.setTransform(id, newTransform)

        #expect(model.logs.count == initialLogsCount + 1)
        guard let lastLog = model.logs.last else {
            Issue.record("Expected log entry")
            return
        }
        #expect(lastLog.subsystem == "Scene")
        #expect(lastLog.level == .info)
        #expect(lastLog.message.contains("box-1"))
        #expect(lastLog.message.contains("15.0"))
        #expect(lastLog.message.contains("2.0"))
    }

    @Test @MainActor func testSetTransformUnchangedValueAddsNoLogEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        guard let current = model.document.objects.first(where: { $0.id == id }) else {
            Issue.record("Default box-1 not found")
            return
        }
        let initialLogsCount = model.logs.count

        model.setTransform(id, current.transform)

        #expect(model.logs.count == initialLogsCount)
    }

    @Test @MainActor func testSetTransformNonExistentIdAddsNoLogEntry() {
        let model = WorkspaceModel()
        let fakeId = ObjectId("nonexistent-solid-999")
        let initialLogsCount = model.logs.count

        model.setTransform(fakeId, Transform(position: SIMD3<Float>(10, 10, 10)))

        #expect(model.logs.count == initialLogsCount)
    }

    @Test @MainActor func testSetTransformLockedObjectAddsNoLogEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        model.document.setLocked(id: id, isLocked: true)
        let initialLogsCount = model.logs.count

        model.setTransform(id, Transform(position: SIMD3<Float>(50, 0, 0)))

        #expect(model.logs.count == initialLogsCount)
    }

    @Test @MainActor func testTelemetryInitialEmptyState() {
        let model = WorkspaceModel()
        #expect(model.kernelStats == KernelStats())
        #expect(model.kernelStats.dispatched == 0)
        #expect(model.kernelStats.conflated == 0)
        #expect(model.kernelStats.dropped == 0)
        #expect(model.kernelStats.completed == 0)
        #expect(model.renderStats.renderCount == 0)
        #expect(model.renderStats.drawCalls == 0)
        #expect(model.renderStats.lastReason == "init")
    }

    @Test @MainActor func testTelemetryReadsFromRenderInstrumentationAndKernelClient() async {
        let model = WorkspaceModel()
        RenderInstrumentation.shared.reset()
        RenderInstrumentation.shared.recordRender(drawCalls: 7)
        RenderInstrumentation.shared.recordInvalidation(reason: .camera)

        _ = await model.kernelClient.request(.makeBox(jobId: JobId("telemetry-read-box"), solidId: SolidId("t-box"), params: BoxParams(width: 10, depth: 10, height: 10)))
        await model.updateKernelStats()
        model.updateStats()
        await model.updateKernelStats()

        #expect(model.renderStats.renderCount == 1)
        #expect(model.renderStats.drawCalls == 7)
        #expect(model.renderStats.lastReason == "camera")
        #expect(model.kernelStats.dispatched >= 1)
        #expect(model.kernelStats.completed >= 1)
    }

    @Test @MainActor func testTelemetryDrawerHiddenWhenCountersChange() async {
        let model = WorkspaceModel()
        model.isConsoleVisible = false

        RenderInstrumentation.shared.reset()
        RenderInstrumentation.shared.recordRender(drawCalls: 4)
        RenderInstrumentation.shared.recordInvalidation(reason: .model)
        _ = await model.kernelClient.request(.makeBox(jobId: JobId("drawer-hidden-box"), solidId: SolidId("dh-box"), params: BoxParams(width: 12, depth: 12, height: 12)))

        model.updateStats()
        await model.updateKernelStats()

        #expect(model.renderStats.renderCount == 1)
        #expect(model.renderStats.drawCalls == 4)
        #expect(model.renderStats.lastReason == "model")
        #expect(model.kernelStats.dispatched >= 1)

        model.toggleConsole()
        #expect(model.isConsoleVisible == true)
        #expect(model.renderStats.drawCalls == 4)
        #expect(model.kernelStats.dispatched >= 1)
    }

    @Test @MainActor func testTelemetryWhenViewportUnavailable() async {
        let model = WorkspaceModel()
        model.viewportManager.state = .unavailable(reason: .noDevice)
        #expect(model.viewportManager.state.isUnavailable)

        model.updateStats()
        await model.updateKernelStats()

        #expect(model.renderStats.lastReason != "")
        #expect(model.kernelStats.dispatched >= 0)
    }

    @Test @MainActor func testTelemetrySuppressesRedundantUpdates() async {
        let model = WorkspaceModel()
        RenderInstrumentation.shared.reset()
        RenderInstrumentation.shared.recordRender(drawCalls: 3)
        RenderInstrumentation.shared.recordInvalidation(reason: .interaction)

        model.updateStats()
        await model.updateKernelStats()

        let initialRenderStats = model.renderStats
        let initialKernelStats = model.kernelStats

        // Second update without changes
        model.updateStats()
        await model.updateKernelStats()

        #expect(model.renderStats == initialRenderStats)
        #expect(model.kernelStats == initialKernelStats)
    }

    @Test @MainActor func testRapidParameterEditsConflateAndDispatchInKernelStats() async throws {
        let model = WorkspaceModel()
        model.setUp()
        let id = ObjectId("box-1")

        // Allow initial setUp recomputes to settle
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let initialConflated = model.kernelStats.conflated
        let initialDispatched = model.kernelStats.dispatched

        // Rapid setParam calls to trigger conflation (debounce is 60ms)
        model.setParam(id, "width", 25.0)
        model.setParam(id, "width", 30.0)
        model.setParam(id, "width", 35.0)

        // Await recomputes to settle
        try await Task.sleep(for: .milliseconds(250))
        await model.updateKernelStats()

        #expect(model.kernelStats.conflated > initialConflated)
        #expect(model.kernelStats.dispatched > initialDispatched)
    }

    @Test @MainActor func testToggleConsoleCyclesVisibility() {
        let model = WorkspaceModel()
        #expect(model.isConsoleVisible == false)

        model.toggleConsole()
        #expect(model.isConsoleVisible == true)

        model.toggleConsole()
        #expect(model.isConsoleVisible == false)
    }

    @Test @MainActor func testConsoleToggleTitlesAndShortcutConstants() {
        let model = WorkspaceModel()
        model.isConsoleVisible = false
        #expect(model.consoleToggleTitle == "Show Console")
        #expect(model.consoleToggleHelp == "Show Console (⇧⌘Y)")

        model.toggleConsole()
        #expect(model.consoleToggleTitle == "Hide Console")
        #expect(model.consoleToggleHelp == "Hide Console (⇧⌘Y)")

        #expect(WorkspaceModel.consoleShortcutKey == "y")
        #expect(WorkspaceModel.consoleShortcutModifiers == [.command, .shift])
    }
}
