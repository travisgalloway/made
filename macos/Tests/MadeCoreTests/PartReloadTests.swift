import Testing
import Foundation
import Darwin
import Synchronization
import simd
@testable import MadeCore

@MainActor
private final class RecordingMeshSink: SolidMeshSink {
    struct InstalledMesh: Sendable {
        let payload: MeshPayload
        let transform: Transform
        let color: SIMD4<Float>
        let isHidden: Bool

        var xExtent: Float {
            guard !payload.positions.isEmpty else { return 0 }
            var minX = Float.greatestFiniteMagnitude
            var maxX = -Float.greatestFiniteMagnitude
            for i in stride(from: 0, to: payload.positions.count, by: 3) {
                let x = payload.positions[i]
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            return maxX - minX
        }
    }

    var installed: [SolidId: InstalledMesh] = [:]
    var installCount = 0

    func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool {
        installCount += 1
        installed[id] = InstalledMesh(payload: payload, transform: transform, color: color, isHidden: isHidden)
        return true
    }

    func updateTransform(_ transform: Transform, for id: SolidId) -> Bool {
        guard let existing = installed[id] else { return false }
        installed[id] = InstalledMesh(
            payload: existing.payload,
            transform: transform,
            color: existing.color,
            isHidden: existing.isHidden
        )
        return true
    }

    func removeMesh(for id: SolidId) -> Bool {
        installed.removeValue(forKey: id) != nil
    }
}

/// Wraps `LocalKernelEngine` and records whether any evaluation ran on the main thread, plus optional delay injection.
private actor InstrumentedShapeEngine: KernelEngine {
    private let inner = LocalKernelEngine()
    private nonisolated let ranOnMainThreadFlag = Mutex(false)
    private nonisolated let evaluateShapeCount = Mutex(0)
    private nonisolated let delayFirstShapeEval = Mutex<Duration?>(nil)

    nonisolated var ranOnMainThread: Bool {
        ranOnMainThreadFlag.withLock { $0 }
    }

    nonisolated var shapeEvaluations: Int {
        evaluateShapeCount.withLock { $0 }
    }

    nonisolated func setNextShapeEvalDelay(_ delay: Duration?) {
        delayFirstShapeEval.withLock { $0 = delay }
    }

    func execute(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        if pthread_main_np() != 0 {
            ranOnMainThreadFlag.withLock { $0 = true }
        }
        if case .evaluateShape = request {
            evaluateShapeCount.withLock { $0 += 1 }
            let delay = delayFirstShapeEval.withLock { current -> Duration? in
                let d = current
                current = nil
                return d
            }
            if let delay {
                try? await Task.sleep(for: delay)
            }
        }
        return await inner.execute(request)
    }

    func dispose(solidId: SolidId) async {
        await inner.dispose(solidId: solidId)
    }

    func terminate(jobId: JobId) async -> Bool {
        await inner.terminate(jobId: jobId)
    }

    nonisolated func restarts() -> AsyncStream<KernelRestart> {
        inner.restarts()
    }

    func storeCounts() async -> KernelEngineCounts {
        await inner.storeCounts()
    }
}

/// Tests for `.part.ts` / `.part.js` file watching, 60-ms save debounce, off-main-thread reload,
/// single viewport redraw on success, preserving last good model on failure, and `file:line:column` diagnostics (#427).
@MainActor
@Suite struct PartReloadTests {
    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("made-part-reload-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(10),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return condition()
    }

    // MARK: - 1. Valid Edit Live Reload (.part.ts and .part.js)

    @Test func testValidEditToTypeScriptAndJavaScriptPartReloadsMeshAndRedrawsOnceWithinOneSecond() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tsFile = dir.appendingPathComponent("plate.part.ts")
        try """
        import { Box, type Shape } from 'made';
        const plate: Shape = Box({ width: 20, depth: 30, height: 10 });
        export default plate;
        """.write(to: tsFile, atomically: true, encoding: .utf8)

        let engine = InstrumentedShapeEngine()
        let kernel = KernelClient(engine: engine, debounceDuration: .milliseconds(60))
        let runtime = PartRuntime(kernelClient: kernel)
        let doc = DocumentModel()
        let sink = RecordingMeshSink()
        var redrawCount = 0
        var recordedErrors: [(ObjectId, PartRuntimeError)] = []

        let controller = PartReloadController(
            document: doc,
            partRuntime: runtime,
            kernelClient: kernel,
            meshSink: sink,
            debounceDuration: .milliseconds(60),
            onViewportInvalidated: { redrawCount += 1 },
            onReloadResult: { result, id in
                if case .failure(_, let err) = result, err.code != .cancelled {
                    recordedErrors.append((id, err))
                }
            }
        )
        defer { controller.stopAll() }

        let partId = controller.openPartFile(at: tsFile)
        let initialLoaded = await waitUntil {
            sink.installed[partId] != nil
        }
        #expect(initialLoaded)
        #expect(abs((sink.installed[partId]?.xExtent ?? 0) - 20) < 0.01)
        #expect(redrawCount == 1)
        #expect(!engine.ranOnMainThread)
        #expect(controller.lastOutputs[partId]?.evaluatedOnMainThread == false)

        // Save a valid edit on disk changing width from 20 to 64.
        let saveStart = ContinuousClock.now
        try """
        import { Box, type Shape } from 'made';
        const plate: Shape = Box({ width: 64, depth: 30, height: 10 });
        export default plate;
        """.write(to: tsFile, atomically: true, encoding: .utf8)

        let reloaded = await waitUntil(timeout: .seconds(1)) {
            abs((sink.installed[partId]?.xExtent ?? 0) - 64) < 0.01
        }
        let elapsed = saveStart.duration(to: ContinuousClock.now)
        #expect(reloaded)
        #expect(elapsed < .seconds(1))
        #expect(redrawCount == 2)
        #expect(recordedErrors.isEmpty)
        #expect(controller.failures.message(for: partId) == nil)
        #expect(!engine.ranOnMainThread)
        #expect(controller.lastOutputs[partId]?.evaluatedOnMainThread == false)

        if case .part(_, let shape?) = doc.objects.first(where: { $0.id == partId })?.def,
           case .box(let params) = shape {
            #expect(params == BoxParams(width: 64, depth: 30, height: 10))
        } else {
            Issue.record("Expected .part object with updated ShapeNode")
        }

        // Also verify plain .part.js live reload.
        let jsFile = dir.appendingPathComponent("rod.part.js")
        try """
        import { Box } from 'made';
        export default Box(15, 15, 40);
        """.write(to: jsFile, atomically: true, encoding: .utf8)

        let jsId = controller.openPartFile(at: jsFile)
        #expect(await waitUntil { sink.installed[jsId] != nil })
        #expect(abs((sink.installed[jsId]?.xExtent ?? 0) - 15) < 0.01)

        try """
        import { Box } from 'made';
        export default Box(42, 15, 40);
        """.write(to: jsFile, atomically: true, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(1)) {
            abs((sink.installed[jsId]?.xExtent ?? 0) - 42) < 0.01
        })
        #expect(!engine.ranOnMainThread)
    }

    // MARK: - 2. Invalid Edit Preserves Last Good Model and Reports file:line:column

    @Test func testInvalidEditKeepsLastGoodModelOnScreenAndReportsFileLineColumnDiagnostic() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let partFile = dir.appendingPathComponent("housing.part.ts")
        try """
        import { Box } from 'made';
        export default Box({ width: 32, depth: 20, height: 12 });
        """.write(to: partFile, atomically: true, encoding: .utf8)

        let kernel = KernelClient(engine: LocalKernelEngine(), debounceDuration: .milliseconds(15))
        let runtime = PartRuntime(kernelClient: kernel)
        let doc = DocumentModel()
        let sink = RecordingMeshSink()
        var redrawCount = 0
        var latestErrors: [PartRuntimeError] = []

        let controller = PartReloadController(
            document: doc,
            partRuntime: runtime,
            kernelClient: kernel,
            meshSink: sink,
            debounceDuration: .milliseconds(30),
            onViewportInvalidated: { redrawCount += 1 },
            onReloadResult: { result, _ in
                if case .failure(_, let err) = result, err.code != .cancelled {
                    latestErrors.append(err)
                }
            }
        )
        defer { controller.stopAll() }

        let partId = controller.openPartFile(at: partFile)
        #expect(await waitUntil { sink.installed[partId] != nil })
        #expect(abs((sink.installed[partId]?.xExtent ?? 0) - 32) < 0.01)
        #expect(redrawCount == 1)
        #expect(sink.installCount == 1)

        // 1. Save a syntax error on line 3.
        try """
        import { Box } from 'made';
        const w: number = 32;
        export default Box({ width: w, depth:
        """.write(to: partFile, atomically: true, encoding: .utf8)

        #expect(await waitUntil { latestErrors.count == 1 })
        // Last good mesh and shape remain intact, and viewport was not invalidated for the failed reload.
        #expect(abs((sink.installed[partId]?.xExtent ?? 0) - 32) < 0.01)
        #expect(redrawCount == 1)
        #expect(sink.installCount == 1)
        if case .part(_, let shape?) = doc.objects.first(where: { $0.id == partId })?.def,
           case .box(let params) = shape {
            #expect(params == BoxParams(width: 32, depth: 20, height: 12))
        } else {
            Issue.record("Expected last good ShapeNode to remain on DocumentModel")
        }

        let syntaxErr = try #require(latestErrors.last)
        #expect(syntaxErr.code == .syntaxError)
        #expect(syntaxErr.diagnostic.file.hasSuffix("housing.part.ts"))
        #expect(syntaxErr.diagnostic.line == 3)
        #expect(syntaxErr.diagnostic.column >= 1)
        #expect(controller.failures.message(for: partId)?.contains("housing.part.ts:3:") == true)

        // 2. Save a runtime error on line 4.
        try """
        import { Box } from 'made';
        function makeBroken(): any {
          const scale = 2;
          throw new Error('negative wall thickness');
        }
        export default makeBroken();
        """.write(to: partFile, atomically: true, encoding: .utf8)

        #expect(await waitUntil { latestErrors.count == 2 })
        #expect(abs((sink.installed[partId]?.xExtent ?? 0) - 32) < 0.01)
        #expect(redrawCount == 1)

        let runtimeErr = try #require(latestErrors.last)
        #expect(runtimeErr.code == .scriptError)
        #expect(runtimeErr.diagnostic.file.hasSuffix("housing.part.ts"))
        #expect(runtimeErr.diagnostic.line == 4)
        #expect(runtimeErr.diagnostic.column >= 1)
        #expect(runtimeErr.diagnostic.message.contains("negative wall thickness"))
        #expect(controller.failures.message(for: partId)?.contains("housing.part.ts:4:") == true)

        // 3. Save a valid edit (width 48) and verify failure clears and viewport redraws once.
        try """
        import { Box } from 'made';
        export default Box({ width: 48, depth: 20, height: 12 });
        """.write(to: partFile, atomically: true, encoding: .utf8)

        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 48) < 0.01 })
        #expect(controller.failures.message(for: partId) == nil)
        #expect(controller.lastErrors[partId] == nil)
        #expect(redrawCount == 2)
        #expect(sink.installCount == 2)
    }

    // MARK: - 3. Rapid Saves Conflate Within 60-ms Debounce Window

    @Test func testRapidSavesWithinDebounceWindowConflateToLatestFileContentsAndRedrawOnce() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let partFile = dir.appendingPathComponent("rapid.part.ts")
        try """
        import { Box } from 'made';
        export default Box(20, 20, 20);
        """.write(to: partFile, atomically: true, encoding: .utf8)

        let engine = InstrumentedShapeEngine()
        let kernel = KernelClient(engine: engine, debounceDuration: .milliseconds(60))
        let runtime = PartRuntime(kernelClient: kernel)
        let doc = DocumentModel()
        let sink = RecordingMeshSink()
        var redrawCount = 0

        let controller = PartReloadController(
            document: doc,
            partRuntime: runtime,
            kernelClient: kernel,
            meshSink: sink,
            debounceDuration: .milliseconds(60),
            onViewportInvalidated: { redrawCount += 1 }
        )
        defer { controller.stopAll() }

        let partId = controller.openPartFile(at: partFile)
        #expect(await waitUntil { sink.installed[partId] != nil })
        #expect(redrawCount == 1)
        #expect(engine.shapeEvaluations == 1)

        // Perform 4 rapid saves back-to-back within the 60-ms debounce window, including a transient syntax error.
        try "import { Box } from 'made'; export default Box(30, 20, 20);".write(to: partFile, atomically: true, encoding: .utf8)
        try "import { Box } from 'made'; export default Box(broken".write(to: partFile, atomically: true, encoding: .utf8)
        try "import { Box } from 'made'; export default Box(50, 20, 20);".write(to: partFile, atomically: true, encoding: .utf8)
        try "import { Box } from 'made'; export default Box(75, 20, 20);".write(to: partFile, atomically: true, encoding: .utf8)

        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 75) < 0.01 })
        // Give a short settle window to verify no extra evaluations or redraws occur.
        try? await Task.sleep(for: .milliseconds(100))

        #expect(redrawCount == 2)
        #expect(sink.installCount == 2)
        #expect(engine.shapeEvaluations == 2)
        #expect(controller.failures.message(for: partId) == nil)
    }

    // MARK: - 4. Superseded In-Flight Evaluation Discarded by JobId

    @Test func testSupersededInFlightEvaluationIsDiscardedByJobId() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let partFile = dir.appendingPathComponent("inflight.part.ts")
        try "import { Box } from 'made'; export default Box(18, 18, 18);".write(to: partFile, atomically: true, encoding: .utf8)

        let engine = InstrumentedShapeEngine()
        let kernel = KernelClient(engine: engine, debounceDuration: .milliseconds(10))
        let runtime = PartRuntime(kernelClient: kernel)
        let doc = DocumentModel()
        let sink = RecordingMeshSink()
        var redrawCount = 0

        let controller = PartReloadController(
            document: doc,
            partRuntime: runtime,
            kernelClient: kernel,
            meshSink: sink,
            debounceDuration: .milliseconds(15),
            onViewportInvalidated: { redrawCount += 1 }
        )
        defer { controller.stopAll() }

        let partId = controller.openPartFile(at: partFile)
        #expect(await waitUntil { sink.installed[partId] != nil })
        #expect(redrawCount == 1)

        // Slow down the next kernel evaluation so a newer save arrives while the first reload is in flight.
        engine.setNextShapeEvalDelay(.milliseconds(180))
        try "import { Box } from 'made'; export default Box(36, 18, 18);".write(to: partFile, atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .milliseconds(40))
        try "import { Box } from 'made'; export default Box(82, 18, 18);".write(to: partFile, atomically: true, encoding: .utf8)

        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 82) < 0.01 })
        try? await Task.sleep(for: .milliseconds(80))

        #expect(abs((sink.installed[partId]?.xExtent ?? 0) - 82) < 0.01)
        #expect(redrawCount == 2)
        #expect(controller.failures.message(for: partId) == nil)
    }

    // MARK: - 5. Relative Helper Module Watching and Error Mapping

    @Test func testEditingImportedHelperModuleReloadsPartAndMapsHelperErrorLocation() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let helperFile = dir.appendingPathComponent("dimensions.ts")
        let partFile = dir.appendingPathComponent("flange.part.ts")

        try """
        export const flangeWidth: number = 26;
        """.write(to: helperFile, atomically: true, encoding: .utf8)

        try """
        import { Box } from 'made';
        import { flangeWidth } from './dimensions';
        export default Box(flangeWidth, 20, 10);
        """.write(to: partFile, atomically: true, encoding: .utf8)

        let kernel = KernelClient(engine: LocalKernelEngine(), debounceDuration: .milliseconds(15))
        let runtime = PartRuntime(kernelClient: kernel)
        let doc = DocumentModel()
        let sink = RecordingMeshSink()

        let controller = PartReloadController(
            document: doc,
            partRuntime: runtime,
            kernelClient: kernel,
            meshSink: sink,
            debounceDuration: .milliseconds(25)
        )
        defer { controller.stopAll() }

        let partId = controller.openPartFile(at: partFile)
        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 26) < 0.01 })

        // Edit the imported helper module on disk; the parent part should automatically reload!
        try """
        export const flangeWidth: number = 58;
        """.write(to: helperFile, atomically: true, encoding: .utf8)

        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 58) < 0.01 })
        #expect(controller.failures.message(for: partId) == nil)

        // Break the helper module on line 2; last good mesh (58) stays on screen and diagnostic points to dimensions.ts:2.
        try """
        export const flangeWidth: number = 58;
        throw new Error('helper calibration failed');
        """.write(to: helperFile, atomically: true, encoding: .utf8)

        #expect(await waitUntil { controller.failures.message(for: partId) != nil })
        #expect(abs((sink.installed[partId]?.xExtent ?? 0) - 58) < 0.01)
        let message = try #require(controller.failures.message(for: partId))
        #expect(message.contains("dimensions.ts:2:"))
        #expect(message.contains("helper calibration failed"))
    }

    // MARK: - 6. In-Place Writes, Atomic Saves, Delete/Recreate, and Unrelated Sibling Isolation

    @Test func testInPlaceWriteAtomicRenameAndDeleteRecreateAreObservedWhileSiblingFilesAreIgnored() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let partFile = dir.appendingPathComponent("block.part.ts")
        let siblingFile = dir.appendingPathComponent("notes.txt")
        try "import { Box } from 'made'; export default Box(20, 10, 10);".write(to: partFile, atomically: true, encoding: .utf8)

        let engine = InstrumentedShapeEngine()
        let kernel = KernelClient(engine: engine, debounceDuration: .milliseconds(15))
        let runtime = PartRuntime(kernelClient: kernel)
        let doc = DocumentModel()
        let sink = RecordingMeshSink()

        let controller = PartReloadController(
            document: doc,
            partRuntime: runtime,
            kernelClient: kernel,
            meshSink: sink,
            debounceDuration: .milliseconds(25)
        )
        defer { controller.stopAll() }

        let partId = controller.openPartFile(at: partFile)
        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 20) < 0.01 })
        let evalsAfterOpen = engine.shapeEvaluations

        // 1. Writing an unrelated file in the same directory does NOT trigger a reload.
        try "unrelated notes".write(to: siblingFile, atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(engine.shapeEvaluations == evalsAfterOpen)

        // 2. In-place write (atomically: false) triggers reload.
        try "import { Box } from 'made'; export default Box(34, 10, 10);".write(to: partFile, atomically: false, encoding: .utf8)
        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 34) < 0.01 })

        // 3. Deleting and recreating the file triggers failure on delete (keeping mesh 34) and recovery on recreate (mesh 52).
        try FileManager.default.removeItem(at: partFile)
        #expect(await waitUntil { controller.failures.message(for: partId) != nil })
        #expect(abs((sink.installed[partId]?.xExtent ?? 0) - 34) < 0.01)

        try "import { Box } from 'made'; export default Box(52, 10, 10);".write(to: partFile, atomically: true, encoding: .utf8)
        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 52) < 0.01 })
        #expect(controller.failures.message(for: partId) == nil)
    }

    // MARK: - 7. Removal Stops Watching and Regenerate / CADTools Integration

    @Test func testPartRegenerationCADToolsAndRemovalCleanup() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let partFile = dir.appendingPathComponent("spacer.part.ts")
        try "import { Box } from 'made'; export default Box(30, 20, 10);".write(to: partFile, atomically: true, encoding: .utf8)

        let engine = InstrumentedShapeEngine()
        let kernel = KernelClient(engine: engine, debounceDuration: .milliseconds(15))
        let runtime = PartRuntime(kernelClient: kernel)
        let doc = DocumentModel()
        let sink = RecordingMeshSink()

        let controller = PartReloadController(
            document: doc,
            partRuntime: runtime,
            kernelClient: kernel,
            meshSink: sink,
            debounceDuration: .milliseconds(25)
        )
        defer { controller.stopAll() }

        let partId = controller.openPartFile(at: partFile)
        #expect(await waitUntil { abs((sink.installed[partId]?.xExtent ?? 0) - 30) < 0.01 })

        // Verify CADToolRegistry can list and measure the part solid.
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let sceneReply = await registry.callTool(name: "cad_get_scene", arguments: [:])
        #expect(sceneReply.isError != true)
        #expect(sceneReply.content.first?.text?.contains(partId.rawValue) == true)
        #expect(sceneReply.content.first?.text?.contains("spacer.part.ts") == true)

        let measureReply = await registry.callTool(
            name: "cad_measure",
            arguments: ["id": .string(partId.rawValue)]
        )
        #expect(measureReply.isError != true)
        #expect(measureReply.content.first?.text?.contains("spacer.part.ts") == true)

        // Verify KernelRegeneration rebuilds the part solid from its stored ShapeNode.
        await kernel.dispose(solidId: partId)
        await KernelRegeneration.regenerate(document: doc, client: kernel, excluding: nil)
        let tessellated = await kernel.request(.tessellate(jobId: JobId("t-part"), solidId: partId))
        #expect(tessellated.isSuccess)

        // Remove the part from the document and sync; watcher stops and mesh is removed.
        doc.removeObject(id: partId)
        _ = SolidMeshApplier.remove(id: partId, from: sink)
        controller.syncWithDocument()
        #expect(!controller.watchedSolidIds.contains(partId))
        #expect(sink.installed[partId] == nil)

        let evalsBeforeWrite = engine.shapeEvaluations
        try "import { Box } from 'made'; export default Box(90, 20, 10);".write(to: partFile, atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(engine.shapeEvaluations == evalsBeforeWrite)
    }
}
