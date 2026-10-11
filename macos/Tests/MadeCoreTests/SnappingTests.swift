import XCTest
import simd
@testable import MadeCore

final class SnappingTests: XCTestCase {
    func testGridSnapRoundsXYAndPreservesZ() {
        let input = SIMD3<Float>(14.2, 26.8, 5.5)
        let snapped = snapToGrid(input, spacing: 10.0)
        
        XCTAssertEqual(snapped.x, 10.0)
        XCTAssertEqual(snapped.y, 30.0)
        XCTAssertEqual(snapped.z, 5.5)
    }
    
    func testPriorityVertexBeatsCloserEdgeAndGrid() {
        let vertexCandidate = SnapCandidate(
            kind: .vertex,
            point: SIMD3<Float>(10, 10, 0),
            screenDistancePx: 15.0 // Further, but higher priority
        )
        let edgeCandidate = SnapCandidate(
            kind: .edge,
            point: SIMD3<Float>(12, 10, 0),
            screenDistancePx: 8.0 // Closer, but lower priority
        )
        let gridCandidate = SnapCandidate(
            kind: .grid,
            point: SIMD3<Float>(0, 0, 0),
            screenDistancePx: 2.0 // Closest, but lowest priority
        )
        
        let result = resolveSnap(candidates: [gridCandidate, edgeCandidate, vertexCandidate], tolerancePx: 20.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .vertex)
        XCTAssertEqual(result?.point, SIMD3<Float>(10, 10, 0))
    }
    
    func testEdgeBeatsCloserGrid() {
        let edgeCandidate = SnapCandidate(
            kind: .edge,
            point: SIMD3<Float>(5, 5, 0),
            screenDistancePx: 12.0
        )
        let gridCandidate = SnapCandidate(
            kind: .grid,
            point: SIMD3<Float>(0, 0, 0),
            screenDistancePx: 4.0
        )
        
        let result = resolveSnap(candidates: [gridCandidate, edgeCandidate], tolerancePx: 20.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .edge)
        XCTAssertEqual(result?.point, SIMD3<Float>(5, 5, 0))
    }
    
    func testCandidateBeyondToleranceIsIgnored() {
        let candidate = SnapCandidate(
            kind: .vertex,
            point: SIMD3<Float>(10, 10, 0),
            screenDistancePx: 25.0 // Exceeds tolerance of 20
        )
        
        let result = resolveSnap(candidates: [candidate], tolerancePx: 20.0)
        XCTAssertNil(result)
    }
}
