import Testing
import Foundation
@testable import MadeCore

@Suite struct CADDSLTests {
    let kernel = KernelClient(debounceDuration: .milliseconds(5))
    
    private func payload(_ shape: any CADShape) async throws -> MeshPayload {
        try #require(await shape.evaluate(on: kernel, solidId: SolidId("dsl")).value)
    }
    
    @Test func testDeclarativeBoxCreation() async throws {
        let box = Box(width: 40, depth: 30, height: 10)
        let payload = try await payload(box)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
        #expect(payload.positions.count == payload.normals.count)
    }
    
    @Test func testDeclarativeCylinderCreation() async throws {
        let cyl = Cylinder(radius: 5, height: 20, slices: 16)
        let payload = try await payload(cyl)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testDeclarativeSubtractionOperator() async throws {
        let plateWithHole = Box(width: 50, depth: 50, height: 10) - Cylinder(radius: 8, height: 20)
        let payload = try await payload(plateWithHole)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testDeclarativeUnionOperator() async throws {
        let combined = Box(width: 20, depth: 20, height: 20) + Box(width: 10, depth: 10, height: 10).translated(x: 20)
        let payload = try await payload(combined)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testDeclarativeIntersectionOperator() async throws {
        let common = Box(width: 20, depth: 20, height: 20) & Cylinder(radius: 10, height: 30)
        let payload = try await payload(common)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testDeclarativeMethodChaining() async throws {
        let part = Box(width: 60, depth: 40, height: 15)
            .subtracting(Cylinder(radius: 5, height: 25))
            .translated(z: 5)
        let payload = try await payload(part)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    // MARK: - Descriptions (no kernel)
    
    @Test func testBoxOffsetWrapsInTranslate() {
        let params = BoxParams(width: 1, depth: 2, height: 3)
        var box = Box(width: 1, depth: 2, height: 3)
        #expect(box.shapeDescription == .box(params))
        box.offset = SIMD3(4, 5, 6)
        #expect(box.shapeDescription == .translate(.box(params), offset: SIMD3(4, 5, 6)))
        
        var cyl = Cylinder(radius: 1, height: 2, slices: 12)
        cyl.offset = SIMD3(0, 0, 1)
        #expect(cyl.shapeDescription == .translate(.cylinder(CylinderParams(radius: 1, height: 2), slices: 12), offset: SIMD3(0, 0, 1)))
    }
    
    @Test func testOperatorsBuildBooleanNodes() {
        let a = Box(width: 1, depth: 1, height: 1), b = Cylinder(radius: 1, height: 1)
        let pairs: [(CSGCompositeShape, BooleanOp)] = [(a - b, .subtract), (a + b, .union), (a & b, .intersect)]
        for (shape, op) in pairs {
            #expect(shape.shapeDescription == .boolean(op, a.shapeDescription, b.shapeDescription))
        }
    }
    
    @Test func testTranslatedWrapsNode() {
        let box = Box(width: 1, depth: 1, height: 1)
        #expect(box.translated(x: 1, z: 2).shapeDescription == .translate(box.shapeDescription, offset: SIMD3(1, 0, 2)))
    }
}
