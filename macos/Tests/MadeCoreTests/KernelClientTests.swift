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
        let client = KernelClient(debounceDuration: .milliseconds(20))
        let solidId = SolidId("conflation-box")
        
        async let r1 = client.request(.makeBox(jobId: JobId("j1"), solidId: solidId, params: BoxParams(width: 10, depth: 10, height: 10)))
        async let r2 = client.request(.makeBox(jobId: JobId("j2"), solidId: solidId, params: BoxParams(width: 20, depth: 20, height: 20)))
        async let r3 = client.request(.makeBox(jobId: JobId("j3"), solidId: solidId, params: BoxParams(width: 30, depth: 30, height: 30)))
        
        let (_, _, finalResult) = await (r1, r2, r3)
        
        // Final request should succeed with the latest dimensions
        XCTAssertTrue(finalResult.isSuccess)
        let stats = await client.getStats()
        XCTAssertGreaterThanOrEqual(stats.conflated, 1)
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
}
