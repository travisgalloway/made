import XCTest
@testable import MadeCore

final class KernelClientTests: XCTestCase {
    func testMakeBoxGeneratesIndexedTriangles() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("box-test")
        let jobId = JobId("job-1")
        let params = BoxParams(width: 20, depth: 30, height: 40)
        
        let result = await client.request(.makeBox(jobId: jobId, solidId: solidId, params: params))
        
        XCTAssertTrue(result.isSuccess)
        guard let payload = result.value else {
            XCTFail("Expected mesh payload")
            return
        }
        
        XCTAssertEqual(payload.triangleCount, 12) // 6 faces * 2 triangles
        XCTAssertEqual(payload.indices.count, 36)
        XCTAssertEqual(payload.positions.count, payload.normals.count)
        XCTAssertEqual(payload.positions.count, payload.triangleCount * 3 * 3)
    }
    
    func testMakeCylinderGeneratesValidNormals() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("cylinder-test")
        let jobId = JobId("job-2")
        let params = CylinderParams(radius: 10, height: 25)
        
        let result = await client.request(.makeCylinder(jobId: jobId, solidId: solidId, params: params))
        
        XCTAssertTrue(result.isSuccess)
        guard let payload = result.value else {
            XCTFail("Expected mesh payload")
            return
        }
        
        XCTAssertGreaterThan(payload.triangleCount, 0)
        XCTAssertEqual(payload.positions.count, payload.normals.count)
    }
    
    func testRapidRequestsConflateToLatestValue() async {
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
        
        XCTAssertEqual(r1.error?.code, .cancelled)
        XCTAssertEqual(r2.error?.code, .cancelled)
        XCTAssertTrue(r3.isSuccess)
        XCTAssertEqual(r3.jobId, JobId("j3"))
        if let payload = r3.value {
            XCTAssertEqual(extentX(payload), 30, accuracy: 1e-3)
        } else {
            XCTFail("Expected the latest request to produce a mesh")
        }
        
        let stats = await client.getStats()
        XCTAssertEqual(stats.conflated, 2)
        XCTAssertEqual(stats.dispatched, 1)
    }
    
    func testStaleDebounceDoesNotStrandNewerRequest() async {
        // Regression for #90: a stale debounce firing must leave the newer pending job in place.
        let client = KernelClient(debounceDuration: .milliseconds(50))
        let solidId = SolidId("stale-box")
        
        let newer = Task { await client.request(.makeBox(jobId: JobId("new"), solidId: solidId, params: BoxParams(width: 12, depth: 12, height: 12))) }
        await waitForPending(client, solidId, JobId("new"))
        
        await client.executePending(for: solidId, expectedJobId: JobId("stale"))
        
        let stillPending = await client.pendingJobId(for: solidId)
        XCTAssertEqual(stillPending, JobId("new"))
        guard stillPending != nil else { return } // Without the fix the newer task never resumes.
        
        let result = await newer.value
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.jobId, JobId("new"))
    }
    
    func testInvalidDimensionsFailWithErrorCode() async {
        let client = KernelClient(debounceDuration: .milliseconds(5))
        let solidId = SolidId("invalid-box")
        let jobId = JobId("job-err")
        let params = BoxParams(width: -5, depth: 10, height: 10)
        
        let result = await client.request(.makeBox(jobId: jobId, solidId: solidId, params: params))
        
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.error?.code, .invalidParams)
    }
    
    private func waitForPending(_ client: KernelClient, _ solidId: SolidId, _ jobId: JobId) async {
        for _ in 0..<1_000 {
            if await client.pendingJobId(for: solidId) == jobId { return }
            await Task.yield()
        }
        XCTFail("Job \(jobId) never became pending")
    }
    
    private func extentX(_ payload: MeshPayload) -> Float {
        let xs = stride(from: 0, to: payload.positions.count, by: 3).map { payload.positions[$0] }
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }
}
