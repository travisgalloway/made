import XCTest
@testable import MadeCore

final class CADDSLTests: XCTestCase {
    func testDeclarativeBoxCreation() {
        let box = Box(width: 40, depth: 30, height: 10)
        let payload = box.toMeshPayload()
        
        XCTAssertGreaterThan(payload.triangleCount, 0)
        XCTAssertEqual(payload.indices.count, payload.triangleCount * 3)
        XCTAssertEqual(payload.positions.count, payload.normals.count)
    }
    
    func testDeclarativeCylinderCreation() {
        let cyl = Cylinder(radius: 5, height: 20, slices: 16)
        let payload = cyl.toMeshPayload()
        
        XCTAssertGreaterThan(payload.triangleCount, 0)
        XCTAssertEqual(payload.indices.count, payload.triangleCount * 3)
    }
    
    func testDeclarativeSubtractionOperator() {
        let plateWithHole = Box(width: 50, depth: 50, height: 10) - Cylinder(radius: 8, height: 20)
        let payload = plateWithHole.toMeshPayload()
        
        XCTAssertGreaterThan(payload.triangleCount, 0)
        XCTAssertEqual(payload.indices.count, payload.triangleCount * 3)
    }
    
    func testDeclarativeUnionOperator() {
        let combined = Box(width: 20, depth: 20, height: 20) + Box(width: 10, depth: 10, height: 10).translated(x: 20)
        let payload = combined.toMeshPayload()
        
        XCTAssertGreaterThan(payload.triangleCount, 0)
        XCTAssertEqual(payload.indices.count, payload.triangleCount * 3)
    }
    
    func testDeclarativeIntersectionOperator() {
        let common = Box(width: 20, depth: 20, height: 20) & Cylinder(radius: 10, height: 30)
        let payload = common.toMeshPayload()
        
        XCTAssertGreaterThan(payload.triangleCount, 0)
        XCTAssertEqual(payload.indices.count, payload.triangleCount * 3)
    }
    
    func testDeclarativeMethodChaining() {
        let part = Box(width: 60, depth: 40, height: 15)
            .subtracting(Cylinder(radius: 5, height: 25))
            .translated(z: 5)
        let payload = part.toMeshPayload()
        
        XCTAssertGreaterThan(payload.triangleCount, 0)
        XCTAssertEqual(payload.indices.count, payload.triangleCount * 3)
    }
}
