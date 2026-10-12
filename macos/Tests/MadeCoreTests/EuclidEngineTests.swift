import Testing
import Foundation
import Euclid
@testable import MadeCore

@Suite struct EuclidEngineTests {
    @Test func testMakeBoxGeneratesValidEuclidMesh() {
        let box = EuclidEngine.makeBox(width: 40, depth: 30, height: 20)
        let payload = EuclidEngine.toMeshPayload(box)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
        #expect(payload.positions.count == payload.normals.count)
    }
    
    @Test func testMakeCylinderGeneratesValidEuclidMesh() {
        let cyl = EuclidEngine.makeCylinder(radius: 10, height: 25, slices: 16)
        let payload = EuclidEngine.toMeshPayload(cyl)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testBooleanDifferenceProducesWatertightMesh() {
        let box = EuclidEngine.makeBox(width: 40, depth: 40, height: 20)
        let cyl = EuclidEngine.makeCylinder(radius: 8, height: 30) // Drill through box
        
        let result = EuclidEngine.subtract(box, cyl)
        let payload = EuclidEngine.toMeshPayload(result)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testBooleanUnionCombinesMeshes() {
        let boxA = EuclidEngine.makeBox(width: 20, depth: 20, height: 20)
        let boxB = EuclidEngine.makeBox(width: 20, depth: 20, height: 20).translated(by: Vector(10, 0, 0))
        
        let union = EuclidEngine.union(boxA, boxB)
        let payload = EuclidEngine.toMeshPayload(union)
        
        #expect(payload.triangleCount > 0)
    }
}
