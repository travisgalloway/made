import Testing
import Foundation
import XPC
@testable import MadeCore

/// The kernel XPC boundary, run in-process against an anonymous listener. A real segfault cannot be
/// raised here; cancelling the service side of the session reproduces what the app observes.
@Suite struct KernelXPCTests {
    private let box = BoxParams(width: 10, depth: 20, height: 30)
    
    // MARK: - Wire contract
    
    @Test func testRequestRoundTripsEveryCase() throws {
        let j = JobId("j"), s = SolidId("s")
        let messages: [KernelWireMessage] = [
            .execute(.makeBox(jobId: j, solidId: s, params: box)),
            .execute(.makeCylinder(jobId: j, solidId: s, params: CylinderParams(radius: 2, height: 3))),
            .execute(.makeSphere(jobId: j, solidId: s, params: SphereParams(radius: 5))),
            .execute(.makeCone(jobId: j, solidId: s, params: ConeParams(bottomRadius: 5, topRadius: 1, height: 10))),
            .execute(.makeTorus(jobId: j, solidId: s, params: TorusParams(majorRadius: 10, minorRadius: 2))),
            .execute(.makeWedge(jobId: j, solidId: s, params: WedgeParams(width: 10, depth: 10, height: 10, topWidth: 2))),
            .execute(.tessellate(jobId: j, solidId: s)),
            .execute(.importStep(jobId: j, solidId: s, data: Data([1, 2, 3]))),
            .execute(.booleanOperation(jobId: j, solidId: s, op: .intersect, solidA: SolidId("a"), solidB: SolidId("b"))),
            .execute(.evaluateShape(jobId: j, solidId: s, shape: .boolean(.subtract, .translate(.box(box), offset: SIMD3(1, -2, 0.5)), .cylinder(CylinderParams(radius: 2, height: 3), slices: 12)))),
            .dispose(s),
            .terminate
        ]
        for message in messages {
            #expect(try KernelWire.decodeMessage(KernelWire.encode(message)) == message)
        }
    }
    
    @Test func testErrorCodesRoundTrip() {
        for code in KernelErrorCode.allCases {
            let error = KernelError(code: code, message: "m-\(code.rawValue)")
            let reply = KernelWire.encodeReply(.failure(jobId: JobId("j"), error: error))
            #expect(KernelWire.decodeReply(reply, jobId: JobId("j")).error == error)
        }
    }
    
    @Test func testEmptyMeshCrossesWithoutShmem() throws {
        let reply = KernelWire.encodeReply(.success(jobId: JobId("j"), value: MeshPayload(positions: [], normals: [], indices: [])))
        #expect(reply[KernelWire.meshKey, as: XPC_TYPE_SHMEM] == nil)
        let payload = try #require(KernelWire.decodeReply(reply, jobId: JobId("j")).value)
        #expect(payload.triangleCount == 0)
        #expect(payload.positions.isEmpty)
    }
    
    @Test func testMalformedReplyReturnsGeometryFailed() throws {
        #expect(KernelWire.decodeReply(XPCDictionary(), jobId: JobId("j")).error?.code == .geometryFailed)
        
        var noRegion = XPCDictionary()
        noRegion[KernelWire.headerKey] = try KernelWire.dataObject(KernelWireReply(jobId: JobId("j"), indexCount: 3))
        #expect(KernelWire.decodeReply(noRegion, jobId: JobId("j")).error?.code == .geometryFailed)
        
        // A one-page region whose header claims more than a page of indices.
        let small = MeshPayload(positions: [], normals: [], indices: [0, 1, 2])
        var short = KernelWire.encodeReply(.success(jobId: JobId("j"), value: small))
        short[KernelWire.headerKey] = try KernelWire.dataObject(KernelWireReply(jobId: JobId("j"), indexCount: 1_000_000))
        let result = KernelWire.decodeReply(short, jobId: JobId("j"))
        #expect(result.error?.code == .geometryFailed)
        #expect(result.error?.message.contains("Malformed kernel reply") == true)
    }
    
    // MARK: - Service round trip
    
    @Test func testBoxRoundTripsThroughService() async throws {
        let harness = KernelServiceHarness()
        let engine = harness.makeEngine()
        let request = KernelRequest.makeBox(jobId: JobId("j"), solidId: SolidId("b"), params: box)
        
        let remote = try #require(await engine.execute(request).value)
        let local = try #require(await LocalKernelEngine().execute(request).value)
        #expect(Array(remote.positions) == Array(local.positions))
        #expect(Array(remote.normals) == Array(local.normals))
        #expect(Array(remote.indices) == Array(local.indices))
        #expect(await engine.execute(.tessellate(jobId: JobId("t"), solidId: SolidId("b"))).isSuccess)
    }

    @Test func testPrimitivesRoundTripThroughService() async throws {
        let harness = KernelServiceHarness()
        let engine = harness.makeEngine()
        let localEngine = LocalKernelEngine()

        let requests: [KernelRequest] = [
            .makeSphere(jobId: JobId("jsph"), solidId: SolidId("sph"), params: SphereParams(radius: 10)),
            .makeCone(jobId: JobId("jcn"), solidId: SolidId("cn"), params: ConeParams(bottomRadius: 10, topRadius: 2, height: 20)),
            .makeTorus(jobId: JobId("jtor"), solidId: SolidId("tor"), params: TorusParams(majorRadius: 15, minorRadius: 3)),
            .makeWedge(jobId: JobId("jwdg"), solidId: SolidId("wdg"), params: WedgeParams(width: 15, depth: 15, height: 15, topWidth: 5))
        ]

        for req in requests {
            let remote = try #require(await engine.execute(req).value)
            let local = try #require(await localEngine.execute(req).value)
            #expect(remote.triangleCount > 0)
            #expect(Array(remote.indices) == Array(local.indices))
            #expect(await engine.execute(.tessellate(jobId: JobId("t-\(req.solidId.rawValue)"), solidId: req.solidId)).isSuccess)
        }
    }
    
    @Test func testShapeTreeRoundTripsThroughService() async throws {
        let harness = KernelServiceHarness()
        let engine = harness.makeEngine()
        let shape = ShapeNode.boolean(.subtract, .box(box), .translate(.cylinder(CylinderParams(radius: 1, height: 20), slices: 16), offset: SIMD3(1, 1, 0)))
        let request = KernelRequest.evaluateShape(jobId: JobId("j"), solidId: SolidId("tree"), shape: shape)
        
        let remote = try #require(await engine.execute(request).value)
        let local = try #require(await LocalKernelEngine().execute(request).value)
        #expect(remote.triangleCount > 0)
        #expect(Array(remote.indices) == Array(local.indices))
        #expect(await engine.execute(.tessellate(jobId: JobId("t"), solidId: SolidId("tree"))).isSuccess)
    }
    
    @Test func testSessionFactoryFailureReturnsKernelInitFailed() async {
        let engine = XPCKernelEngine { _ in throw CocoaError(.fileNoSuchFile) }
        let result = await engine.execute(.makeBox(jobId: JobId("j"), solidId: SolidId("b"), params: box))
        #expect(result.error?.code == .kernelInitFailed)
    }
    
    // MARK: - Crash recovery
    
    @Test func testPeerLossDuringJobRetriesOnceThenSucceeds() async {
        // The first service launch dies on its first job; the relaunch answers.
        let harness = KernelServiceHarness { session, _, crash in
            if session == 0 { crash(); return false }
            return true
        }
        let engine = harness.makeEngine()
        var restarts = engine.restarts().makeAsyncIterator()
        
        let result = await engine.execute(.makeBox(jobId: JobId("j"), solidId: SolidId("b"), params: box))
        #expect(result.isSuccess)
        #expect(await restarts.next() == KernelRestart(reason: .crashed, excludedSolid: nil))
    }
    
    @Test func testRepeatedPeerLossReturnsWorkerCrashed() async {
        let harness = KernelServiceHarness { _, request, crash in
            if request.solidId == SolidId("bad") { crash(); return false }
            return true
        }
        let engine = harness.makeEngine()
        var restarts = engine.restarts().makeAsyncIterator()
        
        let bad = await engine.execute(.makeBox(jobId: JobId("j1"), solidId: SolidId("bad"), params: box))
        #expect(bad.error?.code == .workerCrashed)
        #expect(await restarts.next() == KernelRestart(reason: .crashed, excludedSolid: SolidId("bad")))
        
        let good = await engine.execute(.makeBox(jobId: JobId("j2"), solidId: SolidId("good"), params: box))
        #expect(good.isSuccess)
    }
    
    @Test func testQueuedJobsSurviveACrash() async {
        let started = Flag()
        let harness = KernelServiceHarness { _, request, crash in
            guard request.solidId == SolidId("bad") else { return true }
            started.set()
            try? await Task.sleep(for: .milliseconds(100)) // let the other jobs queue behind this one
            crash()
            return false
        }
        let engine = harness.makeEngine()
        
        let bad = Task { await engine.execute(.makeBox(jobId: JobId("bad"), solidId: SolidId("bad"), params: box)) }
        #expect(await eventually { started.isSet })
        let queued = (0..<3).map { i in
            Task { await engine.execute(.makeBox(jobId: JobId("q\(i)"), solidId: SolidId("q\(i)"), params: box)) }
        }
        
        #expect(await bad.value.error?.code == .workerCrashed)
        for task in queued {
            #expect(await task.value.isSuccess)
        }
    }
    
    @Test func testRelaunchedServiceInstanceTriggersRestart() async throws {
        // XPC may relaunch an idle service behind a live session; the reply's instance is the only sign.
        let instances = ["first", "first", "second"]
        let counter = Counter()
        let listener = XPCListener { request in
            request.accept(incomingMessageHandler: { (message: XPCDictionary) -> XPCDictionary? in
                let index = counter.next()
                guard case .execute(let req) = try? KernelWire.decodeMessage(message) else { return nil }
                let payload = MeshPayload(positions: [], normals: [], indices: [])
                return KernelWire.encodeReply(.success(jobId: req.jobId, value: payload), instance: instances[min(index, 2)])
            })
        }
        defer { listener.cancel() }
        let endpoint = listener.endpoint
        let engine = XPCKernelEngine { try XPCSession(endpoint: endpoint, cancellationHandler: $0) }
        var restarts = engine.restarts().makeAsyncIterator()
        
        for i in 0..<3 {
            #expect(await engine.execute(.tessellate(jobId: JobId("j\(i)"), solidId: SolidId("s"))).isSuccess)
        }
        #expect(await restarts.next() == KernelRestart(reason: .crashed, excludedSolid: nil))
    }
    
    @Test func testBreakerOpensAfterRepeatedRestarts() async {
        let clock = TestClock()
        let harness = KernelServiceHarness { _, request, crash in
            if request.solidId == SolidId("bad") { crash(); return false }
            return true
        }
        let engine = harness.makeEngine(maxRestarts: 2, clock: clock)
        
        _ = await engine.execute(.makeBox(jobId: JobId("j1"), solidId: SolidId("bad"), params: box))
        let sessions = harness.sessionCount
        let blocked = await engine.execute(.makeBox(jobId: JobId("j2"), solidId: SolidId("good"), params: box))
        #expect(blocked.error?.code == .kernelInitFailed)
        #expect(harness.sessionCount == sessions) // the open breaker never reaches the service
    }
    
    @Test func testBreakerClosesAfterWindow() async {
        let clock = TestClock()
        let harness = KernelServiceHarness { _, request, crash in
            if request.solidId == SolidId("bad") { crash(); return false }
            return true
        }
        let engine = harness.makeEngine(maxRestarts: 2, clock: clock)
        
        _ = await engine.execute(.makeBox(jobId: JobId("j1"), solidId: SolidId("bad"), params: box))
        clock.advance(.seconds(31))
        #expect(await engine.execute(.makeBox(jobId: JobId("j2"), solidId: SolidId("good"), params: box)).isSuccess)
    }
    
    // MARK: - Cancellation
    
    @Test func testCancelInFlightJobTerminatesService() async throws {
        let started = Flag()
        let harness = KernelServiceHarness { session, request, _ in
            guard session == 0, request.solidId == SolidId("stuck") else { return true }
            started.set()
            return false
        }
        let client = KernelClient(engine: harness.makeEngine(), debounceDuration: .milliseconds(5))
        var restarts = await client.restarts().makeAsyncIterator()
        
        let stuck = Task { await client.request(.makeBox(jobId: JobId("stuck-job"), solidId: SolidId("stuck"), params: box)) }
        #expect(await eventually { started.isSet })
        await client.cancel(jobId: JobId("stuck-job"))
        
        #expect(await stuck.value.error?.code == .cancelled)
        #expect(await restarts.next() == KernelRestart(reason: .terminated, excludedSolid: SolidId("stuck")))
        #expect(await eventually { harness.peerGoneCount >= 1 })
        #expect(await client.request(.makeBox(jobId: JobId("next"), solidId: SolidId("stuck"), params: box)).isSuccess)
    }
    
    @Test func testCancelPendingJobDoesNotTerminate() async {
        let harness = KernelServiceHarness()
        let client = KernelClient(engine: harness.makeEngine(), debounceDuration: .milliseconds(200))
        
        let pending = Task { await client.request(.makeBox(jobId: JobId("p"), solidId: SolidId("p"), params: box)) }
        #expect(await eventually { await client.pendingJobId(for: SolidId("p")) == JobId("p") })
        await client.cancel(jobId: JobId("p"))
        
        #expect(await pending.value.error?.code == .cancelled)
        #expect(harness.sessionCount == 0)
        #expect(harness.peerGoneCount == 0)
    }
    
    @Test func testDisposeDuringInFlightJobLeavesNoServiceEntry() async throws {
        let started = Flag()
        let harness = KernelServiceHarness { _, _, _ in
            started.set()
            try? await Task.sleep(for: .milliseconds(100))
            return true
        }
        let client = KernelClient(engine: harness.makeEngine(), debounceDuration: .milliseconds(5))
        let id = SolidId("inflight")
        
        let job = Task { await client.request(.makeBox(jobId: JobId("f1"), solidId: id, params: box)) }
        #expect(await eventually { started.isSet })
        await client.dispose(solidId: id)
        
        #expect(await job.value.error?.code == .cancelled)
        let service = try #require(harness.engines.first)
        #expect(await eventually { await service.storeCounts() == KernelEngineCounts() })
    }
}
