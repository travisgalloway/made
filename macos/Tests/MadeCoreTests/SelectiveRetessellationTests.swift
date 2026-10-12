import Testing
import Foundation
import Synchronization
@testable import MadeCore

/// Per-solid isolation in the kernel client: a request re-tessellates only its own solid.
@Suite struct SelectiveRetessellationTests {
    private final class Recorder: Sendable {
        private let ids = Mutex<[SolidId]>([])
        func record(_ id: SolidId) { ids.withLock { $0.append(id) } }
        func reset() { ids.withLock { $0.removeAll() } }
        var recorded: [SolidId] { ids.withLock { $0 } }
    }
    
    private func box(_ job: String, _ id: SolidId, _ size: Float) -> KernelRequest {
        .makeBox(jobId: JobId(job), solidId: id, params: BoxParams(width: size, depth: size, height: size))
    }
    
    private func makeClient(_ recorder: Recorder) -> KernelClient {
        KernelClient(engine: HookedEngine { request in
            recorder.record(request.solidId)
            return true
        }, debounceDuration: .milliseconds(50))
    }
    
    @Test func testRequestForOneSolidExecutesOnlyThatSolid() async {
        let recorder = Recorder()
        let client = makeClient(recorder)
        let a = SolidId("a"), b = SolidId("b")
        #expect(await client.request(box("a1", a, 10)).isSuccess)
        #expect(await client.request(box("b1", b, 10)).isSuccess)
        recorder.reset()
        let before = await client.getStats()
        
        let result = await client.request(box("a2", a, 20))
        
        #expect(result.isSuccess)
        #expect(recorder.recorded == [a])
        let after = await client.getStats()
        #expect(after.dispatched - before.dispatched == 1)
        #expect(after.conflated - before.conflated == 0)
    }
    
    @Test func testTwoSolidsPendingAtOnceBothDispatch() async {
        let recorder = Recorder()
        let client = makeClient(recorder)
        let a = SolidId("a"), b = SolidId("b")
        
        let ta = Task { await client.request(box("a1", a, 10)) }
        await waitForPending(client, a, JobId("a1"))
        let tb = Task { await client.request(box("b1", b, 20)) }
        await waitForPending(client, b, JobId("b1"))
        let (ra, rb) = await (ta.value, tb.value)
        
        #expect(ra.isSuccess)
        #expect(rb.isSuccess)
        #expect(ra.value.map(extentX).map { abs($0 - 10) <= 1e-3 } == true)
        #expect(rb.value.map(extentX).map { abs($0 - 20) <= 1e-3 } == true)
        let stats = await client.getStats()
        #expect(stats.dispatched == 2)
        #expect(stats.completed == 2)
        #expect(stats.conflated == 0)
        #expect(stats.dropped == 0)
    }
    
    @Test func testConflationForOneSolidDoesNotDropAnother() async {
        let recorder = Recorder()
        let client = makeClient(recorder)
        let a = SolidId("a"), b = SolidId("b")
        
        let tb = Task { await client.request(box("b1", b, 40)) }
        await waitForPending(client, b, JobId("b1"))
        let t1 = Task { await client.request(box("a1", a, 10)) }
        await waitForPending(client, a, JobId("a1"))
        let t2 = Task { await client.request(box("a2", a, 20)) }
        await waitForPending(client, a, JobId("a2"))
        let t3 = Task { await client.request(box("a3", a, 30)) }
        await waitForPending(client, a, JobId("a3"))
        
        let (r1, r2, r3, rb) = await (t1.value, t2.value, t3.value, tb.value)
        
        #expect(r1.error?.code == .cancelled)
        #expect(r2.error?.code == .cancelled)
        #expect(r3.isSuccess)
        #expect(rb.isSuccess)
        #expect(rb.value.map(extentX).map { abs($0 - 40) <= 1e-3 } == true)
        #expect(recorder.recorded.filter { $0 == a }.count == 1)
        #expect(recorder.recorded.filter { $0 == b }.count == 1)
        let stats = await client.getStats()
        #expect(stats.conflated == 2)
        #expect(stats.dispatched == 2)
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
