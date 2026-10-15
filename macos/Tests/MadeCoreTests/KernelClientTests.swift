import Testing
import Foundation
@testable import MadeCore

@Suite struct KernelClientTests {
    @Test func testMakeBoxGeneratesIndexedTriangles() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("box-test")
        let jobId = JobId("job-1")
        let params = BoxParams(width: 20, depth: 30, height: 40)
        
        let result = await client.request(.makeBox(jobId: jobId, solidId: solidId, params: params))
        
        #expect(result.isSuccess)
        guard let payload = result.value else {
            Issue.record("Expected mesh payload")
            return
        }
        
        #expect(payload.triangleCount == 12) // 6 faces * 2 triangles
        #expect(payload.indices.count == 36)
        #expect(payload.positions.count == payload.normals.count)
        #expect(payload.positions.count == (payload.triangleCount * 3 * 3))
    }
    
    @Test func testMakeCylinderGeneratesValidNormals() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("cylinder-test")
        let jobId = JobId("job-2")
        let params = CylinderParams(radius: 10, height: 25)
        
        let result = await client.request(.makeCylinder(jobId: jobId, solidId: solidId, params: params))
        
        #expect(result.isSuccess)
        guard let payload = result.value else {
            Issue.record("Expected mesh payload")
            return
        }
        
        #expect(payload.triangleCount > 0)
        #expect(payload.positions.count == payload.normals.count)
    }

    @Test func testImportStepGeneratesMesh() async throws {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("step-test")
        let jobId = JobId("job-step-1")
        
        let stepData = try #require(OCCTEngine.sampleBoxStepData())
        #expect(!stepData.isEmpty)
        
        let result = await client.request(.importStep(jobId: jobId, solidId: solidId, data: stepData))
        #expect(result.isSuccess)
        guard let payload = result.value else {
            Issue.record("Expected mesh payload from STEP import")
            return
        }
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == payload.triangleCount * 3)
        #expect(payload.positions.count == payload.normals.count)
        #expect(payload.positions.count > 0)
    }

    @Test func testImportStepEmptyDataReturnsGeometryFailed() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("step-empty")
        let jobId = JobId("job-step-2")
        
        let result = await client.request(.importStep(jobId: jobId, solidId: solidId, data: Data()))
        #expect(!result.isSuccess)
        #expect(result.error?.code == .geometryFailed)
        #expect(result.error?.message == "STEP data is empty")
    }

    @Test func testImportStepCorruptDataReturnsGeometryFailed() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("step-corrupt")
        let jobId = JobId("job-step-3")
        let corruptData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])
        
        let result = await client.request(.importStep(jobId: jobId, solidId: solidId, data: corruptData))
        #expect(!result.isSuccess)
        #expect(result.error?.code == .geometryFailed)
        #expect(result.error?.message == "Failed to parse STEP geometry")
    }

    @Test func testStepRoundTripBox1VolumeAndBoundingBox() async throws {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let boxObject = SceneObject(
            id: SolidId("box-1"),
            name: "box-1",
            def: .box(BoxParams(width: 40, depth: 30, height: 20)),
            transform: Transform(position: SIMD3<Float>(-25, 0, 0))
        )
        let exportResult = await client.exportStep(objects: [boxObject])
        #expect(exportResult.isSuccess)
        let data = try #require(exportResult.value)
        #expect(!data.isEmpty)

        let measurement = try OCCTEngine.measureShape(data: data)
        #expect(abs(measurement.volume - 24000.0) < 0.001)
        #expect(abs(measurement.min.x - (-45.0)) < 0.001)
        #expect(abs(measurement.min.y - (-15.0)) < 0.001)
        #expect(abs(measurement.min.z - (-10.0)) < 0.001)
        #expect(abs(measurement.max.x - (-5.0)) < 0.001)
        #expect(abs(measurement.max.y - 15.0) < 0.001)
        #expect(abs(measurement.max.z - 10.0) < 0.001)
    }

    @Test func testExportStepMultipleObjectsCompounds() async throws {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let box = SceneObject(
            id: SolidId("box-1"),
            name: "box-1",
            def: .box(BoxParams(width: 40, depth: 30, height: 20)),
            transform: Transform(position: SIMD3<Float>(-25, 0, 0))
        )
        let cyl = SceneObject(
            id: SolidId("cylinder-1"),
            name: "cylinder-1",
            def: .cylinder(CylinderParams(radius: 15, height: 40)),
            transform: Transform(position: SIMD3<Float>(25, 0, 0))
        )
        let exportResult = await client.exportStep(objects: [box, cyl])
        #expect(exportResult.isSuccess)
        let data = try #require(exportResult.value)
        #expect(!data.isEmpty)

        let count = try OCCTEngine.solidCount(data: data)
        #expect(count == 2)
    }

    @Test func testImportStepNonMmUnitsScaledToMm() async throws {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let baseData = try #require(OCCTEngine.sampleBoxStepData())
        let stepText = try #require(String(data: baseData, encoding: .utf8))

        // Replace millimeter unit with meter unit: SI_UNIT(.MILLI.,.METRE.) -> SI_UNIT($,.METRE.)
        guard stepText.contains(".MILLI.,.METRE.") else {
            Issue.record("Expected STEP text to contain SI_UNIT(.MILLI.,.METRE.)")
            return
        }
        let meterStepText = stepText.replacingOccurrences(of: ".MILLI.,.METRE.", with: "$,.METRE.")
        let meterData = try #require(meterStepText.data(using: .utf8))

        // Import the 10x10x10 meter STEP box, scaled into millimeter scene space (10 m = 10,000 mm)
        let solidId = SolidId("meter-box")
        let result = await client.request(.importStep(jobId: JobId("job-m-1"), solidId: solidId, data: meterData))
        #expect(result.isSuccess)
        let payload = try #require(result.value)
        #expect(payload.triangleCount > 0)

        // Verify that the extent along X is scaled to ~10,000 mm (10 m in mm) instead of 10 mm
        let xs = stride(from: 0, to: payload.positions.count, by: 3).map { payload.positions[$0] }
        let extent = (xs.max() ?? 0) - (xs.min() ?? 0)
        #expect(abs(extent - 10000.0) < 1.0)
    }
    
    @Test func testRapidRequestsConflateToLatestValue() async {
        let client = KernelClient(debounceDuration: .milliseconds(50))
        let solidId = SolidId("conflation-box")
        
        // Enqueue in a fixed order; `async let` gives no arrival-order guarantee.
        let t1 = Task { await client.request(.makeBox(jobId: JobId("j1"), solidId: solidId, params: BoxParams(width: 10, depth: 10, height: 10))) }
        await waitForPending(client, solidId, JobId("j1"))
        let t2 = Task { await client.request(.makeBox(jobId: JobId("j2"), solidId: solidId, params: BoxParams(width: 20, depth: 20, height: 20))) }
        await waitForPending(client, solidId, JobId("j2"))
        let t3 = Task { await client.request(.makeBox(jobId: JobId("j3"), solidId: solidId, params: BoxParams(width: 30, depth: 30, height: 30))) }
        await waitForPending(client, solidId, JobId("j3"))
        
        let (r1, r2, r3) = await (t1.value, t2.value, t3.value)
        
        #expect((r1.error?.code) == .cancelled)
        #expect((r2.error?.code) == .cancelled)
        #expect(r3.isSuccess)
        #expect(r3.jobId == JobId("j3"))
        if let payload = r3.value {
            #expect(abs(extentX(payload) - 30) <= 1e-3)
        } else {
            Issue.record("Expected the latest request to produce a mesh")
        }
        
        let stats = await client.getStats()
        #expect(stats.conflated == 2)
        #expect(stats.dispatched == 1)
    }
    
    @Test func testStaleDebounceDoesNotStrandNewerRequest() async {
        // Regression for #90: a stale debounce firing must leave the newer pending job in place.
        let client = KernelClient(debounceDuration: .milliseconds(50))
        let solidId = SolidId("stale-box")
        
        let newer = Task { await client.request(.makeBox(jobId: JobId("new"), solidId: solidId, params: BoxParams(width: 12, depth: 12, height: 12))) }
        await waitForPending(client, solidId, JobId("new"))
        
        await client.executePending(for: solidId, expectedJobId: JobId("stale"))
        
        let stillPending = await client.pendingJobId(for: solidId)
        #expect(stillPending == JobId("new"))
        guard stillPending != nil else { return } // Without the fix the newer task never resumes.
        
        let result = await newer.value
        #expect(result.isSuccess)
        #expect(result.jobId == JobId("new"))
    }
    
    @Test func testInvalidDimensionsFailWithErrorCode() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("invalid-box")
        let jobId = JobId("job-err")
        let params = BoxParams(width: -5, depth: 10, height: 10)
        
        let result = await client.request(.makeBox(jobId: jobId, solidId: solidId, params: params))
        
        #expect(!result.isSuccess)
        #expect((result.error?.code) == .invalidParams)
    }
    
    @Test func testDisposeMakesSolidUnknownToBoolean() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let a = SolidId("dispose-a"), b = SolidId("dispose-b")
        await makeBox(client, a, "ja")
        await makeBox(client, b, "jb")
        
        await client.dispose(solidId: a)
        
        let result = await client.request(.booleanOperation(jobId: JobId("jc"), solidId: SolidId("out"), op: .union, solidA: a, solidB: b))
        #expect(result.error?.code == .unknownSolid)
    }

    @Test func testDisposeReleasesStateAndSubsequentBooleanFails() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let a = SolidId("dispose-rel-a"), b = SolidId("dispose-rel-b")
        await makeBox(client, a, "ja")
        await makeBox(client, b, "jb")
        
        #expect(await client.storeCounts().solids == 2)
        await client.dispose(solidId: a)
        #expect(await client.storeCounts().solids == 1)
        
        let booleanResult = await client.request(.booleanOperation(jobId: JobId("jc"), solidId: SolidId("out"), op: .union, solidA: a, solidB: b))
        #expect(booleanResult.error?.code == .unknownSolid)
        
        let tessellateResult = await client.request(.tessellate(jobId: JobId("jd"), solidId: a))
        #expect(tessellateResult.error?.code == .unknownSolid)
    }
    
    @Test func testFiftyAddAndDisposeCyclesLeavesStoresEmpty() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        for i in 0..<50 {
            let id = SolidId("cycle-50-\(i)")
            await makeBox(client, id, "cycle-50-job-\(i)")
            await client.dispose(solidId: id)
        }
        #expect(await client.storeCounts() == KernelStoreCounts())
    }
    
    @Test func testRepeatedAddAndDisposeLeavesStoresEmpty() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        for i in 0..<20 {
            let id = SolidId("cycle-\(i)")
            await makeBox(client, id, "cycle-job-\(i)")
            await client.dispose(solidId: id)
        }
        #expect(await client.storeCounts() == KernelStoreCounts())
    }
    
    @Test func testDisposeWithPendingJobResumesCancelled() async {
        let client = KernelClient(debounceDuration: .seconds(10))
        let solidId = SolidId("pending-dispose")
        let jobId = JobId("pending-job")
        
        let waiting = Task { await client.request(.makeBox(jobId: jobId, solidId: solidId, params: BoxParams(width: 5, depth: 5, height: 5))) }
        await waitForPending(client, solidId, jobId)
        await client.cancel(jobId: jobId)
        await client.dispose(solidId: solidId)
        
        let result = await waiting.value
        #expect(result.error?.code == .cancelled)
        #expect(await client.getStats().dropped == 1)
        #expect(await client.getStats().completed == 0)
        #expect(await client.storeCounts() == KernelStoreCounts())
    }
    
    @Test func testDisposeUnknownSolidIsNoOp() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let a = SolidId("noop-a")
        await makeBox(client, a, "ja")
        
        await client.dispose(solidId: SolidId("never-seen"))
        
        let result = await client.request(.booleanOperation(jobId: JobId("jb"), solidId: SolidId("out"), op: .union, solidA: a, solidB: a))
        #expect(result.isSuccess)
        #expect(await client.storeCounts().solids == 2)
    }
    
    @Test func testReAddAfterDisposeRestoresSolid() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let a = SolidId("readd-a"), b = SolidId("readd-b")
        await makeBox(client, a, "ja")
        await makeBox(client, b, "jb")
        await client.dispose(solidId: a)
        
        let failed = await client.request(.booleanOperation(jobId: JobId("j1"), solidId: SolidId("o1"), op: .union, solidA: a, solidB: b))
        #expect(failed.error?.code == .unknownSolid)
        
        await makeBox(client, a, "ja2")
        let ok = await client.request(.booleanOperation(jobId: JobId("j2"), solidId: SolidId("o2"), op: .union, solidA: a, solidB: b))
        #expect(ok.isSuccess)
    }
    
    @Test func testDisposeDuringInFlightRequestLeavesNoCache() async {
        let client = KernelClient(debounceDuration: .milliseconds(200))
        let solidId = SolidId("inflight")
        
        let first = Task { await client.request(.makeBox(jobId: JobId("f1"), solidId: solidId, params: BoxParams(width: 5, depth: 5, height: 5))) }
        await waitForPending(client, solidId, JobId("f1"))
        await client.dispose(solidId: solidId)
        #expect((await first.value).error?.code == .cancelled)
        #expect(await client.storeCounts() == KernelStoreCounts())
        
        // A request landing after dispose repopulates the cache; the second dispose clears it.
        _ = await client.request(.makeBox(jobId: JobId("f2"), solidId: solidId, params: BoxParams(width: 5, depth: 5, height: 5)))
        await client.dispose(solidId: solidId)
        #expect(await client.storeCounts() == KernelStoreCounts())
    }
    
    @Test func testDisposeDuringExecutingJobLeavesNoEngineEntry() async {
        let started = Flag()
        let engine = HookedEngine { _ in
            started.set()
            try? await Task.sleep(for: .milliseconds(100))
            return true
        }
        let client = KernelClient(engine: engine, debounceDuration: .milliseconds(5))
        let solidId = SolidId("executing")
        
        let job = Task { await client.request(.makeBox(jobId: JobId("e1"), solidId: solidId, params: BoxParams(width: 5, depth: 5, height: 5))) }
        #expect(await eventually { started.isSet })
        await client.dispose(solidId: solidId)
        
        #expect((await job.value).error?.code == .cancelled)
        #expect(await client.storeCounts() == KernelStoreCounts())
    }
    
    private func makeBox(_ client: KernelClient, _ id: SolidId, _ job: String) async {
        let r = await client.request(.makeBox(jobId: JobId(job), solidId: id, params: BoxParams(width: 10, depth: 10, height: 10)))
        #expect(r.isSuccess)
    }
    
    private func waitForPending(_ client: KernelClient, _ solidId: SolidId, _ jobId: JobId) async {
        for _ in 0..<1_000 {
            if await client.pendingJobId(for: solidId) == jobId { return }
            await Task.yield()
        }
        Issue.record("Job \(jobId) never became pending")
    }
    
    private func extentX(_ payload: MeshPayload) -> Float {
        let xs = stride(from: 0, to: payload.positions.count, by: 3).map { payload.positions[$0] }
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }
}
