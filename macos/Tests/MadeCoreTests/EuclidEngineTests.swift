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
    
    @Test func testBooleanIntersectionProducesExpectedMesh() {
        let boxA = EuclidEngine.makeBox(width: 20, depth: 20, height: 20)
        let boxB = EuclidEngine.makeBox(width: 20, depth: 20, height: 20).translated(by: Vector(5, 5, 5))
        
        let intersection = EuclidEngine.intersect(boxA, boxB)
        let payload = EuclidEngine.toMeshPayload(intersection)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
        #expect(payload.positions.count == payload.normals.count)
    }
    
    @Test func testMakeBoxProducesZUpCoordinates() {
        let width: Float = 40
        let depth: Float = 30
        let height: Float = 20
        let box = EuclidEngine.makeBox(width: width, depth: depth, height: height)
        let payload = EuclidEngine.toMeshPayload(box)
        
        #expect(payload.triangleCount > 0)
        var minX: Float = .infinity
        var maxX: Float = -.infinity
        var minY: Float = .infinity
        var maxY: Float = -.infinity
        var minZ: Float = .infinity
        var maxZ: Float = -.infinity
        
        for i in stride(from: 0, to: payload.positions.count, by: 3) {
            let x = payload.positions[i]
            let y = payload.positions[i + 1]
            let z = payload.positions[i + 2]
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
            minZ = min(minZ, z)
            maxZ = max(maxZ, z)
        }
        
        let halfWidth = width / 2.0
        let halfDepth = depth / 2.0
        let halfHeight = height / 2.0
        let epsilon: Float = 0.001
        
        #expect(abs(minX - (-halfWidth)) < epsilon)
        #expect(abs(maxX - halfWidth) < epsilon)
        #expect(abs(minY - (-halfDepth)) < epsilon)
        #expect(abs(maxY - halfDepth) < epsilon)
        #expect(abs(minZ - (-halfHeight)) < epsilon)
        #expect(abs(maxZ - halfHeight) < epsilon)
    }
}
